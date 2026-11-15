/**
 * Compiles every stage of the SHEEPFALL web game into the compact level pack
 * the Roku app loads (pkg:/levels/*.json).
 *
 * The original authoring format is a list of vector terrain operations that the
 * web engine rasterises with floating-point polygon maths. BrightScript on a
 * low-end Roku is far too slow to do that per pixel (a stage is 0.2 - 1.0
 * million cells), so the mask is rasterised HERE with the web game's own
 * rasteriser and stored as run-length encoded row bands. On the device a band
 * becomes one native String()/FromHexString() call, so a stage decodes in a few
 * milliseconds and is bit-identical to the web game's collision grid.
 *
 * Every mask is checked against the stage's published geometryHash, and the
 * decoder used on the device is mirrored below and round-tripped.
 *
 *   npx tsx build-levels.mts [--sheep ../Sheep]
 */
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { ACTS, ROOT, SKILLS, SOURCE_COMMIT_FILE, fmtBytes, listJson, readJson, sheepRepo, writeFileIfChanged } from './lib/common.mjs';

const SHEEP = sheepRepo();
const { compileLevel } = await import(path.join(SHEEP, 'src/engine/Level.ts'));
const { playReplay } = await import(path.join(SHEEP, 'src/engine/Replay.ts'));

const OUT = path.join(ROOT, 'levels');
const FIXTURES = path.join(ROOT, 'tests', 'fixtures');

interface Band { h: number; runs: number[] }

/** Row bands: consecutive identical rows collapse into one [height, material, length, ...] entry. */
function toBands(cells: Uint8Array, w: number, h: number): Band[] {
  const bands: Band[] = [];
  let prevKey = '';
  for (let y = 0; y < h; y++) {
    const runs: number[] = [];
    let x = 0;
    const row = y * w;
    while (x < w) {
      const m = cells[row + x];
      let n = 1;
      while (x + n < w && cells[row + x + n] === m) n++;
      runs.push(m, n);
      x += n;
    }
    const key = runs.join(',');
    if (key === prevKey) bands[bands.length - 1].h++;
    else { bands.push({ h: 1, runs }); prevKey = key; }
  }
  return bands;
}

/** Mirror of the device decoder (source/Terrain.brs) used to prove the encoding round-trips. */
function fromBands(rows: number[][], w: number, h: number): Uint8Array {
  const cells = new Uint8Array(w * h);
  let y = 0;
  for (const r of rows) {
    const bh = r[0];
    let x = 0;
    for (let k = 1; k < r.length; k += 2) {
      const m = r[k], n = r[k + 1];
      for (let j = 0; j < bh; j++) cells.fill(m, (y + j) * w + x, (y + j) * w + x + n);
      x += n;
    }
    if (x !== w) throw new Error('band width mismatch');
    y += bh;
  }
  if (y !== h) throw new Error('band height mismatch');
  return cells;
}

function sha256Hex(data: Uint8Array): string {
  return crypto.createHash('sha256').update(data).digest('hex');
}

function encodeInputs(inputs: any[]): number[][] {
  return [...inputs].sort((a, b) => a.tick - b.tick).map((i) => {
    switch (i.type) {
      case 'assign': return [i.tick, 0, i.sheepId, SKILLS.indexOf(i.skill)];
      case 'rate': return [i.tick, 1, i.value, 0];
      case 'nuke': return [i.tick, 2, 0, 0];
      case 'finish': return [i.tick, 3, 0, 0];
      default: throw new Error(`unknown input ${i.type}`);
    }
  });
}

const manifest = readJson(path.join(SHEEP, 'src/content/manifest.json'));
const codes = readJson(path.join(SHEEP, 'src/content/access-codes.v1.json')).codesByStageId as Record<string, string>;

const index: any = { schema: 1, physics: manifest.physicsPreset, stages: [], lessons: [] };
/**
 * Tutorial cards are written for a mouse and number keys. The rules they teach
 * are unchanged; only the "how to press it" wording is adapted to a TV remote.
 */
function tutorialForRemote(id: string, cards: string[]): string[] {
  const out = cards.map((t) => t
    .replace(/ \(key \d\)/g, '')
    .replace(/, then click /g, ', then press OK on ')
    .replace(/ and click /g, ' and press OK on ')
    .replace(/\bclick\b/g, 'press OK on'));
  for (const t of out) {
    if (/\b(click|mouse|keyboard|key \d)\b/i.test(t)) throw new Error(`${id}: tutorial still mentions pointer or keyboard input: ${t}`);
  }
  // the first stage needs no input, so it is the calm place to introduce the remote
  if (id === 'meadow-01') {
    out.push('On your remote: the arrows move the cursor and the view follows it. Rewind and Fast Forward change the skill in hand, and OK gives it to the sheep in the ring. Play/Pause freezes time while you aim.');
  }
  return out;
}

const expected: Record<string, any> = {};
let written = 0, bytes = 0, maxBands = 0, maxRuns = 0;

