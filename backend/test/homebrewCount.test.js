import test from 'node:test';
import assert from 'node:assert/strict';
import { generate500HomebrewingQuestions } from '../../src/homebrewingDatabase.js';

test('src/homebrewingDatabase.js generates at least 500 unique questions', () => {
  const questions = generate500HomebrewingQuestions();
  assert.ok(questions.length >= 500, `Expected at least 500 questions, got ${questions.length}`);

  const seen = new Set();
  const duplicates = [];
  for (const q of questions) {
    const text = q.text.toLowerCase().trim();
    if (seen.has(text)) {
      duplicates.push(text);
    }
    seen.add(text);
  }

  assert.strictEqual(duplicates.length, 0, `Found duplicate questions: ${duplicates.slice(0, 5).join(', ')}`);
});
