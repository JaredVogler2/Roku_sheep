' =============================================================================
' SHEEPFALL for Roku - locomotion and the eight Classic skills.
'
' BrightScript port of src/engine/Locomotion.ts and src/skills/*.ts. Each
' function advances one sheep by one tick and mirrors the web engine statement
' for statement; the numbers are the classic-dos-inspired-v1 calibration:
'
'   walk 1 px/tick, step up <= 6, step down <= 3, fall 3 px/tick,
'   fatal fall > 63 px, parachute opens after 12 px and sinks 2 px/tick,
'   climb 1 px/tick, top-out 6 ticks,
'   builder: 12 planks, 16 ticks each, laid on phase 8, 6 px wide, advance 2,
'   basher cycle 8 (stroke on phase 1), miner cycle 10, digger cycle 4,
'   bomber: 85 ticks (5 s), 10 tick "oh no", crater lifted 5 px.
'
' Terrain cells are read straight from the padded grid (see Terrain.brs):
'   solid  <=>  c > 0 and c < 8   where c = cells[y * stride + x + base]
' =============================================================================

sub SkillStartFalling(sim as object, s as object)
    s.fallDistance = 0
    SimSetState(sim, s, 0)
end sub

sub SkillLand(sim as object, s as object)
    if s.fallDistance > 63
        SimKill(sim, s, 0)
        return
    end if
    s.fallDistance = 0
    SimSetState(sim, s, 1)
end sub

sub SkillAdvanceFalling(sim as object, s as object)
    t = sim.terrain
    cells = t.cells
    stride = t.stride
    base = t.base
    x = s.x
    y = s.y
    c = cells[y * stride + x + base]
    if c > 0 and c < 8
        ' terrain appeared at the feet: rise out of it, then land
        k = 0
        while k < 6 and c > 0 and c < 8
            y = y - 1
            k = k + 1
            c = cells[y * stride + x + base]
        end while
        s.y = y
        SkillLand(sim, s)
        return
    end if
    fd = s.fallDistance
    for i = 1 to 3
        c = cells[(y + 1) * stride + x + base]
        if c > 0 and c < 8
            s.y = y
            s.fallDistance = fd
            SkillLand(sim, s)
            return
        end if
        y = y + 1
        fd = fd + 1
        if y >= t.h
            ' left the world; the trigger pass removes it
            s.y = y
            s.fallDistance = fd
            return
        end if
        if s.canFloat and fd >= 12
            s.y = y
            s.fallDistance = fd
            SimSetState(sim, s, 4)
            return
        end if
    end for
    s.y = y
    s.fallDistance = fd
    c = cells[(y + 1) * stride + x + base]
    if c > 0 and c < 8 then SkillLand(sim, s)
end sub

' Floater ("Parachute"): descent capped at 2 px/tick, strictly vertical, always a safe landing.
sub SkillAdvanceFloater(sim as object, s as object)
    t = sim.terrain
    cells = t.cells
    stride = t.stride
    base = t.base
    x = s.x
    y = s.y
    for i = 1 to 2
        c = cells[(y + 1) * stride + x + base]
        if c > 0 and c < 8
            s.y = y
            s.fallDistance = 0
            SimSetState(sim, s, 1)
            return
        end if
        y = y + 1
        if y >= t.h
            s.y = y
            return
        end if
    end for
    s.y = y
    c = cells[(y + 1) * stride + x + base]
    if c > 0 and c < 8
        s.fallDistance = 0
        SimSetState(sim, s, 1)
    end if
end sub

' Climber: scales any wall taller than a step flush against the mask, tops out
' over the lip, and lets go (turned around) if its head meets an overhang.
sub SkillAdvanceClimber(sim as object, s as object)
    t = sim.terrain
    cells = t.cells
    stride = t.stride
    base = t.base
    if s.state = 2
        c = cells[(s.y - 10) * stride + s.x + base]
        if c > 0 and c < 8
            s.dir = -s.dir
            SkillStartFalling(sim, s)
            return
        end if
        s.y = s.y - 1
        c = cells[s.y * stride + s.x + s.dir + base]
        if c = 0 or c = 8 then SimSetState(sim, s, 3)
        return
    end if
    ' topOut: pull over the lip, then walk on top
    if s.stateTicks >= 6
        c = cells[s.y * stride + s.x + s.dir + base]
        if c = 0 or c = 8 then s.x = s.x + s.dir
        SimSetState(sim, s, 1)
    end if
