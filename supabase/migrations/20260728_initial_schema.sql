-- Bar Roomss Trivia Schema & RLS Policies
-- Date: 2026-07-28

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. SUBSCRIPTIONS TABLE (B2B Bar Licensing)
CREATE TABLE IF NOT EXISTS public.subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    bar_name TEXT NOT NULL,
    plan_type TEXT NOT NULL DEFAULT 'standard_monthly', -- 'trial', 'standard_monthly', 'enterprise'
    status TEXT NOT NULL DEFAULT 'active', -- 'active', 'past_due', 'canceled'
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. QUESTIONS TABLE (Trivia Bank)
CREATE TABLE IF NOT EXISTS public.questions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category TEXT NOT NULL,
    difficulty TEXT NOT NULL DEFAULT 'medium', -- 'easy', 'medium', 'hard'
    question_text TEXT NOT NULL,
    option_a TEXT NOT NULL,
    option_b TEXT NOT NULL,
    option_c TEXT NOT NULL,
    option_d TEXT NOT NULL,
    correct_option CHAR(1) NOT NULL CHECK (correct_option IN ('A', 'B', 'C', 'D')),
    time_limit_seconds INT NOT NULL DEFAULT 20,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. GAME SESSIONS TABLE
CREATE TABLE IF NOT EXISTS public.game_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    room_code VARCHAR(10) UNIQUE NOT NULL,
    host_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'lobby', -- 'lobby', 'question_active', 'timer_expired', 'round_ended', 'completed'
    current_question_id UUID REFERENCES public.questions(id) ON DELETE SET NULL,
    question_index INT DEFAULT 0,
    timer_ends_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. PLAYERS TABLE (Anonymous & Authenticated Users)
CREATE TABLE IF NOT EXISTS public.players (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_uid UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    room_code VARCHAR(10) NOT NULL REFERENCES public.game_sessions(room_code) ON DELETE CASCADE,
    nickname VARCHAR(30) NOT NULL,
    cumulative_score INT NOT NULL DEFAULT 0,
    is_connected BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_player_per_room UNIQUE (room_code, player_uid)
);

-- 6. PLAYER ANSWERS TABLE
CREATE TABLE IF NOT EXISTS public.player_answers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES public.game_sessions(id) ON DELETE CASCADE,
    question_id UUID NOT NULL REFERENCES public.questions(id) ON DELETE CASCADE,
    player_uid UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    selected_option CHAR(1) NOT NULL CHECK (selected_option IN ('A', 'B', 'C', 'D')),
    is_correct BOOLEAN DEFAULT NULL, -- Calculated server-side by Edge Function
    score_awarded INT DEFAULT 0,     -- Calculated server-side by Edge Function
    submitted_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_answer_per_question UNIQUE (session_id, question_id, player_uid)
);

-- 7. INDEXES FOR HIGH-PERFORMANCE LOOKUPS & REALTIME
CREATE INDEX IF NOT EXISTS idx_game_sessions_room ON public.game_sessions(room_code);
CREATE INDEX IF NOT EXISTS idx_players_room_score ON public.players(room_code, cumulative_score DESC);
CREATE INDEX IF NOT EXISTS idx_player_answers_session_q ON public.player_answers(session_id, question_id);

-- 8. ROW LEVEL SECURITY (RLS) POLICIES

-- Subscriptions RLS
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Hosts can read their own subscriptions" 
    ON public.subscriptions FOR SELECT 
    USING (auth.uid() = user_id);

CREATE POLICY "Hosts can update their own subscriptions" 
    ON public.subscriptions FOR UPDATE 
    USING (auth.uid() = user_id);

-- Game Sessions RLS
ALTER TABLE public.game_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view active game sessions" 
    ON public.game_sessions FOR SELECT 
    USING (true);

CREATE POLICY "Hosts can create game sessions" 
    ON public.game_sessions FOR INSERT 
    WITH CHECK (auth.uid() = host_id);

CREATE POLICY "Hosts can update their game sessions" 
    ON public.game_sessions FOR UPDATE 
    USING (auth.uid() = host_id);

-- Questions RLS
ALTER TABLE public.questions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone authenticated or anon can read questions" 
    ON public.questions FOR SELECT 
    USING (true);

-- Players RLS
ALTER TABLE public.players ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read leaderboard players for room" 
    ON public.players FOR SELECT 
    USING (true);

CREATE POLICY "Players can register themselves in a room" 
    ON public.players FOR INSERT 
    WITH CHECK (auth.uid() = player_uid);

CREATE POLICY "Players can update their status" 
    ON public.players FOR UPDATE 
    USING (auth.uid() = player_uid);

-- Player Answers RLS
ALTER TABLE public.player_answers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Players can insert their own answer" 
    ON public.player_answers FOR INSERT 
    WITH CHECK (auth.uid() = player_uid);

CREATE POLICY "Players can view their own submitted answers" 
    ON public.player_answers FOR SELECT 
    USING (auth.uid() = player_uid);

-- Enable Realtime for Broadcast and Database Changes
ALTER PUBLICATION supabase_realtime ADD TABLE public.game_sessions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.players;
