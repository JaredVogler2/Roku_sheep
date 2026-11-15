# Porting notes

Source: [JaredVogler2/Sheep](https://github.com/JaredVogler2/Sheep) at the commit in `docs/SOURCE_COMMIT` — a TypeScript / Canvas 2D / WebAudio browser game. Target: Roku, BrightScript, 2D API.

## What maps to what

| Web game | Roku app |
|---|---|
| `src/engine/Simulation.ts`, skills, masks | `Engine.brs`, `EngineSkills.brs`, `Terrain.brs` — same rules, same order of operations, checked by state hash |
| Stage definitions (`levels-src`) rasterised at load | `levels/*.json`, rasterised at build time into run-length row bands |
| Committed winning replays | The `sol` list in each stage file; used for "Watch a solution", the title backdrop and the tests |
| Access codes | `Levels.brs` — same alphabet, check symbol and code list |
| Canvas 2D renderer, per-pixel terrain shading | `GameDraw.brs`, `TerrainPaint.brs` — textured runs and flat fills from the same collision data |
| Procedural sprite, object and backdrop art | Rendered offline by that same code into atlases (`tools/build-art.mts`) |
| WebAudio synth and sequencer | Rendered offline into `.wav` and `.mp3` (`tools/build-audio.mts`) |
| Pointer, keyboard shortcuts | Remote cursor, skill cycling, toolbar focus |
| `localStorage` progress | Registry section `sheepfall` |
| DOM menus | `Menu*.brs` scenes drawn with nine-slice panels |

## Deliberate differences

- **No level editor.** It depends on a pointer and a keyboard.
- **Controls.** The tutorial cards say "press OK on" where the web game says "click", and the first stage adds one card introducing the remote. No rule text was changed.
- **No copy / share / notebook buttons.** The stage code is simply shown, large, wherever the web game offers to copy it.
- **Sound variants.** A Roku cannot re-pitch a sample, so pitched effects are pre-rendered: five countdown pips, three rescue bells (the web game has five pitches), three last-plank warnings, two bleats. Effects are mono.
- **Music loop.** Each tune is a file that plays three times and rings out before the Roku restarts it. There is no music volume, only on and off, because `roAudioPlayer` has none.
- **Compressor.** The web game runs everything through a dynamics compressor. The offline render instead sets the loudest effect just under full scale and lifts quieter ones part of the way toward it.
- **Cosmetics.** Fewer particles (64 at most, against 900). Water, lava and fire use short pre-rendered strips. Terrain shading is the run-and-edge scheme described in ARCHITECTURE.md, not per-pixel lighting.
- **"New Game"** goes straight to stage 1's brief. Nothing is erased either way, so the web game's confirmation dialog was dropped.
- **Codes in Stage Select.** A setting chooses between showing codes for beaten stages or for every open stage.

## Not yet run on hardware

The app has been exercised only on the brs-node simulator. The simulator is faithful about language semantics (it reproduced a real nested `for each` bug) but says nothing reliable about speed, texture memory or audio. On a device, check these first:

1. **It launches and reaches the title.** If it does not, the debug console (`telnet <roku-ip> 8085`) will name the line.
2. **Frame rate in a busy stage** — try Storm 23 (3200 px wide) and a stage with 80–100 sheep, at 1x and 4x. The frame-rate guard should shed scenery on slow models. If 4x cannot keep up, the tick budget in `GameUpdate` drops the backlog rather than freezing the remote.
3. **Stage load time** on a low-end model. First paint is the main cost.
4. **Audio.** Effect levels against the music, the feel of the loop restart, and whether two simultaneous effects are enough.
5. **Text fit.** Layout measures text with the device font, but the simulator's font is not Roku's. Look at the HUD counters with three-digit values, the stage select tabs and the brief.
6. **Overscan.** HUD controls sit at y 644–703, inside the action-safe area.
7. **The launch beacon.** `AppSignalLaunchComplete` cannot run in the simulator (it needs SceneGraph).
8. **Registry.** Progress should survive closing and reopening the app.

## Certification checklist

Status means "implemented here"; each still needs confirming on a device and with Roku's own tools.

| Requirement | Status |
|---|---|
| Package 4 MB or less | Enforced by `tools/package.mjs` (3.25 MB) |
| Splash screen for FHD and HD, home-screen icons | In `manifest` and `images/` |
| Back returns to the previous screen and exits from the home screen | Implemented in every scene |
| Launch within the time limit, `AppLaunchComplete` beacon | Beacon fired after the title is ready; launch time unmeasured |
| Works without a network connection | The app makes no network requests |
| Deep linking via launch parameters and `roInput` | `contentId` accepts a stage code or a stage id |
| `game=1`, `ui_resolutions=hd` | In `manifest` |
| Static analysis, performance and memory tests | Not run — they need Roku's tooling and a device |

Channel store artwork, description, rating and screenshots are not part of this repository.

## Ideas that were left out

- Per-device quality presets chosen from `roDeviceInfo` at start-up, instead of measuring frame time.
- A higher-resolution atlas set for FHD devices. The 4 MB limit leaves about 0.7 MB.
- Localisation. All strings are English and inline.
