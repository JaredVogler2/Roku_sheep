' =============================================================================
' SHEEPFALL for Roku - authoritative fixed-timestep simulation.
'
' BrightScript port of src/engine/Simulation.ts (physics preset
' classic-dos-inspired-v1). No screen, no wall clock, no randomness: the same
' inputs always produce the same state, tick for tick, and the 129 committed
' winning replays of the web game end in the identical 64-bit state hash here
' (see tests/ and tools/run-replays.mjs).
'
' Frozen per-tick order (golden-tested):
'   1. apply queued player inputs for this tick, in arrival order
'   2. nuke: give the next un-primed sheep its countdown
'   3. for each sheep in id order:
'        a. bomber countdown
'        b. locomotion / skill action (terrain edits apply immediately)
'        c. triggers: world bounds -> exit -> hazards
'      terminal (already counted) sheep only advance their cosmetic animation
'   4. blocker hands reverse approaching grounded sheep
'   5. hatch release
'   6. clock and end-of-level checks
'   7. tick += 1
'
' Integer codes (strings would cost a compare per use on a Roku):
'   sheep.state  0 falling   1 walking   2 climbing   3 topOut    4 floating
'                5 blocking  6 building  7 shrugging  8 bashing   9 mining
'               10 digging  11 detonating
'               12 exiting  13 splatting 14 drowning 15 burning  16 exploding
'               17 crushed  18 gone          (12..18 are cosmetic terminal states)
'   sheep.fate   0 active    1 saved     2 lost
'   skill        0 climber   1 floater   2 bomber    3 blocker
'                4 builder   5 basher    6 miner     7 digger
'   death cause  0 splat 1 drown 2 burn 3 spikes 4 crush 5 explode 6 fell 7 wandered
'   sim.phase    0 running   1 won       2 lost
'   input kind   0 assign    1 rate      2 nuke      3 finish
'   event kind   1 spawn 2 assign 3 reject 4 parachute 5 brick 6 excavate
'                7 barrier 8 countdown 9 explode 10 saved 11 lost 12 rate
'                13 nuke 14 end
' =============================================================================

function SimStateNames() as object
    return ["falling", "walking", "climbing", "topOut", "floating", "blocking", "building", "shrugging", "bashing", "mining", "digging", "detonating", "exiting", "splatting", "drowning", "burning", "exploding", "crushed", "gone"]
end function

function SimSkillLabels() as object
    return ["Climb", "Parachute", "Boom", "Block", "Build", "Bash", "Mine", "Dig"]
end function

' Classic 1..99 scale: 1 slowest, 99 quickest. Ticks between releases.
function SimReleaseInterval(rate as integer) as integer
    r = rate
    if r < 1 then r = 1
    if r > 99 then r = 99
    return (99 - r) \ 2 + 4
end function

function SimNew(level as object) as object
    sim = {}
    sim.level = level
    sim.terrain = TerrainFromRows(level.rows, level.w, level.h)
    sim.masks = TerrainBuildMasks()
    sim.sheep = []
    sim.tick = 0
    sim.phase = 0
    sim.endReason = ""
    sim.endTick = -1
    sim.total = level.total
    sim.required = level.req
    sim.saved = 0
    sim.lost = 0
    sim.waiting = level.total
    sim.active = 0
    stock = []
    for each n in level.skills
        if n < 0 then n = 0
        stock.Push(n)
    end for
    sim.stock = stock
    sim.minReleaseRate = level.minrate
    rate = level.rate
    if rate > 99 then rate = 99
    if rate < level.minrate then rate = level.minrate
    sim.releaseRate = rate
    sim.timeLeft = level.time
    sim.lastSpawnTick = -1000000
    sim.hatchCursor = 0
    spawned = []
    for each e in level.ent
        spawned.Push(0)
    end for
    sim.hatchSpawned = spawned
    sim.nuking = false
    sim.finishRequested = false
    sim.events = []
    sim.applied = []
    sim.pending = []
    ' ---- lookup tables ----
    ' exit trigger boxes [x0, x1, y0, y1]
    rects = []
    for each e in level.exits
        hw = e[2] \ 2
        rects.Push([e[0] - hw, e[0] + hw, e[1] - e[3] + 1, e[1]])
    end for
    sim.exitRects = rects
    ' hazards [x0, x1(exclusive), y0, y1(exclusive), cause, phase, period, offset]
    causeOf = { water: 1, lava: 2, fire: 2, steam: 2, lightning: 2, spikes: 3, crush: 4, pit: 6 }
    hz = []
    for each z in level.haz
        period = 0
        if z[5] > 0 then period = z[5] + z[6]
        hz.Push([z[1], z[1] + z[3], z[2], z[2] + z[4], causeOf[z[0]], z[5], period, z[7]])
    end for
    sim.hazards = hz
    ' death cause -> terminal state, terminal state -> cosmetic duration (index = state - 12)
    sim.deathState = [13, 14, 15, 17, 17, 16, 18, 18]
    sim.terminalTicks = [10, 14, 18, 16, 12, 12, 0]
    return sim
