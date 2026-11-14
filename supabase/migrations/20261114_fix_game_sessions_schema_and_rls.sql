-- Migration: Ensure game_sessions schema completeness & anon/authenticated RLS policies
-- Date: 2026-11-14

ALTER TABLE public.game_sessions
    ADD COLUMN IF NOT EXISTS current_question_index INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS current_round INT DEFAULT 1,
    ADD COLUMN IF NOT EXISTS round_number INT DEFAULT 1,
    ADD COLUMN IF NOT EXISTS timer_state TEXT DEFAULT 'idle',
    ADD COLUMN IF NOT EXISTS game_play_mode TEXT DEFAULT 'Auto',
    ADD COLUMN IF NOT EXISTS genre TEXT,
    ADD COLUMN IF NOT EXISTS category TEXT,
    ADD COLUMN IF NOT EXISTS difficulty TEXT,
    ADD COLUMN IF NOT EXISTS question_text TEXT,
    ADD COLUMN IF NOT EXISTS options JSONB,
    ADD COLUMN IF NOT EXISTS correct_index INT,
    ADD COLUMN IF NOT EXISTS question_data JSONB,
    ADD COLUMN IF NOT EXISTS current_question_data JSONB,
    ADD COLUMN IF NOT EXISTS duration_seconds INT DEFAULT 20,
    ADD COLUMN IF NOT EXISTS remaining_question_seconds INT DEFAULT 20,
    ADD COLUMN IF NOT EXISTS starts_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS round_ends_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS timer_ends_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS is_sound_effects_enabled BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

CREATE UNIQUE INDEX IF NOT EXISTS game_sessions_room_code_idx
    ON public.game_sessions (room_code);

-- Replace restrictive host-only policies so anon/authenticated hosts, TVs, and players can sync live sessions
DROP POLICY IF EXISTS "Hosts can create game sessions" ON public.game_sessions;
DROP POLICY IF EXISTS "Hosts can update their game sessions" ON public.game_sessions;
DROP POLICY IF EXISTS "Anyone can manage active game sessions" ON public.game_sessions;

CREATE POLICY "Anyone can insert game sessions"
    ON public.game_sessions FOR INSERT
    WITH CHECK (true);

CREATE POLICY "Anyone can update active game sessions"
    ON public.game_sessions FOR UPDATE
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "Players can register themselves in a room" ON public.players;
DROP POLICY IF EXISTS "Players can update their status" ON public.players;
DROP POLICY IF EXISTS "Anyone can delete room players" ON public.players;

CREATE POLICY "Anyone can register room players"
    ON public.players FOR INSERT
    WITH CHECK (true);

CREATE POLICY "Anyone can update room players"
    ON public.players FOR UPDATE
    USING (true)
    WITH CHECK (true);

CREATE POLICY "Anyone can delete room players"
    ON public.players FOR DELETE
    USING (true);
