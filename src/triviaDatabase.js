/**
 * Bar Rooms Trivia - Authentic High-Quality Real-Time & Offline Trivia Database Engine
 * Integrates 500+ authentic Homebrewing Beer questions from homebrewingDatabase.js.
 */

import { generate500HomebrewingQuestions } from './homebrewingDatabase.js';
import { generateGenreQuestions } from './genreQuestionsEngine.js';

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
  if (!text) return '';
  if (typeof document !== 'undefined') {
    const textarea = document.createElement('textarea');
    textarea.innerHTML = text;
    return textarea.value;
  }
  return text
    .replace(/&quot;/g, '"')
    .replace(/&#039;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&eacute;/g, 'é')
    .replace(/&rsquo;/g, "'");
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

      const response = await fetch(url, { signal: AbortSignal.timeout(3500) });
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

  // ⚽ SPORTS & STADIUMS
  { category: 'Sports & Stadiums', difficulty: 'Standard', text: 'Which country won the FIFA Men\'s World Cup in 2022?', options: { A: 'France', B: 'Argentina', C: 'Brazil', D: 'Germany' }, correct: 'B' },
  { category: 'Sports & Stadiums', difficulty: 'Standard', text: 'How many regulation holes are played in a standard round of golf?', options: { A: '9', B: '18', C: '24', D: '36' }, correct: 'B' },
  { category: 'Sports & Stadiums', difficulty: 'Beginner', text: 'What is the highest possible single-game score in ten-pin bowling?', options: { A: '200', B: '250', C: '300', D: '350' }, correct: 'C' },
  { category: 'Sports & Stadiums', difficulty: 'Standard', text: 'Which NBA franchise has won the most championships tied with the Boston Celtics?', options: { A: 'Golden State Warriors', B: 'Chicago Bulls', C: 'LA Lakers', D: 'Miami Heat' }, correct: 'C' },
  { category: 'Sports & Stadiums', difficulty: 'Standard', text: 'In American football, how many points is a touchdown worth before the extra point?', options: { A: '3', B: '6', C: '7', D: '8' }, correct: 'B' },

  // 🌍 WORLD GEOGRAPHY
  { category: 'World Geography', difficulty: 'Standard', text: 'What is the capital city of Australia?', options: { A: 'Sydney', B: 'Melbourne', C: 'Canberra', D: 'Brisbane' }, correct: 'C' },
  { category: 'World Geography', difficulty: 'Standard', text: 'Which African nation has the largest population?', options: { A: 'Egypt', B: 'South Africa', C: 'Nigeria', D: 'Kenya' }, correct: 'C' },
  { category: 'World Geography', difficulty: 'Standard', text: 'What is the longest river in the world?', options: { A: 'Amazon', B: 'Nile', C: 'Mississippi', D: 'Yangtze' }, correct: 'B' },
  { category: 'World Geography', difficulty: 'Beginner', text: 'Which ocean lies between North America and Europe?', options: { A: 'Pacific Ocean', B: 'Indian Ocean', C: 'Atlantic Ocean', D: 'Arctic Ocean' }, correct: 'C' },
  { category: 'World Geography', difficulty: 'Standard', text: 'What is the smallest country in the world by both area and population?', options: { A: 'Monaco', B: 'San Marino', C: 'Vatican City', D: 'Liechtenstein' }, correct: 'C' },

  // 📜 WORLD HISTORY
  { category: 'World History', difficulty: 'Standard', text: 'In what year did the Titanic sink after hitting an iceberg in the North Atlantic?', options: { A: '1905', B: '1912', C: '1918', D: '1923' }, correct: 'B' },
  { category: 'World History', difficulty: 'Standard', text: 'Who was the first President of the United States under the Constitution?', options: { A: 'Thomas Jefferson', B: 'George Washington', C: 'John Adams', D: 'Benjamin Franklin' }, correct: 'B' },
  { category: 'World History', difficulty: 'Standard', text: 'The ancient city of Rome was founded along the banks of which river?', options: { A: 'Po River', B: 'Tiber River', C: 'Danube River', D: 'Rhine River' }, correct: 'B' },
  { category: 'World History', difficulty: 'Standard', text: 'Which wall fell in November 1989, symbolizing the end of the Cold War in Europe?', options: { A: 'Great Wall of China', B: 'Hadrian\'s Wall', C: 'Berlin Wall', D: 'Western Wall' }, correct: 'C' },

  // 🎵 POP CULTURE & MUSIC
  { category: 'Pop Culture & Music', difficulty: 'Beginner', text: 'Which pop superstar released the record-breaking album "1989" in 2014?', options: { A: 'Katy Perry', B: 'Taylor Swift', C: 'Lady Gaga', D: 'Ariana Grande' }, correct: 'B' },
  { category: 'Pop Culture & Music', difficulty: 'Standard', text: 'What famous music festival took place in Bethel, New York in August 1969?', options: { A: 'Coachella', B: 'Lollapalooza', C: 'Woodstock', D: 'Glastonbury' }, correct: 'C' },
  { category: 'Pop Culture & Music', difficulty: 'Beginner', text: 'Who is known as the "King of Pop"?', options: { A: 'Prince', B: 'Michael Jackson', C: 'Elvis Presley', D: 'Stevie Wonder' }, correct: 'B' },

  // 🎬 MOVIES & HOLLYWOOD
  { category: 'Movies & Hollywood', difficulty: 'Standard', text: 'Who directed the 1993 sci-fi blockbuster "Jurassic Park"?', options: { A: 'James Cameron', B: 'Steven Spielberg', C: 'Christopher Nolan', D: 'George Lucas' }, correct: 'B' },
  { category: 'Movies & Hollywood', difficulty: 'Standard', text: 'Which movie won the Academy Award for Best Picture in 1997, tying the record for 11 Oscars?', options: { A: 'Braveheart', B: 'Titanic', C: 'Gladiator', D: 'Forrest Gump' }, correct: 'B' },
  { category: 'Movies & Hollywood', difficulty: 'Standard', text: 'In "The Matrix", what color pill does Neo take to wake up to the real world?', options: { A: 'Blue Pill', B: 'Red Pill', C: 'Green Pill', D: 'Yellow Pill' }, correct: 'B' },

  // 📺 80s & 90s NOSTALGIA
  { category: '80s & 90s Nostalgia', difficulty: 'Standard', text: 'Which handheld gaming console did Nintendo release worldwide in 1989?', options: { A: 'Sega Game Gear', B: 'Game Boy', C: 'Atari Lynx', D: 'Nintendo DS' }, correct: 'B' },
  { category: '80s & 90s Nostalgia', difficulty: 'Standard', text: 'On the sitcom "Friends", what is the name of the coffee house where the gang frequently hangs out?', options: { A: 'Monk\'s Diner', B: 'Central Perk', C: 'Café Nervosa', D: 'The Max' }, correct: 'B' },
  { category: '80s & 90s Nostalgia', difficulty: 'Standard', text: 'In "Back to the Future", what speed must the DeLorean reach to travel through time?', options: { A: '65 mph', B: '77 mph', C: '88 mph', D: '99 mph' }, correct: 'C' },

  // 🧪 SCIENCE & TECHNOLOGY
  { category: 'Science & Technology', difficulty: 'Standard', text: 'What is the hardest natural substance found on Earth?', options: { A: 'Titanium', B: 'Quartz', C: 'Diamond', D: 'Graphene' }, correct: 'C' },
  { category: 'Science & Technology', difficulty: 'Standard', text: 'What is the primary gas found in the Earth\'s atmosphere?', options: { A: 'Oxygen', B: 'Nitrogen', C: 'Carbon Dioxide', D: 'Argon' }, correct: 'B' },
  { category: 'Science & Technology', difficulty: 'Standard', text: 'What does "HTTP" stand for in website addresses?', options: { A: 'High Tech Transfer Protocol', B: 'HyperText Transfer Protocol', C: 'Hyperlink Text Telemetry Protocol', D: 'Home Terminal Tool Provider' }, correct: 'B' },

  // 🍻 BEER, WINE & SPIRITS
  { category: 'Beer, Wine & Spirits', difficulty: 'Standard', text: 'What botanical ingredient gives gin its distinct primary pine-like flavor?', options: { A: 'Coriander', B: 'Juniper Berries', C: 'Cardamom', D: 'Angelica Root' }, correct: 'B' },
  { category: 'Beer, Wine & Spirits', difficulty: 'Standard', text: 'True Tequila must be produced primarily from which plant species?', options: { A: 'Sorghum', B: 'Blue Agave', C: 'Sugar Cane', D: 'Barley Malt' }, correct: 'B' },
  { category: 'Beer, Wine & Spirits', difficulty: 'Standard', text: 'In winemaking, what term describes the science and study of wine production?', options: { A: 'Viticulture', B: 'Oenology', C: 'Sommellerie', D: 'Terroir' }, correct: 'B' },

  // 🍕 FOOD & CULINARY
  { category: 'Food & Culinary', difficulty: 'Standard', text: 'What traditional Italian cheese is used as the base for authentic Tiramisu?', options: { A: 'Ricotta', B: 'Mascarpone', C: 'Fontina', D: 'Gorgonzola' }, correct: 'B' },
  { category: 'Food & Culinary', difficulty: 'Standard', text: 'Which spice, derived from crocus flower stigmas, is considered the most expensive by weight in the world?', options: { A: 'Vanilla', B: 'Saffron', C: 'Cardamom', D: 'Cinnamon' }, correct: 'B' },

  // 🎮 VIDEO GAMES & GAMING
  { category: 'Video Games & Gaming', difficulty: 'Standard', text: 'What is the name of the protagonist in Nintendo\'s "The Legend of Zelda" franchise?', options: { A: 'Zelda', B: 'Link', C: 'Ganon', D: 'Sheik' }, correct: 'B' },
  { category: 'Video Games & Gaming', difficulty: 'Standard', text: 'Which iconic tile-matching arcade game was created by Russian software engineer Alexey Pajitnov in 1984?', options: { A: 'Pac-Man', B: 'Tetris', C: 'Breakout', D: 'Space Invaders' }, correct: 'B' }
];