function build(dir: string, isLesson: boolean): void {
  for (const f of listJson(path.join(SHEEP, dir))) {
    const def = readJson(path.join(SHEEP, dir, f));
    const level = compileLevel(def, false);
    const cells: Uint8Array = level.baseTerrain.cells;
    if (def.geometryHash && def.geometryHash !== level.geometryHash) {
      throw new Error(`${def.id}: rasterised geometry does not match the published geometryHash`);
    }
    if (def.height !== 320) throw new Error(`${def.id}: unexpected height ${def.height}`);
    const bands = toBands(cells, def.width, def.height);
    const rows = bands.map((b) => [b.h, ...b.runs]);
    const back = fromBands(rows, def.width, def.height);
    if (sha256Hex(back) !== sha256Hex(cells)) throw new Error(`${def.id}: band encoding does not round-trip`);
    maxBands = Math.max(maxBands, bands.length);
    maxRuns = Math.max(maxRuns, ...bands.map((b) => b.runs.length / 2));

    let sol: number[][] = [];
    const replayPath = def.solutionReplayId ? path.join(SHEEP, def.solutionReplayId) : '';
    if (replayPath && fs.existsSync(replayPath)) {
      const replay = readJson(replayPath);
      if (replay.levelContentHash !== level.contentHash) throw new Error(`${def.id}: replay is for different content`);
      sol = encodeInputs(replay.inputs);
      // Re-run the committed solution on the web engine so the fixture is what that engine does today.
      const out = playReplay(level, replay.inputs);
      const e = replay.expected;
      if (!e || e.finalStateHash !== out.stateHash || e.endTick !== out.endTick || e.saved !== out.saved) {
        throw new Error(`${def.id}: committed replay no longer reproduces on the web engine`);
      }
      expected[def.id] = {
        phase: out.phase, reason: out.reason, saved: out.saved, lost: out.lost, endTick: out.endTick,
        stateHash: out.stateHash, geometryHash: level.geometryHash, inputs: sol.length,
      };
    } else if (!isLesson) {
      throw new Error(`${def.id}: no committed solution replay`);
    }

    const out: any = {
      id: def.id,
      act: def.act,
      index: def.index,
      title: def.title,
      desc: def.description,
      hint: def.goalHint ?? '',
      tut: tutorialForRemote(def.id, def.tutorial ?? []),
      code: isLesson ? '' : codes[def.id],
      w: def.width,
      h: def.height,
      theme: def.theme,
      music: def.musicTrackId,
      total: def.sheepTotal,
      req: def.requiredCount,
      time: def.timeLimitTicks,
      minrate: def.minReleaseRate,
      rate: def.initialReleaseRate,
      skills: SKILLS.map((s) => def.abilities[s] ?? 0),
      cam: def.cameraStartX ?? 0,
      remix: def.remixOf ?? '',
      ent: def.entrances.map((e: any) => [e.x, e.y, e.dir, e.sheepCount ?? -1, e.startDelayTicks ?? 0]),
      exits: def.exits.map((e: any) => [e.x, e.y, e.triggerW ?? 9, e.triggerH ?? 12]),
      haz: def.hazards.map((h: any) => [h.type, h.x, h.y, h.w, h.h, h.phaseTicks ?? 0, h.cooldownTicks ?? 0, h.offsetTicks ?? 0]),
      decor: def.decor.map((d: any) => [d.kind, d.x, d.y, d.s ?? 1, d.flip ? 1 : 0, d.layer === 'front' ? 1 : 0]),
      rows,
      sol,
    };
    if (!isLesson && !codes[def.id]) throw new Error(`${def.id}: no access code`);
    const text = JSON.stringify(out);
    if (writeFileIfChanged(path.join(OUT, `${def.id}.json`), text)) written++;
    bytes += text.length;

    const entry = {
      id: def.id, title: def.title, code: out.code, theme: def.theme, total: def.sheepTotal, req: def.requiredCount,
    };
    (isLesson ? index.lessons : index.stages).push(entry);
  }
}

build('src/content/levels', false);
build('src/content/lessons', true);

// campaign order: act, then stage number
index.stages.sort((a: any, b: any) => {
  const [aa, ai] = a.id.split('-'), [ba, bi] = b.id.split('-');
  return ACTS.indexOf(aa) - ACTS.indexOf(ba) || Number(ai) - Number(bi);
});
if (index.stages.length !== 120) throw new Error(`expected 120 stages, found ${index.stages.length}`);
if (new Set(index.stages.map((s: any) => s.code)).size !== 120) throw new Error('access codes are not unique');

writeFileIfChanged(path.join(OUT, 'index.json'), JSON.stringify(index));
writeFileIfChanged(path.join(FIXTURES, 'expected.json'), JSON.stringify(expected, null, 1) + '\n');

let commit = 'unknown';
try { commit = execFileSync('git', ['-C', SHEEP, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim(); } catch { /* not a checkout */ }
writeFileIfChanged(SOURCE_COMMIT_FILE, `${commit}\n`);

console.log(`levels: ${index.stages.length} stages + ${index.lessons.length} lessons, ${written} files changed, ` +
  `${fmtBytes(bytes)} JSON, widest band list ${maxBands} bands / ${maxRuns} runs, source ${commit.slice(0, 7)}`);
