/**
 * Engine parity gate.
 *
 * Runs the BrightScript engine (the exact files that ship in the channel) on
 * the brs-node simulator, plays the recorded winning solution of every stage,
 * and compares the outcome with tests/fixtures/expected.json, which was
 * produced by the web game's own TypeScript engine:
 *
 *   phase, end reason, saved, lost, end tick  and the 64-bit state hash that
 *   covers every counter, every sheep field and every terrain cell.
 *
 *   node run-replays.mjs                 all 129 stages (120 campaign + 9 lessons)
 *   node run-replays.mjs meadow-01 ...   just these
 *   node run-replays.mjs --act cave      one act
 *   node run-replays.mjs --quick         a 16-stage spread (used for fast local checks)
 *   node run-replays.mjs --jobs 4        worker processes (default: CPU count)
 */
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { ROOT, TOOLS, readJson } from './lib/common.mjs';
import { hashState } from './lib/statehash.mjs';

const expected = readJson(path.join(ROOT, 'tests', 'fixtures', 'expected.json'));
const argv = process.argv.slice(2);
const flag = (name) => {
  const i = argv.indexOf(name);
  if (i < 0) return undefined;
  const v = argv[i + 1];
  argv.splice(i, 2);
  return v;
};
const jobs = Math.max(1, Number(flag('--jobs') ?? os.cpus().length));
const act = flag('--act');
const quick = argv.includes('--quick');
const verbose = argv.includes('--verbose');
let ids = argv.filter((a) => !a.startsWith('--'));
if (ids.length === 0) ids = Object.keys(expected);
if (act) ids = ids.filter((id) => id.startsWith(act + '-'));
if (quick) {
  const all = Object.keys(expected);
  ids = all.filter((_, i) => i % 8 === 3);
}
for (const id of ids) if (!expected[id]) throw new Error(`no expected result for ${id}`);

const ENGINE_FILES = ['source/Terrain.brs', 'source/Engine.brs', 'source/EngineSkills.brs', 'source/Levels.brs', 'tests/replay_runner.brs'];
const CLI = path.join(TOOLS, 'node_modules', 'brs-node', 'bin', 'brs.cli.js');

function runBatch(batch) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [CLI, '--root', ROOT, '--no-sg', '-k', `levels=${batch.join('+')}`, ...ENGINE_FILES], {
      cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'],
    });
    let out = '', err = '';
    child.stdout.on('data', (d) => { out += d; });
    child.stderr.on('data', (d) => { err += d; });
    child.on('error', reject);
    child.on('close', () => resolve({ out, err }));
  });
}

function parse(out) {
  const results = [];
  let cur = null;
  for (const line of out.split(/\r?\n/)) {
    if (line.startsWith('RESULT|')) {
      const p = line.split('|');
      cur = {
        id: p[1], phase: p[2], reason: p[3], saved: +p[4], lost: +p[5], endTick: +p[6], invariantOk: p[7] === '1',
        rejected: +p[8], unusedInputs: +p[9], loadMs: +p[10], simMs: +p[11],
      };
      results.push(cur);
    } else if (line.startsWith('STATE|') && cur) {
      const p = line.split('|');
      const f = p[1].split(',').map(Number);
      Object.assign(cur, {
        tick: f[0], waiting: f[1], active: f[2], releaseRate: f[3], timeLeft: f[4], lastSpawnTick: f[5], hatchCursor: f[6],
        nuking: f[7] === 1, stock: p[2].split(',').map(Number), hatchSpawned: p[3] === '' ? [] : p[3].split(',').map(Number),
      });
    } else if (line.startsWith('SHEEP|') && cur) {
      const body = line.slice(6);
      cur.sheep = body === '' ? [] : body.split(';').map((r) => {
        const v = r.split(',');
        return {
          id: +v[0], x: +v[1], y: +v[2], dir: +v[3], state: v[4], canClimb: v[5] === '1', canFloat: v[6] === '1',
          bomberTicks: +v[7], fallDistance: +v[8], stateTicks: +v[9], bricks: +v[10], fate: v[11],
        };
      });
    } else if (line.startsWith('TERRAIN|') && cur) {
      const p = line.split('|');
      cur.dims = { w: +p[1], h: +p[2], pad: +p[3], len: +p[4] };
      cur.b64 = [];
    } else if (line.startsWith('T|') && cur?.b64) {
      cur.b64.push(line.slice(2));
    } else if (line === 'TERRAIN-END' && cur?.b64) {
      const { w, h, pad, len } = cur.dims;
      const text = cur.b64.join('');
      if (text.length !== len) throw new Error(`${cur.id}: terrain dump truncated`);
      const padded = Buffer.from(text, 'base64');
      const stride = w + 2 * pad;
      if (padded.length !== stride * (h + 2 * pad)) throw new Error(`${cur.id}: unexpected terrain size`);
      const cells = new Uint8Array(w * h);
      for (let y = 0; y < h; y++) cells.set(padded.subarray((y + pad) * stride + pad, (y + pad) * stride + pad + w), y * w);
      // the padding must be untouched: steel above, open air beside and below
      for (let y = 0; y < h + 2 * pad; y++) {
        for (let x = 0; x < stride; x++) {
          const inside = y >= pad && y < pad + h && x >= pad && x < pad + w;
          if (inside) { x = pad + w - 1; continue; }
          const want = y < pad ? 5 : 0;
          if (padded[y * stride + x] !== want) throw new Error(`${cur.id}: padding corrupted at ${x - pad},${y - pad}`);
        }
      }
      cur.cells = cells;
      delete cur.b64;
    } else if (line.startsWith('ERROR|')) {
      throw new Error(line);
    }
  }
  return results;
}

