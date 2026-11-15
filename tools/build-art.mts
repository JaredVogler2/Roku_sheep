/**
 * Renders every image the Roku app ships, from the web game's own procedural
 * art code, and writes the metadata the BrightScript renderer reads.
 *
 *   images/sheep.png            sheep poses (right-facing; the device mirrors them once at start-up)
 *   images/obj-<biome>.png      hatch, sheepfold and decor per biome
 *   images/common.png           icons, cursor, HUD buttons, nine-slices, particles, hazard strips, logo
 *   images/tex-<biome>-*.png    seamless terrain material tiles
 *   images/bg-<biome>-*.{jpg,png}  parallax backdrop layers
 *   images/splash-*.jpg, icon-*.png   launch and home-screen artwork
 *   images/art.json             atlas rectangles, anchors, colours, layer factors
 *
 * Everything is palette-quantised (tools/quantize.py) because the whole
 * channel has to fit in 4 MB.
 *
 *   npx tsx build-art.mts [--sheep ../Sheep] [--only sheep,objects,common,textures,backgrounds,channel]
 */
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { installDomShim } from './lib/dom-shim.mjs';
import { BIOMES, ROOT, TOOLS, fmtBytes, listJson, readJson, sheepRepo } from './lib/common.mjs';

installDomShim();
const SHEEP = sheepRepo();
const { buildSheepAtlas, buildBiomeAtlas, decorByBiome } = await import('./art/sprites.mts');
const { buildCommonAtlas } = await import('./art/common.mts');
const { buildTerrainArt, SHEET_W, SHEET_H } = await import('./art/textures.mts');
const { buildBackground } = await import('./art/backgrounds.mts');
const { buildChannelArt } = await import('./art/channel.mts');

const IMAGES = path.join(ROOT, 'images');
const RAW = path.join(ROOT, 'build', 'art-raw');
fs.mkdirSync(IMAGES, { recursive: true });
fs.mkdirSync(RAW, { recursive: true });

const onlyArg = process.argv.indexOf('--only');
const only = onlyArg >= 0 ? new Set(process.argv[onlyArg + 1].split(',')) : null;
const want = (part: string) => !only || only.has(part);

const metaPath = path.join(IMAGES, 'art.json');
const meta: any = fs.existsSync(metaPath) ? readJson(metaPath) : {};
meta.schema = 1;
let total = 0;

/** Write a canvas as RGBA PNG, then quantise / encode it into images/. */
function emit(canvas: any, name: string, opts: { colors?: number; jpeg?: number; dither?: number }) {
  const raw = path.join(RAW, name.replace(/\.(png|jpg)$/, '') + '.png');
  fs.writeFileSync(raw, canvas.toBuffer('image/png'));
  const out = path.join(IMAGES, name);
  const args = [path.join(TOOLS, 'quantize.py'), raw, out];
  if (opts.jpeg) args.push('--jpeg', String(opts.jpeg));
  else args.push('--colors', String(opts.colors ?? 256), '--dither', String(opts.dither ?? 0));
  execFileSync('python3', args, { stdio: 'inherit' });
  const size = fs.statSync(out).size;
  total += size;
  return size;
}

const levels = listJson(path.join(ROOT, 'levels')).filter((f) => f !== 'index.json').map((f) => readJson(path.join(ROOT, 'levels', f)));

if (want('sheep')) {
  const s = await buildSheepAtlas(SHEEP);
  const size = emit(s.atlas.canvas, 'sheep.png', { colors: 256 });
  meta.sheep = { file: 'pkg:/images/sheep.png', w: s.atlas.width, h: s.atlas.height, ...s.meta };
  console.log(s.atlas.stats(), fmtBytes(size));
}

