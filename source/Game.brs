' =============================================================================
' SHEEPFALL for Roku - the stage scene: simulation clock, remote-control input,
' camera, cursor and targeting, overlays. Drawing lives in GameDraw.brs.
'
' Remote mapping (the web game is driven by a pointer; a TV remote is not one,
' so the scheme follows the console ports of the genre):
'
'   D-pad          move the cursor (it accelerates while held; the view follows)
'   OK             give the selected skill to the highlighted sheep
'   Rewind / FF    previous / next skill
'   Play/Pause     pause - the cursor still moves and OK still queues a skill,
'                  so every assignment can be made calmly
'   Instant Replay cycle speed 1x, 2x, 4x, 1/2x
'   * (Options)    jump between the playfield and the toolbar
'   Down at the bottom edge also enters the toolbar: release rate, skills,
'                  pause, speed, rewind, finish, nuke, menu
'   Back           pause menu (resume, restart, quit)
'
' The simulation is the unchanged 17 Hz engine; speed only changes how often it
' ticks. Sheep are drawn interpolated between ticks.
' =============================================================================

function GameNew(app as object, level as object, opts as object) as object
    g = {
        kind: "game"
        app: app
        level: level
        opts: opts
        update: GameUpdate
        draw: GameDraw
        onKey: GameOnKey
        animated: true
    }
    set = app.progress.data.set
    g.replay = opts.replay
    g.backdrop = opts.backdrop = true
    g.lesson = LevelIsLesson(level.id)
    g.assist = set.assist = 1 and g.replay = invalid and not g.backdrop
    g.sim = SimNew(level)
    g.biome = AssetsUseBiome(app.assets, level.theme)
    g.tp = TerrainPaintNew(level, g.sim.terrain, g.biome)
    g.sim.terrain.dirty = []
    effects = set.effects
    if effects > app.quality.effects then effects = app.quality.effects
    if g.backdrop and effects > 1 then effects = 1
    g.particles = ParticlesNew(level.theme, effects, g.biome.colors)
    g.scenery = set.scenery
    if g.scenery > app.quality.scenery then g.scenery = app.quality.scenery
    g.frameCount = 0
    g.frameMs = 0
    g.strips = {}
    g.animOf = [1, 0, 3, 4, 2, 5, 6, 7, 8, 9, 10, 11, 12]    ' sheep state -> animation in the atlas
    g.showMinimap = set.minimap = 1 and not g.backdrop

    ' ---- clock
    g.speeds = [1.0, 2.0, 4.0, 0.5]
    g.speedLabels = ["1x", "2x", "4x", "1/2x"]
    g.speedIndex = 0
    g.speedLabel = "1x"
    g.paused = false
    g.acc = 0.0
    g.alpha = 0.0
    g.animMs = 0
    g.endMs = 0
    g.ended = false
    g.replayNext = 0

    ' ---- camera (in screen pixels; the world is drawn 2x)
    g.maxCam = level.w * 2 - 1280
    if g.maxCam < 0 then g.maxCam = 0
    g.camPx = ClampInt(level.cam * 2, 0, g.maxCam)
    g.panIdleMs = 100000

    ' ---- cursor (world pixels) and toolbar focus
    g.curX = (g.camPx + 640) / 2.0
    g.curY = 150.0
    if level.ent.Count() > 0
        g.curX = level.ent[0][0] + 0.0
        g.curY = level.ent[0][1] + 40.0
        if g.curY > 300 then g.curY = 300.0
    end if
    g.held = [false, false, false, false]    ' up, down, left, right
    g.holdMs = 0
    speeds = [0.7, 1.0, 1.5]
    g.cursorSpeed = speeds[set.cursor]
    g.focusTool = -1
    g.targetId = -1
    g.targetOk = false
    g.okHeld = false
    g.okRepeatMs = 0

    ' never start with Boom selected: a stray first press must not blow up a sheep
    g.selected = -1
    for i = 0 to 7
        if i <> 2 and g.sim.stock[i] > 0 and g.selected < 0 then g.selected = i
    end for
    if g.selected < 0 and g.sim.stock[2] > 0 then g.selected = 2
    g.anySkills = g.selected >= 0

    ' ---- overlays
    g.toast = ""
    g.toastMs = 0
    g.toastBad = false
    g.nukeArmedMs = 0
    g.modal = invalid
    g.titleMs = 4500
    g.snapshots = []
    g.hud = invalid
    if not g.backdrop then g.hud = HudNew(g)

    ' ---- decor: resolve sprites once
    decor = []
    for each d in level.decor
        n = g.biome.decorFrames[d[0]]
        if n <> invalid
            frames = []
            offs = []
            for f = 0 to n - 1
                key = "decor." + d[0] + "." + f.ToStr()
                if g.biome.spr[key] <> invalid
                    frames.Push(g.biome.spr[key])
                    offs.Push(g.biome.off[key])
                end if
            end for
            if frames.Count() > 0
                ms = g.biome.decorMs[d[0]]
                if ms = invalid then ms = 1000
                decor.Push({ x: d[1], y: d[2], s: d[3], front: d[5] = 1, frames: frames, offs: offs, ms: ms })
            end if
        end if
    end for
    g.decor = decor

    ' ---- hazards: screen-space rectangles and animation state
    ' (indexed loops: BrightScript keeps one for-each position per array, so the
    ' same array must never be walked by two nested for-each loops)
    hz = []
    haz = level.haz
    nHaz = haz.Count()
    for i = 0 to nHaz - 1
        z = haz[i]
        period = 0
        if z[5] > 0 then period = z[5] + z[6]
        ' stacked water (a tide in several steps): is there more water right under this one?
        below = false
        if z[0] = "water"
            for j = 0 to nHaz - 1
                o = haz[j]
                if j <> i and o[0] = "water"
                    dy = o[2] - (z[2] + z[4])
                    if dy >= -1 and dy <= 1 and o[1] < z[1] + z[3] and o[1] + o[3] > z[1] then below = true
                end if
            end for
        end if
        hz.Push({ kind: z[0], x: z[1], y: z[2], w: z[3], h: z[4], phase: z[5], period: period, offset: z[7], below: below })
    end for
    g.hazards = hz

    if g.replay <> invalid and not g.backdrop then GameToast(g, "Watching a recorded run. Left / Right scrolls, Back stops.", 3500, false)
    if g.backdrop
        g.camPx = ClampInt(560 * 2 - 640, 0, g.maxCam)
    else
        AudioPlay(app.audio, "hatch")
        if set.tutorials = 1 and g.replay = invalid and level.tut.Count() > 0 then g.modal = { kind: "tutorial", page: 0 }
    end if
    return g
