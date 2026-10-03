/**
 * Automated Weekly Trivia Ingestion Script for Bar Room Trivia
 * Ingests 100+ fresh questions weekly combining:
 * 1. The Trivia API (https://the-trivia-api.com) - 50 questions
 * 2. Open Trivia Database (https://opentdb.com) - 50 questions
 *
 * Normalizes categories, formats 4 choices (A, B, C, D),
 * deduplicates questions, and upserts into Supabase public.questions
 * and updates local JSON question cache.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// Category mapping to BarRoomTrivia 30 standard genres
const GENRE_MAPPING = {
  // The Trivia API mappings
  'music': 'Rock & Roll Classics',
  'sport_and_leisure': 'Sports & Stadiums',
  'film_and_tv': 'Movies & Hollywood',
  'arts_and_literature': 'Classic Literature',
  'history': 'World History',
  'society_and_culture': 'World History',
  'science': 'Science & Technology',
  'geography': 'World Geography',
  'food_and_drink': 'Food & Culinary',
  'general_knowledge': 'Pop Culture & Music',

  // OpenTDB mappings
  'Sports': 'Sports & Stadiums',
  'History': 'World History',
  'Geography': 'World Geography',
  'Science & Nature': 'Science & Technology',
  'Science: Computers': 'Science & Technology',
  'Science: Gadgets': 'Science & Technology',
  'Mythology': 'Mythology & Folklore',
  'Entertainment: Music': 'Rock & Roll Classics',
  'Entertainment: Film': 'Movies & Hollywood',
  'Entertainment: Television': 'Sitcoms & TV Dramas',
  'Entertainment: Video Games': 'Video Games & Gaming',
  'Entertainment: Board Games': 'Mind Benders & Riddles',
  'Entertainment: Books': 'Classic Literature',
  'Entertainment: Comics': 'Comics & Superheroes',
  'Entertainment: Musicals & Theatres': 'Broadway & Theater',
  'Entertainment: Japanese Anime & Manga': 'Pop Culture & Music',
  'Entertainment: Cartoon & Animations': 'Pop Culture & Music',
  'General Knowledge': 'Pop Culture & Music',
  'Celebrities': 'Pop Culture & Music',
  'Animals': 'Wildlife & Nature',
  'Vehicles': 'Automotive & Racing',
  'Art': 'Art & Architecture',
  'Politics': 'World History'
};

function decodeHTMLEntities(str) {
  if (!str) return '';
  return str
    .replace(/&quot;/g, '"')
    .replace(/&#039;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&eacute;/g, 'é')
    .replace(/&rsquo;/g, "'")
    .replace(/&ldquo;/g, '"')
    .replace(/&rdquo;/g, '"')
    .replace(/&hellip;/g, '...')
    .replace(/&trade;/g, '™')
    .replace(/&deg;/g, '°')
    .trim();
}

function cleanQuestionText(raw) {
  let text = decodeHTMLEntities(raw);
  return text
    .replace(/\s*\([^)]*#(?:\d+|INDEX)[^)]*\)/gi, '')
    .replace(/\s*#\d+\b/g, '')
    .replace(/\s+\?/g, '?')
    .trim();
}

function computeQuestionHash(text) {
  const normalized = text.toLowerCase().replace(/[^a-z0-9]/g, '');
  return crypto.createHash('sha256').update(normalized).digest('hex');
}

function shuffleArray(arr) {
  const shuffled = [...arr];
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
  }
  return shuffled;
}

/**
 * Fetch 50 questions from The Trivia API
 */
