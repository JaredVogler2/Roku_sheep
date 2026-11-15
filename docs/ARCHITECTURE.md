# Architecture

SHEEPFALL for Roku is a 2D-API app: one `roScreen` (1280×720, double buffered), one loop, no SceneGraph. This document says how it is put together and why.

## The loop

`source/App.brs`

```
read remote events → scene.update(dt) → scene.draw(screen) → SwapBuffers
```

`SwapBuffers` waits for the display, so the loop runs at the TV's refresh rate. A scene is an associative array with `update`, `draw` and `onKey` functions; exactly one is current.

There are two kinds of scene:

- **Animated** (a stage, the title, results, the finale): drawn every frame.
- **Static** (stage select, brief, code entry, How to Play, settings, credits): drawn twice after any key press or scene change, once into each buffer, then the app sleeps on the message port. The living backdrop holds its current frame behind them.

`AppMain(args, driver)` takes an optional `driver`. On a device it is `invalid`. The smoke test passes an object that supplies key presses and a fixed frame time, which is how the whole app runs unattended in a simulator.

## Files

| File | Role |
|---|---|
| `main.brs` | Entry point; calls `AppMain`. |
| `App.brs` | Start-up, the loop, scene changes, deep links, shared menu furniture. |
| `Engine.brs`, `EngineSkills.brs` | The simulation: one tick, the eight skills, inputs, win/lose rules. |
| `Terrain.brs` | The collision grid, excavation masks, edits. |
| `Levels.brs` | Stage index, stage files, access codes. |
| `Game.brs` | The stage scene: clock, remote input, cursor and targeting, camera, Assisted Mode. |
| `GameDraw.brs` | Composing a stage frame: backdrop, scenery, terrain, hazards, sheep, overlays. |
| `TerrainPaint.brs` | Turning the collision grid into pixels, and keeping them in step with edits. |
| `Hud.brs` | The bar under the playfield. |
| `Particles.brs` | Dust, sparkles, weather. Cosmetic only. |
| `Assets.brs`, `Gfx.brs` | Image loading and drawing helpers (text, nine-slices). |
| `Audio.brs` | Effects with priorities, looping music. |
| `Progress.brs` | Saved progress and settings in the registry. |
| `Menu*.brs` | The menu scenes. |
| `Util.brs` | Type checks and small formatters. |

Code is flat in `source/` because a 2D-API app compiles every `.brs` there into one namespace; function names carry a module prefix instead (`Sim…`, `Tp…`, `Game…`, `Menu…`).

## The engine

The engine is a statement-for-statement port of the web game's `Simulation.ts`, with its calibration constants inlined. It is deterministic and integer-only, which is what makes the parity test possible.

**State as integers.** Sheep states, fates, skills, death causes and event kinds are small integer codes (listed at the top of `Engine.brs`). Comparing integers is far cheaper in BrightScript than comparing strings, and a tick does a lot of it.

**The grid.** `Terrain.brs` keeps one `roByteArray`, one byte per world pixel, padded by 32 cells on every side. The top padding is steel and the rest is empty, which is exactly how the web engine treats out-of-bounds reads. A cell is `cells[y * stride + x + base]`, so the hot paths never test bounds.

**Stage decoding.** A stage's collision mask is stored as row bands: `[height, material, runLength, material, runLength, …]`. A band is a stack of identical rows. Decoding builds one hex string with `String()` and `Join()` and converts it with a single `FromHexString()`; nothing loops per pixel in BrightScript.

