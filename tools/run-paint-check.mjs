/**
 * Terrain paint check.
 *
 * Runs tests/paint_check.brs on the brs-node simulator for a spread of stages
 * (every biome, one-way walls, steel, bridges) and fails if the fast first
 * paint and the cell-by-cell repaint used after every dig ever disagree by a
 * single pixel - which on a TV would show as a seam around each edit.
 *
 *   node run-paint-check.mjs                    the default spread
 *   node run-paint-check.mjs meadow-05 cave-09  just these
 */
import { spawn } from 'node:child_process';
import os from 'node:os';
import path from 'node:path';
import { ROOT, TOOLS } from './lib/common.mjs';

const CLI = path.join(TOOLS, 'node_modules', 'brs-node', 'bin', 'brs.cli.js');
const FILES = ['Util', 'Gfx', 'Assets', 'Terrain', 'TerrainPaint', 'Engine', 'EngineSkills', 'Levels'].map((f) => `source/${f}.brs`).concat('tests/paint_check.brs');
let ids = process.argv.slice(2).filter((a) => !a.startsWith('--'));
if (ids.length === 0) ids = ['lesson-digger', 'meadow-20', 'hill-11', 'cave-09', 'storm-05'];

function run(id) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [CLI, '--root', ROOT, '--no-sg', '-k', `levels=${id}`, ...FILES], { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'] });
    let out = '';
    child.stdout.on('data', (d) => { out += d; });
    child.on('error', reject);
    child.on('close', () => resolve(out));
  });
}

const t0 = Date.now();
const queue = [...ids];
const outputs = [];
await Promise.all(Array.from({ length: Math.min(os.cpus().length, ids.length) }, async () => {
  while (queue.length) outputs.push(await run(queue.shift()));
}));
let failed = 0;
const seen = new Set();
for (const out of outputs) {
  if (!out.includes('PAINT-DONE')) { failed++; console.log(`FAIL a simulator run did not finish:\n${out.slice(-1500)}`); }
  for (const line of out.split(/\r?\n/)) {
    if (line.startsWith('ERROR|')) { failed++; console.log(`FAIL ${line}`); }
    if (!line.startsWith('PAINT|')) continue;
    const [, id, w, chunks, pristineDiff, spots, editDiff, bandMs, cellMs, changed, bytes] = line.split('|');
    seen.add(id);
    const problems = [];
    if (+pristineDiff) problems.push(`${pristineDiff} of ${chunks} chunks differ between the band paint and the cell paint`);
    if (+editDiff) problems.push(`${editDiff} of ${chunks} chunks differ between incremental and full repaint after edits`);
    if (!+changed || !+spots) problems.push('the test edits did not change the picture (vacuous run)');
    if (+bytes < 1000) problems.push('pixels could not be read back');
    if (problems.length) failed++;
    console.log(`${problems.length ? 'FAIL' : 'ok  '} ${id.padEnd(14)} ${w} px wide, ${chunks} chunks, ${spots} edits repainted; first paint ${bandMs} ms vs ${cellMs} ms cell by cell`);
    for (const p of problems) console.log(`   - ${p}`);
  }
}
for (const id of ids) if (!seen.has(id)) { failed++; console.log(`FAIL ${id}: no result`); }
console.log(`paint check: ${ids.length - failed}/${ids.length} stages pixel-identical in ${((Date.now() - t0) / 1000).toFixed(1)}s`);
if (failed) process.exit(1);