async function fetchTheTriviaApiQuestions() {
  console.log('Fetching questions from The Trivia API (50 questions)...');
  try {
    const res = await fetch('https://the-trivia-api.com/v2/questions?limit=50', {
      headers: { 'Accept': 'application/json' },
      signal: AbortSignal.timeout(10000)
    });
    if (!res.ok) {
      throw new Error(`The Trivia API returned HTTP ${res.status}`);
    }
    const data = await res.json();
    console.log(`✓ Received ${data.length} questions from The Trivia API`);

    const formatted = [];
    for (const item of data) {
      if (!item.question || !item.question.text || !item.correctAnswer || !Array.isArray(item.incorrectAnswers) || item.incorrectAnswers.length < 3) {
        continue;
      }
      const qText = cleanQuestionText(item.question.text);
      const correctText = decodeHTMLEntities(item.correctAnswer);
      const incorrectTexts = item.incorrectAnswers.slice(0, 3).map(decodeHTMLEntities);

      // Unique options validation
      const allOptTexts = [correctText, ...incorrectTexts];
      if (new Set(allOptTexts.map(t => t.toLowerCase())).size < 4) {
        continue; // skip if any duplicates in options
      }

      const shuffled = shuffleArray(allOptTexts);
      const optA = shuffled[0];
      const optB = shuffled[1];
      const optC = shuffled[2];
      const optD = shuffled[3];

      let correctOpt = 'A';
      if (optB === correctText) correctOpt = 'B';
      else if (optC === correctText) correctOpt = 'C';
      else if (optD === correctText) correctOpt = 'D';

      const mappedCategory = GENRE_MAPPING[item.category] || 'Pop Culture & Music';

      formatted.push({
        id: `tta-${item.id || computeQuestionHash(qText).substring(0, 12)}`,
        question_hash: computeQuestionHash(qText),
        category: mappedCategory,
        difficulty: item.difficulty ? item.difficulty.charAt(0).toUpperCase() + item.difficulty.slice(1) : 'Standard',
        question_text: qText,
        option_a: optA,
        option_b: optB,
        option_c: optC,
        option_d: optD,
        correct_option: correctOpt,
        time_limit_seconds: 20,
        source: 'the-trivia-api'
      });
    }
    return formatted;
  } catch (err) {
    console.error('Error fetching from The Trivia API:', err.message);
    return [];
  }
}

/**
 * Fetch 50 questions from Open Trivia Database (OpenTDB)
 */
async function fetchOpenTdbQuestions() {
  console.log('Fetching questions from Open Trivia Database (50 questions)...');
  try {
    const res = await fetch('https://opentdb.com/api.php?amount=50&type=multiple', {
      signal: AbortSignal.timeout(10000)
    });
    if (!res.ok) {
      throw new Error(`OpenTDB returned HTTP ${res.status}`);
    }
    const data = await res.json();
    if (data.response_code !== 0 || !Array.isArray(data.results)) {
      throw new Error(`OpenTDB response code: ${data.response_code}`);
    }
    console.log(`✓ Received ${data.results.length} questions from OpenTDB`);

    const formatted = [];
    for (const item of data.results) {
      if (!item.question || !item.correct_answer || !Array.isArray(item.incorrect_answers) || item.incorrect_answers.length < 3) {
        continue;
      }
      const qText = cleanQuestionText(item.question);
      const correctText = decodeHTMLEntities(item.correct_answer);
      const incorrectTexts = item.incorrect_answers.slice(0, 3).map(decodeHTMLEntities);

      const allOptTexts = [correctText, ...incorrectTexts];
      if (new Set(allOptTexts.map(t => t.toLowerCase())).size < 4) {
        continue;
      }

      const shuffled = shuffleArray(allOptTexts);
      const optA = shuffled[0];
      const optB = shuffled[1];
      const optC = shuffled[2];
      const optD = shuffled[3];

      let correctOpt = 'A';
      if (optB === correctText) correctOpt = 'B';
      else if (optC === correctText) correctOpt = 'C';
      else if (optD === correctText) correctOpt = 'D';

      const mappedCategory = GENRE_MAPPING[item.category] || 'Pop Culture & Music';

      formatted.push({
        id: `otdb-${computeQuestionHash(qText).substring(0, 12)}`,
        question_hash: computeQuestionHash(qText),
        category: mappedCategory,
        difficulty: item.difficulty ? item.difficulty.charAt(0).toUpperCase() + item.difficulty.slice(1) : 'Standard',
        question_text: qText,
        option_a: optA,
        option_b: optB,
        option_c: optC,
        option_d: optD,
        correct_option: correctOpt,
        time_limit_seconds: 20,
        source: 'opentdb'
      });
    }
    return formatted;
  } catch (err) {
    console.error('Error fetching from OpenTDB:', err.message);
    return [];
  }
}