if (want('objects')) {
  const kinds = decorByBiome(levels);
  meta.biomes ??= {};
  for (const biome of BIOMES) {
    const b = await buildBiomeAtlas(SHEEP, biome, kinds[biome] ?? []);
    const size = emit(b.atlas.canvas, `obj-${biome}.png`, { colors: 256 });
    meta.biomes[biome] = { ...(meta.biomes[biome] ?? {}), objects: { file: `pkg:/images/obj-${biome}.png`, w: b.atlas.width, h: b.atlas.height, ...b.meta } };
    console.log(b.atlas.stats(), fmtBytes(size));
  }
}

if (want('common')) {
  const c = await buildCommonAtlas(SHEEP);
  const size = emit(c.atlas.canvas, 'common.png', { colors: 256 });
  meta.common = { file: 'pkg:/images/common.png', w: c.atlas.width, h: c.atlas.height, ...c.meta };
  console.log(c.atlas.stats(), fmtBytes(size));
}

const terrainArt: Record<string, any> = {};
if (want('textures') || want('channel')) {
  meta.biomes ??= {};
  let sum = 0;
  for (const biome of BIOMES) {
    const t = await buildTerrainArt(SHEEP, biome);
    terrainArt[biome] = t;
    if (!want('textures')) continue;
    const files: Record<string, any> = {};
    for (const [name, canvas] of Object.entries<any>(t.tiles)) {
      sum += emit(canvas, `tex-${biome}-${name}.png`, { colors: 16 });
      files[name] = { file: `pkg:/images/tex-${biome}-${name}.png`, w: canvas.width, h: canvas.height };
    }
    meta.biomes[biome] = { ...(meta.biomes[biome] ?? {}), terrain: { sheetw: SHEET_W, sheeth: SHEET_H, tiles: files, colors: t.colors } };
  }
  if (want('textures')) console.log(`terrain tiles: ${BIOMES.length * 8} files, ${fmtBytes(sum)}`);
}

const backgrounds: Record<string, any> = {};
if (want('backgrounds') || want('channel')) {
  meta.biomes ??= {};
  let sum = 0;
  for (const biome of BIOMES) {
    const b = await buildBackground(SHEEP, biome);
    backgrounds[biome] = b;
    if (!want('backgrounds')) continue;
    sum += emit(b.far, `bg-${biome}-far.jpg`, { jpeg: 84 });
    sum += emit(b.mid, `bg-${biome}-mid.png`, { colors: 64 });
    sum += emit(b.near, `bg-${biome}-near.png`, { colors: 64 });
    meta.biomes[biome] = {
      ...(meta.biomes[biome] ?? {}),
      background: {
        w: b.meta.w, h: b.meta.h,
        far: { file: `pkg:/images/bg-${biome}-far.jpg`, ...b.meta.far },
        mid: { file: `pkg:/images/bg-${biome}-mid.png`, ...b.meta.mid },
        near: { file: `pkg:/images/bg-${biome}-near.png`, ...b.meta.near },
      },
    };
  }
  if (want('backgrounds')) console.log(`backdrops: ${BIOMES.length * 3} files, ${fmtBytes(sum)}`);
}

if (want('channel')) {
  const art = await buildChannelArt(SHEEP, backgrounds.meadow, terrainArt.meadow);
  const sizes = [
    emit(art.splashFhd, 'splash-fhd.jpg', { jpeg: 80 }),
    emit(art.splashHd, 'splash-hd.jpg', { jpeg: 80 }),
    emit(art.splashSd, 'splash-sd.jpg', { jpeg: 78 }),
    emit(art.iconFhd, 'icon-focus-fhd.png', { colors: 256, dither: 1 }),
    emit(art.iconHd, 'icon-focus-hd.png', { colors: 256, dither: 1 }),
  ];
  console.log(`channel art: splash ${fmtBytes(sizes[0])} + ${fmtBytes(sizes[1])} + ${fmtBytes(sizes[2])}, icons ${fmtBytes(sizes[3])} + ${fmtBytes(sizes[4])}`);
}

fs.writeFileSync(metaPath, JSON.stringify(meta));
total += fs.statSync(metaPath).size;
console.log(`art.json ${fmtBytes(fs.statSync(metaPath).size)}; written this run: ${fmtBytes(total)}`);
