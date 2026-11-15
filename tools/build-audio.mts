/**
 * Renders the Roku audio from the web game's own sound design.
 *
 * The web game synthesises every sound live with WebAudio (oscillators with
 * exponential envelopes, filtered noise, a few small instrument patches) and
 * sequences its nine tunes from note lists. A Roku has no synthesiser, so this
 * tool is an offline WebAudio stand-in: it implements the handful of node
 * behaviours the game uses and renders
 *
 *   audio/sfx-<name>.wav     44.1 kHz 16-bit mono PCM, played with roAudioResource
 *   audio/music-<id>.mp3     44.1 kHz mono MP3, looped with roAudioPlayer
 *
 * The voices are transcribed from src/audio/AudioManager.ts, and the note data
 * is imported directly from src/audio/music.ts, so the compositions cannot
 * drift from the web game's.
 *
 * Differences that are deliberate:
 *   - a few pitched variants are pre-rendered (countdown pips, rescue bells,
 *     last-plank warnings, bleats) because a Roku cannot re-pitch a sample;
 *   - no stereo panning (effects are mono);
 *   - each music file holds the tune a few times over and ends on a short
 *     ring-out, so the unavoidable gap when a Roku restarts a looped file
 *     falls between phrases instead of in the middle of one.
 *
 *   npx tsx build-audio.mts [--sheep ../Sheep] [--only sfx|music] [--loops 3]
 */
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { ROOT, fmtBytes, sheepRepo } from './lib/common.mjs';

const SHEEP = sheepRepo();
const { TRACKS } = await import(path.join(SHEEP, 'src/audio/music.ts'));
const SR = 44100;
const OUT = path.join(ROOT, 'audio');
fs.mkdirSync(OUT, { recursive: true });

const argv = process.argv.slice(2);
const flag = (name: string) => { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : undefined; };
const only = flag('--only');
const LOOPS = Number(flag("--loops") ?? 3);

// ---------------------------------------------------------------- oscillators

type Wave = 'sine' | 'square' | 'sawtooth' | 'triangle';
const TABLE = 4096;
const tables = new Map<string, Float32Array>();

/** One period of a band-limited standard waveform with `harmonics` partials, peak-normalised like WebAudio's. */
function wavetable(type: Wave, harmonics: number): Float32Array {
  const k = type === 'sine' ? 1 : Math.max(1, Math.min(harmonics, 400));
  const key = `${type}:${k}`;
  let t = tables.get(key);
  if (t) return t;
  t = new Float32Array(TABLE + 1);
  for (let n = 1; n <= k; n++) {
    let b = 0;
    if (type === 'sine') b = 1;
    else if (type === 'square') b = n % 2 === 1 ? 4 / (n * Math.PI) : 0;
    else if (type === 'sawtooth') b = (n % 2 === 1 ? 1 : -1) * 2 / (n * Math.PI);
    else b = (8 * Math.sin((n * Math.PI) / 2)) / (Math.PI * n) ** 2;
    if (b === 0) continue;
    for (let i = 0; i <= TABLE; i++) t[i] += b * Math.sin((2 * Math.PI * n * i) / TABLE);
  }
  let peak = 0;
  for (let i = 0; i < TABLE; i++) peak = Math.max(peak, Math.abs(t[i]));
  for (let i = 0; i <= TABLE; i++) t[i] /= peak;
  tables.set(key, t);
  return t;
}

class Mix {
  data: Float32Array;
  constructor(seconds: number) { this.data = new Float32Array(Math.ceil(seconds * SR)); }
}

/** v0 -> v1 exponentially over [0, 1]. */
const expo = (v0: number, v1: number, x: number) => v0 * Math.pow(v1 / v0, Math.min(1, Math.max(0, x)));

/**
 * The game's basic voice: an oscillator through a gain that rises exponentially
 * to `gain` in `attack` seconds and decays exponentially to silence at `dur`.
 * `freq(tau)` may bend the pitch; `shape(sample, tau)` may post-process (filters).
 */
