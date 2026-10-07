const fs = require('fs');
const path = require('path');
const vm = require('vm');

const dartCode = fs.readFileSync(path.join(__dirname, '../lib/shared/data/genre_questions_engine.dart'), 'utf8');

function convertDartGenerator(name, dartBody) {
  const jsName = name.replace(/^_/, '');
  // Trim trailing closing brace and whitespace if present
  let js = dartBody.trim();
  if (js.endsWith('}')) {
    js = js.slice(0, -1).trim();
  }

  // Replace final / var declarations
  js = js.replace(/\bfinal\s+/g, 'const ');
  js = js.replace(/\bvar\s+(\w+)\s+in\s+/g, 'const $1 of ');
  js = js.replace(/\bvar\s+/g, 'const ');
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
const converted = {};
let errors = 0;
while ((m = regex.exec(dartCode)) !== null) {
  const code = convertDartGenerator(m[1], m[2]);
  try {
    new vm.Script(code);
    converted[m[1]] = code;
  } catch (err) {
    console.error('Syntax error in', m[1], err.message);
    errors++;
  }
}

console.log('Converted successfully:', Object.keys(converted).length, 'Errors:', errors);
module.exports = { converted };