end function

sub GameToast(g as object, text as string, ms as integer, bad as boolean)
    g.toast = text
    g.toastMs = ms
    g.toastBad = bad
end sub

' ------------------------------------------------------------------- update

sub GameUpdate(dtMs as integer)
    g = m
    sim = g.sim
    if dtMs > 250 then dtMs = 250
    g.animMs = g.animMs + dtMs
    if g.toastMs > 0 then g.toastMs = g.toastMs - dtMs
    if g.titleMs > 0 then g.titleMs = g.titleMs - dtMs
    if g.nukeArmedMs > 0
        g.nukeArmedMs = g.nukeArmedMs - dtMs
        if g.nukeArmedMs < 0 then g.nukeArmedMs = 0
    end if

    if g.modal = invalid or g.modal.kind <> "pause" then GameMoveCursor(g, dtMs)

    ' ---- frame-rate guard: if this Roku cannot keep up, shed cosmetic work (never rules)
    if not g.paused and g.modal = invalid and sim.phase = 0
        g.frameCount = g.frameCount + 1
        g.frameMs = g.frameMs + dtMs
        if g.frameCount >= 150
            if g.frameMs > 150 * 27 then GameLowerQuality(g)
            g.frameCount = 0
            g.frameMs = 0
        end if
    end if

    ' ---- simulation
    period = 58.8235294 / g.speeds[g.speedIndex]
    if sim.phase = 0
        if not g.paused and g.modal = invalid
            g.acc = g.acc + dtMs
            n = Int(g.acc / period)
            if n > 16
                n = 16
                g.acc = 0.0
            else
                g.acc = g.acc - n * period
            end if
            if n > 0
                budget = CreateObject("roTimespan")
                for i = 1 to n
                    GameTick(g)
                    if sim.phase <> 0 then exit for
                    ' a slow box at 4x: drop the backlog rather than freeze the remote
                    if budget.TotalMilliseconds() > 70
                        g.acc = 0.0
                        exit for
                    end if
                end for
            end if
        end if
        g.alpha = g.acc / period
    else
        ' cosmetic tail after the stage ends: let exit and poof animations finish
        before = g.endMs
        g.endMs = g.endMs + dtMs
        if (g.endMs * 17) \ 1000 > (before * 17) \ 1000 then SimAdvanceCosmetic(sim)
        g.alpha = 1.0
        if not g.ended and g.endMs > 1300
            g.ended = true
            if g.backdrop
                GameRestartBackdrop(g)
            else
                g.app.onGameEnd(g, GameResult(g, false, false))
            end if
            return
        end if
    end if
    if g.backdrop and sim.tick > 1400 then GameRestartBackdrop(g)

    x0 = g.camPx / 2.0
    ParticlesUpdate(g.particles, dtMs, x0, x0 + 640)
    GamePick(g)

    ' rate buttons repeat while OK is held on them
    if g.okHeld and g.focusTool >= 0 and g.hud <> invalid
        t = g.hud.tools[g.focusTool]
        if t <> invalid
            if t.kind = "rate"
                g.okRepeatMs = g.okRepeatMs - dtMs
                if g.okRepeatMs <= 0
                    g.okRepeatMs = 70
                    GameActivateTool(g, t)
                end if
            end if
        end if
    end if