end function

' ---------------------------------------------------------------------- inputs

' Queue an input for the next tick to be simulated.
'   kind 0 assign (a = sheep id, b = skill)   1 rate (a = value)   2 nuke   3 finish
sub SimEnqueue(sim as object, kind as integer, a as integer, b as integer)
    sim.pending.Push([sim.tick, kind, a, b])
end sub

sub SimApplyInputs(sim as object)
    batch = sim.pending
    sim.pending = []
    for each inp in batch
        if sim.phase <> 0 then exit for
        kind = inp[1]
        if kind = 0
            reason = SimTryAssign(sim, inp[2], inp[3])
            if reason = ""
                sim.applied.Push([sim.tick, 0, inp[2], inp[3]])
            else
                sim.events.Push({ k: 3, id: inp[2], skill: inp[3], reason: reason })
            end if
        else if kind = 1
            v = inp[2]
            if v > 99 then v = 99
            if v < sim.minReleaseRate then v = sim.minReleaseRate
            if v <> sim.releaseRate
                sim.releaseRate = v
                sim.applied.Push([sim.tick, 1, v, 0])
                sim.events.Push({ k: 12, v: v })
            end if
        else if kind = 2
            if not sim.nuking
                sim.nuking = true
                sim.lost = sim.lost + sim.waiting
                sim.waiting = 0
                sim.applied.Push([sim.tick, 2, 0, 0])
                sim.events.Push({ k: 13 })
            end if
        else if kind = 3
            if sim.saved >= sim.required and not sim.finishRequested
                sim.finishRequested = true
                sim.applied.Push([sim.tick, 3, 0, 0])
            end if
        end if
    end for
end sub

' Pure eligibility check used by input targeting and the HUD (no side effects).
' Returns "" when the assignment is legal, otherwise a player-facing reason.
function SimCheckAssign(sim as object, sheepId as integer, skill as integer) as string
    if sim.phase <> 0 then return "The stage is over"
    if sheepId < 0 or sheepId >= sim.sheep.Count() then return "No sheep there"
    s = sim.sheep[sheepId]
    if s.fate <> 0 then return "No sheep there"
    labels = SimSkillLabels()
    if sim.stock[skill] <= 0 then return "No " + labels[skill] + " left"
    st = s.state
    ' transition matrix: which locomotion states may take which skill
    ok = false
    if skill <= 2
        ok = st <= 10
    else if skill = 3 or skill = 4
        ok = st = 1 or (st >= 6 and st <= 10)
    else if skill = 5
        ok = st = 1 or st = 6 or st = 7 or st = 9 or st = 10
    else if skill = 6
        ok = st = 1 or st = 6 or st = 7 or st = 8 or st = 10
    else
        ok = st = 1 or (st >= 6 and st <= 9)
    end if
    if not ok
        what = SimStateNames()[st]
        if st = 4 then what = "parachuting"
        if st = 3 then what = "climbing"
        if st = 11 then what = "about to go boom"
        return "Can't " + labels[skill] + " while " + what
    end if
    ' per-skill extra conditions
    if skill = 0
        if s.canClimb then return "Already a Climber"
    else if skill = 1
        if s.canFloat then return "Already has a parachute"
    else if skill = 2
        if s.bomberTicks >= 0 then return "Already counting down"
    else if skill = 3
        if SimBlockerNear(sim, s) then return "Too close to another Blocker"
    else if skill = 4
        if st = 6 and s.bricks > 3 then return "Already building"
    end if
    return ""
end function

