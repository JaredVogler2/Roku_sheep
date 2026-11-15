' =============================================================================
' Terrain paint check, run by tools/run-paint-check.mjs on the brs-node
' simulator (it never ships in the channel package).
'
' source/TerrainPaint.brs draws a stage two ways: the first paint works from the
' stage's run-length row bands (fast), and every later edit repaints a small
' rectangle cell by cell from the live collision mask. If the two paths ever
' disagreed, each dig, bash or plank would leave a visible seam around it.
'
' This test paints a stage with the band path, reads every pixel back, then
' repaints the WHOLE stage with the cell path and reads it back again. The two
' pictures must be identical. It also carves a few holes with the real engine
' masks and checks that a full cell-path repaint of the edited stage equals the
' incremental repaint the game performs.
'
' Launch parameter:  levels=meadow-05+cave-09+...
' =============================================================================

sub Main(args as dynamic)
    ids = []
    if args <> invalid and args.levels <> invalid then ids = args.levels.Split("+")
    assets = AssetsLoad()
    if assets = invalid
        print "ERROR|assets could not be loaded"
        return
    end if
    for each id in ids
        PaintCheck(assets, id)
    end for
    print "PAINT-DONE"
end sub

' All pixels of every chunk as one string per chunk.
function PaintSnapshot(tp as object) as object
    out = []
    for each bmp in tp.chunks
        ba = bmp.GetByteArray(0, 0, bmp.GetWidth(), bmp.GetHeight())
        out.Push(ba.ToBase64String())
    end for
    return out
end function

function PaintDiff(a as object, b as object) as integer
    bad = 0
    for i = 0 to a.Count() - 1
        if a[i] <> b[i] then bad = bad + 1
    end for
    return bad
end function

sub PaintCheck(assets as object, id as string)
    timer = CreateObject("roTimespan")
    level = LevelLoad(id)
    if level = invalid
        print "ERROR|" + id + "|cannot load level"
        return
    end if
    biome = AssetsUseBiome(assets, level.theme)
    sim = SimNew(level)
    t = sim.terrain

    ' 1. band path against cell path on the untouched stage
    tp = TerrainPaintNew(level, t, biome)
    bandMs = timer.TotalMilliseconds()
    first = PaintSnapshot(tp)
    timer.Mark()
    TpRepaint(tp, 0, 0, level.w, level.h)
    cellMs = timer.TotalMilliseconds()
    second = PaintSnapshot(tp)
    pristineDiff = PaintDiff(first, second)

    ' 2. carve with the real masks (a basher bite, a miner bite, a dig row, a crater, a plank)
    '    at a few places, repainting incrementally exactly as the game does
    masks = sim.masks
    spots = 0
    seed = 4711
    for n = 1 to 40
        seed = (seed * 1103 + 12849) mod 65536
        x = 20 + seed mod (level.w - 40)
        seed = (seed * 1103 + 12849) mod 65536
        y = 20 + seed mod (level.h - 40)
        kind = n mod 5
        if kind = 0
            TerrainRemoveWithMask(t, masks.bash, x, y, 1, 0)
        else if kind = 1
            TerrainRemoveWithMask(t, masks.mine, x, y, -1, 1)
        else if kind = 2
            TerrainRemoveWithMask(t, masks.dig, x, y, 1, 2)
        else if kind = 3
            TerrainRemoveWithMask(t, masks.blast, x, y, 1, 3)
        else
            TerrainAddRun(t, x, x + 5, y, 4)
        end if
        for each r in t.dirty
            TpRepaint(tp, r[0], r[1], r[2], r[3])
            spots = spots + 1
        end for
        t.dirty = []
    end for
    incremental = PaintSnapshot(tp)
    TpRepaint(tp, 0, 0, level.w, level.h)
    full = PaintSnapshot(tp)
    editDiff = PaintDiff(incremental, full)
    ' guards against a vacuous pass: the edits must have changed the picture, and pixels must really be read
    changed = PaintDiff(first, incremental)

    print "PAINT|" + id + "|" + level.w.ToStr() + "|" + tp.chunks.Count().ToStr() + "|" + pristineDiff.ToStr() + "|" + spots.ToStr() + "|" + editDiff.ToStr() + "|" + bandMs.ToStr() + "|" + cellMs.ToStr() + "|" + changed.ToStr() + "|" + Len(first[0]).ToStr()
end sub