end sub

' Builder: exactly 12 load-bearing planks per assignment.
sub SkillAdvanceBuilder(sim as object, s as object)
    t = sim.terrain
    cells = t.cells
    stride = t.stride
    base = t.base
    c = cells[(s.y + 1) * stride + s.x + base]
    if c = 0 or c = 8
        SkillStartFalling(sim, s)
        return
    end if
    if s.state = 7
        if s.stateTicks >= 8 then SimSetState(sim, s, 1)
        return
    end if
    ph = s.stateTicks mod 16
    if ph = 8 and s.bricks > 0
        x0 = s.x
        x1 = s.x + 5 * s.dir
        TerrainAddRun(t, x0, x1, s.y, 4)
        s.bricks = s.bricks - 1
        lo = x0
        if x1 < x0 then lo = x1
        sim.events.Push({ k: 5, id: s.id, x: s.x, y: s.y, left: s.bricks, rx: lo, ry: s.y })
    else if ph = 0
        ax = s.x + s.dir
        bx = s.x + 2 * s.dir
        ny = s.y - 1
        blocked = false
        c = cells[ny * stride + ax + base]
        if c > 0 and c < 8 then blocked = true
        if not blocked
            c = cells[ny * stride + bx + base]
            if c > 0 and c < 8 then blocked = true
        end if
        if not blocked
            c = cells[(ny - 9) * stride + bx + base]
            if c > 0 and c < 8 then blocked = true
        end if
        if not blocked
            c = cells[(s.y - 10) * stride + s.x + base]
            if c > 0 and c < 8 then blocked = true
        end if
        if blocked
            s.dir = -s.dir
            SimSetState(sim, s, 1)
            return
        end if
        s.x = bx
        s.y = ny
        if s.bricks <= 0 then SimSetState(sim, s, 7)
    end if
end sub

' Basher: horizontal tunnel in the facing direction.
sub SkillAdvanceBasher(sim as object, s as object)
    t = sim.terrain
    cells = t.cells
    stride = t.stride
    base = t.base
    x = s.x
    y = s.y
    d = s.dir
    gap = 0
    c = cells[(y + 1) * stride + x + base]
    while gap <= 3 and (c = 0 or c = 8)
        gap = gap + 1
        c = cells[(y + 1 + gap) * stride + x + base]
    end while
    if gap > 3
        SkillStartFalling(sim, s)
        return
    end if
    y = y + gap
    s.y = y
    ph = s.stateTicks mod 8
    if ph = 1
        ' steel or wrong-way one-way earth in the core body band stops the bash
        for ddx = 1 to 4
            for ddy = -7 to -1
                mat = cells[(y + ddy) * stride + x + ddx * d + base]
                if mat = 5 or (mat = 6 and d = 1) or (mat = 7 and d = -1)
                    sim.events.Push({ k: 7, id: s.id, x: x + ddx * d, y: y + ddy })
                    s.dir = -d
                    SimSetState(sim, s, 1)
                    return
                end if
            end for
        end for
        ' nothing diggable within the look-ahead ends the bash
        found = false
        ddx = 1
        while ddx <= 8 and not found
            for ddy = -9 to -1
                mat = cells[(y + ddy) * stride + x + ddx * d + base]
                if (mat >= 1 and mat <= 4) or (mat = 6 and d = -1) or (mat = 7 and d = 1)
                    found = true
                    exit for
                end if
            end for
            ddx = ddx + 1
        end while
        if not found
            SimSetState(sim, s, 1)
            return
        end if
        n = TerrainRemoveWithMask(t, sim.masks.bash, x, y, d, 0)
        if n > 0 then sim.events.Push({ k: 6, id: s.id, kind: 0, x: x, y: y, dir: d, cells: n, mat: t.lastMat })
    else if ph = 3 or ph = 5 or ph = 7
        c = cells[y * stride + x + d + base]
        if c = 0 or c = 8 then s.x = x + d
    end if
end sub

