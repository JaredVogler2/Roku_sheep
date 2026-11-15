/**
 * Store and launch artwork: the home-screen tile (mm_icon_focus_*) and the
 * splash screen, composed from the game's own backdrop, terrain, sheep,
 * hatch and barn art so they show exactly what the game looks like.
 * Certification 6.4 asks for FHD (1920x1080) and HD (1280x720) splash screens.
 */
import path from 'node:path';
import { createCanvas } from 'canvas';

const CREAM = '#fff8e7';
const GOLD = '#ffd25e';
const WOOD = '#7a5232';
const WOOD_DARK = '#4f321d';

function drawLogo(ctx: any, cx: number, baseline: number, size: number, stacked = false) {
  ctx.save();
  ctx.font = `900 ${size}px Inter, "DejaVu Sans", sans-serif`;
  ctx.textBaseline = 'alphabetic';
  const sp = size * 0.045;
  const widthOf = (s: string) => [...s].reduce((n, ch) => n + ctx.measureText(ch).width + sp, 0) - sp;
  const lines: [string, string, number][] = stacked
    ? [['SHEEP', CREAM, baseline - size * 0.92], ['FALL', GOLD, baseline]]
    : [['SHEEP', CREAM, baseline], ['FALL', GOLD, baseline]];
  const total = stacked ? 0 : widthOf('SHEEP') + sp + widthOf('FALL');
  const pass = (dy: number, override: string | null) => {
    let px = stacked ? 0 : cx - total / 2;
    for (const [s, col, y] of lines) {
      if (stacked) px = cx - widthOf(s) / 2;
      ctx.fillStyle = override ?? col;
      for (const ch of s) { ctx.fillText(ch, px, y + dy); px += ctx.measureText(ch).width + sp; }
      if (!stacked) px += 0;
    }
  };
  const d = Math.max(2, Math.round(size * 0.075));
  ctx.shadowColor = 'rgba(0,0,0,0.45)'; ctx.shadowBlur = size * 0.16; ctx.shadowOffsetY = size * 0.12;
  pass(d, WOOD_DARK);
  ctx.shadowColor = 'transparent';
  for (let dy = d; dy > d / 2; dy--) pass(dy, WOOD_DARK);
  for (let dy = Math.floor(d / 2); dy >= 1; dy--) pass(dy, WOOD);
  pass(0, null);
  ctx.restore();
}

