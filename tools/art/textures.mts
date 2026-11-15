/**
 * Terrain material tiles and edge colours for the Roku terrain painter.
 *
 * The web game shades every terrain pixel in a per-pixel software shader
 * (src/render/TerrainChunks.ts) and re-runs it around every edit. That is far
 * beyond what BrightScript can do, so the Roku app paints terrain from
 *   - one pre-shaded seamless tile per material and biome (this file), which
 *     the device repeats into a 256 x 320 sheet, and
 *   - a handful of flat edge colours (grass / snow / moss caps, lit top edges,
 *     outlines), also derived here from the web game's biome palettes.
 *
 * The material functions below are the web shader's own (soil strata with
 * embedded stones, cracked rock, riveted steel, timber boards, one-way
 * chevrons, excavated cavity) with three changes that keep the whole set
 * under 100 KB: every lattice wraps so the tiles are seamless in both
 * directions, the noise periods are nudged to divide the tile size, and the
 * per-pixel grain is reduced so the palette PNGs compress well.
 */
import path from 'node:path';
import { createCanvas } from 'canvas';

/** On the device every material becomes a sheet this size (one terrain chunk). */
export const SHEET_W = 256;
export const SHEET_H = 320;

type RGB = [number, number, number];

function hash2(x: number, y: number, seed = 0): number {
  let h = Math.imul(x | 0, 374761393) ^ Math.imul(y | 0, 668265263) ^ Math.imul(seed | 0, 2246822519);
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}
const smooth = (t: number) => t * t * (3 - 2 * t);
const pm = (v: number, m: number) => ((v % m) + m) % m;

/** Bilinear value noise on a lattice that wraps every wrapX / wrapY cells. */
function vnoise(x: number, y: number, scale: number, seed: number, wrapX: number, wrapY: number): number {
  const fx = x / scale, fy = y / scale;
  const ix = Math.floor(fx), iy = Math.floor(fy);
  const tx = smooth(fx - ix), ty = smooth(fy - iy);
  const x0 = pm(ix, wrapX), x1 = pm(ix + 1, wrapX);
  const y0 = pm(iy, wrapY), y1 = pm(iy + 1, wrapY);
  const a = hash2(x0, y0, seed), b = hash2(x1, y0, seed);
  const c = hash2(x0, y1, seed), d = hash2(x1, y1, seed);
  return a + (b - a) * tx + (c - a) * ty + (a - b - c + d) * tx * ty;
}

const scale = (c: RGB, k: number): RGB => [c[0] * k, c[1] * k, c[2] * k];
const mix = (a: RGB, b: RGB, t: number): RGB => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
const smooth01 = (t: number) => { const x = t < 0 ? 0 : t > 1 ? 1 : t; return x * x * (3 - 2 * x); };
const clamp8 = (v: number) => Math.max(0, Math.min(255, Math.round(v)));
const hex = (c: RGB) => '#' + c.map((v) => clamp8(v).toString(16).padStart(2, '0')).join('');

