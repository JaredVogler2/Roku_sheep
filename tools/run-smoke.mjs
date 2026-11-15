/**
 * App smoke test.
 *
 * Runs the whole channel (every file in source/ except main.brs, plus
 * tests/smoke_main.brs) on the brs-node BrightScript simulator with a scripted
 * remote, checks the state lines the script asks for, and saves screenshots to
 * build/smoke/ so the picture can be inspected.
 *
 *   node run-smoke.mjs                 every scenario below
 *   node run-smoke.mjs menus play      just these
 *   node run-smoke.mjs --script "w30+smenu"   an ad-hoc script (saved as "adhoc")
 *   node run-smoke.mjs --link storm-23 --script "w20+sbrief"   ... launched with a deep link
 *
 * This proves the app starts, every screen renders, the remote mapping works
 * and a stage can be won and lost end to end. It cannot prove frame rate or
 * audio: those need a real Roku.
 */
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { ROOT, TOOLS } from './lib/common.mjs';
import zlib from 'node:zlib';
import { crc32 } from './lib/zip.mjs';

const CLI = path.join(TOOLS, 'node_modules', 'brs-node', 'bin', 'brs.cli.js');
const OUT = path.join(ROOT, 'build', 'smoke');
const K = { back: 0, up: 2, down: 3, left: 4, right: 5, ok: 6, replay: 7, rew: 8, ff: 9, star: 10, play: 13 };
const tap = (name, times = 1) => Array.from({ length: times }, () => `k${K[name]}`).join('+');
/** Type a stage code on a keyboard (letters and digits only). */
const type = (text) => [...text.replace(/[^A-Z0-9]/g, '')].map((c) => `c${c.charCodeAt(0)}`).join('+');

/**
 * Scenarios: a script and the state lines it must print, in order.
 * Each `expect` entry is a regular expression matched against one INFO line.
 */