end sub

' Called when frames have averaged slower than ~37 per second for 150 frames.
' Drops one backdrop layer at a time, then thins the particles. The ceiling is
' remembered for the session (not saved), so later stages start out lighter.
sub GameLowerQuality(g as object)
    cap = g.app.quality
    if g.scenery > 0
        g.scenery = g.scenery - 1
        cap.scenery = g.scenery
    else if g.particles.level > 1
        g.particles.level = 1
        g.particles.cap = 24
        cap.effects = 1
    else
        return
    end if
    if not g.backdrop then GameToast(g, "Scenery simplified to keep the game smooth", 2200, false)
end sub

' The menu backdrop loops a small demo stage for ever.
sub GameRestartBackdrop(g as object)
    g.sim = SimNew(g.level)
    g.tp = TerrainPaintNew(g.level, g.sim.terrain, g.biome)
    g.sim.terrain.dirty = []
    g.replayNext = 0
    g.acc = 0.0
    g.endMs = 0
    g.ended = false
    ParticlesClear(g.particles)
end sub

sub GameTick(g as object)
    sim = g.sim
    rp = g.replay
    if rp <> invalid
        n = rp.Count()
        while g.replayNext < n and rp[g.replayNext][0] <= sim.tick
            inp = rp[g.replayNext]
            sim.pending.Push([sim.tick, inp[1], inp[2], inp[3]])
            g.replayNext = g.replayNext + 1
        end while
    end if
    ' Assisted Mode: a snapshot every 3 seconds, at most 20
    if g.assist and sim.tick mod 51 = 0
        n = g.snapshots.Count()
        fresh = true
        if n > 0 then fresh = g.snapshots[n - 1].tick <> sim.tick
        if fresh then GameSnapshot(g)
    end if
    sheep = sim.sheep
    for each s in sheep
        s.px = s.x
        s.py = s.y
    end for
    events = SimStep(sim)
    if events.Count() > 0 then GameOnEvents(g, events)
    t = sim.terrain
    if t.dirty.Count() > 0
        for each r in t.dirty
            TpRepaint(g.tp, r[0], r[1], r[2], r[3])
        end for
        t.dirty = []
    end if
