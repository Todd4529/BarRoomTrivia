-- Migration: Purge AI-Generated and Synthetic Specialty Genre Questions
-- Description: Removes all questions belonging to removed AI specialty categories
-- and any synthetic template generated questions (univ_*, fill_*, gen_*).
-- Date: 2026-10-07

-- 1. Delete questions that belong to removed synthetic specialty categories
DELETE FROM public.questions
WHERE category NOT IN (
    '80s & 90s Nostalgia',
    'Art & Architecture',
    'Automotive & Racing',
    'Beer, Wine & Spirits',
    'Classic Literature',
    'Comics & Superheroes',
    'Food & Culinary',
    'Homebrewing Beer',
    'Mind Benders & Riddles',
    'Movies & Hollywood',
    'Mythology & Folklore',
    'Pop Culture & Music',
    'Rock & Roll Classics',
    'Science & Technology',
    'Sitcoms & TV Dramas',
    'Sports & Stadiums',
    'Video Games & Gaming',
    'Wildlife & Nature',
    'World Geography',
    'World History',
    -- General fallback categories
    'General Knowledge',
    'General Trivia'
);

-- 2. Delete any lingering synthetic/template/AI questions by ID prefix pattern or synthetic stems
DELETE FROM public.questions
WHERE id::text LIKE 'fill_%'
   OR id::text LIKE 'univ_%'
   OR id::text LIKE 'gen_%'
   OR question_text ILIKE '%signature achievement or core definition%'
   OR question_text ILIKE '%authoritative retrospectives%'
   OR question_text ILIKE '%fundamental fact is recognized about%'
   OR question_text ILIKE '%In classic universal knowledge%';
