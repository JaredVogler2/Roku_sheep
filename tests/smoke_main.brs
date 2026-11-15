' =============================================================================
' Scripted smoke test, run by tools/run-smoke.mjs on the brs-node BrightScript
' simulator (it never ships in the channel package).
'
' It starts the REAL app (source/App.brs and everything behind it) with a
' driver that stands in for the remote and the clock: every frame it may press
' keys, and it reports a fixed frame time so runs are repeatable. Screenshots
' are read back from the screen and printed as base64 for the Node side to save.
'
' Launch parameter:  script=<cmd>+<cmd>+...
'   wN        wait N frames                  kN     tap remote key N
'   dN / uN   hold / release key N           cN     type character code N
'   s<name>   screenshot                     i      print a state line
'   tN        frame time in ms (default 16)  fN     run N simulation ticks at once
'   jX:Y      put the cursor at world X,Y    aID:S  give skill S to sheep ID
'   gID       put the cursor on sheep ID     q      quit
'   S<stage>  start a stage                  R<stage>  watch a stage's recorded solution
'   W<stage>  start a stage and play its recorded solution as player input, to the end
' Remote keys: 0 Back, 2 Up, 3 Down, 4 Left, 5 Right, 6 OK, 7 Instant Replay,
'              8 Rewind, 9 Fast Forward, 10 Options, 13 Play/Pause.
' =============================================================================

sub Main(args as dynamic)
    script = ""
    if args <> invalid and args.script <> invalid then script = args.script
    driver = {
        steps: script.Split("+")
        at: 0
        waitFrames: 0
        dt: 16
        release: []
        shot: ""
        frames: 0
        timer: CreateObject("roTimespan")
        perf: {}
        advance: SmokeStep
        drawn: SmokeFrame
    }
    launch = {}
    if args <> invalid and args.contentId <> invalid then launch.contentId = args.contentId
    AppMain(launch, driver)
    for each kind in driver.perf
        p = driver.perf[kind]
        print "PERF|" + kind + "|" + p.n.ToStr() + "|" + Str(p.total / p.n).Trim() + "|" + p.worst.ToStr()
    end for
    print "SMOKE-DONE|" + driver.frames.ToStr()
end sub

function SmokeStep(app as object) as integer
    d = m
    for each code in d.release
        AppKey(app, code, false)
    end for
    d.release = []
    while d.waitFrames = 0 and d.at < d.steps.Count() and not app.quit
        cmd = d.steps[d.at]
        d.at = d.at + 1
        op = Left(cmd, 1)
        arg = Mid(cmd, 2)
        if op = "w"
            d.waitFrames = arg.ToInt()
        else if op = "k"
            AppKey(app, arg.ToInt(), true)
            d.release.Push(arg.ToInt())
            d.waitFrames = 3
        else if op = "d"
            AppKey(app, arg.ToInt(), true)
        else if op = "u"
            AppKey(app, arg.ToInt(), false)
        else if op = "c"
            AppChar(app, arg.ToInt())
            d.waitFrames = 2
        else if op = "s"
            d.shot = arg
            d.waitFrames = 1
        else if op = "t"
            d.dt = arg.ToInt()
        else if op = "i"
            SmokeInfo(app)
        else if op = "q"
            app.quit = true
        else if op = "S"
            AppStartStage(app, arg, { replay: invalid, viaCode: false, from: "stages" })
        else if op = "R"
            level = LevelLoad(arg)
            AppStartStage(app, arg, { replay: level.sol, viaCode: false, from: "stages" })
        else if op = "W"
            AppStartStage(app, arg, { replay: invalid, viaCode: false, from: "stages" })
            g = app.scene
            g.modal = invalid
            sol = g.level.sol
            nextIn = 0
            while g.sim.phase = 0 and g.sim.tick < g.level.time + 60
                while nextIn < sol.Count() and sol[nextIn][0] <= g.sim.tick
                    SimEnqueue(g.sim, sol[nextIn][1], sol[nextIn][2], sol[nextIn][3])
                    nextIn = nextIn + 1
                end while
                GameTick(g)
            end while
        else if app.scene.kind = "game"
            g = app.scene
            if op = "f"
                for i = 1 to arg.ToInt()
                    if g.sim.phase = 0 then GameTick(g)
                end for
            else if op = "j"
                xy = arg.Split(":")
                g.curX = xy[0].ToInt() + 0.0
                g.curY = xy[1].ToInt() + 0.0
                g.camPx = ClampInt(xy[0].ToInt() * 2 - 640, 0, g.maxCam)
            else if op = "a"
                pair = arg.Split(":")
                SimEnqueue(g.sim, 0, pair[0].ToInt(), pair[1].ToInt())
            else if op = "g"
                sheep = g.sim.sheep[arg.ToInt()]
                g.curX = sheep.x + 0.0
                g.curY = sheep.y - 6.0
            end if
        end if
    end while
    if d.waitFrames > 0 then d.waitFrames = d.waitFrames - 1
    if d.at >= d.steps.Count() and d.waitFrames = 0 and d.shot = "" then app.quit = true
    d.timer.Mark()
    return d.dt