// 3. GET LOCAL QUESTIONS WITH ZERO REPEATS ACROSS 500+ QUESTIONS PER GENRE
export function getLocalQuestions(genre, difficulty = 'Standard', count = 10) {
  let targetGenre = genre;
  if (!targetGenre || targetGenre === 'Random' || targetGenre === 'Auto Select') {
    const valid = ALL_SPECIFIC_GENRES.filter(g => g !== 'Random' && g !== 'Auto Select');
    targetGenre = valid[Math.floor(Math.random() * valid.length)];
  }

  // Generate or retrieve guaranteed 500+ pool for this genre
  const pool = generateGenreQuestions(targetGenre);

  // Filter out any questions already seen in this session
  const unseen = pool.filter(q => !seenQuestionTexts.has(q.text.toLowerCase()));

  let candidatePool = unseen;
  // If session has consumed almost all questions, reset session tracker
  if (candidatePool.length < count) {
    seenQuestionTexts.clear();
    candidatePool = [...pool];
  }

  // Shuffle candidate pool
  const shuffled = [...candidatePool].sort(() => 0.5 - Math.random());
  const selected = [];

  for (const q of shuffled) {
    if (selected.length >= count) break;
    seenQuestionTexts.add(q.text.toLowerCase());
    selected.push({
      ...q,
      id: q.id || `offline_${Date.now()}_${Math.random()}`,
      category: q.category || targetGenre,
      difficulty: q.difficulty || difficulty
    });
  }

  // Absolute guarantee: if somehow selected is empty, fall back to first questions
  if (selected.length === 0 && pool.length > 0) {
    for (let i = 0; i < Math.min(count, pool.length); i++) {
      const q = pool[i];
      selected.push({
        ...q,
        id: q.id || `offline_fallback_${Date.now()}_${i}`,
        category: q.category || targetGenre,
        difficulty: q.difficulty || difficulty
      });
    }
  }

  return selected;
}
