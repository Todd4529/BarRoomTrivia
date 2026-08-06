import fs from 'fs';
import path from 'path';

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
    .replace(/&ntilde;/g, 'ñ')
    .replace(/&ldquo;/g, '"')
    .replace(/&rdquo;/g, '"')
    .replace(/&hellip;/g, '...');
}

function escapeSqlString(str) {
  if (!str) return "''";
  return "'" + str.replace(/'/g, "''") + "'";
}

function shuffle(arr) {
  const array = [...arr];
  for (let i = array.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [array[i], array[j]] = [array[j], array[i]];
  }
  return array;
}

const categories = [
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

async function main() {
  console.log('Fetching OpenTDB questions and compiling into SQL seed script...');
  const allRows = [];

  for (const cat of categories) {
    console.log(`Fetching questions for "${cat.name}"...`);
    let catCount = 0;

    for (let fetchBatch = 0; fetchBatch < 2; fetchBatch++) {
      try {
        const url = `https://opentdb.com/api.php?amount=50&category=${cat.id}&type=multiple`;
        const res = await fetch(url);
        const data = await res.json();

        if (data.response_code === 0 && data.results && data.results.length > 0) {
          data.results.forEach(item => {
            const incorrect = item.incorrect_answers.map(decodeEntities);
            const correct = decodeEntities(item.correct_answer);
            const allOpts = shuffle([correct, ...incorrect]);

            const correctIdx = allOpts.indexOf(correct);
            const correctLetter = ['A', 'B', 'C', 'D'][correctIdx];

            const cName = escapeSqlString(cat.name);
            const diff = escapeSqlString((item.difficulty || 'medium').toLowerCase());
            const qText = escapeSqlString(decodeEntities(item.question));
            const optA = escapeSqlString(allOpts[0] || 'A');
            const optB = escapeSqlString(allOpts[1] || 'B');
            const optC = escapeSqlString(allOpts[2] || 'C');
            const optD = escapeSqlString(allOpts[3] || 'D');
            const corr = escapeSqlString(correctLetter);

            allRows.push(`(${cName}, ${diff}, ${qText}, ${optA}, ${optB}, ${optC}, ${optD}, ${corr}, 20)`);
            catCount++;
          });
        }
        await new Promise(r => setTimeout(r, 5200));
      } catch (err) {
        console.error(`Error fetching ${cat.name}:`, err.message);
        break;
      }
    }
    console.log(`   + Collected ${catCount} questions for "${cat.name}"`);
  }

  const header = `-- OpenTDB Categories Trivia Questions Seed
-- Execute this script in your Supabase SQL Editor (https://supabase.com/dashboard/project/tzdikvbvdvgjaiznqkcd/sql)

INSERT INTO public.questions (category, difficulty, question_text, option_a, option_b, option_c, option_d, correct_option, time_limit_seconds) VALUES
`;

  const fullSql = header + allRows.join(',\n') + ';\n';
  const outputPath = path.resolve(process.cwd(), 'supabase/seed_opentdb_categories.sql');
  fs.writeFileSync(outputPath, fullSql, 'utf8');

  console.log(`\n🎉 Generated ${allRows.length} questions into: ${outputPath}`);
}

main().catch(err => console.error(err));