function tone(out: Mix, type: Wave, t: number, dur: number, env: (tau: number) => number, freq: (tau: number) => number, fmax: number,
  shape?: (x: number, tau: number) => number): void {
  const table = wavetable(type, Math.floor(16000 / fmax));
  const i0 = Math.round(t * SR);
  const n = Math.round((dur + 0.02) * SR);
  let phase = 0;
  for (let i = 0; i < n && i0 + i < out.data.length; i++) {
    const tau = i / SR;
    const p = phase * TABLE;
    const pi = Math.floor(p);
    let x = table[pi] + (table[pi + 1] - table[pi]) * (p - pi);
    if (shape) x = shape(x, tau);
    out.data[i0 + i] += x * env(tau);
    phase += freq(tau) / SR;
    phase -= Math.floor(phase);
  }
}

function osc(out: Mix, type: Wave, f: number, t: number, dur: number, gain: number, attack = 0.005, glideTo?: number): void {
  const env = (tau: number) => (tau < attack ? expo(0.0001, gain, tau / attack) : expo(gain, 0.0001, (tau - attack) / (dur - attack)));
  const freq = glideTo ? (tau: number) => expo(f, glideTo, tau / dur) : () => f;
  tone(out, type, t, dur, env, freq, Math.max(f, glideTo ?? f));
}

// -------------------------------------------------------------------- filters

type FilterType = 'lowpass' | 'highpass' | 'bandpass';

/** A WebAudio BiquadFilterNode: same coefficient formulas (Q is in dB for low/highpass). */
class Biquad {
  private x1 = 0; private x2 = 0; private y1 = 0; private y2 = 0;
  private b0 = 1; private b1 = 0; private b2 = 0; private a1 = 0; private a2 = 0;
  constructor(private type: FilterType, private q: number) {}
  set(freq: number): void {
    const w0 = (2 * Math.PI * Math.min(freq, SR * 0.49)) / SR;
    const cos = Math.cos(w0), sin = Math.sin(w0);
    let b0: number, b1: number, b2: number, alpha: number;
    if (this.type === 'bandpass') {
      alpha = sin / (2 * this.q);
      b0 = alpha; b1 = 0; b2 = -alpha;
    } else {
      alpha = sin / (2 * Math.pow(10, this.q / 20));
      if (this.type === 'lowpass') { b0 = (1 - cos) / 2; b1 = 1 - cos; b2 = (1 - cos) / 2; }
      else { b0 = (1 + cos) / 2; b1 = -(1 + cos); b2 = (1 + cos) / 2; }
    }
    const a0 = 1 + alpha;
    this.b0 = b0 / a0; this.b1 = b1 / a0; this.b2 = b2 / a0;
    this.a1 = (-2 * cos) / a0; this.a2 = (1 - alpha) / a0;
  }
  run(x: number): number {
    const y = this.b0 * x + this.b1 * this.x1 + this.b2 * this.x2 - this.a1 * this.y1 - this.a2 * this.y2;
    this.x2 = this.x1; this.x1 = x; this.y2 = this.y1; this.y1 = y;
    return y;
  }
}

// one second of the same white noise the web game generates
const NOISE = new Float32Array(SR);
{
  let seed = 22222;
  for (let i = 0; i < SR; i++) { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; NOISE[i] = seed / 2147483648 - 1; }
}
let noiseOffset = 0;

function noise(out: Mix, t: number, dur: number, gain: number, filter: FilterType, freq: number, freqTo?: number, q = 1): void {
  const f = new Biquad(filter, q);
  const i0 = Math.round(t * SR);
  const n = Math.round((dur + 0.02) * SR);
  // the web game starts each burst at a random place in the buffer; a fixed stride keeps builds reproducible
  noiseOffset = (noiseOffset + 7919) % (SR / 2);
  for (let i = 0; i < n && i0 + i < out.data.length; i++) {
    const tau = i / SR;
    if (i % 16 === 0) f.set(freqTo ? expo(freq, freqTo, tau / dur) : freq);
    out.data[i0 + i] += f.run(NOISE[(noiseOffset + i) % SR]) * expo(gain, 0.0001, tau / dur);
  }
}

