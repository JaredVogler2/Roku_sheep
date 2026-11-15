/**
 * The shared atlas (images/common.png): everything that is not tied to one
 * biome. Skill and control icons come straight from the web game's SVG set;
 * the remote-control cursor, focus frames, HUD buttons, nine-slice panels,
 * particles and the tiling hazard strips are drawn here for the TV interface,
 * in the web game's storybook palette.
 *
 * All sizes are 720p screen pixels.
 */
import path from 'node:path';
import { createCanvas, loadImage } from 'canvas';
import { Atlas } from '../lib/atlas.mjs';
import { SKILLS } from '../lib/common.mjs';

const INK = '#3b2a1c';
const WOOD_DARK = '#4f321d';
const CREAM = '#fff8e7';
const CREAM_2 = '#f6ead0';
const GOLD = '#ffd25e';
const GOLD_DARK = '#c9962a';
const GRASS = '#5aa04a';
const GRASS_DARK = '#3c7a31';
const BARN = '#c4452f';
const BARN_DARK = '#8f2d1d';
const FOCUS = '#ffb703';

type Ctx = any;

function canvasOf(w: number, h: number): [any, Ctx] {
  const c = createCanvas(w, h);
  return [c, c.getContext('2d')];
}

function vgrad(ctx: Ctx, y0: number, y1: number, stops: [number, string][]) {
  const g = ctx.createLinearGradient(0, y0, 0, y1);
  for (const [o, c] of stops) g.addColorStop(o, c);
  return g;
}

function rr(ctx: Ctx, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, r);
}

async function svgIcon(svg: string, size: number) {
  const [c, ctx] = canvasOf(size, size);
  const img = await loadImage(Buffer.from(svg.replace('<svg ', `<svg width="${size * 2}" height="${size * 2}" `)));
  ctx.imageSmoothingQuality = 'high';
  ctx.drawImage(img, 0, 0, size, size);
  return c;
}

/** HUD tool button: cream storybook key with a hard drop edge. */
function toolButton(w: number, h: number, kind: 'normal' | 'selected' | 'empty' | 'active' | 'nuke' | 'armed') {
  const [c, ctx] = canvasOf(w, h);
  const fills: Record<string, [number, string][]> = {
    normal: [[0, '#fffdf6'], [0.6, '#f3e6c8'], [1, '#e3cfa6']],
    selected: [[0, '#fffbe0'], [0.55, '#ffe27a'], [1, GOLD]],
    empty: [[0, '#cfc9bb'], [0.6, '#b9b2a2'], [1, '#a59d8c']],
    active: [[0, '#e2f4ff'], [0.6, '#9ad4f7'], [1, '#6fb8e8']],
    nuke: [[0, '#ffc8ba'], [0.6, '#f07a5f'], [1, '#d4553c']],
    armed: [[0, '#fff3a8'], [0.5, '#ffb22e'], [1, '#e0481c']],
  };
  // drop edge
  ctx.fillStyle = '#1c1108';
  rr(ctx, 0, 3, w, h - 3, 9);
  ctx.fill();
  // border
  ctx.fillStyle = kind === 'selected' ? GOLD_DARK : '#2c1b0e';
  rr(ctx, 0, 0, w, h - 3, 9);
  ctx.fill();
  // face
  ctx.fillStyle = vgrad(ctx, 2, h - 5, fills[kind]);
  rr(ctx, 2, 2, w - 4, h - 7, 7);
  ctx.fill();
  // inner top light
  ctx.fillStyle = kind === 'empty' ? 'rgba(255,255,255,0.35)' : 'rgba(255,255,255,0.9)';
  rr(ctx, 4, 3, w - 8, 2, 1);
  ctx.fill();
  if (kind === 'selected') {
    ctx.strokeStyle = '#ffffff';
    ctx.lineWidth = 2;
    rr(ctx, 3, 3, w - 6, h - 9, 6);
    ctx.stroke();
  }
  return c;
}