const SCENARIOS = {
  // every menu screen, by remote only
  menus: {
    script: [
      'w40', 'i', 'smain',
      tap('down', 2), tap('ok'), 'w4', 'i', 'sstages',
      tap('right', 2), tap('down'), 'w3', 'i',
      tap('ok'), 'w3', 'sstages-locked',
      tap('ff'), 'w3', 'i', 'sstages-act2',
      tap('back'), 'w4', 'i',
      tap('down', 3), tap('ok'), 'w4', 'i', 'shelp',
      tap('back'), 'w4',
      tap('down', 4), tap('ok'), 'w4', 'i', 'ssettings',
      tap('down', 3), tap('left'), 'w3', 'ssettings-changed', tap('right'),
      tap('back'), 'w4',
      tap('down', 5), tap('ok'), 'w4', 'i', 'scredits',
      tap('back'), 'w4', 'i',
    ].join('+'),
    expect: [/^INFO\|main$/, /^INFO\|stages\|act=0\|sel=0$/, /^INFO\|stages\|act=0\|sel=8$/, /^INFO\|stages\|act=1\|sel=8$/, /^INFO\|main$/,
      /^INFO\|help$/, /^INFO\|settings$/, /^INFO\|credits$/, /^INFO\|main$/],
  },
  // code entry: a wrong code is refused, a real one (typed with its SHP prefix) opens its stage brief
  codes: {
    script: [
      'w30', tap('down'), tap('ok'), 'w4', 'i', 'scode-empty',
      type('SHPAAAAAAAAA'), 'w2', tap('ok'), 'w3', 'i', 'scode-bad',
      tap('left'), tap('ok'), 'w3', 'i',                              // Clear
      tap('up'), tap('ok'), tap('rew'), tap('ok', 2), 'w2', 'i',       // on-screen keys and Rewind = delete
      tap('down'), tap('ok'),                                          // Clear again
      type('SHP-HF92-3BJ7-C'), 'w3', 'i', 'scode-typed', 'c13', 'w5', 'i', 'sbrief-code',
    ].join('+'),
    expect: [/^INFO\|code\|\|$/, /^INFO\|code\|AAAAAAAAA\|That code doesn't open/, /^INFO\|code\|\|$/, /^INFO\|code\|[A-Z2-9]{2}\|$/,
      /^INFO\|code\|HF923BJ7C\|$/, /^INFO\|brief\|meadow-02$/],
  },
  // stage 1 needs no help: start it from the title, pause, change speed, open the pause menu, win, continue
  play: {
    script: [
      'w30', tap('ok'), 'w4', 'i', 'sbrief', tap('ok'), 'w6', 'i', 'stutorial',
      tap('ok', 3), 'w30', 'i', 'splay-start', 'f170', 'w20', 'i', 'splay-mid',
      tap('play'), 'w3', 'i', 'splay-paused', tap('play'),
      tap('replay'), 'w2', 'i', tap('back'), 'w3', 'i', 'spause-menu', tap('back'),
      'f900', 'w130', 'i', 'sresult-win',
      tap('right', 2), tap('ok'), 'w8', 'i', 'f1100', 'w130', 'i',          // Watch my run, to its end
      tap('back'), 'w4', 'i', 'sstages-progress',                            // the brief's Back leads to Stage Select
      tap('back'), 'w4', 'i', 'smain-progress',
    ].join('+'),
    expect: [/^INFO\|brief\|meadow-01$/, /^INFO\|game\|meadow-01\|tick=0\|.*\|modal=tutorial$/, /^INFO\|game\|meadow-01\|tick=[1-9]\d*\|phase=0\|.*paused=false\|st=[\d.]*$/,
      /^INFO\|game\|meadow-01\|tick=\d+\|phase=0\|saved=0\|lost=0\|active=[1-9]/, /\|paused=true\|/, /\|speed=2x\|paused=false\|/, /\|modal=pause$/,
      /^INFO\|result\|meadow-01\|won=true\|saved=10\|medal=3\|next=meadow-02\|done=1$/, /^INFO\|game\|meadow-01\|.*\|replay$/, /^INFO\|brief\|meadow-01$/,
      /^INFO\|stages\|act=0\|sel=0$/, /^INFO\|main$/],
  },
  // the last stage, won with real inputs: the finale, and Stage Select afterwards
  finale: {
    script: ['w10', 'Wstorm-30', 'w130', 'i', 'sresult-final', tap('ok'), 'w5', 'i', 'sending', tap('ok'), 'w4', 'i', 'sstages-storm'].join('+'),
    expect: [/^INFO\|result\|storm-30\|won=true\|saved=\d+\|medal=[123]\|next=\|done=1$/, /^INFO\|ending$/, /^INFO\|stages\|act=3\|sel=29$/],
  },
  // a deep link (launch parameter) opens that stage's brief
  link: {
    extra: ['contentId=SHP-HF92-3BJ7-C'],
    script: ['w20', 'i', 'slink-brief', tap('back'), 'w4', 'i'].join('+'),
    expect: [/^INFO\|brief\|meadow-02$/, /^INFO\|stages\|act=0\|sel=1$/],
  },
  // a lesson with real input: aim, assign, toolbar, cursor travel, nuke (with its confirmation), lose, watch the answer
  lesson: {
    script: [
      'w30', tap('down', 3), tap('ok'), 'w4', tap('down', 7), tap('ok'), 'w6', 'i', tap('ok'), 'w4',
      'f60', 'w6', 'g0', 'w3', 'i', 'slesson-target', tap('ok'), 'f3', 'w4', 'i', 'slesson-digging',
      tap('star'), 'w3', 'i', tap('right', 3), 'w2', 'i', 'stoolbar-nuke', tap('up'), 'w2',
      'd5', 'w30', 'u5', 'w2', 'i', 'scursor-moved',
      'd3', 'w100', 'u3', tap('down'), 'w2', 'i',
      tap('right', 3), tap('ok'), 'w3', 'i', 'snuke-armed', tap('ok'), 'f220', 'w130', 'i', 'sresult-lose',
      tap('right', 2), tap('ok'), 'w8', 'i', 'swatching', tap('back'), 'w3', tap('down'), tap('ok'), 'w5', 'i',
    ].join('+'),
    expect: [/^INFO\|game\|lesson-digger\|tick=0\|/, /\|selected=7\|focus=-1\|.*\|target=0\|/, /\|st=10\./,
      /\|focus=9\|/, /\|focus=12\|/, /\|focus=-1\|cursor=(1[3-9]\d|2\d\d),/, /\|focus=9\|cursor=\d+,318\|/, /\|focus=12\|/,
      /^INFO\|result\|lesson-digger\|won=false\|/, /^INFO\|game\|lesson-digger\|.*\|replay$/, /^INFO\|help$/],
  },
  // Assisted Mode: turn it on in Settings, dig a shaft, rewind, and the ground is whole again
  assist: {
    script: [
      'w30', tap('down', 4), tap('ok'), 'w4', tap('down', 8), tap('ok'), 'w3', 'sassist-on', tap('back'), 'w4',
      'Slesson-digger', 'w4', tap('ok'), 'w3', 'f70', 'a0:7', 'f45', 'w4', 'i', 'sdug',
      tap('star'), tap('right', 3), 'w2', 'i', tap('ok'), 'w4', 'i', tap('ok'), 'w4', 'i', 'srewound',
    ].join('+'),
    // the dig starts at tick 70; snapshots are taken every 51 ticks: 102 (digging) and 51 (still walking, ground whole)
    expect: [/\|tick=11\d\|.*\|st=10\./, /\|focus=12\|/, /\|tick=10[2-6]\|.*\|st=10\./, /\|tick=5[1-5]\|.*\|st=[01]\./],
  },
  // recorded solutions across the four biomes and every kind of hazard: pictures to look at, and proof they load and run
  gallery: {
    script: ['w6',
      ...[['cave-30', 700], ['storm-05', 620], ['cave-21', 400], ['hill-11', 215], ['storm-13', 420], ['cave-09', 330], ['storm-23', 900], ['hill-28', 500]]
        .flatMap(([id, ticks]) => [`R${id}`, 'w4', `f${ticks}`, 't100', 'w25', 't16', 'w3', 'i', `s${id}`]),
      'Rlesson-climber', 'w4', 'f1200', 'w130', 'i',
    ].join('+'),
    expect: [...Array(8).fill(/^INFO\|game\|[a-z]+-\d\d\|tick=\d+\|phase=0\|.*\|replay$/), /^INFO\|help$/],
  },
};