' Validate and apply a skill assignment. Returns "" on success or the reason.
function SimTryAssign(sim as object, sheepId as integer, skill as integer) as string
    reason = SimCheckAssign(sim, sheepId, skill)
    if reason <> "" then return reason
    s = sim.sheep[sheepId]
    ' an action skill interrupts whichever action owned the sheep (only Builder has state to drop)
    if skill >= 3 and skill <> 4 and (s.state = 6 or s.state = 7) then s.bricks = 0
    sim.stock[skill] = sim.stock[skill] - 1
    if skill = 0
        s.canClimb = true
    else if skill = 1
        s.canFloat = true
    else if skill = 2
        s.bomberTicks = 85
        sim.events.Push({ k: 8, id: s.id, v: 5 })
    else if skill = 3
        SimSetState(sim, s, 5)
    else if skill = 4
        SimSetState(sim, s, 6)
        s.bricks = 12
    else if skill = 5
        SimSetState(sim, s, 8)
    else if skill = 6
        SimSetState(sim, s, 9)
    else
        SimSetState(sim, s, 10)
    end if
    sim.events.Push({ k: 2, id: s.id, skill: skill, x: s.x, y: s.y })
    return ""
end function

' A new blocker may not be planted inside an existing blocker's field.
function SimBlockerNear(sim as object, s as object) as boolean
    ' indexed on purpose: callers may themselves be inside a "for each" over sim.sheep,
    ' and BrightScript keeps only one for-each position per array
    sheep = sim.sheep
    for i = 0 to sheep.Count() - 1
        b = sheep[i]
        if b.fate = 0 and b.state = 5 and b.id <> s.id
            ddx = s.x - b.x
            if ddx < 0 then ddx = -ddx
            ddy = s.y - b.y
            if ddx <= 6 and ddy >= -6 and ddy <= 4 then return true
        end if
    end for
    return false
end function

' ------------------------------------------------------------------ primitives

sub SimSetState(sim as object, s as object, st as integer)
    if s.state = st
        s.stateTicks = 0
        return
    end if
    s.state = st
    s.stateTicks = 0
    if st = 4 then sim.events.Push({ k: 4, id: s.id, x: s.x, y: s.y })
end sub

sub SimKill(sim as object, s as object, cause as integer)
    if s.fate <> 0 then return
    s.fate = 2
    s.cause = cause
    s.bomberTicks = -1
    sim.active = sim.active - 1
    sim.lost = sim.lost + 1
    SimSetState(sim, s, sim.deathState[cause])
    sim.events.Push({ k: 11, id: s.id, x: s.x, y: s.y, cause: cause })
end sub

sub SimRescue(sim as object, s as object, exitIndex as integer)
    if s.fate <> 0 then return
    s.fate = 1
    s.bomberTicks = -1
    sim.active = sim.active - 1
    sim.saved = sim.saved + 1
    SimSetState(sim, s, 12)
    sim.events.Push({ k: 10, id: s.id, x: s.x, y: s.y, exitIndex: exitIndex })
end sub

' ------------------------------------------------------------------------ tick