const t0 = Date.now();
// spread long stages across workers: interleave the id list
const batches = Array.from({ length: Math.min(jobs, ids.length) }, () => []);
ids.forEach((id, i) => batches[i % batches.length].push(id));
const outputs = await Promise.all(batches.map(runBatch));

let pass = 0;
const failures = [];
const seen = new Set();
let simMs = 0, ticks = 0;
for (const { out, err } of outputs) {
  if (!out.includes('RUNNER-DONE')) {
    failures.push(`a simulator worker did not finish:\n${out.slice(-2000)}\n${err.slice(-2000)}`);
  }
  for (const r of parse(out)) {
    seen.add(r.id);
    const e = expected[r.id];
    const problems = [];
    if (r.phase !== e.phase) problems.push(`phase ${r.phase} != ${e.phase}`);
    if (r.reason !== (e.reason ?? '')) problems.push(`reason ${r.reason} != ${e.reason}`);
    if (r.saved !== e.saved) problems.push(`saved ${r.saved} != ${e.saved}`);
    if (r.lost !== e.lost) problems.push(`lost ${r.lost} != ${e.lost}`);
    if (r.endTick !== e.endTick) problems.push(`endTick ${r.endTick} != ${e.endTick}`);
    if (!r.invariantOk) problems.push('conservation invariant violated');
    if (r.rejected) problems.push(`${r.rejected} solution inputs rejected`);
    if (r.unusedInputs) problems.push(`${r.unusedInputs} solution inputs never applied`);
    let hash = '';
    if (r.cells && r.sheep) {
      hash = hashState({ ...r, endReason: r.reason });
      if (hash !== e.stateHash) problems.push(`state hash ${hash} != ${e.stateHash}`);
    } else problems.push('incomplete state dump');
    simMs += r.simMs;
    ticks += r.endTick;
    if (problems.length) failures.push(`${r.id}: ${problems.join('; ')}`);
    else pass++;
    if (verbose) console.log(`${problems.length ? 'FAIL' : 'ok  '} ${r.id.padEnd(15)} ${r.phase} saved ${r.saved} end ${r.endTick} hash ${hash} (${r.simMs} ms)`);
  }
}
for (const id of ids) if (!seen.has(id)) failures.push(`${id}: no result`);

const secs = ((Date.now() - t0) / 1000).toFixed(1);
console.log(`engine parity: ${pass}/${ids.length} stages identical to the web engine ` +
  `(${ticks} ticks, ${secs}s wall, ${(simMs / Math.max(1, ticks)).toFixed(2)} ms/tick in the simulator)`);
fs.mkdirSync(path.join(ROOT, 'tests', 'results'), { recursive: true });
fs.writeFileSync(path.join(ROOT, 'tests', 'results', 'engine-parity.json'),
  JSON.stringify({ stages: ids.length, identical: pass, failures }, null, 1) + '\n');
if (failures.length) {
  console.error(failures.join('\n'));
  process.exit(1);
}