end sub

sub GameOnEvents(g as object, events as object)
    audio = g.app.audio
    viewX0 = g.camPx \ 2 - 40
    viewX1 = viewX0 + 720
    quiet = g.backdrop
    for each e in events
        k = e.k
        if not quiet
            if k = 2
                AudioPlay(audio, "assign")
            else if k = 3
                if g.replay = invalid
                    AudioPlay(audio, "reject")
                    GameToast(g, e.reason, 1800, true)
                end if
            else if k = 4
                if e.x > viewX0 and e.x < viewX1 then AudioPlay(audio, "chute")
            else if k = 5
                if e.x > viewX0 and e.x < viewX1
                    if e.left < 3
                        AudioPlay(audio, "plankwarn" + (2 - e.left).ToStr())
                    else
                        AudioPlay(audio, "plank")
                    end if
                end if
            else if k = 6
                if e.x > viewX0 and e.x < viewX1
                    if e.kind = 1
                        AudioPlay(audio, "pick")
                    else if e.kind = 2
                        AudioPlay(audio, "shovel")
                    else
                        AudioPlay(audio, "crumble")
                    end if
                end if
            else if k = 7
                AudioPlay(audio, "ting")
            else if k = 8
                AudioPlay(audio, "pip" + e.v.ToStr())
            else if k = 9
                AudioPlay(audio, "pop")
            else if k = 10
                AudioPlay(audio, "bell" + (g.sim.saved mod 3).ToStr())
                if g.sim.saved mod 4 = 1 then AudioPlay(audio, "bleat" + (e.id mod 2).ToStr())
            else if k = 11
                if e.cause = 1
                    AudioPlay(audio, "splash")
                else if e.cause = 2
                    AudioPlay(audio, "sizzle")
                else if e.cause = 0 or e.cause = 3 or e.cause = 4
                    AudioPlay(audio, "poof")
                end if
            else if k = 14
                if e.phase = 1
                    AudioPlay(audio, "fanfare")
                else
                    AudioPlay(audio, "sigh")
                end if
            end if
        end if
    end for
    ParticlesOnEvents(g.particles, events, g.app.assets.spr)
end sub

function GameResult(g as object, aborted as boolean, restart as boolean) as object
    sim = g.sim
    ticks = sim.tick
    if sim.endTick >= 0 then ticks = sim.endTick
    return {
        won: sim.phase = 1 and not aborted
        saved: sim.saved
        required: sim.required
        total: sim.total
        lost: sim.lost
        reason: sim.endReason
        ticks: ticks
        inputs: sim.applied
        aborted: aborted
        restart: restart
    }
end function

' ---------------------------------------------------------- Assisted Mode
' A snapshot keeps the counters and a copy of every sheep. Terrain is never
' copied: while Assisted Mode is on, Terrain.brs logs the old value of every
' cell it changes into the newest snapshot's undo list, and rewinding puts
' those cells back and repaints just the rectangles they were in.

sub GameSnapshot(g as object)
    sim = g.sim
    copies = []
    for each s in sim.sheep
        c = {}
        c.Append(s)
        copies.Push(c)
    end for
    stock = []
    stock.Append(sim.stock)
    spawned = []
    spawned.Append(sim.hatchSpawned)
    snap = {
        tick: sim.tick, saved: sim.saved, lost: sim.lost, waiting: sim.waiting, active: sim.active
        stock: stock, releaseRate: sim.releaseRate, timeLeft: sim.timeLeft, lastSpawnTick: sim.lastSpawnTick
        hatchCursor: sim.hatchCursor, hatchSpawned: spawned, nuking: sim.nuking, finishRequested: sim.finishRequested
        sheep: copies, undo: [], appliedLen: sim.applied.Count()
    }
    sim.terrain.undo = snap.undo
    g.snapshots.Push(snap)
    if g.snapshots.Count() > 20 then g.snapshots.Shift()