export async function buildChannelArt(SHEEP: string, bg: { far: any; mid: any; near: any; meta: any }, terrain: { tiles: any; colors: any }) {
  const S = await import(path.join(SHEEP, 'src/render/SheepSpriteSystem.ts'));
  const O = await import(path.join(SHEEP, 'src/render/ObjectArt.ts'));

  function backdrop(ctx: any, W: number, H: number, horizon: number, shift = 0) {
    // the three layers, stretched so the stage height fills down to `horizon`
    const k = horizon / 320;
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';
    for (const [layer, top, f] of [[bg.far, 0, 0.3], [bg.mid, bg.meta.mid.top, 0.6], [bg.near, bg.meta.near.top, 1]] as [any, number, number][]) {
      const w = 1024 * k;
      for (let x = -((shift * f) % w) - w; x < W; x += w) ctx.drawImage(layer, x, top * k, w + 1, layer.height * k);
    }
  }

  function ground(ctx: any, W: number, H: number, top: number, px: number) {
    // turf sheet at `px` screen pixels per world pixel, with the grass cap rows on top
    const t = terrain.tiles.turf;
    ctx.imageSmoothingEnabled = false;
    for (let y = top; y < H; y += t.height * px) for (let x = 0; x < W; x += t.width * px) ctx.drawImage(t, x, y, t.width * px, t.height * px);
    terrain.colors.cap.forEach((c: string, i: number) => { ctx.fillStyle = c; ctx.fillRect(0, top + i * px, W, px); });
    // blades
    const blades: string[] = terrain.colors.blades;
    for (let x = 0; x < W / px; x++) {
      const h = (Math.imul(x, 2654435761) >>> 0) % 7;
      if (h < 2) continue;
      const bh = 1 + (h % 3);
      ctx.fillStyle = blades[h % blades.length];
      ctx.fillRect(x * px, top - bh * px, px, bh * px);
    }
    ctx.imageSmoothingEnabled = true;
  }

  function sheepAt(ctx: any, scale: number, anim: string, frame: number, x: number, y: number, dir = 1, climber = false, floater = false) {
    const sys = new S.SheepSpriteSystem();
    sys.setScale(scale, false);
    const { canvas, box } = sys.frame(anim, frame, climber, floater);
    const k = scale * S.SHEEP_VISUAL_SCALE;
    ctx.save();
    ctx.translate(x, y);
    if (dir < 0) ctx.scale(-1, 1);
    // contact shadow
    if (anim !== 'float' && anim !== 'fall') {
      ctx.fillStyle = 'rgba(24,16,10,0.28)';
      ctx.beginPath(); ctx.ellipse(0, 0.7 * scale, 5.2 * scale * 1.2, 1.4 * scale, 0, 0, Math.PI * 2); ctx.fill();
    }
    ctx.drawImage(canvas, box.x * k, box.y * k);
    ctx.restore();
  }

  function world(ctx: any, scale: number, x: number, y: number, fn: (c: any) => void) {
    ctx.save();
    ctx.translate(x, y);
    ctx.scale(scale, scale);
    fn(ctx);
    ctx.restore();
  }

  // ---- splash, composed at FHD
  function splash(W: number, H: number) {
    const c = createCanvas(W, H);
    const ctx = c.getContext('2d');
    const u = W / 1920;
    const gy = Math.round(820 * u);
    backdrop(ctx, W, H, gy + 40 * u, 180);
    ground(ctx, W, H, gy, Math.round(4 * u) || 1);
    const s = 4 * u;
    world(ctx, s, 1560 * u, gy, (x) => O.drawExit(x, { id: 'e', x: 0, y: -1 }, 'meadow', 0.6));
    world(ctx, s, 250 * u, 600 * u, (x) => { O.drawHatch(x, { id: 'h', x: 0, y: 0, dir: 1 }, 100000, 'meadow', 'all'); });
    world(ctx, s, 860 * u, gy, (x) => O.drawDecor(x, { kind: 'apple-tree', x: 0, y: 0 }, 'meadow', 0));
    world(ctx, s, 1180 * u, gy, (x) => O.drawDecor(x, { kind: 'flowers', x: 0, y: 0 }, 'meadow', 0));
    world(ctx, s, 640 * u, gy, (x) => O.drawDecor(x, { kind: 'fence', x: 0, y: 0 }, 'meadow', 0));
    sheepAt(ctx, s, 'fall', 1, 250 * u, 700 * u);
    sheepAt(ctx, s, 'float', 1, 420 * u, 740 * u, 1, false, true);
    const walkers: [number, number, boolean, boolean][] = [[560, 0, false, false], [700, 3, true, false], [1010, 5, false, true], [1130, 1, false, false], [1290, 6, true, true], [1400, 2, false, false]];
    for (const [x, f, cl, fl] of walkers) sheepAt(ctx, s, 'walk', f, x * u, gy, 1, cl, fl);
    sheepAt(ctx, s, 'block', 0, 110 * u, gy);
    drawLogo(ctx, W / 2, 250 * u, 190 * u);
    ctx.font = `800 ${Math.round(40 * u)}px Inter, "DejaVu Sans", sans-serif`;
    ctx.textAlign = 'center';
    ctx.lineJoin = 'round';
    ctx.lineWidth = 8 * u;
    ctx.strokeStyle = 'rgba(40,24,10,0.75)';
    const tag = 'Tiny sheep. Unstoppable hooves. 120 stages to bring them home.';
    ctx.strokeText(tag, W / 2, 330 * u);
    ctx.fillStyle = CREAM;
    ctx.fillText(tag, W / 2, 330 * u);
    return c;
  }

  // ---- home-screen tile
  function icon(W: number, H: number) {
    const c = createCanvas(W, H);
    const ctx = c.getContext('2d');
    const u = W / 540;
    const gy = Math.round(338 * u);
    backdrop(ctx, W, H, gy + 20 * u, 520);
    ground(ctx, W, H, gy, Math.max(1, Math.round(3 * u)));
    const s = 4.4 * u;
    world(ctx, 2.2 * u, 440 * u, gy, (x) => O.drawExit(x, { id: 'e', x: 0, y: -1 }, 'meadow', 0.6));
    sheepAt(ctx, s, 'walk', 2, 120 * u, gy);
    sheepAt(ctx, s * 0.8, 'walk', 5, 262 * u, gy, 1, true, false);
    drawLogo(ctx, W / 2, 196 * u, 104 * u, true);
    return c;
  }

  // SD is anamorphic 720x480: squeeze the HD frame
  const hd = splash(1280, 720);
  const sd = createCanvas(720, 480);
  const sctx = sd.getContext('2d');
  sctx.imageSmoothingQuality = 'high';
  sctx.drawImage(hd, 0, 0, 720, 480);
  return {
    splashFhd: splash(1920, 1080),
    splashHd: hd,
    splashSd: sd,
    iconFhd: icon(540, 405),
    iconHd: icon(290, 218),
  };
}