end function

' Called after the scene has been drawn (or when a static menu had nothing to redraw).
sub SmokeFrame(app as object)
    d = m
    ms = d.timer.TotalMilliseconds()
    d.frames = d.frames + 1
    kind = app.scene.kind
    p = d.perf[kind]
    if p = invalid
        p = { n: 0, total: 0, worst: 0 }
        d.perf[kind] = p
    end if
    p.n = p.n + 1
    p.total = p.total + ms
    if ms > p.worst then p.worst = ms
    if d.shot <> ""
        png = app.screen.GetPng(0, 0, 1280, 720)
        if png = invalid
            print "ERROR|screenshot failed|" + d.shot
        else
            text = png.ToBase64String()
            print "SHOT|" + d.shot + "|" + Len(text).ToStr()
            at = 1
            while at <= Len(text)
                print "P|" + Mid(text, at, 480)
                at = at + 480
            end while
            print "SHOT-END"
        end if
        d.shot = ""
    end if
end sub

sub SmokeInfo(app as object)
    s = app.scene
    line = "INFO|" + s.kind
    if s.kind = "game"
        sim = s.sim
        line = line + "|" + s.level.id + "|tick=" + sim.tick.ToStr() + "|phase=" + sim.phase.ToStr() + "|saved=" + sim.saved.ToStr() + "|lost=" + sim.lost.ToStr()
        line = line + "|active=" + sim.active.ToStr() + "|waiting=" + sim.waiting.ToStr() + "|selected=" + s.selected.ToStr() + "|focus=" + s.focusTool.ToStr()
        line = line + "|cursor=" + Int(s.curX).ToStr() + "," + Int(s.curY).ToStr() + "|target=" + s.targetId.ToStr() + "|cam=" + s.camPx.ToStr()
        line = line + "|particles=" + s.particles.list.Count().ToStr() + "|speed=" + s.speedLabel + "|paused=" + s.paused.ToStr()
        ' the state code of the first sheep (see Engine.brs), enough to tell what a command did
        states = ""
        for i = 0 to sim.sheep.Count() - 1
            if i < 8 then states = states + sim.sheep[i].state.ToStr() + "."
        end for
        line = line + "|st=" + states
        if s.replay <> invalid then line = line + "|replay"
        if s.modal <> invalid then line = line + "|modal=" + s.modal.kind
    else if s.kind = "stages"
        line = line + "|act=" + s.act.ToStr() + "|sel=" + s.sel.ToStr()
    else if s.kind = "brief"
        line = line + "|" + s.id
    else if s.kind = "code"
        line = line + "|" + s.text + "|" + s.message
    else if s.kind = "result"
        line = line + "|" + s.level.id + "|won=" + s.result.won.ToStr() + "|saved=" + s.result.saved.ToStr()
        if s.win <> invalid then line = line + "|medal=" + s.win.medal.ToStr() + "|next=" + s.win.nextId
        line = line + "|done=" + app.progress.data.done.Count().ToStr()
    end if
    print line
end sub
