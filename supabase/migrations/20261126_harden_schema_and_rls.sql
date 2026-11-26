-- Migration: Add remaining session/player sync columns & harden RLS policies
-- Date: 2026-11-26

-- 1. Missing sync columns referenced by Web & Flutter clients
ALTER TABLE public.game_sessions
    ADD COLUMN IF NOT EXISTS leaderboard_cleared_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS inter_round_duration INT DEFAULT 120,
    ADD COLUMN IF NOT EXISTS paused_at TIMESTAMPTZ;

ALTER TABLE public.players
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- Allow players table to track players cleanly by room_code + nickname when anonymous auth is unavailable
CREATE UNIQUE INDEX IF NOT EXISTS players_room_code_nickname_lower_idx
    ON public.players (room_code, LOWER(nickname));

-- 2. Harden subscriptions RLS: users may read their own subscription, but cannot self-upgrade plan/expiry via client API
DROP POLICY IF EXISTS "Hosts can update their own subscriptions" ON public.subscriptions;

-- 3. Remove open anonymous INSERT on public.questions (service_role bypasses RLS for automated ingestion)
DROP POLICY IF EXISTS "Allow automated weekly ingestion inserts" ON public.questions;
DROP POLICY IF EXISTS "Anyone can insert questions" ON public.questions;

-- 4. Tighten game_sessions & players policies to require non-empty room_code and authenticated/anon role scope
DROP POLICY IF EXISTS "Anyone can insert game sessions" ON public.game_sessions;
DROP POLICY IF EXISTS "Anyone can update active game sessions" ON public.game_sessions;

CREATE POLICY "Authenticated or anon can insert valid game sessions"
    ON public.game_sessions FOR INSERT
    WITH CHECK (
        room_code IS NOT NULL
        AND length(trim(room_code)) BETWEEN 3 AND 16
        AND (host_id IS NULL OR host_id = auth.uid())
    );

CREATE POLICY "Session host or unclaimed room can update game sessions"
    ON public.game_sessions FOR UPDATE
    USING (host_id IS NULL OR host_id = auth.uid())
    WITH CHECK (host_id IS NULL OR host_id = auth.uid());

DROP POLICY IF EXISTS "Anyone can register room players" ON public.players;
DROP POLICY IF EXISTS "Anyone can update room players" ON public.players;
DROP POLICY IF EXISTS "Anyone can delete room players" ON public.players;

CREATE POLICY "Players can register in an existing room"
    ON public.players FOR INSERT
    WITH CHECK (
        room_code IS NOT NULL
        AND length(trim(nickname)) BETWEEN 1 AND 30
        AND (player_uid = auth.uid() OR auth.role() = 'service_role')
    );

CREATE POLICY "Player or room host can update player record"
    ON public.players FOR UPDATE
    USING (
        player_uid = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.game_sessions gs
            WHERE gs.room_code = players.room_code
              AND (gs.host_id = auth.uid() OR gs.host_id IS NULL)
        )
    )
    WITH CHECK (
        player_uid = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.game_sessions gs
            WHERE gs.room_code = players.room_code
              AND (gs.host_id = auth.uid() OR gs.host_id IS NULL)
        )
    );

CREATE POLICY "Room host can delete room players"
    ON public.players FOR DELETE
    USING (
        player_uid = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.game_sessions gs
            WHERE gs.room_code = players.room_code
              AND (gs.host_id = auth.uid() OR gs.host_id IS NULL)
        )
    );
