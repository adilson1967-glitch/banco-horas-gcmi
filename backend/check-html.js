const fs = require('fs');
const vm = require('vm');
const path = require('path');

const file = path.join(__dirname, '..', 'public', 'index.html');
const html = fs.readFileSync(file, 'utf8');
const scripts = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map((m) => m[1]);

for (let i = 0; i < scripts.length; i += 1) {
  new vm.Script(scripts[i], { filename: `index-script-${i}.js` });
}

console.log(`OK: ${scripts.length} script(s) validado(s).`);
