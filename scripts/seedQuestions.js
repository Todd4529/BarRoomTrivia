import { createClient } from '@supabase/supabase-js';
import { generate500HomebrewingQuestions } from '../src/homebrewingDatabase.js';
import fs from 'fs';
import path from 'path';

// Read .env manually to avoid extra dependencies
const envPath = path.resolve(process.cwd(), '.env');
let supabaseUrl = 'https://tzdikvbvdvgjaiznqkcd.supabase.co';
let supabaseAnonKey = 'sb_publishable_VjyTwHSKG0WNtVJMGk4omw_fRQwSUWb';

if (fs.existsSync(envPath)) {
  const envContent = fs.readFileSync(envPath, 'utf8');
  envContent.split('\n').forEach(line => {
    const [key, ...vals] = line.split('=');
    if (key && vals.length > 0) {
      const val = vals.join('=').trim();
      if (key.trim() === 'VITE_SUPABASE_URL') supabaseUrl = val;
      if (key.trim() === 'VITE_SUPABASE_ANON_KEY') supabaseAnonKey = val;
    }
  });
}

console.log('Connecting to Supabase at:', supabaseUrl);
const supabase = createClient(supabaseUrl, supabaseAnonKey);

function decodeEntities(text) {
  if (!text) return '';
  return text
    .replace(/&quot;/g, '"')
    .replace(/&#039;/g, "'")
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&deg;/g, '°')
    .replace(/&eacute;/g, 'é')
    .replace(/&Aacute;/g, 'Á')
    .replace(/&ntilde;/g, 'ñ');
}

function shuffle(arr) {
  const array = [...arr];
  for (let i = array.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [array[i], array[j]] = [array[j], array[i]];
  }
  return array;
}

// 1. SEED HOMEBREWING QUESTIONS (500+)
async function seedHomebrewing() {
  console.log('\n--- Generating 500 Homebrewing Questions ---');
  const hbQuestions = generate500HomebrewingQuestions();
  
  // Format for DB
  const records = hbQuestions.map(q => {
    return {
      category: 'Beer, Wine & Spirits',
      difficulty: (q.difficulty || 'medium').toLowerCase(),
      question_text: q.text,
      option_a: q.options.A,
      option_b: q.options.B,
      option_c: q.options.C,
      option_d: q.options.D,
      correct_option: q.correct,
      time_limit_seconds: 20
    };
  });

  // Batch insert into Supabase in chunks of 100
  let insertedCount = 0;
  for (let i = 0; i < records.length; i += 100) {
    const chunk = records.slice(i, i + 100);
    const { error } = await supabase.from('questions').insert(chunk);
    if (error) {
      console.error('Error inserting homebrewing batch:', error.message);
    } else {
      insertedCount += chunk.length;
      console.log(`Inserted ${insertedCount} / ${records.length} Homebrewing questions...`);
    }
  }
  console.log(`✅ Successfully seeded ${insertedCount} Homebrewing questions.`);
}

// 2. OPENTDB CATEGORY MAP FOR POPULATING OTHER GENRES
const categoryMap = [
  { id: 9, name: 'General Knowledge' },
  { id: 11, name: 'Movies & Hollywood' },
  { id: 12, name: 'Pop Culture & Music' },
  { id: 14, name: 'Sitcoms & TV Dramas' },
  { id: 15, name: 'Video Games & Gaming' },
  { id: 17, name: 'Science & Technology' },
  { id: 21, name: 'Sports & Stadiums' },
  { id: 22, name: 'World Geography' },
  { id: 23, name: 'World History' },
  { id: 25, name: 'Art & Architecture' },
  { id: 27, name: 'Wildlife & Nature' },
  { id: 29, name: 'Comics & Superheroes' }
];

async function fetchFromOpenTDB(catId, catName) {
  console.log(`\nFetching OpenTDB questions for category: "${catName}" (ID: ${catId})...`);
  let fetchedCount = 0;
  
  // Fetch multiple batches of 50 questions
  for (let page = 0; page < 4; page++) {
    try {
      const url = `https://opentdb.com/api.php?amount=50&category=${catId}&type=multiple`;
      const res = await fetch(url);
      const data = await res.json();

      if (data.response_code === 0 && data.results && data.results.length > 0) {
        const records = data.results.map(item => {
          const incorrect = item.incorrect_answers.map(decodeEntities);
          const correct = decodeEntities(item.correct_answer);
          const allOptions = shuffle([correct, ...incorrect]);
          
          const correctIdx = allOptions.indexOf(correct);
          const correctLetter = ['A', 'B', 'C', 'D'][correctIdx];

          return {
            category: catName,
            difficulty: item.difficulty.toLowerCase(),
            question_text: decodeEntities(item.question),
            option_a: allOptions[0] || 'A',
            option_b: allOptions[1] || 'B',
            option_c: allOptions[2] || 'C',
            option_d: allOptions[3] || 'D',
            correct_option: correctLetter,
            time_limit_seconds: 20
          };
        });

        const { error } = await supabase.from('questions').insert(records);
        if (error) {
          console.error(`Error inserting chunk for ${catName}:`, error.message);
        } else {
          fetchedCount += records.length;
          console.log(`   + Added ${records.length} questions to "${catName}" (Total: ${fetchedCount})`);
        }
      }

      // Respect OpenTDB rate limits (5 seconds between requests)
      await new Promise(r => setTimeout(r, 5200));
    } catch (err) {
      console.error(`Failed to fetch for ${catName}:`, err.message);
      break;
    }
  }
}

async function main() {
  console.log('🚀 Starting Supabase Questions Seeder Script...');
  
  // 1. Seed Homebrewing
  await seedHomebrewing();

  // 2. Seed OpenTDB Categories
  for (const cat of categoryMap) {
    await fetchFromOpenTDB(cat.id, cat.name);
  }

  // 3. Count Total Questions in Supabase
  const { count, error } = await supabase
    .from('questions')
    .select('*', { count: 'exact', head: true });

  if (!error) {
    console.log(`\n🎉 SEEDING COMPLETE! Total questions now in Supabase database: ${count}`);
  } else {
    console.log('\n🎉 SEEDING COMPLETE!');
  }
}

main().catch(err => {
  console.error('Seeding script failed:', err);
});