function SimStep(sim as object) as object
    sim.events = []
    if sim.phase <> 0 then return sim.events

    ' 1. inputs
    if sim.pending.Count() > 0 then SimApplyInputs(sim)

    sheep = sim.sheep

    ' 2. nuke
    if sim.nuking
        for each s in sheep
            if s.fate = 0 and s.bomberTicks < 0 and s.state <> 11
                s.bomberTicks = 85
                sim.events.Push({ k: 8, id: s.id, v: 5 })
                exit for
            end if
        end for
    end if

    ' 3. sheep in id order
    t = sim.terrain
    cells = t.cells
    stride = t.stride
    base = t.base
    w = t.w
    h = t.h
    exitRects = sim.exitRects
    hazards = sim.hazards
    nExits = exitRects.Count()
    nHaz = hazards.Count()
    tick = sim.tick
    blockers = 0
    nSheep = sheep.Count()
    for si = 0 to nSheep - 1
        s = sheep[si]
        if s.fate = 0
            s.stateTicks = s.stateTicks + 1
            acted = false
            if s.bomberTicks > 0 then acted = SkillTickBomber(sim, s)
            if not acted
                st = s.state
                if st = 1
                    ' ---- walking (inlined: this is the common case) ----
                    x = s.x
                    y = s.y
                    ' rise out of terrain laid at the feet (another sheep's plank)
                    k = 0
                    c = cells[y * stride + x + base]
                    while k < 6 and c > 0 and c < 8
                        y = y - 1
                        k = k + 1
                        c = cells[y * stride + x + base]
                    end while
                    nx = x + s.dir
                    c = cells[y * stride + nx + base]
                    if c > 0 and c < 8
                        ' a bump: step up to 6 px, otherwise it is a wall
                        hh = 1
                        c = cells[(y - 1) * stride + nx + base]
                        while hh <= 6 and c > 0 and c < 8
                            hh = hh + 1
                            c = cells[(y - hh) * stride + nx + base]
                        end while
                        s.y = y
                        if hh <= 6
                            s.x = nx
                            s.y = y - hh
                        else if s.canClimb
                            SimSetState(sim, s, 2)
                        else
                            s.dir = -s.dir
                        end if
                    else
                        s.x = nx
                        ' step down up to 3 px without becoming a faller
                        gap = 0
                        c = cells[(y + 1) * stride + nx + base]
                        while gap <= 3 and (c = 0 or c = 8)
                            gap = gap + 1
                            c = cells[(y + 1 + gap) * stride + nx + base]
                        end while
                        if gap <= 3
                            s.y = y + gap
                        else
                            s.y = y
                            s.fallDistance = 0
                            SimSetState(sim, s, 0)
                        end if
                    end if
                else if st = 0
                    SkillAdvanceFalling(sim, s)
                else if st = 5
                    ' blocking: the only way out is losing the support under the feet
                    c = cells[(s.y + 1) * stride + s.x + base]
                    if c = 0 or c = 8
                        s.fallDistance = 0
                        SimSetState(sim, s, 0)
                    end if
                else if st = 2 or st = 3
                    SkillAdvanceClimber(sim, s)
                else if st = 4
                    SkillAdvanceFloater(sim, s)
                else if st = 6 or st = 7
                    SkillAdvanceBuilder(sim, s)
                else if st = 8
                    SkillAdvanceBasher(sim, s)
                else if st = 9
                    SkillAdvanceMiner(sim, s)
                else if st = 10
                    SkillAdvanceDigger(sim, s)
                else if st = 11
                    SkillAdvanceDetonating(sim, s)
                end if
            end if

            ' ---- triggers: world bounds -> exit -> hazards ----
            if s.fate = 0
                x = s.x
                y = s.y
                if x < 0 or x >= w
                    SimKill(sim, s, 7)
                else if y >= h
                    SimKill(sim, s, 6)
                else
                    st = s.state
                    if st = 5 then blockers = blockers + 1
                    if st <> 5 and st <> 11
                        for i = 0 to nExits - 1
                            r = exitRects[i]
                            if x >= r[0] and x <= r[1] and y >= r[2] and y <= r[3]
                                SimRescue(sim, s, i)
                                exit for
                            end if
                        end for
                    end if
                    if s.fate = 0 and nHaz > 0
                        for i = 0 to nHaz - 1
                            z = hazards[i]
                            if x >= z[0] and x < z[1]
                                midY = y - 5
                                if (y >= z[2] and y < z[3]) or (midY >= z[2] and midY < z[3])
                                    lethal = true
                                    if z[6] > 0
                                        ph = (((tick + z[7]) mod z[6]) + z[6]) mod z[6]
                                        lethal = ph < z[5]
                                    end if
                                    if lethal
                                        SimKill(sim, s, z[4])
                                        exit for
                                    end if
                                end if
                            end if
                        end for
                    end if
                end if
            end if
        else if s.state <> 18
            ' already counted: only the cosmetic terminal animation advances
            s.stateTicks = s.stateTicks + 1
            if s.stateTicks >= sim.terminalTicks[s.state - 12] then s.state = 18
        end if
    end for

    ' 4. blocker hands
    if blockers > 0 then SimApplyBlockers(sim)

    ' 5. release
    if sim.waiting > 0 and not sim.nuking and tick >= 20 then SimSpawn(sim)

    ' 6. clock and end checks
    if sim.timeLeft > 0 then sim.timeLeft = sim.timeLeft - 1
    SimCheckEnd(sim)

    ' 7.
    sim.tick = tick + 1
    return sim.events
end function