async function run() {
  const isDryRun = process.argv.includes('--dry-run');
  console.log(`=== BarRoomTrivia Weekly Ingestion Starting (Dry Run: ${isDryRun}) ===`);

  // 1. Fetch from BOTH free services
  const ttaQuestions = await fetchTheTriviaApiQuestions();
  const otdbQuestions = await fetchOpenTdbQuestions();

  const combined = [...ttaQuestions, ...otdbQuestions];
  console.log(`Total questions retrieved: ${combined.length}`);

  // 2. Deduplicate within this batch
  const seenHashes = new Set();
  const uniqueBatch = [];
  for (const q of combined) {
    if (!seenHashes.has(q.question_hash)) {
      seenHashes.add(q.question_hash);
      uniqueBatch.push(q);
    }
  }
  console.log(`Unique questions in this batch: ${uniqueBatch.length}`);

  // 3. Update local bundle files (for offline client fallback & GitHub Pages)
  const bundlePaths = [
    path.join(__dirname, '..', 'public', 'data', 'weekly_trivia_pack.json'),
    path.join(__dirname, '..', 'assets', 'data', 'weekly_trivia_pack.json')
  ];

  for (const bundlePath of bundlePaths) {
    try {
      const dir = path.dirname(bundlePath);
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }

      let existing = [];
      if (fs.existsSync(bundlePath)) {
        try {
          existing = JSON.parse(fs.readFileSync(bundlePath, 'utf8'));
          if (!Array.isArray(existing)) existing = [];
        } catch (_) {
          existing = [];
        }
      }

      const existingHashes = new Set(existing.map(q => q.question_hash || computeQuestionHash(q.question_text || '')));
      let newlyAdded = 0;

      for (const q of uniqueBatch) {
        if (!existingHashes.has(q.question_hash)) {
          existingHashes.add(q.question_hash);
          existing.unshift(q); // Newest questions first
          newlyAdded++;
        }
      }

      // Cap bundle at 1,000 recent questions to maintain high performance
      const trimmed = existing.slice(0, 1000);
      fs.writeFileSync(bundlePath, JSON.stringify(trimmed, null, 2), 'utf8');
      console.log(`✓ Updated bundle at ${bundlePath}: +${newlyAdded} new questions (total: ${trimmed.length})`);
    } catch (e) {
      console.warn(`Could not write to ${bundlePath}:`, e.message);
    }
  }

  // 4. Upsert into Supabase database (if credentials available and not dry run)
  const supabaseUrl = process.env.SUPABASE_URL || 'https://tzdikvbvdvgjaiznqkcd.supabase.co';
  const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InR6ZGlrdmJ2ZHZnamFpem5xa2NkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDAxNTMwNzksImV4cCI6MjA1NTcyOTA3OX0.12k3oY1iO6wYk_hJ8e2V0n1QY-B5-v1XyPZ47_3q1W8';

  if (!isDryRun && supabaseUrl && supabaseKey) {
    try {
      const { createClient } = require('@supabase/supabase-js');
      const supabase = createClient(supabaseUrl, supabaseKey, {
        auth: { persistSession: false }
      });

      console.log(`Connecting to Supabase at ${supabaseUrl}...`);
      
      // Upsert in chunks of 25
      let insertedCount = 0;
      for (let i = 0; i < uniqueBatch.length; i += 25) {
        const chunk = uniqueBatch.slice(i, i + 25);
        const { data, error } = await supabase
          .from('questions')
          .upsert(
            chunk.map(q => ({
              category: q.category,
              difficulty: q.difficulty.toLowerCase() === 'hard' ? 'hard' : (q.difficulty.toLowerCase() === 'easy' ? 'easy' : 'medium'),
              question_text: q.question_text,
              option_a: q.option_a,
              option_b: q.option_b,
              option_c: q.option_c,
              option_d: q.option_d,
              correct_option: q.correct_option,
              time_limit_seconds: q.time_limit_seconds
            })),
            { onConflict: 'question_text', ignoreDuplicates: true }
          );

        if (error) {
          console.warn(`Supabase upsert chunk warning:`, error.message);
        } else {
          insertedCount += chunk.length;
        }
      }
      console.log(`✓ Supabase ingestion complete. Attempted ${insertedCount} questions.`);
    } catch (sbErr) {
      console.warn(`Supabase connection skipped or failed: ${sbErr.message}`);
    }
  }

  console.log('=== BarRoomTrivia Weekly Ingestion Completed Successfully ===');
}

run().catch(err => {
  console.error('Fatal ingestion error:', err);
  process.exit(1);
});
