-- Migration: Add ad_slides and is_ad_mode_active to game_sessions table
-- Date: 2026-11-09

ALTER TABLE public.game_sessions 
    ADD COLUMN IF NOT EXISTS is_ad_mode_active BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS ad_slide_duration_seconds INT DEFAULT 20,
    ADD COLUMN IF NOT EXISTS ad_slides JSONB DEFAULT '[]'::jsonb;