export async function buildTerrainArt(SHEEP: string, biome: string) {
  const { PALETTES } = await import(path.join(SHEEP, 'src/render/palette.ts'));
  const pal = PALETTES[biome];
  const underground = biome !== 'meadow' && biome !== 'hills';

  // ---- soil (256 x 160): wavy strata, soft grain, embedded stones and pebbles
  const SW = 256, SH = 160;
  function strata(base: RGB): RGB[] {
    const warm: RGB = biome === 'storm' ? [120, 120, 132] : biome === 'caverns' ? [110, 84, 120] : [196, 120, 62];
    const sand: RGB = biome === 'storm' ? [150, 146, 150] : biome === 'caverns' ? [132, 112, 140] : [214, 170, 104];
    return [scale(base, 0.72), mix(base, warm, 0.35), base, mix(base, sand, 0.4), scale(mix(base, warm, 0.2), 0.85)];
  }
  function stone(sx: number, sy: number, cs: number, p: number, rmin: number, rmax: number, seed: number, base: RGB): RGB | null {
    const cx = Math.floor(sx / cs), cy = Math.floor(sy / cs);
    const wx = pm(cx, SW / cs), wy = pm(cy, SH / cs);
    if (hash2(wx, wy, seed) >= p) return null;
    const rad = rmin + hash2(wx, wy, seed + 1) * (rmax - rmin);
    const px = cx * cs + rad + 0.5 + hash2(wx, wy, seed + 2) * Math.max(0, cs - 2 * rad - 1);
    const py = cy * cs + rad + 0.5 + hash2(wx, wy, seed + 3) * Math.max(0, cs - 2 * rad - 1);
    const squash = 0.62 + hash2(wx, wy, seed + 4) * 0.3;
    const dx = (sx + 0.5 - px) / rad, dy = (sy + 0.5 - py) / (rad * squash);
    const q = dx * dx + dy * dy;
    if (q >= 1) return null;
    const hue = hash2(wx, wy, seed + 5);
    const light: RGB = biome === 'caverns' ? [170, 160, 196] : biome === 'storm' ? [176, 182, 196] : [222, 204, 168];
    const st = mix(mix(pal.rock, light, 0.35 + hue * 0.3), base, 0.18);
    if (q > 0.78) return scale(mix(st, base, 0.4), 0.72);
    const lit = -(dx * 0.6 + dy * 0.8);
    let rgb = scale(st, 1.02 + lit * 0.3);
    if (lit > 0.55 && q < 0.35) rgb = mix(rgb, [255, 255, 255], 0.25);
    return rgb;
  }
  function soil(sx: number, sy: number, base: RGB): RGB {
    const warp = (vnoise(sx, sy, 32, 3, SW / 32, SH / 32) - 0.5) * 18 + (vnoise(sx, sy, 8, 4, SW / 8, SH / 8) - 0.5) * 3;
    const yy = sy + warp;
    const layer = vnoise(0, yy, 16, 5, 1, SH / 16) * 0.75 + vnoise(sx / 32, yy, 4, 6, SW / 128, SH / 4) * 0.25;
    const tones = strata(base);
    const f = layer * (tones.length - 1);
    const li = Math.min(tones.length - 2, Math.floor(f));
    let rgb = mix(tones[li], tones[li + 1], smooth01((f - li - 0.35) / 0.3));
    const grain = vnoise(sx * 0.25, sy * 0.5, 2, 8, SW / 8, SH / 4);
    rgb = scale(rgb, 0.97 + grain * 0.06);
    const st = stone(sx, sy, 16, 0.16, 1.6, 3.4, 51, base);
    if (st) return st;
    const pb = stone(sx, sy, 8, 0.2, 0.6, 1.2, 56, base);
    if (pb) return pb;
    const n = hash2(pm(sx, SW), pm(sy, SH), 57);
    if (n > 0.991) rgb = scale(rgb, 1.16);
    else if (n < 0.011) rgb = scale(rgb, 0.8);
    if (underground && n > 0.997) rgb = pal.vein;
    return rgb;
  }

  // ---- rock (128 x 160): cracked stone blocks, bevelled, with mineral veins underground
  const RW = 128, RH = 160;
  function rock(sx: number, sy: number): RGB {
    const cs = 8;
    const cx = Math.floor(sx / cs), cy = Math.floor(sy / cs);
    let f1 = 1e9, f2 = 1e9, bx = 0, by = 0, bh = 0;
    for (let oy = -1; oy <= 1; oy++) {
      for (let ox = -1; ox <= 1; ox++) {
        const gx = cx + ox, gy = cy + oy;
        const wgx = pm(gx, RW / cs), wgy = pm(gy, RH / cs);
        const px = (gx + 0.15 + hash2(wgx, wgy, 81) * 0.7) * cs;
        const py = (gy + 0.15 + hash2(wgx, wgy, 82) * 0.7) * cs;
        const dx = sx - px, dy = (sy - py) * 1.25;
        const dd = dx * dx + dy * dy;
        if (dd < f1) { f2 = f1; f1 = dd; bx = px; by = py; bh = hash2(wgx, wgy, 83); }
        else if (dd < f2) f2 = dd;
      }
    }
    const edge = Math.sqrt(f2) - Math.sqrt(f1);
    if (edge < 0.9) return scale(pal.rockDark, 0.78);
    const bevel = -((sx - bx) * 0.55 + (sy - by) * 0.8) / cs;
    let rgb = scale(pal.rock, 0.86 + Math.round(bh * 4) * 0.05 + Math.round(bevel * 4) * 0.055);
    if (edge < 1.8) rgb = scale(rgb, 0.88);
    if (underground) {
      const ridge = 1 - Math.abs(2 * vnoise(sx, sy, 16, 13, RW / 16, RH / 16) - 1);
      if (ridge > 0.965) rgb = mix(rgb, pal.vein, 0.85);
      else if (ridge > 0.93) rgb = mix(rgb, pal.vein, 0.25);
    }
    return rgb;
  }

  // ---- steel (16 x 16): riveted plates
  function steel(sx: number, sy: number): RGB {
    const P = 16;
    const u = pm(sx, P), v = pm(sy, P);
    if (u < 1 || v < 1) return mix(pal.steel, pal.steelHi, 0.75);
    if (u >= P - 1 || v >= P - 1) return scale(pal.steel, 0.5);
    for (const [rx, ry] of [[3, 3], [12, 3], [3, 12], [12, 12]]) {
      const dx = u - (rx + 0.5), dy = v - (ry + 0.5);
      const q = dx * dx + dy * dy;
      if (q < 1.3) return q < 0.35 && dx < 0 && dy < 0 ? [255, 255, 255] : q < 0.8 ? pal.steelHi : scale(pal.steel, 0.55);
    }
    const sheen = ((u + v) % P) / P;
    const stripe = sheen > 0.28 && sheen < 0.4 ? 0.08 : 0;
    return scale(pal.steel, 1.08 - Math.round((v / P) * 4) * 0.05 + stripe);
  }

  // ---- bridge (64 x 32): 2 px timber boards, 16 px long, staggered per row
  const BW = 64, BHT = 32;
  function planks(sx: number, sy: number): RGB {
    const BH = 2, L = 16;
    const row = pm(Math.floor(sy / BH), BHT / BH);
    const v = pm(sy, BH);
    const off = Math.floor(hash2(row, 0, 92) * L);
    const u = pm(sx + off, L);
    if (u === 0) return pal.bridgeDark;
    const grain = vnoise(sx * 0.125, sy * 2, 2, 93, BW / 16, BHT);
    let rgb = scale(pal.bridge, 0.86 + Math.round(grain * 3) * 0.07);
    if (v === 0) rgb = mix(rgb, [255, 240, 205], 0.35);
    else rgb = mix(rgb, pal.bridgeDark, 0.55);
    if ((u === 1 || u === L - 1) && v === 1) rgb = scale(pal.bridgeDark, 0.7);
    return rgb;
  }

  // ---- one-way earth (64 x 64): glowing chevrons that point the way a basher or miner may go
  function oneway(sx: number, sy: number, dir: number): RGB {
    const U = 16, V = 16;
    const u = pm(sx, U), v = pm(sy, V);
    const uu = dir === 1 ? u : U - 1 - u;
    const arm = Math.abs(v - V / 2) + (uu - 5);
    const base = scale(pal.onewayTint, 0.86 + Math.round(vnoise(sx, sy, 16, 5, 4, 4) * 3) * 0.06);
    if (uu >= 5 && uu <= 11 && v >= 2 && v <= 14) {
      if (arm >= 2 && arm <= 4) return mix(pal.arrow, [255, 255, 255], arm - 2 < 1 ? 0.35 : 0);
      if (arm >= 1 && arm <= 5) return mix(base, pal.arrow, 0.38);
    }
    return base;
  }

  // ---- cavity (128 x 160): the dark, banded backdrop left where ground was excavated
  const CW = 128, CH = 160;
  function cavity(sx: number, sy: number): RGB {
    const band = vnoise(sx * 0.3125, sy, 5, 11, CW / 16, CH / 5);
    const k = 0.78 + (Math.round(band * 6) / 6) * 0.32;
    return scale(pal.cavity, k * 0.86);
  }

  const cave = (c: RGB): RGB => (biome === 'caverns' ? mix(c, [40, 30, 70], 0.12) : c);
  // one interior light level stands in for the web shader's per-pixel depth darkening (1.0 at the surface, 0.62 deep)
  const BODY = 0.8;

  function tile(w: number, h: number, fn: (x: number, y: number) => RGB, light: number, useCave = true) {
    const canvas = createCanvas(w, h);
    const ctx = canvas.getContext('2d');
    const img = ctx.createImageData(w, h);
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        let c = scale(fn(x, y), light);
        if (useCave) c = cave(c);
        const i = (y * w + x) * 4;
        img.data[i] = clamp8(c[0]); img.data[i + 1] = clamp8(c[1]); img.data[i + 2] = clamp8(c[2]); img.data[i + 3] = 255;
      }
    }
    ctx.putImageData(img, 0, 0);
    return canvas;
  }

  // keyed by material name plus the cavity backdrop
  const tiles: Record<string, any> = {
    dirt: tile(SW, SH, (x, y) => soil(x, y, pal.dirt), BODY),
    rock: tile(RW, RH, rock, BODY),
    turf: tile(SW, SH, (x, y) => soil(x, y, pal.soil), BODY),
    bridge: tile(BW, BHT, planks, 0.96),
    steel: tile(16, 16, steel, 0.9),
    onewayl: tile(64, 64, (x, y) => oneway(x, y, -1), BODY + 0.08),
    onewayr: tile(64, 64, (x, y) => oneway(x, y, 1), BODY + 0.08),
    cavity: tile(CW, CH, cavity, 1, false),
  };
  for (const [name, c] of Object.entries(tiles)) {
    if (SHEET_W % c.width !== 0 || SHEET_H % c.height !== 0) throw new Error(`${name} tile does not divide the sheet`);
  }

  // ---- flat edge colours (hex strings, RGB)
  const lit = (c: RGB, k = 1.0) => hex(cave(scale(c, k)));
  const dark = (c: RGB, k = 0.5) => hex(cave(scale(c, k)));
  const capMid = pal.cap, capHi = pal.capHi;
  let cap: string[];
  if (biome === 'storm') {
    // snow: bright crust fading to blue shadow, then a blend into the ground
    const blue: RGB = [196, 214, 236];
    cap = [hex(capHi), hex(mix(capHi, blue, 0.3)), hex(mix(capHi, blue, 0.6)), hex(mix(mix(capHi, blue, 0.8), scale(pal.soil, BODY), 0.5))];
  } else if (biome === 'caverns') {
    // thin moss
    cap = [hex(cave(capHi)), hex(cave(scale(mix(capHi, capMid, 0.9), 0.95))), hex(cave(scale(mix(capMid, pal.soil, 0.5), 0.62)))];
  } else {
    // grass: lit blade tips, body, then the dark root line
    cap = [hex(scale(capHi, 1.02)), hex(mix(capHi, capMid, 0.55)), hex(scale(capMid, 0.98)), hex(scale(mix(capMid, pal.soil, 0.5), 0.62))];
  }
  const rockTop: RGB = biome === 'storm' ? [240, 246, 252] : [255, 248, 230];
  const colors = {
    // top edge (a solid pixel with open space above), by material id 0..7
    top: [
      '#000000',
      lit(mix(pal.dirt, capHi, 0.28)),
      lit(mix(pal.rock, rockTop, 0.3)),
      cap[0],
      lit(mix(pal.bridge, [255, 240, 205], 0.45)),
      lit(mix(pal.steel, pal.steelHi, 0.75)),
      lit(pal.onewayTint, 1.22),
      lit(pal.onewayTint, 1.22),
    ],
    // lip (a solid pixel with EXCAVATED space above: tunnel floors get a lit edge but never grass)
    lip: [
      '#000000',
      lit(pal.dirt, 1.02),
      lit(mix(pal.rock, rockTop, 0.18)),
      lit(pal.soil, 1.04),
      lit(mix(pal.bridge, [255, 240, 205], 0.45)),
      lit(mix(pal.steel, pal.steelHi, 0.75)),
      lit(pal.onewayTint, 1.22),
      lit(pal.onewayTint, 1.22),
    ],
    // outline (a solid pixel beside or over open space), by material id 0..7
    edge: [
      '#000000',
      dark(pal.dirt, 0.52), dark(pal.rock, 0.5), dark(pal.soil, 0.5), dark(pal.bridgeDark, 0.72),
      dark(pal.steel, 0.46), dark(pal.onewayTint, 0.5), dark(pal.onewayTint, 0.5),
    ],
    cap,
    cavityshade: hex(scale(pal.cavity, 0.5)),
    blades: biome === 'meadow' || biome === 'hills'
      ? [hex(scale(mix(capMid, capHi, 0.3), 0.86)), hex(mix(capMid, capHi, 0.6)), hex(scale(mix(capMid, capHi, 0.95), 1.1))]
      : [],
    flowers: biome === 'hills' ? ['#ffd65a', '#ff9646'] : biome === 'meadow' ? ['#ffffff', '#ffd65a', '#ff82aa'] : [],
    minimap: hex(pal.minimapSolid),
    minimapsteel: hex(pal.steel),
    debris: ['#000000', hex(pal.dirt), hex(pal.rock), hex(pal.soil), hex(pal.bridge), hex(pal.steel), hex(pal.onewayTint), hex(pal.onewayTint)],
    sky: pal.sky,
  };
  return { tiles, colors };
}