const midiHz = (m: number) => 440 * Math.pow(2, (m - 69) / 12);
/** Linear ramp through breakpoints [[time, value], ...]. */
function linear(points: [number, number][], tau: number): number {
  if (tau <= points[0][0]) return points[0][1];
  for (let i = 1; i < points.length; i++) {
    if (tau <= points[i][0]) {
      const [t0, v0] = points[i - 1], [t1, v1] = points[i];
      return v0 + ((v1 - v0) * (tau - t0)) / (t1 - t0);
    }
  }
  return points[points.length - 1][1];
}

// ----------------------------------------------------------------- the voices

/** Effects, transcribed from AudioManager.voice(). Returns the length in seconds. */
function voice(name: string, out: Mix, t: number, p: number): number {
  switch (name) {
    case 'ui': osc(out, 'sine', 880 * p, t, 0.06, 0.25); return 0.06;
    case 'rate': osc(out, 'triangle', 660 * p, t, 0.05, 0.2); return 0.05;
    case 'assign': osc(out, 'triangle', 660 * p, t, 0.08, 0.3); osc(out, 'triangle', 990 * p, t + 0.05, 0.1, 0.25); return 0.16;
    case 'reject': osc(out, 'square', 140, t, 0.14, 0.12); osc(out, 'square', 118, t + 0.06, 0.14, 0.1); return 0.2;
    case 'hatch':
      osc(out, 'sawtooth', 90, t, 0.7, 0.08, 0.05, 55);
      noise(out, t, 0.6, 0.15, 'bandpass', 600, 260, 4);
      osc(out, 'sine', 150, t + 0.55, 0.12, 0.3);
      return 0.75;
    case 'plank': osc(out, 'sine', 230 * p, t, 0.09, 0.45); noise(out, t, 0.04, 0.2, 'bandpass', 1800, undefined, 2); return 0.1;
    case 'plankWarn': osc(out, 'triangle', 520 * p, t, 0.08, 0.4); osc(out, 'triangle', 780 * p, t + 0.08, 0.08, 0.3); return 0.18;
    case 'crumble': noise(out, t, 0.16, 0.35, 'lowpass', 700 * p, 200); return 0.17;
    case 'shovel': noise(out, t, 0.1, 0.3, 'bandpass', 900 * p, 400, 1.5); osc(out, 'sine', 300, t, 0.05, 0.15); return 0.12;
    case 'pick': osc(out, 'sine', 1900 * p, t, 0.12, 0.18); osc(out, 'sine', 2730 * p, t, 0.08, 0.1); noise(out, t, 0.05, 0.2, 'highpass', 2500); return 0.13;
    case 'ting': osc(out, 'sine', 3100, t, 0.35, 0.22, 0.002, 2300); osc(out, 'sine', 4650, t, 0.2, 0.08, 0.002, 3500); return 0.36;
    case 'chute': noise(out, t, 0.08, 0.3, 'highpass', 1800); osc(out, 'sine', 520, t + 0.02, 0.1, 0.2, 0.005, 760); return 0.13;
    case 'pip': osc(out, 'sine', 1046 * p, t, 0.07, 0.28); return 0.08;
    case 'pop':
      osc(out, 'sine', 120, t, 0.3, 0.6, 0.005, 45);
      noise(out, t, 0.35, 0.5, 'lowpass', 2400, 150);
      osc(out, 'triangle', 600, t, 0.12, 0.15, 0.002, 1400);
      return 0.36;
    case 'bell':
      for (const [k, g] of [[1, 0.22], [2.4, 0.08], [3.9, 0.05], [5.4, 0.03]]) osc(out, 'sine', 1318 * p * k, t, 0.9 / k + 0.15, g, 0.003);
      return 1.0;
    case 'bleat': {
      // a sawtooth "baa" with vibrato through two formant band-passes
      const f0 = 290 * p;
      const f1 = new Biquad('bandpass', 5); f1.set(850);
      const f2 = new Biquad('bandpass', 7); f2.set(2300);
      const env = (tau: number) => (tau < 0.04 ? expo(0.0001, 0.5, tau / 0.04) : expo(0.5, 0.0001, (tau - 0.04) / 0.41));
      const freq = (tau: number) => linear([[0, f0], [0.08, f0 * 1.06], [0.42, f0 * 0.92]], tau) + Math.sin(2 * Math.PI * 22 * tau) * f0 * 0.05;
      tone(out, 'sawtooth', t, 0.48, env, freq, f0 * 1.12, (x) => f1.run(x) + f2.run(x));
      return 0.5;
    }
    case 'poof': noise(out, t, 0.3, 0.35, 'lowpass', 1600, 180); osc(out, 'sine', 380, t, 0.12, 0.12, 0.005, 180); return 0.32;
    case 'splash': noise(out, t, 0.4, 0.3, 'bandpass', 1500, 500, 1.2); return 0.42;
    case 'sizzle': noise(out, t, 0.45, 0.22, 'highpass', 3000, 6000); return 0.47;
    case 'nukeArm': osc(out, 'square', 880, t, 0.12, 0.12); osc(out, 'square', 660, t + 0.14, 0.12, 0.12); return 0.28;
    case 'fanfare': {
      const notes = [72, 76, 79, 84, 79, 84];
      notes.forEach((m, i) => {
        osc(out, 'triangle', midiHz(m), t + i * 0.11, i === notes.length - 1 ? 0.7 : 0.16, 0.3);
        osc(out, 'sine', midiHz(m + 12), t + i * 0.11, 0.25, 0.08);
      });
      return 1.4;
    }
    case 'sigh': [69, 65, 62, 57].forEach((m, i) => osc(out, 'triangle', midiHz(m), t + i * 0.22, 0.32, 0.25)); return 1.0;
  }
  throw new Error(`unknown effect ${name}`);
}

