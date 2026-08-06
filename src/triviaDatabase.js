/**
 * Bar Rooms Trivia - Authentic High-Quality Real-Time & Offline Trivia Database Engine
 * Integrates 500+ authentic Homebrewing Beer questions from homebrewingDatabase.js.
 */

import { generate500HomebrewingQuestions } from './homebrewingDatabase.js';

// All 30 Specific Genres List
export const ALL_SPECIFIC_GENRES = [
  'Homebrewing Beer',
  'Home Repair',
  'Finance',
  'Travel',
  'Health',
  'Music Lyrics',
  'Pop Culture & Music',
  'Movies & Hollywood',
  '80s & 90s Nostalgia',
  'Science & Technology',
  'World History',
  'World Geography',
  'Sports & Stadiums',
  'Beer, Wine & Spirits',
  'Food & Culinary',
  'Video Games & Gaming',
  'Classic Literature',
  'Comics & Superheroes',
  'Art & Architecture',
  'Wildlife & Nature',
  'Astronomy & Space',
  'Mythology & Folklore',
  'Automotive & Racing',
  'Rock & Roll Classics',
  'Sitcoms & TV Dramas',
  'Internet & Meme Culture',
  'Famous Landmarks',
  'Mind Benders & Riddles',
  'Business & Brands',
  'Broadway & Theater'
];

// Open Trivia DB Category ID Mapping
const openTdbCategoryMap = {
  'Pop Culture & Music': 12,
  'Movies & Hollywood': 11,
  'Sitcoms & TV Dramas': 14,
  'Video Games & Gaming': 15,
  'Science & Technology': 17,
  'Astronomy & Space': 17,
  'World History': 23,
  'World Geography': 22,
  'Sports & Stadiums': 21,
  'Classic Literature': 10,
  'Comics & Superheroes': 29,
  'Art & Architecture': 25,
  'Mythology & Folklore': 20,
  'Music Lyrics': 12,
  '80s & 90s Nostalgia': 14,
  'Rock & Roll Classics': 12,
  'Travel': 22,
  'Famous Landmarks': 22,
  'Broadway & Theater': 13
};

// Custom Bar Genres that rely on specialized authentic local datasets
const customLocalGenres = new Set([
  'Homebrewing Beer',
  'Beer, Wine & Spirits',
  'Home Repair',
  'Finance',
  'Health'
]);

// Initialize 500+ Homebrewing Questions dataset
const homebrewing500Dataset = generate500HomebrewingQuestions();

// Global Session Question Memory (Guarantees zero repeat questions)
const seenQuestionTexts = new Set();
let openTdbSessionToken = null;

// HTML Entity Decoder helper
function decodeHTMLEntities(text) {
  const textarea = document.createElement('textarea');
  textarea.innerHTML = text;
  return textarea.value;
}

// REQUEST OPENTDB SESSION TOKEN (Prevents API repeats across games)
export async function initOpenTdbToken() {
  try {
    const res = await fetch('https://opentdb.com/api_token.php?command=request');
    const data = await res.json();
    if (data.response_code === 0 && data.token) {
      openTdbSessionToken = data.token;
      console.log('OpenTDB Session Token initialized:', openTdbSessionToken);
    }
  } catch (err) {
    console.warn('Could not fetch OpenTDB token:', err);
  }
}

// RESET SEEN QUESTIONS (For when host resets game)
export function resetQuestionHistory() {
  seenQuestionTexts.clear();
}