**One for-each position per array.** BrightScript keeps a single iteration position per array, so two nested `for each` loops over the same array silently cut the outer one short. Anything that may be called from inside a loop over the flock (`SimBlockerNear`, the tick's sheep loop, cursor targeting) uses indexed loops. The smoke test caught one such bug during the port; the comments in the code mark the places.

## Terrain on screen

The web game shades every terrain pixel in software. That is out of reach for BrightScript, so `TerrainPaint.brs` works from the same data the collision grid is built from.

- **First paint** walks the row bands. Each solid run in a band is one textured blit from a material sheet. Edges, grass or snow caps, outlines and grass blades are found with interval arithmetic between neighbouring bands.
- **Edits** (bash, mine, dig, blast, planks) repaint the edited rectangle plus a small margin, cell by cell from the live grid, merging equal neighbours into runs.

Both paths apply the same per-cell style rules, so an edit blends into the first paint with no seam. `tests/paint_check.brs` compares the two paths pixel for pixel.

The stage is held at one pixel per world pixel in 256-pixel-wide chunk bitmaps and drawn 2× with nearest-neighbour scaling. Chunks are written with blending off, so their alpha is exactly 0 or 255 on every GPU. A second copy of the original grid tells excavated ground (drawn as a dark cavity) from open air.

## A stage frame

`GameDraw.brs`, in order: far backdrop (opaque, blending off, doubles as the clear), mid and near parallax layers, scenery behind the ground, terrain chunks, hazards, sheepfolds, hatch frames, contact shadows, sheep, hatch trapdoors, particles, scenery in front, minimap, cursor, info line, toasts, the HUD bar, and any modal.

- Sheep are drawn between ticks by interpolating their last two positions, so 17 Hz movement looks smooth at 60 Hz.
- Sheep sprites are single blits from a pre-mirrored atlas; nothing is scaled or flipped per sprite.
- Hazards are drawn from primitives and a few animated strips, mirroring the web renderer's shapes.
- The HUD is repainted into its bitmap only when one of its values changes.

World pixel `(x, y)` maps to screen `(2x − camera, 2y)`. The playfield is the top 640 rows; the HUD takes the bottom 80, with its controls inside the action-safe area for TVs that overscan.

## Input

A TV remote is not a pointer, so the control scheme follows the console versions of the genre: a world-space cursor with acceleration, a selected skill, and a toolbar reachable from the bottom edge. Targeting ranks sheep under the cursor by "can actually take this skill", then distance, then id, with a generous hit box. Assignments are queued for the next tick exactly as recorded inputs are, so a human run and a replay go through the same code.

## Sound

`tools/build-audio.mts` re-implements the few WebAudio behaviours the web game uses (band-limited oscillators, exponential envelopes, biquad filters, the same seeded noise) and renders its effect patches and note data offline.

- Effects are PCM `.wav` played through `roAudioResource`. A Roku mixes only a couple at once, so each effect has a priority and a minimum gap.
- Music is one `.mp3` per tune through `roAudioPlayer`. Each file holds the tune three times and ends on a short ring-out, so the gap when a Roku restarts a looped file falls between phrases.

## Saved data

`Progress.brs` stores one compact JSON value in the registry: completed stages with best result and medal, the last stage played, stages opened by code, and settings. Every read is validated; damaged data falls back to defaults and never blocks stage 1 or code entry.

## Content pipeline

`tools/` imports the web game's own modules with `tsx`, so the Roku content cannot drift from it.

| Tool | Output |
|---|---|
| `build-levels.mts` | `levels/*.json` (facts, row bands, recorded solution), stage codes, and `tests/fixtures/expected.json` from the web engine. |
| `build-art.mts` | Atlases, terrain tiles, backdrops, icons, splash and `images/art.json`, rendered with the web game's procedural art code and palette-quantised. |
| `build-audio.mts` | Effects and music. |
| `package.mjs` | `out/sheepfall-roku.zip`, reproducible byte for byte, refused over 4 MB. |

## Tests

| Runner | Simulator program | Checks |
|---|---|---|
| `run-replays.mjs` | `tests/replay_runner.brs` | Engine parity with the web engine on all 129 stages. |
| `run-paint-check.mjs` | `tests/paint_check.brs` | Band paint equals cell paint, before and after edits. |
| `run-smoke.mjs` | `tests/smoke_main.brs` | The whole app under a scripted remote, with state assertions and screenshots in `build/smoke/`. |
