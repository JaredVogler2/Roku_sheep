' =============================================================================
' Headless engine verification, run by tools/run-replays.mjs on the brs-node
' BrightScript simulator (it never ships in the channel package).
'
' For every requested stage it plays the recorded winning solution through the
' real engine (source/Engine*.brs, source/Terrain.brs) and prints the complete
' gameplay state. The Node driver hashes that state with the web game's 64-bit
' state hash and compares it with tests/fixtures/expected.json, so a pass means
' the Roku engine reaches the same final state as the web engine: every counter,
' every sheep field and every terrain cell.
'
' Launch parameter:  levels=meadow-01+meadow-02+...
' =============================================================================

sub Main(args as dynamic)
    ids = []
    if args <> invalid and args.levels <> invalid then ids = args.levels.Split("+")
    for each id in ids
        RunReplay(id)
    end for
    print "RUNNER-DONE"
end sub

sub RunReplay(id as string)
    timer = CreateObject("roTimespan")
    level = LevelLoad(id)
    if level = invalid
        print "ERROR|" + id + "|cannot load level"
        return
    end if
    sim = SimNew(level)
    loadMs = timer.TotalMilliseconds()
    timer.Mark()
    inputs = level.sol
    nInputs = inputs.Count()
    nextIn = 0
    rejected = 0
    invariantOk = true
    limit = level.time + 50
    while sim.phase = 0 and sim.tick <= limit
        while nextIn < nInputs and inputs[nextIn][0] = sim.tick
            inp = inputs[nextIn]
            sim.pending.Push([inp[0], inp[1], inp[2], inp[3]])
            nextIn = nextIn + 1
        end while
        events = SimStep(sim)
        for each e in events
            if e.k = 3 then rejected = rejected + 1
        end for
        if not SimCheckInvariant(sim) then invariantOk = false
    end while
    simMs = timer.TotalMilliseconds()

    phases = ["running", "won", "lost"]
    fates = ["active", "saved", "lost"]
    names = SimStateNames()
    nuking = 0
    if sim.nuking then nuking = 1
    inv = 0
    if invariantOk then inv = 1
    head = [id, phases[sim.phase], sim.endReason, sim.saved.ToStr(), sim.lost.ToStr(), sim.endTick.ToStr(), inv.ToStr(), rejected.ToStr(), (nInputs - nextIn).ToStr(), loadMs.ToStr(), simMs.ToStr()]
    print "RESULT|" + head.Join("|")

    f = [sim.tick, sim.waiting, sim.active, sim.releaseRate, sim.timeLeft, sim.lastSpawnTick, sim.hatchCursor, nuking]
    parts = []
    for each v in f
        parts.Push(v.ToStr())
    end for
    stock = []
    for each v in sim.stock
        stock.Push(v.ToStr())
    end for
    spawned = []
    for each v in sim.hatchSpawned
        spawned.Push(v.ToStr())
    end for
    print "STATE|" + parts.Join(",") + "|" + stock.Join(",") + "|" + spawned.Join(",")

    rows = []
    for each s in sim.sheep
        cc = 0
        if s.canClimb then cc = 1
        cf = 0
        if s.canFloat then cf = 1
        rows.Push([s.id.ToStr(), s.x.ToStr(), s.y.ToStr(), s.dir.ToStr(), names[s.state], cc.ToStr(), cf.ToStr(), s.bomberTicks.ToStr(), s.fallDistance.ToStr(), s.stateTicks.ToStr(), s.bricks.ToStr(), fates[s.fate]].Join(","))
    end for
    print "SHEEP|" + rows.Join(";")

    ' the padded grid, base64, in short lines (the simulator console is quadratic in line length)
    t = sim.terrain
    b64 = t.cells.ToBase64String()
    print "TERRAIN|" + t.w.ToStr() + "|" + t.h.ToStr() + "|" + TerrainPad().ToStr() + "|" + Len(b64).ToStr()
    n = Len(b64)
    i = 1
    while i <= n
        print "T|" + Mid(b64, i, 480)
        i = i + 480
    end while
    print "TERRAIN-END"
end sub