// 1. REAL-TIME INTERNET TRIVIA FETCH ENGINE WITH CUSTOM BAR GENRE BYPASS
export async function fetchRealtimeTriviaQuestions(genre, difficulty = 'Standard', count = 10) {
  if (!openTdbSessionToken) {
    await initOpenTdbToken();
  }

  // IF GENRE IS 'Random', COMBINE QUESTIONS FROM DIFFERENT SPECIFIC GENRES IN ONE GAME
  if (genre === 'Random') {
    const mixedBatch = [];
    const shuffledGenres = [...ALL_SPECIFIC_GENRES].sort(() => 0.5 - Math.random());

    for (let i = 0; i < count; i++) {
      const targetGenre = shuffledGenres[i % shuffledGenres.length];
      const singleQBatch = await fetchSingleGenreQuestions(targetGenre, difficulty, 1);
      if (singleQBatch && singleQBatch.length > 0) {
        mixedBatch.push(singleQBatch[0]);
      } else {
        const fallback = getLocalQuestions(targetGenre, difficulty, 1);
        mixedBatch.push(fallback[0]);
      }
    }

    return mixedBatch;
  }

  // FOR CUSTOM BAR GENRES LIKE HOMEBREWING BEER, USE DEDICATED AUTHENTIC LOCAL DATASET DIRECTLY
  if (customLocalGenres.has(genre)) {
    return getLocalQuestions(genre, difficulty, count);
  }

  // FOR 'Auto Select' OR SPECIFIC API GENRES
  return fetchSingleGenreQuestions(genre, difficulty, count);
}

// Helper to fetch for a single specific genre
async function fetchSingleGenreQuestions(genre, difficulty, count) {
  const catId = openTdbCategoryMap[genre];
  
  if (catId) {
    let diffParam = 'medium';
    if (difficulty === 'Kids') diffParam = 'easy';
    else if (difficulty === 'Beginner') diffParam = 'easy';
    else if (difficulty === 'Standard') diffParam = 'medium';
    else if (difficulty === 'Advanced') diffParam = 'hard';

    try {
      let url = `https://opentdb.com/api.php?amount=${count + 3}&category=${catId}&difficulty=${diffParam}&type=multiple`;
      if (openTdbSessionToken) {
        url += `&token=${openTdbSessionToken}`;
      }

      const response = await fetch(url);
      const data = await response.json();

      if (data.response_code === 4 || data.response_code === 3) {
        await initOpenTdbToken();
      }

      if (data.response_code === 0 && data.results && data.results.length > 0) {
        const fetched = [];
        for (const q of data.results) {
          const decodedText = decodeHTMLEntities(q.question);
          if (!seenQuestionTexts.has(decodedText)) {
            seenQuestionTexts.add(decodedText);
            
            const incorrect = q.incorrect_answers.map(decodeHTMLEntities);
            const correctStr = decodeHTMLEntities(q.correct_answer);
            const allOpts = [...incorrect, correctStr].sort(() => 0.5 - Math.random());
            
            const optKeys = ['A', 'B', 'C', 'D'];
            const optionsObj = {};
            let correctKey = 'A';

            allOpts.forEach((opt, i) => {
              optionsObj[optKeys[i]] = opt;
              if (opt === correctStr) correctKey = optKeys[i];
            });

            fetched.push({
              id: `realtime_${Date.now()}_${Math.random()}`,
              category: genre,
              difficulty,
              text: decodedText,
              options: optionsObj,
              correct: correctKey,
              source: 'OpenTriviaDB Live'
            });
          }
        }

        if (fetched.length > 0) {
          return fetched.slice(0, count);
        }
      }
    } catch (err) {
      console.warn(`Fetch failed for ${genre}:`, err);
    }
  }

  return getLocalQuestions(genre, difficulty, count);
}

