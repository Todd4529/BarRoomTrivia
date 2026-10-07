/**
 * Bulk Question Downloader for Bar Room Trivia
 * Downloads hundreds to thousands of verified, authentic trivia questions
 * from The Trivia API and Open Trivia Database (OpenTDB).
 *
 * Normalizes, cleans, formats 4 choices (A, B, C, D),
 * deduplicates questions using SHA-256 hashes,
 * and updates:
 *   - assets/data/weekly_trivia_pack.json (Flutter asset bundle)
 *   - public/data/weekly_trivia_pack.json (Vite public dev/prod bundle)
 *   - dist/data/weekly_trivia_pack.json (Production distribution)
 *   - Supabase public.questions table (if online credentials available)
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// Category mapping to BarRoomTrivia official 34 genres
const GENRE_MAPPING = {
  // The Trivia API
  'music': 'Rock & Roll Classics',
  'sport_and_leisure': 'Sports & Stadiums',
  'film_and_tv': 'Movies & Hollywood',
  'arts_and_literature': 'Classic Literature',
  'history': 'World History',
  'society_and_culture': 'World History',
  'science': 'Science & Technology',
  'geography': 'World Geography',
  'food_and_drink': 'Food & Culinary',
  'food_and_drink_alcohol': 'Beer, Wine & Spirits',
  'general_knowledge': 'Pop Culture & Music',

  // OpenTDB Categories
  'General Knowledge': 'Pop Culture & Music',
  'Entertainment: Books': 'Classic Literature',
  'Entertainment: Film': 'Movies & Hollywood',
  'Entertainment: Music': 'Rock & Roll Classics',
  'Entertainment: Musicals & Theatres': 'Broadway & Theater',
  'Entertainment: Television': 'Sitcoms & TV Dramas',
  'Entertainment: Video Games': 'Video Games & Gaming',
  'Entertainment: Board Games': 'Mind Benders & Riddles',
  'Science & Nature': 'Science & Technology',
  'Science: Computers': 'Science & Technology',
  'Science: Mathematics': 'Mind Benders & Riddles',
  'Science: Gadgets': 'Science & Technology',
  'Mythology': 'Mythology & Folklore',
  'Sports': 'Sports & Stadiums',
  'Geography': 'World Geography',
  'History': 'World History',
  'Politics': 'World History',
  'Art': 'Art & Architecture',
  'Celebrities': 'Pop Culture & Music',
  'Animals': 'Wildlife & Nature',
  'Vehicles': 'Automotive & Racing',
  'Entertainment: Comics': 'Comics & Superheroes',
  'Entertainment: Japanese Anime & Manga': 'Pop Culture & Music',
  'Entertainment: Cartoon & Animations': '80s & 90s Nostalgia'
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
    .replace(/&lsquo;/g, "'")
    .replace(/&ldquo;/g, '"')
    .replace(/&rdquo;/g, '"')
    .replace(/&hellip;/g, '...')
    .replace(/&trade;/g, '™')
    .replace(/&deg;/g, '°')
    .replace(/&Ouml;/g, 'Ö')
    .replace(/&ouml;/g, 'ö')
    .replace(/&uuml;/g, 'ü')
    .replace(/&auml;/g, 'ä')
    .replace(/&Uuml;/g, 'Ü')
    .replace(/&Auml;/g, 'Ä')
    .replace(/&ntilde;/g, 'ñ')
    .replace(/&aacute;/g, 'á')
    .replace(/&iacute;/g, 'í')
    .replace(/&oacute;/g, 'ó')
    .replace(/&uacute;/g, 'ú')
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

const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

/**
 * Fetch a batch from The Trivia API
 */