end sub

' Puts back every cell in an undo list (newest change first).
sub GameUndoTerrain(g as object, undo as object)
    cells = g.sim.terrain.cells
    while undo.Count() > 0
        u = undo.Pop()
        i = u.Count() - 2
        while i >= 4
            cells[u[i]] = u[i + 1]
            i = i - 2
        end while
        TpRepaint(g.tp, u[0], u[1], u[2], u[3])
    end while
end sub

sub GameRewind(g as object)
    if not g.assist or g.snapshots.Count() = 0 or g.sim.phase <> 0 then return
    sim = g.sim
    snap = g.snapshots.Pop()
    GameUndoTerrain(g, snap.undo)
    ' a snapshot taken less than a second ago is not much of a rewind: go further back
    while sim.tick - snap.tick < 17 and g.snapshots.Count() > 0
        snap = g.snapshots.Pop()
        GameUndoTerrain(g, snap.undo)
    end while
    sim.terrain.dirty = []
    sim.tick = snap.tick
    sim.saved = snap.saved
    sim.lost = snap.lost
    sim.waiting = snap.waiting
    sim.active = snap.active
    sim.stock = snap.stock
    sim.releaseRate = snap.releaseRate
    sim.timeLeft = snap.timeLeft
    sim.lastSpawnTick = snap.lastSpawnTick
    sim.hatchCursor = snap.hatchCursor
    sim.hatchSpawned = snap.hatchSpawned
    sim.nuking = snap.nuking
    sim.finishRequested = snap.finishRequested
    sim.sheep = snap.sheep
    sim.pending = []
    sim.events = []
    while sim.applied.Count() > snap.appliedLen
        sim.applied.Pop()
    end while
    g.acc = 0.0
    g.nukeArmedMs = 0
    ParticlesClear(g.particles)
    GameToast(g, "Rewound to " + ClockText(sim.timeLeft) + " (Assisted Mode)", 1500, false)
    ' the state just restored becomes the newest snapshot again
    GameSnapshot(g)
end sub

' ------------------------------------------------------------------ cursor

sub GameMoveCursor(g as object, dtMs as integer)
    h = g.held
    dx = 0
    dy = 0
    if h[2] then dx = dx - 1
    if h[3] then dx = dx + 1
    if h[0] then dy = dy - 1
    if h[1] then dy = dy + 1
    g.panIdleMs = g.panIdleMs + dtMs
    if g.replay <> invalid
        ' watching: Left / Right scroll the view; otherwise it follows the flock
        if dx <> 0 and not g.backdrop
            g.camPx = ClampInt(g.camPx + dx * dtMs * 9 \ 10, 0, g.maxCam)
            g.panIdleMs = 0
        else if g.panIdleMs > 2500 and not g.backdrop
            GameFollowFlock(g, dtMs)
        end if
        return
    end if
    if g.focusTool >= 0 then return
    if dx = 0 and dy = 0
        g.holdMs = 0
    else
        ' world px per second: a gentle start for precise aim, then a quick sweep
        g.holdMs = g.holdMs + dtMs
        v = 50.0
        if g.holdMs > 160 then v = 50.0 + (g.holdMs - 160) * 0.55
        if v > 330.0 then v = 330.0
        v = v * g.cursorSpeed * dtMs / 1000.0
        g.curX = g.curX + dx * v
        g.curY = g.curY + dy * v
    end if
    maxX = g.level.w - 1
    if g.curX < 0 then g.curX = 0.0
    if g.curX > maxX then g.curX = maxX + 0.0
    if g.curY < 2 then g.curY = 2.0
    if g.curY > 318 then g.curY = 318.0
    ' the view follows when the cursor nears the side of the screen
    sx = Int(g.curX * 2) - g.camPx
    if sx < 280
        g.camPx = ClampInt(Int(g.curX * 2) - 280, 0, g.maxCam)
    else if sx > 1000
        g.camPx = ClampInt(Int(g.curX * 2) - 1000, 0, g.maxCam)
    end if