/** Instrument patches, transcribed from AudioManager.note(). */
function note(out: Mix, inst: string, midi: number, t: number, dur: number, vol: number): void {
  const f = midiHz(midi);
  switch (inst) {
    case 'marimba': osc(out, 'sine', f, t, Math.min(0.5, dur), vol); osc(out, 'sine', f * 4, t, 0.06, vol * 0.25); break;
    case 'glock': osc(out, 'sine', f, t, 0.9, vol * 0.8, 0.002); osc(out, 'sine', f * 2.76, t, 0.35, vol * 0.2, 0.002); break;
    case 'pizz': {
      const lp = new Biquad('lowpass', 1);
      const d = Math.min(0.35, dur);
      const env = (tau: number) => (tau < 0.004 ? expo(0.0001, vol, tau / 0.004) : expo(vol, 0.0001, (tau - 0.004) / (d - 0.004)));
      let k = 0;
      tone(out, 'sawtooth', t, 0.38, env, () => f, f, (x, tau) => { if (k++ % 16 === 0) lp.set(expo(f * 6, f * 1.2, tau / 0.18)); return lp.run(x); });
      break;
    }
    case 'flute': {
      const env = (tau: number) => (tau < 0.06 ? expo(0.0001, vol, tau / 0.06) : tau < dur * 0.7 ? vol : expo(vol, 0.0001, (tau - dur * 0.7) / (dur * 0.3)));
      tone(out, 'sine', t, dur + 0.03, env, (tau) => f + Math.sin(2 * Math.PI * 5.2 * tau) * f * 0.008, f * 1.01);
      break;
    }
    case 'bass': osc(out, 'triangle', f, t, Math.min(0.6, dur), vol); break;
    case 'chip': osc(out, 'square', f, t, Math.min(0.18, dur), vol * 0.4); break;
    case 'pad': {
      const a = Math.min(0.4, dur * 0.4);
      osc(out, 'sine', f, t, dur, vol * 0.6, a); osc(out, 'sine', f * 1.005, t, dur, vol * 0.4, a);
      break;
    }
    case 'guitar': osc(out, 'triangle', f, t, Math.min(0.8, dur), vol); osc(out, 'sawtooth', f, t, 0.08, vol * 0.15); break;
    case 'shaker': noise(out, t, 0.05, vol, 'highpass', 6000); break;
    case 'wood': osc(out, 'sine', 820, t, 0.05, vol); break;
    case 'kick': osc(out, 'sine', 110, t, 0.18, vol, 0.003, 45); break;
    default: throw new Error(`unknown instrument ${inst}`);
  }
}

