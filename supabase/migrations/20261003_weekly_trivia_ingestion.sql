-- Migration: Add deduplication hash & ensure ingestion permissions
-- Date: 2026-10-03

-- 1. Add question_hash column if not already existing
ALTER TABLE public.questions 
    ADD COLUMN IF NOT EXISTS question_hash TEXT;

-- 2. Add source column to track provenance (the-trivia-api, opentdb, manual)
ALTER TABLE public.questions 
    ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'system';

-- 3. Unique index for question deduplication
CREATE UNIQUE INDEX IF NOT EXISTS idx_questions_hash_unique 
    ON public.questions (question_hash) 
    WHERE question_hash IS NOT NULL;

-- 4. Unique index on normalized question text as fallback deduplication
CREATE UNIQUE INDEX IF NOT EXISTS idx_questions_text_unique 
    ON public.questions (LOWER(TRIM(question_text)));

-- 5. Index for fast weekly delta queries
CREATE INDEX IF NOT EXISTS idx_questions_created_at 
    ON public.questions (created_at DESC);

-- 6. Ensure insertion policy for questions table
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'questions' AND policyname = 'Allow question inserts for ingestion'
    ) THEN
        CREATE POLICY "Allow question inserts for ingestion" 
            ON public.questions FOR INSERT 
            WITH CHECK (true);
    END IF;
END $$;