end sub

' While watching a replay the camera eases toward the middle of the active flock.
sub GameFollowFlock(g as object, dtMs as integer)
    sum = 0
    n = 0
    for each s in g.sim.sheep
        if s.fate = 0
            sum = sum + s.x
            n = n + 1
        end if
    end for
    if n = 0 then return
    target = ClampInt((sum \ n) * 2 - 640, 0, g.maxCam)
    stepPx = dtMs * 5 \ 10
    if stepPx < 1 then stepPx = 1
    if target > g.camPx + stepPx
        g.camPx = g.camPx + stepPx
    else if target < g.camPx - stepPx
        g.camPx = g.camPx - stepPx
    else
        g.camPx = target
    end if
end sub

' Finds the sheep the cursor points at. Ranking: sheep that can actually take
' the selected skill first, then distance from the body centre, then id.
' The box is the drawn sprite (1.35x the 10 px body) plus a generous margin,
' because a D-pad cursor is not a mouse.
sub GamePick(g as object)
    g.targetId = -1
    g.targetOk = false
    if g.replay <> invalid or g.focusTool >= 0 or g.sim.phase <> 0 then return
    wx = g.curX
    wy = g.curY
    sim = g.sim
    best = invalid
    bestOk = false
    bestD = 1000000.0
    skill = g.selected
    sheep = sim.sheep
    for si = 0 to sheep.Count() - 1
        s = sheep[si]
        if s.fate = 0
            cx = s.x + 1.05 * s.dir
            ddx = wx - cx
            if ddx > -11 and ddx < 11
                ddy = wy - (s.y - 6.75)
                if ddy > -12.5 and ddy < 13.5
                    d = ddx * ddx + ddy * ddy
                    ok = false
                    if skill >= 0 then ok = SimCheckAssign(sim, s.id, skill) = ""
                    better = false
                    if best = invalid
                        better = true
                    else if ok and not bestOk
                        better = true
                    else if ok = bestOk and d < bestD
                        better = true
                    end if
                    if better
                        best = s
                        bestOk = ok
                        bestD = d
                    end if
                end if
            end if
        end if
    end for
    if best <> invalid
        g.targetId = best.id
        g.targetOk = bestOk
    end if
end sub

' -------------------------------------------------------------------- input

sub GameOnKey(code as integer, pressed as boolean)
    g = m
    ' D-pad state is tracked for every mode so a release is never missed
    if code >= 2 and code <= 5 then g.held[code - 2] = pressed
    if code = 6 then g.okHeld = pressed
    if not pressed then return
    if g.backdrop then return

    if g.modal <> invalid
        GameModalKey(g, code)
        return
    end if
    if g.sim.phase <> 0 then return

    if code = 0
        if g.focusTool >= 0
            g.focusTool = -1
        else
            GameOpenPause(g)
        end if
    else if code = 13
        GameSetPaused(g, not g.paused)
    else if code = 7
        GameCycleSpeed(g)
    else if g.replay <> invalid
        ' watching a run: only pause / speed / back, plus OK on the toolbar
        if code = 6 and g.focusTool >= 0 then GameActivateTool(g, g.hud.tools[g.focusTool])
        if code = 10 or code = 3
            g.focusTool = HudFindTool(g.hud, "pause", -1)
        else if code = 2
            g.focusTool = -1
        else if (code = 4 or code = 5) and g.focusTool >= 0
            GameMoveFocus(g, code)
        end if
    else if code = 8
        GameStepSkill(g, -1)
    else if code = 9
        GameStepSkill(g, 1)
    else if code = 10
        if g.focusTool >= 0
            g.focusTool = -1
        else
            GameEnterToolbar(g)
        end if
    else if g.focusTool >= 0
        if code = 4 or code = 5
            GameMoveFocus(g, code)
        else if code = 2
            g.focusTool = -1
        else if code = 6
            g.okRepeatMs = 350
            GameActivateTool(g, g.hud.tools[g.focusTool])
        end if
    else if code = 6
        GameAssign(g)
    else if code = 3
        ' a fresh Down press at the bottom edge steps into the toolbar
        if g.curY >= 317.5 then GameEnterToolbar(g)
    end if
