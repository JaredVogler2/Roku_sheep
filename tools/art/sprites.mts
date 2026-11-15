/**
 * Sprite atlases rendered with the web game's own procedural art code:
 *   sheep.png          every pose of every animation, in the four equipment variants
 *   obj-<biome>.png    hatch, sheepfold (exit) and decor for one biome
 * All sprites are drawn at 2 px per world pixel, the scale of the 720p playfield.
 */
import path from 'node:path';
import { createCanvas } from 'canvas';
import { Atlas, worldCanvas } from '../lib/atlas.mjs';

export const SHEEP_ANIMS = ['walk', 'fall', 'float', 'climb', 'topout', 'block', 'build', 'shrug', 'bash', 'mine', 'dig', 'ohno', 'exit'];
export const WORLD_SCALE = 2;

/** Loop length in seconds and frame count for decor that moves. */
const DECOR_ANIM: Record<string, { n: number; period: number }> = {
  flag: { n: 4, period: (Math.PI * 2) / 4 },
  windmill: { n: 4, period: (Math.PI / 2) / 0.6 },
  'mill-wheel': { n: 4, period: (Math.PI / 4) / 0.4 },
  reeds: { n: 3, period: (Math.PI * 2) / 1.5 },
  willow: { n: 3, period: Math.PI * 2 },
  lantern: { n: 2, period: (Math.PI * 2) / 9 },
  torch: { n: 2, period: (Math.PI * 2) / 9 },
  mushroom: { n: 2, period: Math.PI },
  crystal: { n: 2, period: (Math.PI * 2) / 1.6 },
};

export async function buildSheepAtlas(SHEEP: string) {
  const S = await import(path.join(SHEEP, 'src/render/SheepSpriteSystem.ts'));
  const sys = new S.SheepSpriteSystem();
  sys.setScale(WORLD_SCALE, false);
  const k = WORLD_SCALE * S.SHEEP_VISUAL_SCALE;
  const atlas = new Atlas('sheep', 1024);
  const counts: number[] = [];
  for (const anim of SHEEP_ANIMS) {
    const n = S.ANIM_FRAMES[anim];
    counts.push(n);
    for (let variant = 0; variant < 4; variant++) {
      for (let f = 0; f < n; f++) {
        const { canvas, box } = sys.frame(anim, f, (variant & 1) === 1, (variant & 2) === 2);
        // the pose is drawn with the foot anchor at (-box.x, -box.y) world units
        atlas.add(`${anim}.${variant}.${f}`, canvas, -box.x * k, -box.y * k);
      }
    }
  }
  atlas.pack();
  // frames[anim][variant][frame] = [x, y, w, h, ox, oy]
  const m = atlas.meta();
  const frames = SHEEP_ANIMS.map((anim, ai) =>
    [0, 1, 2, 3].map((v) => Array.from({ length: counts[ai] }, (_, f) => m[`${anim}.${v}.${f}`])));
  return { atlas, meta: { anims: SHEEP_ANIMS, counts, frames } };
}

/** Which decor kinds each biome actually uses, from the compiled stages. */
export function decorByBiome(levels: any[]): Record<string, string[]> {
  const out: Record<string, Set<string>> = {};
  for (const lv of levels) {
    const set = (out[lv.theme] ??= new Set());
    for (const d of lv.decor) set.add(d[0]);
  }
  return Object.fromEntries(Object.entries(out).map(([b, s]) => [b, [...s].sort()]));
}

export async function buildBiomeAtlas(SHEEP: string, biome: string, decorKinds: string[]) {
  const O = await import(path.join(SHEEP, 'src/render/ObjectArt.ts'));
  const atlas = new Atlas(`obj-${biome}`, 1024);
  const sc = WORLD_SCALE;

  // ---- hatch: frame for each facing, trapdoors at six openness steps
  for (const dir of [1, -1]) {
    const { canvas, ctx, ax, ay } = worldCanvas(80, 90, sc, 40, 70);
    O.drawHatch(ctx, { id: 'h', x: 0, y: 0, dir }, 100000, biome, 'frame');
    atlas.add(`hatch.${dir > 0 ? 'r' : 'l'}`, canvas, ax, ay);
  }
  const DOOR_STEPS = 6;
  for (let i = 0; i < DOOR_STEPS; i++) {
    const { canvas, ctx, ax, ay } = worldCanvas(80, 90, sc, 40, 70);
    // openness = tick / HATCH_OPEN_TICKS (17)
    O.drawHatch(ctx, { id: 'h', x: 0, y: 0, dir: 1 }, Math.round((i / (DOOR_STEPS - 1)) * 17), biome, 'doors');
    atlas.add(`doors.${i}`, canvas, ax, ay);
  }

  // ---- sheepfold: four frames of the breathing glow (and the waving flag / lantern flicker)
  const EXIT_FRAMES = 4;
  for (let f = 0; f < EXIT_FRAMES; f++) {
    const { canvas, ctx, ax, ay } = worldCanvas(120, 100, sc, 60, 80);
    const time = (f / EXIT_FRAMES) * ((Math.PI * 2) / 2.2);
    O.drawExit(ctx, { id: 'e', x: 0, y: 0 }, biome, time);
    atlas.add(`exit.${f}`, canvas, ax, ay);
  }

  // ---- decor
  const decor: Record<string, number> = {};
  const decorMs: Record<string, number> = {};
  for (const kind of decorKinds) {
    const anim = DECOR_ANIM[kind];
    const n = anim ? anim.n : 1;
    decor[kind] = n;
    // milliseconds each frame stays up, so the loop lasts as long as it does on the web
    decorMs[kind] = anim ? Math.max(60, Math.round((anim.period * 1000) / n)) : 1000;
    for (let f = 0; f < n; f++) {
      const { canvas, ctx, ax, ay } = worldCanvas(160, 140, sc, 80, 120);
      O.drawDecor(ctx, { kind, x: 0, y: 0 }, biome, anim ? (f / n) * anim.period : 0);
      atlas.add(`decor.${kind}.${f}`, canvas, ax, ay);
    }
  }

  atlas.pack();
  return { atlas, meta: { sprites: atlas.meta(), decorframes: decor, decorms: decorMs, doorsteps: DOOR_STEPS, exitframes: EXIT_FRAMES } };
}

export function contactSheet(atlas: Atlas, bg = '#5f97c0') {
  const c = createCanvas(atlas.canvas.width, atlas.canvas.height);
  const ctx = c.getContext('2d');
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, c.width, c.height);
  ctx.drawImage(atlas.canvas, 0, 0);
  return c;
}