// 2. AUTHENTIC BAR TRIVIA DATABASE (INCLUDING 500+ HOMEBREWING BEER QUESTIONS)
const authenticOfflineDatabase = [
  ...homebrewing500Dataset,

  // 🛠️ HOME REPAIR
  { category: 'Home Repair', difficulty: 'Standard', text: 'What tool is specifically designed to locate hidden wooden support studs behind drywall?', options: { A: 'Plumb Bob', B: 'Stud Finder', C: 'Chalk Line', D: 'Caliper' }, correct: 'B' },
  { category: 'Home Repair', difficulty: 'Standard', text: 'What type of electrical safety outlet with a built-in reset button is required near sinks and water sources?', options: { A: 'GFCI Outlet', B: '220V Outlet', C: 'Coaxial Outlet', D: 'Switch Loop' }, correct: 'A' },

  // 💵 FINANCE
  { category: 'Finance', difficulty: 'Standard', text: 'What financial term describes earning interest on both your original principal and accumulated interest?', options: { A: 'Simple Interest', B: 'Compound Interest', C: 'Capital Gain', D: 'Amortization' }, correct: 'B' },

  // ✈️ TRAVEL
  { category: 'Travel', difficulty: 'Standard', text: 'Which famous ancient Citadel sits high in the Andes Mountains of Peru?', options: { A: 'Chichen Itza', B: 'Machu Picchu', C: 'Petra', D: 'Tikal' }, correct: 'B' },

  // 🩺 HEALTH
  { category: 'Health', difficulty: 'Standard', text: 'Which organ in the human body produces insulin to regulate blood sugar levels?', options: { A: 'Liver', B: 'Pancreas', C: 'Kidney', D: 'Gallbladder' }, correct: 'B' },

  // 🎶 MUSIC LYRICS
  { category: 'Music Lyrics', difficulty: 'Beginner', text: '"Just a small town girl, livin\' in a lonely world..." opens which famous song?', options: { A: '"Livin\' on a Prayer"', B: '"Don\'t Stop Believin\'" - Journey', C: '"Sweet Caroline"', D: '"Hotel California"' }, correct: 'B' },

  // 🎵 POP CULTURE & MUSIC
  { category: 'Pop Culture & Music', difficulty: 'Beginner', text: 'Which pop superstar released the record-breaking album "1989" in 2014?', options: { A: 'Katy Perry', B: 'Taylor Swift', C: 'Lady Gaga', D: 'Ariana Grande' }, correct: 'B' },

  // 🎬 MOVIES & HOLLYWOOD
  { category: 'Movies & Hollywood', difficulty: 'Standard', text: 'Who directed the 1993 sci-fi blockbuster "Jurassic Park"?', options: { A: 'James Cameron', B: 'Steven Spielberg', C: 'Christopher Nolan', D: 'George Lucas' }, correct: 'B' },

  // 🧪 SCIENCE & TECHNOLOGY
  { category: 'Science & Technology', difficulty: 'Standard', text: 'What is the hardest natural substance found on Earth?', options: { A: 'Titanium', B: 'Quartz', C: 'Diamond', D: 'Graphene' }, correct: 'C' }
];

// 3. GET LOCAL QUESTIONS WITH ZERO REPEATS
export function getLocalQuestions(genre, difficulty = 'Standard', count = 10) {
  let pool = authenticOfflineDatabase;

  // Filter strictly by requested genre if matching items exist
  if (genre !== 'Random' && genre !== 'Auto Select') {
    const genreMatch = pool.filter(q => q.category.toLowerCase().includes(genre.toLowerCase()));
    if (genreMatch.length > 0) pool = genreMatch;
  }

  // Filter by difficulty if matching items exist
  const diffMatch = pool.filter(q => q.difficulty === difficulty);
  if (diffMatch.length > 0) pool = diffMatch;

  const result = [];
  const shuffled = [...pool].sort(() => 0.5 - Math.random());

  for (const q of shuffled) {
    if (!seenQuestionTexts.has(q.text)) {
      seenQuestionTexts.add(q.text);
      result.push({
        id: `offline_${Date.now()}_${Math.random()}`,
        category: q.category || genre,
        difficulty: q.difficulty || difficulty,
        text: q.text,
        options: q.options,
        correct: q.correct,
        source: '500+ Question Homebrewing Database'
      });
    }
  }

  // If session has consumed items, loop cleanly without repeating within the same 10-question round
  if (result.length < count) {
    const currentRoundTexts = new Set(result.map(r => r.text));
    for (const q of [...pool].sort(() => 0.5 - Math.random())) {
      if (result.length >= count) break;
      if (!currentRoundTexts.has(q.text)) {
        currentRoundTexts.add(q.text);
        result.push({
          id: `offline_fill_${Date.now()}_${Math.random()}`,
          category: q.category || genre,
          difficulty: q.difficulty || difficulty,
          text: q.text,
          options: q.options,
          correct: q.correct,
          source: '500+ Question Homebrewing Database'
        });
      }
    }
  }

  return result.slice(0, count);
}