end sub

sub GameEnterToolbar(g as object)
    AudioPlay(g.app.audio, "ui")
    g.held = [false, false, false, false]
    if g.selected >= 0
        g.focusTool = HudFindTool(g.hud, "skill", g.selected)
    else
        g.focusTool = HudFindTool(g.hud, "pause", -1)
    end if
    if g.focusTool < 0 then g.focusTool = 0
end sub

sub GameMoveFocus(g as object, code as integer)
    n = g.hud.tools.Count()
    if code = 4
        g.focusTool = g.focusTool - 1
        if g.focusTool < 0 then g.focusTool = n - 1
    else
        g.focusTool = g.focusTool + 1
        if g.focusTool >= n then g.focusTool = 0
    end if
    AudioPlay(g.app.audio, "ui")
end sub

sub GameStepSkill(g as object, dir as integer)
    sim = g.sim
    cur = g.selected
    if cur < 0 then cur = 0
    ' skip skills this stage has none of (unless it has none at all)
    for i = 1 to 8
        cur = (cur + dir + 8) mod 8
        if sim.stock[cur] > 0
            g.selected = cur
            AudioPlay(g.app.audio, "ui")
            GameToast(g, SimSkillLabels()[cur] + " - " + sim.stock[cur].ToStr() + " left", 900, false)
            if g.focusTool >= 0 then g.focusTool = HudFindTool(g.hud, "skill", cur)
            return
        end if
    end for
    GameToast(g, "No skills left on this stage", 1200, true)
end sub

sub GameAssign(g as object)
    sim = g.sim
    if g.targetId < 0 then return
    if g.selected < 0
        if g.anySkills
            GameToast(g, "Pick a skill first: Rewind / Fast Forward, or Down to the toolbar.", 2200, true)
        else
            GameToast(g, "This stage has no skills to give - the flock manages alone.", 2200, false)
        end if
        return
    end if
    reason = SimCheckAssign(sim, g.targetId, g.selected)
    if reason <> ""
        AudioPlay(g.app.audio, "reject")
        GameToast(g, reason, 1800, true)
        return
    end if
    ' one press can never spend two charges on the same sheep within a tick
    for each p in sim.pending
        if p[1] = 0 and p[2] = g.targetId then return
    end for
    SimEnqueue(sim, 0, g.targetId, g.selected)
    if g.paused then GameToast(g, SimSkillLabels()[g.selected] + " queued - it starts when you resume", 1500, false)
end sub

sub GameSetPaused(g as object, paused as boolean)
    if g.sim.phase <> 0 then return
    g.paused = paused
    if not paused then g.acc = 0.0
    AudioPlay(g.app.audio, "ui")
end sub

sub GameCycleSpeed(g as object)
    g.speedIndex = (g.speedIndex + 1) mod 4
    g.speedLabel = g.speedLabels[g.speedIndex]
    g.acc = 0.0
    AudioPlay(g.app.audio, "ui")
    GameToast(g, "Speed " + g.speedLabel, 800, false)
end sub

