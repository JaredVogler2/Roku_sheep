// Shared helpers for the SHEEPFALL Roku build tools.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const TOOLS = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
export const ROOT = path.dirname(TOOLS);

/** Commit of JaredVogler2/Sheep the committed assets were generated from. */
export const SOURCE_COMMIT_FILE = path.join(ROOT, 'docs', 'SOURCE_COMMIT');

export const SKILLS = ['climber', 'floater', 'bomber', 'blocker', 'builder', 'basher', 'miner', 'digger'];
export const SKILL_LABELS = ['Climb', 'Parachute', 'Boom', 'Block', 'Build', 'Bash', 'Mine', 'Dig'];
export const ACTS = ['meadow', 'hill', 'cave', 'storm'];
export const BIOMES = ['meadow', 'hills', 'caverns', 'storm'];

/**
 * Locate the checkout of the original web game. Order: --sheep <path>,
 * $SHEEP_REPO, then a few sibling directories.
 */
export function sheepRepo(argv = process.argv) {
  const i = argv.indexOf('--sheep');
  const candidates = [
    i >= 0 ? argv[i + 1] : null,
    process.env.SHEEP_REPO,
    path.join(ROOT, '..', 'Sheep'),
    path.join(ROOT, '..', 'sheep'),
  ].filter(Boolean);
  for (const c of candidates) {
    const p = path.resolve(c);
    if (fs.existsSync(path.join(p, 'src', 'engine', 'Simulation.ts'))) return p;
  }
  throw new Error(
    'Cannot find the SHEEPFALL web repository. Clone https://github.com/JaredVogler2/Sheep next to this ' +
    'repository, or pass --sheep <path> / set SHEEP_REPO.',
  );
}

export function readJson(p) {
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

export function writeFileIfChanged(p, data) {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  const buf = Buffer.isBuffer(data) ? data : Buffer.from(data);
  if (fs.existsSync(p) && fs.readFileSync(p).equals(buf)) return false;
  fs.writeFileSync(p, buf);
  return true;
}

export function listJson(dir) {
  return fs.readdirSync(dir).filter((f) => f.endsWith('.json')).sort();
}

export function fmtBytes(n) {
  return n < 1024 ? `${n} B` : n < 1048576 ? `${(n / 1024).toFixed(1)} KB` : `${(n / 1048576).toFixed(2)} MB`;
}