// --------------------------------------------------------------------- output

const peakOf = (d: Float32Array) => d.reduce((m, v) => Math.max(m, Math.abs(v)), 0);

const rmsOf = (d: Float32Array) => Math.sqrt(d.reduce((m, v) => m + v * v, 0) / d.length);

/** A 1.5 ms fade-in (noise bursts start at full level) and a fade-out, so no file starts or ends on a click. */
function fadeEnds(d: Float32Array, fadeOut: number): void {
  const a = Math.min(d.length, Math.round(0.0015 * SR));
  for (let i = 0; i < a; i++) d[i] *= i / a;
  const n = Math.min(d.length, Math.round(fadeOut * SR));
  for (let i = 0; i < n; i++) d[d.length - 1 - i] *= i / n;
}

function writeWav(file: string, d: Float32Array, gain: number): number {
  const pcm = Buffer.alloc(44 + d.length * 2);
  pcm.write('RIFF', 0); pcm.writeUInt32LE(36 + d.length * 2, 4); pcm.write('WAVEfmt ', 8);
  pcm.writeUInt32LE(16, 16); pcm.writeUInt16LE(1, 20); pcm.writeUInt16LE(1, 22);
  pcm.writeUInt32LE(SR, 24); pcm.writeUInt32LE(SR * 2, 28); pcm.writeUInt16LE(2, 32); pcm.writeUInt16LE(16, 34);
  pcm.write('data', 36); pcm.writeUInt32LE(d.length * 2, 40);
  for (let i = 0; i < d.length; i++) pcm.writeInt16LE(Math.max(-32767, Math.min(32767, Math.round(d[i] * gain * 32767))), 44 + i * 2);
  fs.writeFileSync(file, pcm);
  return pcm.length;
}

// ---- effects: [file name, voice, pitch, extra volume]
const EFFECTS: [string, string, number, number][] = [
  ['ui', 'ui', 1, 1], ['rate', 'rate', 1.2, 1], ['assign', 'assign', 1, 1], ['reject', 'reject', 1, 1], ['hatch', 'hatch', 1, 1],
  ['plank', 'plank', 1, 1], ['plankwarn0', 'plankWarn', 1.12, 1], ['plankwarn1', 'plankWarn', 1.24, 1], ['plankwarn2', 'plankWarn', 1.36, 1],
  ['crumble', 'crumble', 1, 0.7], ['shovel', 'shovel', 1, 0.7], ['pick', 'pick', 1, 0.7], ['ting', 'ting', 1, 1], ['chute', 'chute', 1, 1],
  // the countdown rises as it runs out: pip5 is the first tick, pip1 the last
  ['pip5', 'pip', 1, 1], ['pip4', 'pip', 1.08, 1], ['pip3', 'pip', 1.16, 1], ['pip2', 'pip', 1.24, 1], ['pip1', 'pip', 1.32, 1],
  ['pop', 'pop', 1, 1], ['bell0', 'bell', 1, 1], ['bell1', 'bell', 1.06, 1], ['bell2', 'bell', 1.12, 1],
  ['bleat0', 'bleat', 0.94, 0.6], ['bleat1', 'bleat', 1.08, 0.6], ['poof', 'poof', 1, 1], ['splash', 'splash', 1, 1], ['sizzle', 'sizzle', 1, 1],
  ['nukearm', 'nukeArm', 1, 1], ['fanfare', 'fanfare', 1, 1], ['sigh', 'sigh', 1, 1],
];