' Miner: diagonal tunnel descending 1 px per 2 px forward.
sub SkillAdvanceMiner(sim as object, s as object)
    t = sim.terrain
    cells = t.cells
    stride = t.stride
    base = t.base
    x = s.x
    y = s.y
    d = s.dir
    c = cells[(y + 1) * stride + x + base]
    if c = 0 or c = 8
        SkillStartFalling(sim, s)
        return
    end if
    ph = s.stateTicks mod 10
    if ph = 1
        mask = sim.masks.mine
        mdx = mask.dx
        mdy = mask.dy
        for i = 0 to mask.n - 1
            cc = mdx[i]
            ddy = mdy[i]
            ' grazing the roof never stops a miner
            if ddy >= (cc \ 2) - 7
                mat = cells[(y + ddy) * stride + x + cc * d + base]
                if mat = 5 or (mat = 6 and d = 1) or (mat = 7 and d = -1)
                    sim.events.Push({ k: 7, id: s.id, x: x + cc * d, y: y + ddy })
                    s.dir = -d
                    SimSetState(sim, s, 1)
                    return
                end if
            end if
        end for
        n = TerrainRemoveWithMask(t, mask, x, y, d, 1)
        if n > 0 then sim.events.Push({ k: 6, id: s.id, kind: 1, x: x, y: y, dir: d, cells: n, mat: t.lastMat })
    else if ph = 4 or ph = 8
        nx = x + d
        ny = y
        if ph = 8 then ny = y + 1
        c = cells[ny * stride + nx + base]
        if c > 0 and c < 8
            SimSetState(sim, s, 1)
            return
        end if
        s.x = nx
        s.y = ny
        c = cells[(ny + 1) * stride + nx + base]
        if c = 0 or c = 8 then SkillStartFalling(sim, s)
    end if
end sub

' Digger: vertical shaft straight down, 9 px wide.
sub SkillAdvanceDigger(sim as object, s as object)
    t = sim.terrain
    cells = t.cells
    stride = t.stride
    base = t.base
    x = s.x
    y = s.y
    mat = cells[(y + 1) * stride + x + base]
    if mat = 0 or mat = 8
        SkillStartFalling(sim, s)
        return
    end if
    if s.stateTicks mod 4 <> 1 then return
    ' steel directly under the feet stops it; diggers cut one-way earth either way
    if mat = 5
        sim.events.Push({ k: 7, id: s.id, x: x, y: y + 1 })
        SimSetState(sim, s, 1)
        return
    end if
    n = TerrainRemoveWithMask(t, sim.masks.dig, x, y + 1, s.dir, 2)
    if n > 0 then sim.events.Push({ k: 6, id: s.id, kind: 2, x: x, y: y, dir: s.dir, cells: n, mat: t.lastMat })
    y = y + 1
    s.y = y
    c = cells[(y + 1) * stride + x + base]
    if c = 0 or c = 8 then SkillStartFalling(sim, s)
end sub

' Bomber countdown, called before the state update each tick.
' Returns true if the sheep acted (it popped, or it stopped for its "oh no").
function SkillTickBomber(sim as object, s as object) as boolean
    bt = s.bomberTicks
    if bt <= 0 then return false
    before = (bt + 16) \ 17
    bt = bt - 1
    if bt > 0
        s.bomberTicks = bt
        after = (bt + 16) \ 17
        if after <> before then sim.events.Push({ k: 8, id: s.id, v: after })
        return false
    end if
    s.bomberTicks = -1
    st = s.state
    if st = 0 or st = 4 or st = 2 or st = 3
        ' a sheep in the air when the count ends pops immediately
        SkillExplode(sim, s)
    else
        SimSetState(sim, s, 11)
    end if
    return true
end function

' Detonating: stand (or drop) in place, then explode.
sub SkillAdvanceDetonating(sim as object, s as object)
    t = sim.terrain
    cells = t.cells
    stride = t.stride
    base = t.base
    x = s.x
    y = s.y
    i = 0
    c = cells[(y + 1) * stride + x + base]
    while i < 3 and (c = 0 or c = 8)
        y = y + 1
        if y >= t.h
            s.y = y
            return
        end if
        i = i + 1
        c = cells[(y + 1) * stride + x + base]
    end while
    s.y = y
    if s.stateTicks >= 10 then SkillExplode(sim, s)
end sub

' A harmless wool "pop" that removes a crater of diggable terrain. Steel survives.
sub SkillExplode(sim as object, s as object)
    n = TerrainRemoveWithMask(sim.terrain, sim.masks.blast, s.x, s.y - 5, s.dir, 3)
    sim.events.Push({ k: 9, id: s.id, x: s.x, y: s.y, cells: n })
    SimKill(sim, s, 5)
end sub