/** Bright frame drawn around whatever has the remote's focus. */
function focusFrame(w: number, h: number, r: number) {
  const [c, ctx] = canvasOf(w, h);
  ctx.strokeStyle = 'rgba(40,20,0,0.85)';
  ctx.lineWidth = 6;
  rr(ctx, 3, 3, w - 6, h - 6, r);
  ctx.stroke();
  ctx.strokeStyle = FOCUS;
  ctx.lineWidth = 4;
  rr(ctx, 3, 3, w - 6, h - 6, r);
  ctx.stroke();
  ctx.strokeStyle = '#fff6c8';
  ctx.lineWidth = 1.5;
  rr(ctx, 3, 3, w - 6, h - 6, r);
  ctx.stroke();
  return c;
}

/** Nine-slice source for menu buttons (inset 16). */
function menuButton(kind: 'cream' | 'green' | 'gold' | 'red' | 'locked') {
  const S = 48;
  const [c, ctx] = canvasOf(S, S);
  const spec: Record<string, { face: [number, string][]; border: string }> = {
    cream: { face: [[0, '#fffdf6'], [1, CREAM_2]], border: WOOD_DARK },
    green: { face: [[0, '#73bf5f'], [1, GRASS]], border: GRASS_DARK },
    gold: { face: [[0, '#ffe38f'], [1, GOLD]], border: GOLD_DARK },
    red: { face: [[0, '#e0644c'], [1, BARN]], border: BARN_DARK },
    locked: { face: [[0, '#d9d2c3'], [1, '#c2baa9']], border: '#7d7466' },
  };
  const s = spec[kind];
  ctx.fillStyle = s.border;
  rr(ctx, 0, 0, S, S, 14);
  ctx.fill();
  ctx.fillStyle = vgrad(ctx, 3, S - 7, s.face);
  rr(ctx, 3, 3, S - 6, S - 10, 11);
  ctx.fill();
  return c;
}

/** Nine-slice storybook panel (inset 24). */
function panel(fill: string, border: string, shade: string | null) {
  const S = 64;
  const [c, ctx] = canvasOf(S, S);
  ctx.fillStyle = border;
  rr(ctx, 0, 0, S, S, 18);
  ctx.fill();
  if (shade) {
    ctx.fillStyle = shade;
    rr(ctx, 3, 3, S - 6, S - 6, 15);
    ctx.fill();
  }
  ctx.fillStyle = fill;
  rr(ctx, 3, 3, S - 6, S - (shade ? 11 : 6), 15);
  ctx.fill();
  return c;
}

/** Nine-slice translucent dark pill for toasts and overlays (inset 12). */
function darkPill(alpha: number) {
  const S = 32;
  const [c, ctx] = canvasOf(S, S);
  ctx.fillStyle = `rgba(22,30,26,${alpha})`;
  rr(ctx, 0, 0, S, S, 12);
  ctx.fill();
  ctx.strokeStyle = 'rgba(255,255,255,0.22)';
  ctx.lineWidth = 1.5;
  rr(ctx, 1, 1, S - 2, S - 2, 11);
  ctx.stroke();
  return c;
}

function cursor(active: boolean) {
  const S = 44, m = S / 2;
  const [c, ctx] = canvasOf(S, S);
  if (active) {
    // over a sheep the ring does the pointing; a bead marks where the cursor really is
    ctx.fillStyle = 'rgba(30,16,6,0.95)';
    ctx.beginPath(); ctx.arc(m, m, 4.8, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = GOLD;
    ctx.beginPath(); ctx.arc(m, m, 2.9, 0, Math.PI * 2); ctx.fill();
    return c;
  }
  // an open crosshair: whatever is under the middle stays visible
  const draw = (color: string, lw: number) => {
    ctx.strokeStyle = color;
    ctx.lineWidth = lw;
    ctx.lineCap = 'round';
    ctx.beginPath();
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      ctx.moveTo(m + dx * 9, m + dy * 9);
      ctx.lineTo(m + dx * 18, m + dy * 18);
    }
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(m, m, 1.2, 0, Math.PI * 2);
    ctx.stroke();
  };
  draw('rgba(30,16,6,0.95)', 7);
  draw('#ffffff', 3.4);
  return c;
}