sub GameActivateTool(g as object, t as object)
    if t = invalid then return
    sim = g.sim
    audio = g.app.audio
    id = t.id
    if id = "skill"
        g.selected = t.skill
        AudioPlay(audio, "ui")
        if sim.stock[t.skill] <= 0
            GameToast(g, "No " + SimSkillLabels()[t.skill] + " left on this stage", 1500, true)
        else
            ' back to the flock with the new tool in hand
            g.focusTool = -1
        end if
    else if id = "slower" or id = "faster"
        delta = 1
        if id = "slower" then delta = -1
        v = ClampInt(sim.releaseRate + delta, sim.minReleaseRate, 99)
        if v <> sim.releaseRate
            SimEnqueue(sim, 1, v, 0)
            AudioPlay(audio, "rate")
            ' show the change at once even while paused
            if g.paused then GameToast(g, "Release rate " + v.ToStr() + " when you resume", 900, false)
        else if delta < 0
            GameToast(g, "Release rate cannot go below " + sim.minReleaseRate.ToStr() + " here", 1200, true)
        end if
    else if id = "pause"
        GameSetPaused(g, not g.paused)
    else if id = "speed"
        GameCycleSpeed(g)
    else if id = "rewind"
        GameRewind(g)
    else if id = "finish"
        SimEnqueue(sim, 3, 0, 0)
        AudioPlay(audio, "ui")
        if g.paused then GameSetPaused(g, false)
    else if id = "nuke"
        if sim.nuking then return
        if g.nukeArmedMs > 0
            g.nukeArmedMs = 0
            SimEnqueue(sim, 2, 0, 0)
            GameToast(g, "Nuke! Every sheep goes boom.", 1800, true)
            if g.paused then GameSetPaused(g, false)
        else
            g.nukeArmedMs = 2500
            AudioPlay(audio, "nukearm")
            GameToast(g, "Press NUKE again within 2 seconds to confirm.", 2400, true)
        end if
    else if id = "menu"
        GameOpenPause(g)
    end if
end sub

' ------------------------------------------------------------------- modals

sub GameOpenPause(g as object)
    items = ["Resume"]
    if g.replay = invalid
        items.Push("Restart stage")
        if g.sim.saved >= g.sim.required then items.Push("Finish now")
        items.Push("Quit to menu")
    else
        items.Push("Stop watching")
    end if
    g.modal = { kind: "pause", items: items, sel: 0, wasPaused: g.paused }
    g.held = [false, false, false, false]
    AudioPlay(g.app.audio, "ui")
end sub

sub GameModalKey(g as object, code as integer)
    md = g.modal
    audio = g.app.audio
    if md.kind = "tutorial"
        if code = 6 or code = 13 or code = 5
            md.page = md.page + 1
            AudioPlay(audio, "ui")
            if md.page >= g.level.tut.Count() then g.modal = invalid
        else if code = 4 and md.page > 0
            md.page = md.page - 1
        else if code = 0
            g.modal = invalid
        end if
        return
    end if
    ' pause menu
    n = md.items.Count()
    if code = 2
        md.sel = (md.sel + n - 1) mod n
        AudioPlay(audio, "ui")
    else if code = 3
        md.sel = (md.sel + 1) mod n
        AudioPlay(audio, "ui")
    else if code = 0 or code = 13
        g.modal = invalid
    else if code = 6
        choice = md.items[md.sel]
        g.modal = invalid
        if choice = "Restart stage"
            g.app.onGameEnd(g, GameResult(g, true, true))
        else if choice = "Finish now"
            SimEnqueue(g.sim, 3, 0, 0)
            g.paused = false
        else if choice = "Quit to menu" or choice = "Stop watching"
            g.app.onGameEnd(g, GameResult(g, true, false))
        end if
    end if
end sub

' Human-readable status of a sheep for the info line ("BUILDING 8/12 - CLIMBER").
function GameDescribeSheep(s as object) as string
    st = s.state
    text = UCase(SimStateNames()[st])
    if st = 6
        text = "BUILDING " + (12 - s.bricks).ToStr() + "/12"
    else if st = 7
        text = "BUILT 12/12"
    else if st = 3
        text = "CLIMBING"
    else if st = 4
        text = "PARACHUTING"
    else if st = 11
        text = "OH NO!"
    end if
    if s.canClimb and s.canFloat
        text = text + " - ATHLETE"
    else if s.canClimb
        text = text + " - CLIMBER"
    else if s.canFloat
        text = text + " - PARACHUTE"
    end if
    if s.bomberTicks > 0 then text = text + " - BOOM IN " + ((s.bomberTicks + 16) \ 17).ToStr()
    return text
end function
