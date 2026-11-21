import { readFileSync } from 'node:fs';
import { gzipSync } from 'node:zlib';
const f = new URL('../dist/index.js', import.meta.url);
const kb = gzipSync(readFileSync(f)).length / 1024;
console.log(`@siagasos/js gzip: ${kb.toFixed(2)} KB (target < 10 KB)`);
if (kb >= 10) process.exit(1);