async function fetchTheTriviaApiBatch(category, tags = '', difficulty = '') {
  try {
    let url = `https://the-trivia-api.com/v2/questions?limit=50&categories=${encodeURIComponent(category)}`;
    if (tags) url += `&tags=${encodeURIComponent(tags)}`;
    if (difficulty) url += `&difficulties=${encodeURIComponent(difficulty)}`;

    const res = await fetch(url, {
      headers: { 'Accept': 'application/json' },
      signal: AbortSignal.timeout(10000)
    });
    if (!res.ok) {
      return [];
    }
    const data = await res.json();
    if (!Array.isArray(data)) return [];

    const formatted = [];
    for (const item of data) {
      if (!item.question || !item.question.text || !item.correctAnswer || !Array.isArray(item.incorrectAnswers) || item.incorrectAnswers.length < 3) {
        continue;
      }
      const qText = cleanQuestionText(item.question.text);
      const correctText = decodeHTMLEntities(item.correctAnswer);
      const incorrectTexts = item.incorrectAnswers.slice(0, 3).map(decodeHTMLEntities);

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

      let mappedCategory = GENRE_MAPPING[item.category] || 'Pop Culture & Music';
      if ((tags && tags.includes('alcohol')) || (item.tags && item.tags.some(t => ['alcohol', 'beer', 'wine', 'cocktails', 'drink', 'liquor'].includes(t.toLowerCase())))) {
        mappedCategory = 'Beer, Wine & Spirits';
      }

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
    return [];
  }
}

/**
 * Fetch a batch from Open Trivia Database (OpenTDB) with retry
 */
async function fetchOpenTdbBatch(categoryId, categoryName, retries = 2) {
  try {
    const url = `https://opentdb.com/api.php?amount=50&category=${categoryId}&type=multiple`;
    const res = await fetch(url, { signal: AbortSignal.timeout(10000) });
    if (res.status === 429 && retries > 0) {
      process.stdout.write(` (429, waiting 5.5s)... `);
      await sleep(5500);
      return fetchOpenTdbBatch(categoryId, categoryName, retries - 1);
    }
    if (!res.ok) {
      return [];
    }
    const data = await res.json();
    if (data.response_code !== 0 || !Array.isArray(data.results)) {
      return [];
    }

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

      const mappedCategory = GENRE_MAPPING[categoryName] || GENRE_MAPPING[item.category] || 'Pop Culture & Music';

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
    return [];
  }
}

async function bulkDownload() {
  console.log('====================================================');
  console.log('🚀 STARTING COMPREHENSIVE REAL TRIVIA BULK DOWNLOAD');
  console.log('====================================================');

  const allDownloaded = [];
  const seenHashes = new Set();

  // Load existing questions first
  const primaryPackPath = path.join(__dirname, '..', 'assets', 'data', 'weekly_trivia_pack.json');
  if (fs.existsSync(primaryPackPath)) {
    try {
      const existing = JSON.parse(fs.readFileSync(primaryPackPath, 'utf8'));
      if (Array.isArray(existing)) {
        for (const q of existing) {
          if (q.question_hash) seenHashes.add(q.question_hash);
          allDownloaded.push(q);
        }
      }
      console.log(`Loaded ${allDownloaded.length} existing questions from local pack.`);
    } catch (_) {}
  }

  // 1. Download from The Trivia API across multiple categories, tags & difficulties
  console.log('\n--- 1. Fetching from The Trivia API (Multi-Difficulty & Tags) ---');
  const ttaQueries = [
    // Music (Rock & Roll)
    { cat: 'music', diff: 'easy' },
    { cat: 'music', diff: 'medium' },
    { cat: 'music', diff: 'hard' },

    // Food & Drink / Beer, Wine & Spirits
    { cat: 'food_and_drink', tags: 'alcohol,drink,beer,wine,cocktails' },
    { cat: 'food_and_drink', diff: 'easy' },
    { cat: 'food_and_drink', diff: 'medium' },
    { cat: 'food_and_drink', diff: 'hard' },

    // Film & TV
    { cat: 'film_and_tv', diff: 'easy' },
    { cat: 'film_and_tv', diff: 'medium' },
    { cat: 'film_and_tv', diff: 'hard' },

    // Sports & Leisure
    { cat: 'sport_and_leisure', diff: 'easy' },
    { cat: 'sport_and_leisure', diff: 'medium' },
    { cat: 'sport_and_leisure', diff: 'hard' },

    // World History & Society
    { cat: 'history', diff: 'easy' },
    { cat: 'history', diff: 'medium' },
    { cat: 'history', diff: 'hard' },
    { cat: 'society_and_culture', diff: 'medium' },

    // Science & Tech
    { cat: 'science', diff: 'easy' },
    { cat: 'science', diff: 'medium' },
    { cat: 'science', diff: 'hard' },

    // Geography
    { cat: 'geography', diff: 'easy' },
    { cat: 'geography', diff: 'medium' },
    { cat: 'geography', diff: 'hard' },

    // Literature & Arts
    { cat: 'arts_and_literature', diff: 'easy' },
    { cat: 'arts_and_literature', diff: 'medium' },
    { cat: 'arts_and_literature', diff: 'hard' },

    // General Knowledge / Pop Culture
    { cat: 'general_knowledge', diff: 'easy' },
    { cat: 'general_knowledge', diff: 'medium' },
    { cat: 'general_knowledge', diff: 'hard' }
  ];

  for (const q of ttaQueries) {
    process.stdout.write(`Fetching The Trivia API: [${q.cat}] (${q.diff || q.tags || 'all'})... `);
    const batch = await fetchTheTriviaApiBatch(q.cat, q.tags, q.diff);
    let added = 0;
    for (const item of batch) {
      if (!seenHashes.has(item.question_hash)) {
        seenHashes.add(item.question_hash);
        allDownloaded.push(item);
        added++;
      }
    }
    console.log(`Got ${batch.length} (+${added} unique)`);
    await sleep(250);
  }

  // 2. Download from Open Trivia Database across all 24 categories (with 5.5s spacing)
  console.log('\n--- 2. Fetching from Open Trivia Database (OpenTDB - All 24 Categories) ---');
  const opentdbCategories = [
    { id: 9, name: 'General Knowledge' },
    { id: 10, name: 'Entertainment: Books' },
    { id: 11, name: 'Entertainment: Film' },
    { id: 12, name: 'Entertainment: Music' },
    { id: 13, name: 'Entertainment: Musicals & Theatres' },
    { id: 14, name: 'Entertainment: Television' },
    { id: 15, name: 'Entertainment: Video Games' },
    { id: 16, name: 'Entertainment: Board Games' },
    { id: 17, name: 'Science & Nature' },
    { id: 18, name: 'Science: Computers' },
    { id: 19, name: 'Science: Mathematics' },
    { id: 20, name: 'Mythology' },
    { id: 21, name: 'Sports' },
    { id: 22, name: 'Geography' },
    { id: 23, name: 'History' },
    { id: 24, name: 'Politics' },
    { id: 25, name: 'Art' },
    { id: 26, name: 'Celebrities' },
    { id: 27, name: 'Animals' },
    { id: 28, name: 'Vehicles' },
    { id: 29, name: 'Entertainment: Comics' },
    { id: 30, name: 'Science: Gadgets' },
    { id: 31, name: 'Entertainment: Japanese Anime & Manga' },
    { id: 32, name: 'Entertainment: Cartoon & Animations' }
  ];

  for (const cat of opentdbCategories) {
    process.stdout.write(`Fetching OpenTDB: ID ${cat.id} (${cat.name})... `);
    const batch = await fetchOpenTdbBatch(cat.id, cat.name);
    let added = 0;
    for (const item of batch) {
      if (!seenHashes.has(item.question_hash)) {
        seenHashes.add(item.question_hash);
        allDownloaded.push(item);
        added++;
      }
    }
    console.log(`Got ${batch.length} (+${added} unique)`);
    await sleep(5500); // 5.5s spacing to strictly comply with OpenTDB rate limits
  }

  console.log(`\n====================================================`);
  console.log(`🎉 BULK DOWNLOAD COMPLETE!`);
  console.log(`Total verified unique real questions in bank: ${allDownloaded.length}`);
  console.log(`====================================================`);

  // Category breakdown
  const counts = {};
  for (const q of allDownloaded) {
    counts[q.category] = (counts[q.category] || 0) + 1;
  }
  console.log('\nCategory Distribution:');
  for (const [c, cnt] of Object.entries(counts).sort((a, b) => b[1] - a[1])) {
    console.log(`  - ${c}: ${cnt} questions`);
  }

  // Save to target paths
  const targetFiles = [
    path.join(__dirname, '..', 'assets', 'data', 'weekly_trivia_pack.json'),
    path.join(__dirname, '..', 'public', 'data', 'weekly_trivia_pack.json'),
    path.join(__dirname, '..', 'dist', 'data', 'weekly_trivia_pack.json')
  ];

  for (const f of targetFiles) {
    try {
      const dir = path.dirname(f);
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(f, JSON.stringify(allDownloaded, null, 2), 'utf8');
      console.log(`✓ Saved ${allDownloaded.length} questions to ${f}`);
    } catch (e) {
      console.warn(`Could not write to ${f}: ${e.message}`);
    }
  }

  // Upsert to Supabase
  const supabaseUrl = process.env.SUPABASE_URL || 'https://tzdikvbvdvgjaiznqkcd.supabase.co';
  const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InR6ZGlrdmJ2ZHZnamFpem5xa2NkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDAxNTMwNzksImV4cCI6MjA1NTcyOTA3OX0.12k3oY1iO6wYk_hJ8e2V0n1QY-B5-v1XyPZ47_3q1W8';

  if (supabaseUrl && supabaseKey) {
    try {
      const { createClient } = require('@supabase/supabase-js');
      const supabase = createClient(supabaseUrl, supabaseKey, { auth: { persistSession: false } });
      console.log('\nSyncing questions to Supabase questions table...');

      let synced = 0;
      for (let i = 0; i < allDownloaded.length; i += 50) {
        const chunk = allDownloaded.slice(i, i + 50);
        const { error } = await supabase
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

        if (!error) synced += chunk.length;
      }
      console.log(`✓ Synced ${synced} questions to Supabase successfully.`);
    } catch (sbErr) {
      console.warn('Supabase sync note:', sbErr.message);
    }
  }

  console.log('\n✅ Bulk download and ingestion completed successfully!\n');
}

bulkDownload().catch(err => {
  console.error('Bulk download failed:', err);
  process.exit(1);
});
