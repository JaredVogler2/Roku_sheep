/**
 * Parallax backdrops, rendered with the web game's own BackgroundParallax
 * painter (sun, clouds, ranges, patchwork fields, windmills, crystal caverns,
 * storm peaks, pines) and then regrouped for the Roku fill-rate budget:
 *
 *   far   sky gradient + every layer that moves at <= 8 % of the camera,
 *         flattened into ONE opaque image (stored as JPEG)
 *   mid   the middle layer, with alpha
 *   near  the nearest layer, with alpha
 *
 * The web game paints these at 2x and gives every stage its own seed. Here
 * each biome gets one set at 1 px per world pixel (1024 x 320, tileable
 * horizontally); the device stretches it 2x with bilinear filtering, which
 * suits scenery that is meant to stay hazier than the playfield.
 */
import path from 'node:path';
import { createCanvas } from 'canvas';

export const BG_W = 1024;
export const BG_H = 320;

const SEEDS: Record<string, number> = { meadow: 71, hills: 242, caverns: 5, storm: 913 };

export async function buildBackground(SHEEP: string, biome: string) {
  const B = await import(path.join(SHEEP, 'src/render/BackgroundParallax.ts'));
  const bg: any = new B.BackgroundParallax(biome, BG_H, SEEDS[biome]);
  const layers: { canvas: any; factor: number; top: number }[] = bg.layers;
  const sky: any = bg.skyCanvas;

  // every layer back at full height, 1 px per world pixel
  const full = layers.map((l) => {
    const c = createCanvas(BG_W, BG_H);
    const ctx = c.getContext('2d');
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(l.canvas, 0, l.top, BG_W, l.canvas.height / 2);
    return { canvas: c, factor: l.factor };
  });

  const farLayers = full.filter((l) => l.factor <= 0.08);
  const rest = full.filter((l) => l.factor > 0.08);
  if (rest.length !== 2) throw new Error(`${biome}: expected two foreground layers, found ${rest.length}`);

  const far = createCanvas(BG_W, BG_H);
  const fctx = far.getContext('2d');
  fctx.drawImage(sky, 0, 0, sky.width, sky.height, 0, 0, BG_W, BG_H);
  for (const l of farLayers) fctx.drawImage(l.canvas, 0, 0);
  const farFactor = farLayers.length ? farLayers.reduce((s, l) => s + l.factor, 0) / farLayers.length : 0.04;

  const crop = (c: any) => {
    // drop fully transparent rows from the top (saves fill-rate and bytes)
    const d = c.getContext('2d').getImageData(0, 0, BG_W, BG_H).data;
    let top = 0;
    scan: for (let y = 0; y < BG_H; y++) {
      for (let x = 0; x < BG_W; x++) if (d[(y * BG_W + x) * 4 + 3] !== 0) { top = y; break scan; }
      top = y + 1;
    }
    top = Math.max(0, top - 1);
    const out = createCanvas(BG_W, BG_H - top);
    out.getContext('2d').drawImage(c, 0, -top);
    return { canvas: out, top };
  };
  const mid = crop(rest[0].canvas);
  const near = crop(rest[1].canvas);

  return {
    far,
    mid: mid.canvas,
    near: near.canvas,
    meta: {
      w: BG_W, h: BG_H,
      far: { factor: Math.round(farFactor * 1000) / 1000 },
      mid: { factor: rest[0].factor, top: mid.top, h: mid.canvas.height },
      near: { factor: rest[1].factor, top: near.top, h: near.canvas.height },
    },
  };
}
