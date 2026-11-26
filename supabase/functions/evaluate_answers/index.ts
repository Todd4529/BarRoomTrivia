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
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? serviceRoleKey;

    const authHeader = req.headers.get('Authorization') ?? '';
    if (!authHeader.startsWith('Bearer ')) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized: missing bearer token' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 401 }
      );
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData?.user) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized: invalid user token' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 401 }
      );
    }

    const supabaseClient = createClient(supabaseUrl, serviceRoleKey);
    const { session_id, question_id }: EvaluateRequest = await req.json();

    if (!session_id || !question_id) {
      return new Response(
        JSON.stringify({ error: 'Missing session_id or question_id' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      );
    }

    // 1. Verify caller owns the game session and check timer expiration
    const { data: session, error: sError } = await supabaseClient
      .from('game_sessions')
      .select('id, room_code, host_id, timer_ends_at')
      .eq('id', session_id)
      .single();

    if (sError || !session) {
      return new Response(
        JSON.stringify({ error: 'Game session not found' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 404 }
      );
    }

    if (session.host_id && session.host_id !== authData.user.id) {
      return new Response(
        JSON.stringify({ error: 'Forbidden: only the session host can evaluate answers' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 403 }
      );
    }

    if (session.timer_ends_at && new Date(session.timer_ends_at).getTime() > Date.now() + 2000) {
      return new Response(
        JSON.stringify({ error: 'Timer has not expired yet' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 409 }
      );
    }

    // 2. Fetch the correct question answer
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

    // 3. Fetch ONLY un-evaluated answers (idempotent against duplicate calls)
    const { data: answers, error: aError } = await supabaseClient
      .from('player_answers')
      .select('id, player_uid, selected_option, submitted_at')
      .eq('session_id', session_id)
      .eq('question_id', question_id)
      .is('is_correct', null);

    if (aError) {
      throw aError;
    }

    const scoreMap: Record<string, number> = {};
    const updatePromises = [];

    for (const ans of (answers || [])) {
      const isCorrect = ans.selected_option.trim().toUpperCase() === question.correct_option.trim().toUpperCase();
      // Matches live client scoring: flat 10 points per correct answer
      const scoreAwarded = isCorrect ? 10 : 0;

      updatePromises.push(
        supabaseClient
          .from('player_answers')
          .update({
            is_correct: isCorrect,
            score_awarded: scoreAwarded,
          })
          .eq('id', ans.id)
          .is('is_correct', null)
          .select('id')
      );

      if (isCorrect) {
        scoreMap[ans.player_uid] = (scoreMap[ans.player_uid] || 0) + scoreAwarded;
      }
    }

    const answerResults = await Promise.all(updatePromises);
    for (const r of answerResults) {
      if (r.error) throw r.error;
    }

    // 4. Update cumulative scores scoped strictly to this session's room_code
    for (const [playerUid, points] of Object.entries(scoreMap)) {
      const { data: pData, error: pFetchErr } = await supabaseClient
        .from('players')
        .select('cumulative_score')
        .eq('room_code', session.room_code)
        .eq('player_uid', playerUid)
        .maybeSingle();

      if (pFetchErr || !pData) continue;

      const currentScore = pData.cumulative_score || 0;
      const { error: pUpdateErr } = await supabaseClient
        .from('players')
        .update({ cumulative_score: currentScore + points, updated_at: new Date().toISOString() })
        .eq('room_code', session.room_code)
        .eq('player_uid', playerUid);

      if (pUpdateErr) throw pUpdateErr;
    }

    // 5. Update session status to 'timer_expired'
    const { error: statusErr } = await supabaseClient
      .from('game_sessions')
      .update({ status: 'timer_expired', updated_at: new Date().toISOString() })
      .eq('id', session_id);
    if (statusErr) throw statusErr;

    return new Response(
      JSON.stringify({
        success: true,
        evaluated_count: answers?.length || 0,
        correct_option: question.correct_option,
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