' Blocker influence is a field test between sheep, never terrain. For a blocker
' with feet at (bx, by):
'   left hand  : bx-6 .. bx-2   reverses sheep facing right
'   centre     : |dx| < 2       no effect
'   right hand : bx+2 .. bx+6   reverses sheep facing left
'   band       : feet rows by-6 .. by+4
' Only grounded locomotion (walking, building, bashing, mining) is affected.
sub SimApplyBlockers(sim as object)
    blockers = []
    for each s in sim.sheep
        if s.fate = 0 and s.state = 5 then blockers.Push(s)
    end for
    if blockers.Count() = 0 then return
    for each s in sim.sheep
        if s.fate = 0
            st = s.state
            if st = 1 or st = 6 or st = 8 or st = 9
                for each b in blockers
                    ddy = s.y - b.y
                    if ddy >= -6 and ddy <= 4
                        ddx = s.x - b.x
                        hit = false
                        if s.dir = 1
                            hit = ddx <= -2 and ddx >= -6
                        else
                            hit = ddx >= 2 and ddx <= 6
                        end if
                        if hit
                            s.dir = -s.dir
                            if st = 8 then SimSetState(sim, s, 1)
                            exit for
                        end if
                    end if
                end for
            end if
        end if
    end for
end sub

sub SimSpawn(sim as object)
    tick = sim.tick
    if tick - sim.lastSpawnTick < SimReleaseInterval(sim.releaseRate) then return
    hatches = sim.level.ent
    n = hatches.Count()
    for k = 0 to n - 1
        i = (sim.hatchCursor + k) mod n
        e = hatches[i]
        if tick >= 20 + e[4] and (e[3] < 0 or sim.hatchSpawned[i] < e[3])
            s = {
                id: sim.sheep.Count()
                x: e[0]
                y: e[1]
                dir: e[2]
                state: 0
                canClimb: false
                canFloat: false
                bomberTicks: -1
                fallDistance: 0
                stateTicks: 0
                bricks: 0
                hatch: i
                spawnTick: tick
                fate: 0
                cause: -1
                px: e[0]
                py: e[1]
            }
            sim.sheep.Push(s)
            sim.hatchSpawned[i] = sim.hatchSpawned[i] + 1
            sim.waiting = sim.waiting - 1
            sim.active = sim.active + 1
            sim.lastSpawnTick = tick
            sim.hatchCursor = (i + 1) mod n
            sim.events.Push({ k: 1, id: s.id, x: s.x, y: s.y, hatch: i })
            return
        end if
    end for
end sub

sub SimCheckEnd(sim as object)
    won = sim.saved >= sim.required
    if sim.finishRequested and won
        SimEnd(sim, 1, "finished-early")
        return
    end if
    ' while a nuke runs, let the detonation sequence play out instead of cutting it short
    if not sim.nuking and sim.saved + sim.active + sim.waiting < sim.required
        SimEnd(sim, 2, "not-enough-left")
        return
    end if
    phase = 2
    if won then phase = 1
    if sim.waiting = 0
        if sim.active = 0
            SimEnd(sim, phase, "all-accounted")
            return
        end if
        if SimOnlyIdleBlockersLeft(sim)
            SimEnd(sim, phase, "only-blockers-left")
            return
        end if
    end if
    if sim.timeLeft <= 0 then SimEnd(sim, phase, "time-expired")
end sub

' Nothing can change any more: every remaining sheep is a blocker with no countdown.
function SimOnlyIdleBlockersLeft(sim as object) as boolean
    nuking = sim.nuking
    for each s in sim.sheep
        if s.fate = 0
            ' a running nuke still has un-primed sheep to reach
            if nuking and s.bomberTicks < 0 then return false
            if s.state <> 5 or s.bomberTicks >= 0 then return false
        end if
    end for
    return true
end function

sub SimEnd(sim as object, phase as integer, reason as string)
    sim.phase = phase
    sim.endReason = reason
    sim.endTick = sim.tick
    sim.events.Push({ k: 14, phase: phase, reason: reason })
end sub

' After the stage ends, keep cosmetic terminal animations moving (no gameplay effect).
sub SimAdvanceCosmetic(sim as object)
    for each s in sim.sheep
        if s.fate <> 0 and s.state <> 18
            s.stateTicks = s.stateTicks + 1
            if s.stateTicks >= sim.terminalTicks[s.state - 12] then s.state = 18
        end if
    end for
end sub

' Conservation invariant: total = saved + lost + waiting + active.
function SimCheckInvariant(sim as object) as boolean
    alive = 0
    for each s in sim.sheep
        if s.fate = 0 then alive = alive + 1
    end for
    return alive = sim.active and sim.total = sim.saved + sim.lost + sim.waiting + sim.active
end function