/**
 * The simulator's GetPng writes the pixel data as a raw deflate stream, without
 * the zlib wrapper PNG requires, so most viewers reject the file. Re-wrap it.
 */
function repairPng(buf) {
  const chunks = [];
  let at = 8, idat = [];
  while (at < buf.length) {
    const len = buf.readUInt32BE(at);
    const type = buf.toString('latin1', at + 4, at + 8);
    const body = buf.subarray(at + 8, at + 8 + len);
    if (type === 'IDAT') idat.push(body); else chunks.push([type, body]);
    at += 12 + len;
  }
  const data = Buffer.concat(idat);
  let raw;
  try { raw = zlib.inflateSync(data); return buf; } catch { raw = zlib.inflateRawSync(data); }
  const out = [buf.subarray(0, 8)];
  const put = (type, body) => {
    const head = Buffer.alloc(8);
    head.writeUInt32BE(body.length, 0);
    head.write(type, 4, 'latin1');
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(Buffer.concat([head.subarray(4), body])), 0);
    out.push(head, body, crc);
  };
  for (const [type, body] of chunks) {
    if (type === 'IEND') put('IDAT', zlib.deflateSync(raw, { level: 6 }));
    put(type, body);
  }
  return Buffer.concat(out);
}

function run(name, script, extra = []) {
  return new Promise((resolve, reject) => {
    const files = fs.readdirSync(path.join(ROOT, 'source')).filter((f) => f.endsWith('.brs') && f !== 'main.brs').sort().map((f) => `source/${f}`);
    // launch parameters travel as one comma-separated list
    const args = [CLI, '--root', ROOT, '--no-sg', '-k', [`script=${script}`, ...extra].join(','), ...files, 'tests/smoke_main.brs'];
    const child = spawn(process.execPath, args, { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'] });
    let out = '', err = '';
    child.stdout.on('data', (d) => { out += d; });
    child.stderr.on('data', (d) => { err += d; });
    child.on('error', reject);
    child.on('close', () => {
      const dir = path.join(OUT, name);
      fs.rmSync(dir, { recursive: true, force: true });
      fs.mkdirSync(dir, { recursive: true });
      const info = [], perf = [], other = [], shots = [];
      let shot = null;
      for (const line of out.split(/\r?\n/)) {
        if (line.startsWith('SHOT|')) { const p = line.split('|'); shot = { name: p[1], len: +p[2], parts: [] }; }
        else if (line.startsWith('P|') && shot) shot.parts.push(line.slice(2));
        else if (line === 'SHOT-END' && shot) {
          const text = shot.parts.join('');
          if (text.length !== shot.len) other.push(`screenshot ${shot.name} truncated`);
          fs.writeFileSync(path.join(dir, `${shot.name}.png`), repairPng(Buffer.from(text, 'base64')));
          shots.push(shot.name);
          shot = null;
        } else if (line.startsWith('INFO|')) info.push(line);
        else if (line.startsWith('PERF|')) perf.push(line);
        else if (line.trim() !== '') other.push(line);
      }
      resolve({ info, perf, other, shots, err, done: out.includes('SMOKE-DONE') });
    });
  });
}

const argv = process.argv.slice(2);
const li = argv.indexOf('--link');
const link = li >= 0 ? argv.splice(li, 2)[1] : undefined;
const si = argv.indexOf('--script');
const names = argv.filter((a) => !a.startsWith('--'));
for (const n of si >= 0 ? [] : names) if (!SCENARIOS[n]) throw new Error(`unknown scenario "${n}" (have: ${Object.keys(SCENARIOS).join(', ')})`);
const todo = si >= 0 ? { adhoc: { script: argv[si + 1], expect: [], extra: link ? [`contentId=${link}`] : [] } } : Object.fromEntries(Object.entries(SCENARIOS).filter(([n]) => names.length === 0 || names.includes(n)));
const verbose = argv.includes('--verbose') || si >= 0;
let failed = 0;
const t0 = Date.now();
const results = await Promise.all(Object.entries(todo).map(async ([name, sc]) => [name, sc, await run(name, sc.script, sc.extra ?? [])]));
for (const [name, sc, r] of results) {
  const problems = [];
  if (!r.done) problems.push('the app did not run to the end of the script');
  const stray = r.other.filter((l) => !l.startsWith('SMOKE-DONE') && !l.startsWith('------ Finished'));
  if (stray.length) problems.push(`unexpected output:\n    ${stray.slice(0, 12).join('\n    ')}`);
  // the simulator has no network tools and no SceneGraph (the launch beacon needs a device): not our errors
  const errs = r.err.split('\n').filter((l) => l.trim() !== '' && !/Network Gateway|spawnSync ip|unknown classname "roSGNode"/.test(l));
  if (errs.length) problems.push(`stderr:\n    ${errs.slice(0, 12).join('\n    ')}`);
  sc.expect.forEach((re, i) => {
    if (!r.info[i] || !re.test(r.info[i])) problems.push(`state line ${i + 1}: expected ${re}, got ${r.info[i] ?? '(nothing)'}`);
  });
  if (r.info.length !== sc.expect.length && sc.expect.length) problems.push(`${r.info.length} state lines, expected ${sc.expect.length}`);
  console.log(`${problems.length ? 'FAIL' : 'ok  '} ${name}: ${r.shots.length} screenshots, ${r.info.length} state checks`);
  if (verbose || problems.length) {
    for (const l of r.info) console.log(`     ${l}`);
    for (const l of r.perf) console.log(`     ${l}`);
  }
  for (const p of problems) console.log(`   - ${p}`);
  if (problems.length) failed++;
}
console.log(`smoke: ${results.length - failed}/${results.length} scenarios passed in ${((Date.now() - t0) / 1000).toFixed(1)}s; screenshots in ${path.relative(ROOT, OUT)}/`);
fs.mkdirSync(path.join(ROOT, 'tests', 'results'), { recursive: true });
fs.writeFileSync(path.join(ROOT, 'tests', 'results', 'smoke.json'), JSON.stringify({ scenarios: results.length, passed: results.length - failed }, null, 1) + '\n');
if (failed) process.exit(1);
