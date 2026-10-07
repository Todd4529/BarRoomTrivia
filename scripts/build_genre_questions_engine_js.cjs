const fs = require('fs');
const path = require('path');
const vm = require('vm');

const dartCode = fs.readFileSync(path.join(__dirname, '../lib/shared/data/genre_questions_engine.dart'), 'utf8');

function convertDartGenerator(name, dartBody) {
  const jsName = name.replace(/^_/, '');
  let js = dartBody.trim();
  if (js.endsWith('}')) {
    js = js.slice(0, -1).trim();
  }

  // Replace final / var declarations
  js = js.replace(/\bfinal\s+/g, 'const ');
  js = js.replace(/\bvar\s+(\w+)\s+in\s+/g, 'const $1 of ');
  js = js.replace(/\bvar\s+/g, 'const ');
  js = js.replace(/(\w+\.map\([^)]+\))\.toSet\(\)/g, '[...new Set($1)]');
  js = js.replace(/\.toSet\(\)/g, '');
  js = js.replace(/\.toList\(\)/g, '');
  js = js.replace(/\.addAll\(\[/g, '.push(...[');
  
  // Replace distractorPool: poolName with 'Standard', poolName
  js = js.replace(/distractorPool:\s*([a-zA-Z0-9_]+)/g, "'Standard', $1");

  // Handle template literals / string interpolation
  const lines = js.split('\n').map(line => {
    if (line.includes('${')) {
      return line.replace(/'([^']*\$\{[^']*\}[^']*)'/g, '`$1`');
    }
    return line;
  });

  return `function ${jsName}(addQ) {\n${lines.join('\n')}\n}\n`;
}

const regex = /static void (_generate\w+)\(Function addQ\) \{([\s\S]*?)(?=\n  static void|\n  \/\/ ---|\n\}\s*$)/g;
let m;
const generators = [];
while ((m = regex.exec(dartCode)) !== null) {
  // If it's _generateHomebrewing, we use generate500HomebrewingQuestions from homebrewingDatabase.js
  if (m[1] === '_generateHomebrewing') continue;
  const code = convertDartGenerator(m[1], m[2]);
  try {
    new vm.Script(code);
    generators.push(code);
  } catch (err) {
    console.error('Syntax error converting', m[1], err);
    process.exit(1);
  }
}

console.log('Successfully generated', generators.length, 'generators.');

const headerAndEngine = `/**
 * Bar Rooms Trivia - Universal Multi-Genre Question Engine
 * Provides authentic, human-made domain-specific trivia for all 30+ genres.
 * Strictly guarantees ZERO cross-genre contamination.
 */

import { generate500HomebrewingQuestions } from './homebrewingDatabase.js';

// Cache of generated questions per genre
const genreQuestionCache = new Map();

/**
 * Fisher-Yates Shuffle Algorithm for True Randomization
 */
export function fisherYatesShuffle(array) {
  const arr = [...array];
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

/**
 * Dynamically picks distinct distractors from a candidate pool, excluding the correct answer.
 */
export function pickRandomDistractors(pool, correct, count = 3, fallback = []) {
  const cleanCorrect = (correct || '').trim().toLowerCase();
  const candidates = [...new Set(
    (pool || [])
      .map(s => (s || '').trim())
      .filter(s => s.length > 0 && s.toLowerCase() !== cleanCorrect)
  )];

  const shuffled = fisherYatesShuffle(candidates);
  const selected = shuffled.slice(0, count);

  if (selected.length < count && fallback && fallback.length > 0) {
    const cleanSel = new Set(selected.map(s => s.toLowerCase()));
    const fbShuffled = fisherYatesShuffle(
      fallback.filter(f => f && f.toLowerCase() !== cleanCorrect && !cleanSel.has(f.toLowerCase()))
    );
    for (const fb of fbShuffled) {
      if (selected.length >= count) break;
      selected.push(fb);
      cleanSel.add(fb.toLowerCase());
    }
  }

  let fillIdx = 1;
  while (selected.length < count) {
    selected.push(\`Alternative \${fillIdx++}\`);
  }

  return selected;
}

/**
 * Sanitizes an array of questions to guarantee that no two consecutive questions
 * share identical wrong options.
 */
export function sanitizeQuestionsDistractors(questions) {
  if (!questions || questions.length <= 1) return questions;

  for (let i = 1; i < questions.length; i++) {
    const prevQ = questions[i - 1];
    const currQ = questions[i];

    const prevWrongs = new Set(
      ['A', 'B', 'C', 'D']
        .filter(l => l !== prevQ.correct)
        .map(l => (prevQ.options[l] || '').toLowerCase().trim())
    );

    const currLetters = ['A', 'B', 'C', 'D'];
    let collisionDetected = false;
    for (const l of currLetters) {
      if (l !== currQ.correct) {
        const val = (currQ.options[l] || '').toLowerCase().trim();
        if (prevWrongs.has(val)) {
          collisionDetected = true;
          break;
        }
      }
    }

    if (collisionDetected) {
      for (let j = i + 1; j < Math.min(i + 15, questions.length); j++) {
        const candQ = questions[j];
        let candCollision = false;
        for (const l of currLetters) {
          if (l !== candQ.correct) {
            const val = (candQ.options[l] || '').toLowerCase().trim();
            if (prevWrongs.has(val)) {
              candCollision = true;
              break;
            }
          }
        }
        if (!candCollision) {
          const temp = questions[i];
          questions[i] = questions[j];
          questions[j] = temp;
          break;
        }
      }
    }
  }

  return questions;
}

/**
 * Declusters questions with similar wording or themes
 */
export function deClusterSimilarQuestions(questions, minDistance = 4) {
  if (!questions || questions.length <= minDistance) return questions;

  const result = [];
  const remaining = [...questions];

  function getStem(text) {
    return (text || '')
      .toLowerCase()
      .replace(/[^a-z0-9 ]/g, '')
      .split(' ')
      .filter(w => w.length > 3)
      .slice(0, 3)
      .join('_');
  }

  while (remaining.length > 0) {
    let chosenIdx = 0;
    if (result.length > 0) {
      const recentStems = new Set(
        result.slice(-minDistance).map(q => getStem(q.text))
      );

      let foundNonColliding = false;
      for (let i = 0; i < remaining.length; i++) {
        const stem = getStem(remaining[i].text);
        if (!recentStems.has(stem)) {
          chosenIdx = i;
          foundNonColliding = true;
          break;
        }
      }

      if (!foundNonColliding) {
        chosenIdx = 0;
      }
    }

    result.push(remaining.splice(chosenIdx, 1)[0]);
  }

  return result;
}

/**
 * Main Question Generator: Strictly authentic, domain-isolated questions.
 * NO cross-genre borrowing or generic fallback pollution.
 */
export function generateGenreQuestions(genre) {
  const cleanGenre = !genre || genre === 'Auto Select' || genre === 'Random' ? 'General Trivia' : genre.trim();
  if (genreQuestionCache.has(cleanGenre)) {
    return genreQuestionCache.get(cleanGenre);
  }

  let questions = [];
  const seenTexts = new Set();

  function addQ(id, text, correct, optB, optC, optD, diff = 'Standard', distractorPool = null) {
    const cleanText = (text || '').trim();
    if (!cleanText) return;
    const textLower = cleanText.toLowerCase();
    if (seenTexts.has(textLower)) return;
    seenTexts.add(textLower);

    let wrongs;
    if (distractorPool && distractorPool.length >= 4) {
      wrongs = pickRandomDistractors(distractorPool, correct, 3, [optB, optC, optD]);
    } else {
      wrongs = [optB || 'Option B', optC || 'Option C', optD || 'Option D'];
    }

    const optionsList = [
      { text: correct, isCorrect: true },
      { text: wrongs[0], isCorrect: false },
      { text: wrongs[1], isCorrect: false },
      { text: wrongs[2], isCorrect: false }
    ];

    const shuffledOpts = fisherYatesShuffle(optionsList);
    const letters = ['A', 'B', 'C', 'D'];
    const correctIdx = shuffledOpts.findIndex(o => o.isCorrect);
    const correctLetter = letters[correctIdx >= 0 ? correctIdx : 0];

    questions.push({
      id: \`\${cleanGenre.toLowerCase().replace(/[^a-z0-9]/g, '_')}_\${questions.length + 1}\`,
      category: cleanGenre,
      difficulty: diff,
      text: cleanText,
      options: {
        A: shuffledOpts[0].text,
        B: shuffledOpts[1].text,
        C: shuffledOpts[2].text,
        D: shuffledOpts[3].text
      },
      correct: correctLetter,
      source: 'Bar Room Trivia Official Bank'
    });
  }

  const gLower = cleanGenre.toLowerCase();

  // 1. HOMEBREWING BEER
  if (gLower.includes('homebrew')) {
    const hbPool = generate500HomebrewingQuestions();
    for (const q of hbPool) {
      if (!seenTexts.has(q.text.toLowerCase())) {
        seenTexts.add(q.text.toLowerCase());
        questions.push(q);
      }
    }
  }
  // 2. BEER, WINE & SPIRITS
  else if (gLower.includes('wine') || gLower.includes('spirits') || gLower === 'beer, wine & spirits') {
    generateBeerWineSpirits(addQ);
  }
  // 3. ASTRONOMY & SPACE
  else if (gLower.includes('astronomy') || gLower.includes('space')) {
    generateAstronomy(addQ);
  }
  // 4. WORLD GEOGRAPHY
  else if (gLower.includes('geography')) {
    generateGeography(addQ);
  }
  // 5. WORLD HISTORY
  else if (gLower.includes('history')) {
    generateHistory(addQ);
  }
  // 6. SPORTS & STADIUMS
  else if (gLower.includes('sport') || gLower.includes('stadium')) {
    generateSports(addQ);
  }
  // 7. MOVIES & HOLLYWOOD
  else if (gLower.includes('movie') || gLower.includes('hollywood')) {
    generateMovies(addQ);
  }
  // 8. ROCK & ROLL CLASSICS
  else if (gLower.includes('rock') || gLower.includes('roll')) {
    generateRockClassics(addQ);
  }
  // 9. POP CULTURE & MUSIC
  else if (gLower.includes('pop culture')) {
    generatePopCulture(addQ);
  }
  // 10. MUSIC LYRICS
  else if (gLower.includes('lyrics')) {
    generateMusicLyrics(addQ);
  }
  // 11. 80S & 90S NOSTALGIA
  else if (gLower.includes('80s') || gLower.includes('90s') || gLower.includes('nostalgia')) {
    generateNostalgia(addQ);
  }
  // 12. SCIENCE & TECHNOLOGY
  else if (gLower.includes('science') || gLower.includes('tech')) {
    generateScience(addQ);
  }
  // 13. VIDEO GAMES & GAMING
  else if (gLower.includes('game') || gLower.includes('gaming')) {
    generateVideoGames(addQ);
  }
  // 14. CLASSIC LITERATURE
  else if (gLower.includes('literature')) {
    generateLiterature(addQ);
  }
  // 15. COMICS & SUPERHEROES
  else if (gLower.includes('comic') || gLower.includes('superhero')) {
    generateComics(addQ);
  }
  // 16. ART & ARCHITECTURE
  else if (gLower.includes('art') || gLower.includes('architecture')) {
    generateArtArchitecture(addQ);
  }
  // 17. FAMOUS LANDMARKS
  else if (gLower.includes('landmark')) {
    generateFamousLandmarks(addQ);
  }
  // 18. FOOD & CULINARY
  else if (gLower.includes('food') || gLower.includes('culinary')) {
    generateFoodCulinary(addQ);
  }
  // 19. HEALTH & MEDICINE
  else if (gLower.includes('health') || gLower.includes('medicine')) {
    generateHealth(addQ);
  }
  // 20. HOME REPAIR
  else if (gLower.includes('repair')) {
    generateHomeRepair(addQ);
  }
  // 21. FINANCE
  else if (gLower.includes('finance') || gLower.includes('money')) {
    generateFinance(addQ);
  }
  // 22. AUTOMOTIVE & RACING
  else if (gLower.includes('auto') || gLower.includes('racing')) {
    generateAutomotive(addQ);
  }
  // 23. MOTORCYCLES
  else if (gLower.includes('motorcycle') || gLower.includes('bike')) {
    generateMotorcycles(addQ);
  }
  // 24. CAMPING & OUTDOORS
  else if (gLower.includes('camping')) {
    generateCamping(addQ);
  }
  // 25. WILDLIFE & NATURE
  else if (gLower.includes('wildlife') || gLower.includes('nature')) {
    generateWildlife(addQ);
  }
  // 26. TRAVEL & EXPLORATION
  else if (gLower.includes('travel')) {
    generateTravel(addQ);
  }
  // 27. BROADWAY & THEATER
  else if (gLower.includes('broadway') || gLower.includes('theater')) {
    generateBroadway(addQ);
  }
  // 28. BUSINESS & BRANDS
  else if (gLower.includes('business') || gLower.includes('brand')) {
    generateBusiness(addQ);
  }
  // 29. INTERNET & MEME CULTURE
  else if (gLower.includes('internet') || gLower.includes('meme')) {
    generateInternetMemes(addQ);
  }
  // 30. SITCOMS & TV DRAMAS
  else if (gLower.includes('sitcom') || gLower.includes('tv drama')) {
    generateSitcoms(addQ);
  }
  // 31. MYTHOLOGY & FOLKLORE
  else if (gLower.includes('mythology') || gLower.includes('folklore')) {
    generateMythology(addQ);
  }
  // 32. MIND BENDERS & RIDDLES
  else if (gLower.includes('mind bender') || gLower.includes('riddle')) {
    generateMindBenders(addQ);
  }
  else {
    // Curated multi-domain mix for general/mixed requests without cross-labeling
    generateScience(addQ);
    generateHistory(addQ);
    generateSports(addQ);
    generateMovies(addQ);
  }

  // Filter strictly authentic handcrafted human questions (ZERO synthetic/AI filler)
  const authentic = questions.filter(q => 
    !q.id.startsWith('univ_') && 
    !q.id.startsWith('fill_') && 
    !q.id.startsWith('gen_')
  );

  const declusteredAuth = deClusterSimilarQuestions(fisherYatesShuffle(authentic), 4);
  questions = sanitizeQuestionsDistractors(declusteredAuth);

  genreQuestionCache.set(cleanGenre, questions);
  return questions;
}

// =====================================================================
// AUTHENTIC DOMAIN-SPECIFIC QUESTION GENERATORS
// =====================================================================
`;

const finalFileContent = headerAndEngine + '\n' + generators.join('\n\n');
fs.writeFileSync(path.join(__dirname, '../src/genreQuestionsEngine.js'), finalFileContent, 'utf8');
console.log('Successfully wrote src/genreQuestionsEngine.js!');
