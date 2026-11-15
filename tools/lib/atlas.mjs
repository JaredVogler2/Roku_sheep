// Sprite atlas builder for the SHEEPFALL Roku art pipeline.
//
// Sprites are rendered with the web game's own procedural drawing code on a
// node-canvas, trimmed to their opaque bounding box, de-duplicated by pixel
// content and shelf-packed. The metadata keeps, for every sprite, where it
// sits in the atlas and where its top-left corner is relative to the anchor
// it was drawn around, both in 720p screen pixels:
//
//     [atlasX, atlasY, width, height, offsetX, offsetY]
import crypto from 'node:crypto';
import { createCanvas } from 'canvas';

export const PAD = 2;

/** Opaque bounding box of an RGBA canvas, or null when it is fully transparent. */
export function bounds(canvas, alphaThreshold = 0) {
  const { width: w, height: h } = canvas;
  const d = canvas.getContext('2d').getImageData(0, 0, w, h).data;
  let x0 = w, y0 = h, x1 = -1, y1 = -1;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (d[(y * w + x) * 4 + 3] > alphaThreshold) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < 0) return null;
  return { x: x0, y: y0, w: x1 - x0 + 1, h: y1 - y0 + 1 };
}

export class Atlas {
  constructor(name, width = 1024) {
    this.name = name;
    this.width = width;
    this.items = [];
    this.byHash = new Map();
    this.entries = {};
  }

  /**
   * Add a sprite drawn on `canvas` around the anchor (ax, ay) in canvas pixels.
   * Returns the entry (shared when an identical image was added before).
   */
  add(key, canvas, ax, ay, opts = {}) {
    const b = opts.noTrim ? { x: 0, y: 0, w: canvas.width, h: canvas.height } : bounds(canvas);
    if (!b) {
      const e = { key, empty: true };
      this.entries[key] = e;
      return e;
    }
    const data = canvas.getContext('2d').getImageData(b.x, b.y, b.w, b.h);
    const hash = crypto.createHash('sha1').update(Buffer.from(data.data.buffer)).update(`${b.w}x${b.h}`).digest('hex');
    let item = this.byHash.get(hash);
    if (!item) {
      item = { w: b.w, h: b.h, data, x: 0, y: 0 };
      this.byHash.set(hash, item);
      this.items.push(item);
    }
    const e = { key, item, ox: Math.round(b.x - ax), oy: Math.round(b.y - ay) };
    this.entries[key] = e;
    return e;
  }

  /** Shelf-pack tallest first. Returns the atlas canvas. */
  pack() {
    const items = [...this.items].sort((a, b) => b.h - a.h || b.w - a.w);
    let x = PAD, y = PAD, shelf = 0;
    for (const it of items) {
      if (it.w + 2 * PAD > this.width) throw new Error(`${this.name}: sprite wider than the atlas (${it.w})`);
      if (x + it.w + PAD > this.width) { x = PAD; y += shelf + PAD; shelf = 0; }
      it.x = x;
      it.y = y;
      x += it.w + PAD;
      shelf = Math.max(shelf, it.h);
    }
    this.height = y + shelf + PAD;
    const canvas = createCanvas(this.width, this.height);
    const ctx = canvas.getContext('2d');
    for (const it of items) ctx.putImageData(it.data, it.x, it.y);
    this.canvas = canvas;
    return canvas;
  }

  /** key -> [x, y, w, h, ox, oy] (empty sprites are [0,0,0,0,0,0]). */
  meta() {
    const out = {};
    for (const [key, e] of Object.entries(this.entries)) {
      out[key] = e.empty ? [0, 0, 0, 0, 0, 0] : [e.item.x, e.item.y, e.item.w, e.item.h, e.ox, e.oy];
    }
    return out;
  }

  stats() {
    const used = this.items.reduce((n, it) => n + it.w * it.h, 0);
    return `${this.name}: ${Object.keys(this.entries).length} sprites, ${this.items.length} unique, ` +
      `${this.width}x${this.height}, ${Math.round((100 * used) / (this.width * this.height))}% filled`;
  }
}

/** A canvas whose 2D context draws in world units at `scale` px per unit around a centred anchor. */
export function worldCanvas(wWorld, hWorld, scale, anchorXWorld, anchorYWorld) {
  const canvas = createCanvas(Math.ceil(wWorld * scale), Math.ceil(hWorld * scale));
  const ctx = canvas.getContext('2d');
  const ax = Math.round(anchorXWorld * scale), ay = Math.round(anchorYWorld * scale);
  ctx.setTransform(scale, 0, 0, scale, ax, ay);
  return { canvas, ctx, ax, ay };
}
