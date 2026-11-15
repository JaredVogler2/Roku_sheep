/**
 * Builds the sideloadable / publishable channel package:  out/sheepfall-roku.zip
 *
 * Only what the Roku needs goes in: manifest, source/, images/, audio/, levels/.
 * Tools, tests and docs stay out. The script fails if anything the app loads
 * is missing, or if the package would exceed Roku's 4 MB limit for a channel.
 *
 *   node package.mjs [--out some/dir]
 */
import fs from 'node:fs';
import path from 'node:path';
import { ROOT, fmtBytes, readJson } from './lib/common.mjs';
import { buildZip } from './lib/zip.mjs';

const LIMIT = 4 * 1024 * 1024;
const outArg = process.argv.indexOf('--out');
const outDir = outArg >= 0 ? path.resolve(process.argv[outArg + 1]) : path.join(ROOT, 'out');

const INCLUDE = { source: ['.brs'], images: ['.png', '.jpg', '.json'], audio: ['.wav', '.mp3'], levels: ['.json'] };
// formats that are already compressed are stored, which also makes them quicker for the Roku to open
const STORED = new Set(['.png', '.jpg', '.mp3']);

const entries = [{ name: 'manifest', data: fs.readFileSync(path.join(ROOT, 'manifest')) }];
for (const [dir, exts] of Object.entries(INCLUDE)) {
  for (const f of fs.readdirSync(path.join(ROOT, dir)).sort()) {
    const ext = path.extname(f).toLowerCase();
    if (f.startsWith('.') || !exts.includes(ext)) continue;
    entries.push({ name: `${dir}/${f}`, data: fs.readFileSync(path.join(ROOT, dir, f)), store: STORED.has(ext) });
  }
}

// ---- everything the app will ask for must be present
const have = new Set(entries.map((e) => e.name));
const missing = [];
const need = (name, why) => { if (!have.has(name)) missing.push(`${name} (${why})`); };
const manifest = Object.fromEntries(fs.readFileSync(path.join(ROOT, 'manifest'), 'utf8').split(/\r?\n/)
  .filter((l) => l.includes('=') && !l.startsWith('#')).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]));
for (const key of ['title', 'major_version', 'minor_version', 'build_version', 'mm_icon_focus_fhd', 'mm_icon_focus_hd', 'splash_screen_fhd', 'splash_screen_hd']) {
  if (!manifest[key]) missing.push(`manifest key ${key}`);
}
for (const [key, value] of Object.entries(manifest)) if (value.startsWith('pkg:/')) need(value.slice(5), `manifest ${key}`);
need('source/main.brs', 'entry point');
const index = readJson(path.join(ROOT, 'levels', 'index.json'));
for (const st of [...index.stages, ...index.lessons]) need(`levels/${st.id}.json`, 'stage');
const tracks = new Set(['menu']);
for (const st of [...index.stages, ...index.lessons]) tracks.add(readJson(path.join(ROOT, 'levels', `${st.id}.json`)).music);
for (const t of tracks) need(`audio/music-${t}.mp3`, 'music track');
const audioBrs = fs.readFileSync(path.join(ROOT, 'source', 'Audio.brs'), 'utf8');
for (const m of audioBrs.matchAll(/^\s+\w+: \["(\w+)", \d+, \d+, \d+\]/gm)) need(`audio/sfx-${m[1]}.wav`, 'sound effect');
const art = readJson(path.join(ROOT, 'images', 'art.json'));
const walk = (v) => {
  if (typeof v === 'string') { if (v.startsWith('pkg:/')) need(v.slice(5), 'art.json'); }
  else if (v && typeof v === 'object') Object.values(v).forEach(walk);
};
walk(art);
if (missing.length) {
  console.error(`package: missing files:\n  ${missing.join('\n  ')}`);
  process.exit(1);
}

const { zip, sizes } = buildZip(entries);
const byDir = {};
for (const [name, size] of sizes) byDir[name.includes('/') ? name.split('/')[0] : name] = (byDir[name.includes('/') ? name.split('/')[0] : name] ?? 0) + size;
fs.mkdirSync(outDir, { recursive: true });
const file = path.join(outDir, 'sheepfall-roku.zip');
fs.writeFileSync(file, zip);
console.log(`package: ${path.relative(ROOT, file)}  ${fmtBytes(zip.length)} of ${fmtBytes(LIMIT)} allowed, ${entries.length} files ` +
  `(${Object.entries(byDir).sort((a, b) => b[1] - a[1]).map(([d, s]) => `${d} ${fmtBytes(s)}`).join(', ')})`);
if (zip.length > LIMIT) {
  console.error(`package: ${fmtBytes(zip.length - LIMIT)} over Roku's 4 MB channel limit`);
  process.exit(1);
}