let total = 0;
if (only !== 'music') {
  const rendered = EFFECTS.map(([file, name, pitch, vol]) => {
    const scratch = new Mix(2);
    const dur = voice(name, scratch, 0, pitch);
    // a bell rings on for a second; 0.7 s keeps the package small and the mixer free
    const keep = Math.min(dur, name === 'bell' ? 0.7 : dur) + 0.02;
    const d = scratch.data.slice(0, Math.round(keep * SR));
    for (let i = 0; i < d.length; i++) d[i] *= vol;
    fadeEnds(d, name === 'bell' ? 0.08 : 0.004);
    return { file, d, peak: peakOf(d), ms: Math.round(keep * 1000) };
  });
  // The web game sends everything through a compressor. Here the loudest effect is set
  // just under full scale and quieter ones are lifted part of the way toward it.
  const loudest = Math.max(...rendered.map((r) => r.peak));
  let bytes = 0;
  const table: string[] = [];
  for (const r of rendered) {
    const target = 0.86 * Math.pow(r.peak / loudest, 0.6);
    bytes += writeWav(path.join(OUT, `sfx-${r.file}.wav`), r.d, target / r.peak);
    table.push(`${r.file} ${r.ms}ms peak ${(20 * Math.log10(target)).toFixed(1)} dBFS`);
  }
  total += bytes;
  console.log(`effects: ${rendered.length} files, ${fmtBytes(bytes)} (${table.slice(0, 4).join('; ')}; ...)`);
  // durations for the table in source/Audio.brs (kept in step by hand; the packager checks the file names)
  fs.mkdirSync(path.join(ROOT, 'build'), { recursive: true });
  fs.writeFileSync(path.join(ROOT, 'build', 'sfx-durations.json'), JSON.stringify(Object.fromEntries(rendered.map((r) => [r.file, r.ms])), null, 1));
}

if (only !== 'sfx') {
  let bytes = 0;
  const lines: string[] = [];
  for (const [id, tr] of Object.entries<any>(TRACKS)) {
    const stepDur = 60 / tr.bpm / 4;
    const loopDur = tr.length * stepDur;
    const tail = 0.7;
    const mix = new Mix(loopDur * LOOPS + tail + 1.2);
    for (let s = 0; s < tr.length * LOOPS; s++) {
      for (const part of tr.parts) {
        const n = part.notes[(s % tr.length) % part.notes.length];
        if (n === null || n === undefined) continue;
        note(mix, part.inst, n, s * stepDur, stepDur * (part.dur ?? 2), part.vol ?? 0.2);
      }
    }
    const d = mix.data.slice(0, Math.round((loopDur * LOOPS + tail) * SR));
    fadeEnds(d, 0.45);
    // background level: well under the effects, as in the web game's mix. Tunes are matched
    // by loudness (RMS), not by peak, so a sparse glockenspiel piece is not quieter than a busy one.
    const gain = Math.min(0.055 / rmsOf(d), 0.5 / peakOf(d));
    const raw = Buffer.alloc(d.length * 2);
    for (let i = 0; i < d.length; i++) raw.writeInt16LE(Math.round(d[i] * gain * 32767), i * 2);
    const file = path.join(OUT, `music-${id}.mp3`);
    execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-f', 's16le', '-ar', String(SR), '-ac', '1', '-i', 'pipe:0',
      '-codec:a', 'libmp3lame', '-b:a', '56k', '-ar', String(SR), '-ac', '1', '-map_metadata', '-1', '-id3v2_version', '0', '-write_xing', '0', file], { input: raw });
    const size = fs.statSync(file).size;
    bytes += size;
    lines.push(`${id} ${(d.length / SR).toFixed(1)}s`);
  }
  total += bytes;
  console.log(`music: ${Object.keys(TRACKS).length} tracks x ${LOOPS} loops, ${fmtBytes(bytes)} (${lines.join(', ')})`);
}
console.log(`audio written this run: ${fmtBytes(total)}`);
