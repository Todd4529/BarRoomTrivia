// Supabase Edge Function: evaluate_answers
// Evaluates player responses securely on the server side upon timer expiration.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface EvaluateRequest {
  session_id: string;
  question_id: string;
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const { session_id, question_id }: EvaluateRequest = await req.json();

    if (!session_id || !question_id) {
      return new Response(
        JSON.stringify({ error: 'Missing session_id or question_id' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      );
    }

    // 1. Fetch the correct question answer
    const { data: question, error: qError } = await supabaseClient
      .from('questions')
      .select('id, correct_option, time_limit_seconds')
      .eq('id', question_id)
      .single();

    if (qError || !question) {
      return new Response(
        JSON.stringify({ error: 'Question not found' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 404 }
      );
    }

    // 2. Fetch all un-evaluated answers for this session & question
    const { data: answers, error: aError } = await supabaseClient
      .from('player_answers')
      .select('id, player_uid, selected_option, submitted_at')
      .eq('session_id', session_id)
      .eq('question_id', question_id);

    if (aError) {
      throw aError;
    }

    const updates = [];
    const scoreMap: Record<string, number> = {};

    for (const ans of (answers || [])) {
      const isCorrect = ans.selected_option.trim().toUpperCase() === question.correct_option.trim().toUpperCase();
      // Base score 100 points for correct answer + speed bonus up to 50 points
      const scoreAwarded = isCorrect ? 100 : 0;

      updates.push(
        supabaseClient
          .from('player_answers')
          .update({
            is_correct: isCorrect,
            score_awarded: scoreAwarded
          })
          .eq('id', ans.id)
      );

      if (isCorrect) {
        scoreMap[ans.player_uid] = (scoreMap[ans.player_uid] || 0) + scoreAwarded;
      }
    }

    await Promise.all(updates);

    // 3. Update cumulative scores in public.players
    for (const [playerUid, points] of Object.entries(scoreMap)) {
      // Increment player score
      const { data: pData } = await supabaseClient
        .from('players')
        .select('cumulative_score')
        .eq('player_uid', playerUid)
        .single();
      
      const currentScore = pData?.cumulative_score || 0;
      await supabaseClient
        .from('players')
        .update({ cumulative_score: currentScore + points })
        .eq('player_uid', playerUid);
    }

    // 4. Update session status to 'timer_expired'
    await supabaseClient
      .from('game_sessions')
      .update({ status: 'timer_expired' })
      .eq('id', session_id);

    return new Response(
      JSON.stringify({
        success: true,
        evaluated_count: answers?.length || 0,
        correct_option: question.correct_option
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    );

  } catch (error) {
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    );
  }
});
