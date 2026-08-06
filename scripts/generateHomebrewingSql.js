import { generate500HomebrewingQuestions } from '../src/homebrewingDatabase.js';
import fs from 'fs';
import path from 'path';

function escapeSqlString(str) {
  if (!str) return "''";
  return "'" + str.replace(/'/g, "''") + "'";
}

console.log('Generating 500 Homebrewing Questions SQL seed file...');
const questions = generate500HomebrewingQuestions();

const header = `-- Bar Room Trivia - 500+ Authentic Homebrewing Questions Seed
-- Execute this script in your Supabase SQL Editor (https://supabase.com/dashboard/project/tzdikvbvdvgjaiznqkcd/sql)

INSERT INTO public.questions (category, difficulty, question_text, option_a, option_b, option_c, option_d, correct_option, time_limit_seconds) VALUES
`;

const rows = questions.map(q => {
  const cat = escapeSqlString('Beer, Wine & Spirits');
  const diff = escapeSqlString((q.difficulty || 'medium').toLowerCase());
  const text = escapeSqlString(q.text);
  const optA = escapeSqlString(q.options.A);
  const optB = escapeSqlString(q.options.B);
  const optC = escapeSqlString(q.options.C);
  const optD = escapeSqlString(q.options.D);
  const correct = escapeSqlString(q.correct);
  const timeLimit = 20;

  return `(${cat}, ${diff}, ${text}, ${optA}, ${optB}, ${optC}, ${optD}, ${correct}, ${timeLimit})`;
});

const fullSql = header + rows.join(',\n') + ';\n';

const outputPath = path.resolve(process.cwd(), 'supabase/seed_500_homebrewing.sql');
fs.writeFileSync(outputPath, fullSql, 'utf8');

console.log(`✅ Generated ${questions.length} questions into: ${outputPath}`);