/** Selection ring that hugs a sheep sprite; the "can take this skill" ring grows four reticle ticks. */
function ring(color: string, shadow: string, ticks: boolean) {
  const W = 68, H = 70, cx = W / 2, cy = H / 2;
  const [c, ctx] = canvasOf(W, H);
  const draw = (col: string, lw: number) => {
    ctx.strokeStyle = col;
    ctx.lineWidth = lw;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.ellipse(cx, cy, 21, 22.5, 0, 0, Math.PI * 2);
    ctx.stroke();
    if (!ticks) return;
    ctx.beginPath();
    for (const [dx, dy, r] of [[1, 0, 21], [-1, 0, 21], [0, 1, 22.5], [0, -1, 22.5]]) {
      ctx.moveTo(cx + dx * (r + 3), cy + dy * (r + 3));
      ctx.lineTo(cx + dx * (r + 8), cy + dy * (r + 8));
    }
    ctx.stroke();
  };
  draw(shadow, 5.4);
  draw(color, 2.8);
  return c;
}

function medal(face: string, rim: string, ribbon: string) {
  const [c, ctx] = canvasOf(30, 38);
  ctx.fillStyle = ribbon;
  ctx.beginPath(); ctx.moveTo(8, 2); ctx.lineTo(14, 2); ctx.lineTo(17, 18); ctx.lineTo(10, 18); ctx.fill();
  ctx.beginPath(); ctx.moveTo(22, 2); ctx.lineTo(16, 2); ctx.lineTo(13, 18); ctx.lineTo(20, 18); ctx.fill();
  ctx.fillStyle = '#2c1b0e';
  ctx.beginPath(); ctx.arc(15, 24, 13, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = rim;
  ctx.beginPath(); ctx.arc(15, 24, 11.4, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = face;
  ctx.beginPath(); ctx.arc(15, 24, 8.6, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = 'rgba(255,255,255,0.75)';
  ctx.beginPath(); ctx.ellipse(12, 20.5, 3.6, 2, -0.6, 0, Math.PI * 2); ctx.fill();
  return c;
}

function lock() {
  const [c, ctx] = canvasOf(26, 30);
  ctx.strokeStyle = '#2c1b0e'; ctx.lineWidth = 6;
  ctx.beginPath(); ctx.arc(13, 11, 6.5, Math.PI, 0); ctx.lineTo(19.5, 15); ctx.moveTo(6.5, 11); ctx.lineTo(6.5, 15); ctx.stroke();
  ctx.strokeStyle = '#b9c3cc'; ctx.lineWidth = 3;
  ctx.beginPath(); ctx.arc(13, 11, 6.5, Math.PI, 0); ctx.lineTo(19.5, 15); ctx.moveTo(6.5, 11); ctx.lineTo(6.5, 15); ctx.stroke();
  ctx.fillStyle = '#2c1b0e'; rr(ctx, 2, 13, 22, 16, 4); ctx.fill();
  ctx.fillStyle = GOLD; rr(ctx, 4, 15, 18, 12, 2.5); ctx.fill();
  ctx.fillStyle = '#2c1b0e'; ctx.beginPath(); ctx.arc(13, 20, 2.2, 0, Math.PI * 2); ctx.fill(); ctx.fillRect(12, 20, 2, 5);
  return c;
}

function softDot(size: number, rgb: string, alpha: number, hard = 0.35) {
  const [c, ctx] = canvasOf(size, size);
  const g = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
  g.addColorStop(0, `rgba(${rgb},${alpha})`);
  g.addColorStop(hard, `rgba(${rgb},${alpha})`);
  g.addColorStop(1, `rgba(${rgb},0)`);
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, size, size);
  return c;
}

function star(size: number, color: string) {
  const [c, ctx] = canvasOf(size, size);
  const m = size / 2;
  ctx.fillStyle = 'rgba(120,70,0,0.8)';
  ctx.beginPath();
  for (let i = 0; i < 10; i++) {
    const a = (i / 10) * Math.PI * 2 - Math.PI / 2, r = i % 2 ? m * 0.48 : m;
    ctx.lineTo(m + Math.cos(a) * r, m + Math.sin(a) * r);
  }
  ctx.fill();
  ctx.fillStyle = color;
  ctx.beginPath();
  for (let i = 0; i < 10; i++) {
    const a = (i / 10) * Math.PI * 2 - Math.PI / 2, r = (i % 2 ? m * 0.48 : m) - 1.6;
    ctx.lineTo(m + Math.cos(a) * r, m + Math.sin(a) * r);
  }
  ctx.fill();
  return c;
}

function heart() {
  const [c, ctx] = canvasOf(16, 15);
  const path = (s: number, ox: number, oy: number) => {
    ctx.beginPath();
    ctx.moveTo(ox + 8 * s, oy + 13 * s);
    ctx.bezierCurveTo(ox - 2 * s, oy + 6 * s, ox + 2 * s, oy - 1 * s, ox + 8 * s, oy + 4 * s);
    ctx.bezierCurveTo(ox + 14 * s, oy - 1 * s, ox + 18 * s, oy + 6 * s, ox + 8 * s, oy + 13 * s);
  };
  ctx.fillStyle = '#7a1d3a'; path(1, 0, 1); ctx.fill();
  ctx.fillStyle = '#ff6f91'; path(0.8, 1.6, 2.2); ctx.fill();
  return c;
}

function bubble() {
  const [c, ctx] = canvasOf(10, 10);
  ctx.strokeStyle = 'rgba(220,245,255,0.95)'; ctx.lineWidth = 1.4;
  ctx.beginPath(); ctx.arc(5, 5, 3.4, 0, Math.PI * 2); ctx.stroke();
  ctx.fillStyle = 'rgba(255,255,255,0.9)'; ctx.fillRect(3, 3, 2, 1);
  return c;
}

function splat() {
  const [c, ctx] = canvasOf(34, 12);
  ctx.fillStyle = 'rgba(43,29,20,0.9)'; ctx.beginPath(); ctx.ellipse(17, 7, 16, 4.6, 0, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = '#fbf6ea'; ctx.beginPath(); ctx.ellipse(17, 6.4, 14.6, 3.4, 0, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = '#2d2420'; ctx.beginPath(); ctx.ellipse(25, 6, 2.8, 1.8, 0, 0, Math.PI * 2); ctx.fill();
  return c;
}

function digit(d: number, color: string) {
  const [c, ctx] = canvasOf(18, 22);
  ctx.font = '900 18px Inter, "DejaVu Sans", sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.lineJoin = 'round';
  ctx.lineWidth = 4.5;
  ctx.strokeStyle = '#3a0d05';
  ctx.strokeText(String(d), 9, 11.5);
  ctx.fillStyle = color;
  ctx.fillText(String(d), 9, 11.5);
  return c;
}

// ---------------------------------------------------------------- hazard strips

/** Top of a water body: 8 looping frames, 128 px wide, seamless horizontally. */
function waterStrip(f: number) {
  const W = 128, H = 14;
  const [c, ctx] = canvasOf(W, H);
  const surf = (x: number) => 3.6 + 1.3 * Math.sin(Math.PI * 2 * ((3 * x) / W + (2 * f) / 8)) + 1.0 * Math.sin(Math.PI * 2 * (x / W - f / 8));
  ctx.fillStyle = 'rgba(96,190,240,0.88)';
  ctx.beginPath();
  ctx.moveTo(0, H);
  for (let x = 0; x <= W; x++) ctx.lineTo(x, surf(x));
  ctx.lineTo(W, H);
  ctx.fill();
  ctx.strokeStyle = 'rgba(235,250,255,0.92)';
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  for (let x = -1; x <= W + 1; x++) ctx.lineTo(x, surf(x) + 0.4);
  ctx.stroke();
  // glints
  ctx.fillStyle = 'rgba(255,255,255,0.85)';
  for (let k = 0; k < 4; k++) {
    const gx = (k * 37 + f * 4) % W;
    if (Math.sin(f * 0.9 + k * 1.9) > 0.2) ctx.fillRect(gx, surf(gx) + 2.6, 4, 1);
  }
  return c;
}

/** Top of a lava pool: 4 looping frames with drifting crust and bubbles. */
function lavaStrip(f: number) {
  const W = 128, H = 16;
  const [c, ctx] = canvasOf(W, H);
  const surf = (x: number) => 2.4 + 1.1 * Math.sin(Math.PI * 2 * ((2 * x) / W + f / 4));
  ctx.fillStyle = vgrad(ctx, 0, H, [[0, '#fff0a0'], [0.4, '#ffb22e'], [1, '#f4701c']]);
  ctx.beginPath();
  ctx.moveTo(0, H);
  for (let x = 0; x <= W; x++) ctx.lineTo(x, surf(x));
  ctx.lineTo(W, H);
  ctx.fill();
  ctx.fillStyle = 'rgba(90,20,8,0.55)';
  for (let i = 0; i < 6; i++) {
    const cx = (i * 23 + f * 8) % W, cy = 7 + (i % 3) * 3;
    for (const ox of [-W, 0, W]) { ctx.beginPath(); ctx.ellipse(cx + ox, cy, 6 + (i % 2) * 3, 1.8, 0, 0, Math.PI * 2); ctx.fill(); }
  }
  for (let i = 0; i < 5; i++) {
    const ph = ((f / 4) + i * 0.37) % 1;
    const bx = (i * 29.7 + 9) % W;
    ctx.fillStyle = `rgba(255,240,170,${0.9 * (1 - ph)})`;
    ctx.beginPath(); ctx.arc(bx, surf(bx) - ph * 2.5 + 1.5, 1 + ph * 2, 0, Math.PI * 2); ctx.fill();
  }
  return c;
}

/** Fire: 6 looping frames of eight tongues, 64 px wide, drawn 80 px tall and stretched to the hazard. */
function fireStrip(f: number) {
  const W = 64, H = 80;
  const [c, ctx] = canvasOf(W, H);
  const tongues = 8;
  const t = (f / 6) * Math.PI * 2;
  for (const [col, k, wk] of [['#d8361a', 1, 1], ['#ff8a24', 0.78, 0.72], ['#ffe27a', 0.5, 0.42]] as [string, number, number][]) {
    ctx.fillStyle = col;
    for (let i = -1; i <= tongues; i++) {
      const ii = ((i % tongues) + tongues) % tongues;
      const cx = (i + 0.5) * (W / tongues);
      const fh = H * k * (0.72 + 0.28 * Math.sin(t + ii * 2.1));
      const hw = (W / tongues) * 0.75 * wk;
      const sway = Math.sin(t * 2 + ii) * hw * 0.5;
      ctx.beginPath();
      ctx.moveTo(cx - hw, H);
      ctx.quadraticCurveTo(cx - hw * 1.1, H - fh * 0.45, cx + sway, H - fh);
      ctx.quadraticCurveTo(cx + hw * 1.1, H - fh * 0.45, cx + hw, H);
      ctx.closePath();
      ctx.fill();
    }
  }
  return c;
}

function chain() {
  const [c, ctx] = canvasOf(6, 128);
  for (let y = 0; y < 128; y += 5) {
    ctx.fillStyle = '#1e2126'; ctx.fillRect(0, y, 6, 4);
    ctx.fillStyle = '#5a626c'; ctx.fillRect(1, y + 1, 4, 2);
  }
  return c;
}

function logo() {
  const size = 104, spacing = 5;
  const font = `900 ${size}px Inter, "DejaVu Sans", sans-serif`;
  const [probe, pctx] = canvasOf(8, 8);
  pctx.font = font;
  const a = 'SHEEP', b = 'FALL';
  const widthOf = (s: string) => [...s].reduce((n, ch) => n + pctx.measureText(ch).width + spacing, 0);
  const textW = widthOf(a) + widthOf(b) - spacing;
  const W = Math.ceil(textW) + 48, H = 150;
  const [c, ctx] = canvasOf(W, H);
  ctx.font = font;
  ctx.textBaseline = 'alphabetic';
  const x = (W - textW) / 2;
  const draw = (dy: number, colorA: string, colorB: string) => {
    let px = x;
    for (const [s, col] of [[a, colorA], [b, colorB]] as [string, string][]) {
      ctx.fillStyle = col;
      for (const ch of s) { ctx.fillText(ch, px, 104 + dy); px += ctx.measureText(ch).width + spacing; }
    }
  };
  ctx.shadowColor = 'rgba(0,0,0,0.45)'; ctx.shadowBlur = 16; ctx.shadowOffsetY = 12;
  draw(8, WOOD_DARK, WOOD_DARK);
  ctx.shadowColor = 'transparent';
  for (let dy = 8; dy >= 5; dy--) draw(dy, WOOD_DARK, WOOD_DARK);
  for (let dy = 4; dy >= 1; dy--) draw(dy, '#7a5232', '#7a5232');
  draw(0, CREAM, GOLD);
  return c;
}

export async function buildCommonAtlas(SHEEP: string) {
  const I = await import(path.join(SHEEP, 'src/ui/icons.ts'));
  const O = await import(path.join(SHEEP, 'src/render/ObjectArt.ts'));
  const atlas = new Atlas('common', 1024);
  const add = (key: string, c: any, ax = 0, ay = 0, noTrim = true) => atlas.add(key, c, ax, ay, { noTrim });

  // skill icons (two sizes: HUD and briefing chips) and control icons
  for (let i = 0; i < SKILLS.length; i++) {
    add(`skill.${i}`, await svgIcon(I.SKILL_ICONS[SKILLS[i]], 32));
    add(`skillsm.${i}`, await svgIcon(I.SKILL_ICONS[SKILLS[i]], 28));
  }
  for (const name of ['pause', 'play', 'fast', 'nuke', 'minus', 'plus', 'restart', 'menu', 'finish', 'rewind']) {
    add(`ui.${name}`, await svgIcon(I.UI_ICONS[name], 30));
  }

  // HUD tool buttons and their focus frames
  const TOOL_H = 60, TOOL_SKILL_W = 56, TOOL_CTL_W = 46, TOOL_RATE_W = 36;
  for (const kind of ['normal', 'selected', 'empty'] as const) add(`tool.skill.${kind}`, toolButton(TOOL_SKILL_W, TOOL_H, kind));
  for (const kind of ['normal', 'active', 'nuke', 'armed'] as const) add(`tool.ctl.${kind}`, toolButton(TOOL_CTL_W, TOOL_H, kind));
  add('tool.rate.normal', toolButton(TOOL_RATE_W, TOOL_H, 'normal'));
  // focus frames overhang the button by 5 px on every side (the drop edge included)
  add('focus.skill', focusFrame(TOOL_SKILL_W + 10, TOOL_H + 10, 12), 5, 5);
  add('focus.ctl', focusFrame(TOOL_CTL_W + 10, TOOL_H + 10, 12), 5, 5);
  add('focus.rate', focusFrame(TOOL_RATE_W + 10, TOOL_H + 10, 12), 5, 5);

  // nine-slice sources
  for (const kind of ['cream', 'green', 'gold', 'red', 'locked'] as const) add(`btn.${kind}`, menuButton(kind));
  add('focus.nine', focusFrame(64, 64, 18));
  add('panel.cream', panel(CREAM, WOOD_DARK, CREAM_2));
  add('panel.dark', panel('rgba(22,30,26,0.93)', 'rgba(255,255,255,0.28)', null));
  add('pill.dark', darkPill(0.82));
  add('pill.red', (() => {
    const [c, ctx] = canvasOf(32, 32);
    ctx.fillStyle = 'rgba(60,16,8,0.9)'; rr(ctx, 0, 0, 32, 32, 12); ctx.fill();
    ctx.strokeStyle = 'rgba(255,200,180,0.5)'; ctx.lineWidth = 1.5; rr(ctx, 1, 1, 30, 30, 11); ctx.stroke();
    return c;
  })());

  // cursor and selection rings
  // cursor and rings are anchored at their centres
  add('cursor.idle', cursor(false), 22, 22);
  add('cursor.hot', cursor(true), 22, 22);
  add('ring.gold', ring(GOLD, 'rgba(60,34,0,0.9)', true), 34, 35);
  add('ring.grey', ring('rgba(255,255,255,0.85)', 'rgba(20,20,20,0.6)', false), 34, 35);

  // medals, lock, bomber countdown digits
  add('medal.gold', medal('#ffd25e', '#f0b030', '#c4452f'));
  add('medal.silver', medal('#e4e9ee', '#b3bcc6', '#3d8fd1'));
  add('medal.bronze', medal('#e0a070', '#b9773f', '#5aa04a'));
  add('lock', lock());
  for (let d = 1; d <= 5; d++) add(`digit.${d}`, digit(d, d <= 2 ? '#ff6a4a' : '#fff6c8'));

  // particles
  add('p.star', star(14, '#ffe08a'));
  add('p.heart', heart());
  add('p.puff', softDot(22, '255,252,240', 0.95, 0.45));
  add('p.smoke', softDot(22, '70,70,76', 0.8, 0.3));
  add('p.steam', softDot(26, '240,248,255', 0.75, 0.5));
  add('p.glow', softDot(18, '255,236,150', 0.9, 0.15));
  add('p.bubble', bubble());
  add('splat', splat(), 17, 9);
  add('shadow', (() => {
    // soft contact shadow under a grounded sheep
    const [c, ctx] = canvasOf(24, 8);
    ctx.fillStyle = 'rgba(24,16,10,0.3)';
    ctx.beginPath(); ctx.ellipse(12, 4, 11, 3, 0, 0, Math.PI * 2); ctx.fill();
    return c;
  })(), 12, 3);

  // hazard strips
  for (let f = 0; f < 8; f++) add(`water.${f}`, waterStrip(f));
  for (let f = 0; f < 4; f++) add(`lava.${f}`, lavaStrip(f));
  for (let f = 0; f < 6; f++) add(`fire.${f}`, fireStrip(f));
  add('chain', chain());
  {
    // spikes, straight from the web game's hazard art: a 48 x 12 world-px run (period 3 px)
    const [c, ctx] = canvasOf(96, 26);
    ctx.setTransform(2, 0, 0, 2, 0, 2);
    O.drawHazard(ctx, { id: 's', type: 'spikes', x: 0, y: 0, w: 48, h: 12 }, 0, 0, false);
    const [crop, cctx] = canvasOf(96, 24);
    cctx.drawImage(c, 0, -2);
    add('spikes', crop);
  }

  add('logo', logo(), 0, 0, false);

  atlas.pack();
  return {
    atlas,
    meta: { sprites: atlas.meta(), nine: { btn: 16, focus: 22, panel: 24, pill: 12 }, toolh: TOOL_H, toolw: { skill: TOOL_SKILL_W, ctl: TOOL_CTL_W, rate: TOOL_RATE_W } },
  };
}
