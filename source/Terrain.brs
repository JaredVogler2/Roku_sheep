' =============================================================================
' SHEEPFALL for Roku - authoritative per-pixel material grid.
'
' BrightScript port of src/engine/TerrainMask.ts + MaterialRules.ts from the web
' game. Every collision query in the game reads this grid; the renderer only
' mirrors it.
'
' Roku-specific design:
'   * The grid lives in one roByteArray and is PADDED by TerrainPad() cells on
'     every side, so the hot collision reads never need a bounds check:
'         top padding    = steel   (above the world is an indestructible ceiling)
'         left/right/bottom padding = empty (the world edge is open air)
'     which is exactly the out-of-bounds convention of the web engine.
'     A cell is read as   cells[y * stride + x + base].
'   * Stages are stored as run-length row bands and decoded with native
'     String()/Join()/FromHexString() calls: no per-pixel BrightScript loop.
'
' Materials: 0 empty, 1 dirt, 2 rock, 3 turf, 4 bridge, 5 steel,
'            6 one-way-left, 7 one-way-right, 8 decor (visual only, not solid).
' A cell is solid when its value is 1..7.
' Removal kinds: 0 bash, 1 mine, 2 dig, 3 blast.
' =============================================================================

function TerrainPad() as integer
    return 32
end function

' Builds the padded grid from the compiled row bands of a level file.
' rows = [[bandHeight, material, runLength, material, runLength, ...], ...]
function TerrainFromRows(rows as object, w as integer, h as integer) as object
    pad = TerrainPad()
    stride = w + 2 * pad
    hexOf = ["00", "01", "02", "03", "04", "05", "06", "07", "08"]
    padHex = String(pad, "00")
    parts = []
    parts.Push(String(pad * stride, "05"))
    for each r in rows
        rowHex = padHex
        n = r.Count()
        k = 1
        while k < n
            rowHex = rowHex + String(r[k + 1], hexOf[r[k]])
            k = k + 2
        end while
        rowHex = rowHex + padHex
        parts.Push(String(r[0], rowHex))
    end for
    parts.Push(String(pad * stride, "00"))
    cells = CreateObject("roByteArray")
    cells.FromHexString(parts.Join(""))
    return {
        w: w
        h: h
        stride: stride
        base: pad * stride + pad
        cells: cells
        dirty: []
        version: 0
        lastMat: 0
        undo: invalid
    }
end function

' A copy of the pristine grid (used to tell excavated ground from open air).
function TerrainCopyCells(t as object) as object
    c = CreateObject("roByteArray")
    c.FromBase64String(t.cells.ToBase64String())
    return c
end function

' ---- queries (the engine inlines these in its hot paths) ---------------------

function TerrainMaterialAt(t as object, x as integer, y as integer) as integer
    return t.cells[y * t.stride + x + t.base]
end function

function TerrainIsSolid(t as object, x as integer, y as integer) as boolean
    c = t.cells[y * t.stride + x + t.base]
    return c > 0 and c < 8
end function

' Exact excavation permissions, evaluated at the pixel being removed:
'   steel is never removed; one-way earth may only be bashed/mined by a sheep
'   facing the arrow; diggers and blasts remove one-way earth either way.
function MaterialCanRemove(mat as integer, kind as integer, facing as integer) as boolean
    if mat >= 1 and mat <= 4 then return true
    if mat = 6 then return kind >= 2 or facing = -1
    if mat = 7 then return kind >= 2 or facing = 1
    return false
end function

' True for solid pixels a horizontal/diagonal excavator may NOT pass.
function MaterialIsBarrier(mat as integer, kind as integer, facing as integer) as boolean
    if mat < 1 or mat > 7 then return false
    return not MaterialCanRemove(mat, kind, facing)
end function

function TerrainCanRemove(t as object, x as integer, y as integer, kind as integer, facing as integer) as boolean
    return MaterialCanRemove(t.cells[y * t.stride + x + t.base], kind, facing)
end function

' ---- edits -------------------------------------------------------------------

' Removes the cells under a mask anchored at (ax, ay). Only cells whose
' material permits `kind` for `facing` change. Returns the number of cells
' removed; the changed rectangle is appended to t.dirty for the renderer.
function TerrainRemoveWithMask(t as object, mask as object, ax as integer, ay as integer, facing as integer, kind as integer) as integer
    dx = mask.dx
    dy = mask.dy
    n = mask.n
    w = t.w
    h = t.h
    cells = t.cells
    stride = t.stride
    base = t.base
    changed = 0
    minX = 1000000
    minY = 1000000
    maxX = -1000000
    maxY = -1000000
    lastMat = 0
    ' Assisted Mode keeps an undo record: [x, y, w, h, cell index, old value, ...]
    rec = invalid
    if t.undo <> invalid then rec = [0, 0, 0, 0]
    for i = 0 to n - 1
        x = ax + dx[i] * facing
        y = ay + dy[i]
        if x >= 0 and y >= 0 and x < w and y < h
            idx = y * stride + x + base
            mat = cells[idx]
            if mat > 0 and mat < 8
                ok = false
                if mat <= 4
                    ok = true
                else if mat = 6
                    ok = kind >= 2 or facing = -1
                else if mat = 7
                    ok = kind >= 2 or facing = 1
                end if
                if ok
                    cells[idx] = 0
                    changed = changed + 1
                    lastMat = mat
                    if rec <> invalid
                        rec.Push(idx)
                        rec.Push(mat)
                    end if
                    if x < minX then minX = x
                    if x > maxX then maxX = x
                    if y < minY then minY = y
                    if y > maxY then maxY = y
                end if
            end if
        end if
    end for
    if changed > 0
        t.version = t.version + 1
        t.lastMat = lastMat
        t.dirty.Push([minX, minY, maxX - minX + 1, maxY - minY + 1])
        if rec <> invalid
            rec[0] = minX
            rec[1] = minY
            rec[2] = maxX - minX + 1
            rec[3] = maxY - minY + 1
            t.undo.Push(rec)
        end if
    end if
    return changed
end function

' Lays solid material into the horizontal run [x0, x1] at row y, never
' overwriting solids. Returns the number of cells added.
function TerrainAddRun(t as object, x0 as integer, x1 as integer, y as integer, material as integer) as integer
    changed = 0
    if y < 0 or y >= t.h then return 0
    lo = x0
    hi = x1
    if x1 < x0
        lo = x1
        hi = x0
    end if
    if lo < 0 then lo = 0
    if hi > t.w - 1 then hi = t.w - 1
    cells = t.cells
    rowBase = y * t.stride + t.base
    minX = 1000000
    maxX = -1000000
    rec = invalid
    if t.undo <> invalid then rec = [0, y, 0, 1]
    for x = lo to hi
        c = cells[rowBase + x]
        if c = 0 or c = 8
            cells[rowBase + x] = material
            changed = changed + 1
            if rec <> invalid
                rec.Push(rowBase + x)
                rec.Push(c)
            end if
            if x < minX then minX = x
            if x > maxX then maxX = x
        end if
    end for
    if changed > 0
        t.version = t.version + 1
        t.dirty.Push([minX, y, maxX - minX + 1, 1])
        if rec <> invalid
            rec[0] = minX
            rec[2] = maxX - minX + 1
            t.undo.Push(rec)
        end if
    end if
    return changed
end function

' ---- authored excavation masks ---------------------------------------------
' Written for a sheep facing right and anchored at its foot pixel; mirrored for
' facing left by negating dx. Identical cell sets to src/engine/SkillMasks.ts.

function TerrainBuildMasks() as object
    masks = {}

    ' Basher stroke: a rounded bite 5 wide and 10 tall ahead of the sheep.
    dx = []
    dy = []
    for r = 0 to 9
        for c = 1 to 5
            cut = (r = 0 and c >= 4) or (r = 1 and c = 5)
            if not cut
                dx.Push(c)
                dy.Push(r - 9)
            end if
        end for
    end for
    masks.bash = { dx: dx, dy: dy, n: dx.Count() }

    ' Miner stroke: a diagonal slab descending 1 px per 2 px forward.
    dx = []
    dy = []
    for c = 1 to 5
        bottom = c \ 2
        for d = bottom - 9 to bottom
            if not (c = 5 and d = bottom - 9)
                dx.Push(c)
                dy.Push(d)
            end if
        end for
    end for
    masks.mine = { dx: dx, dy: dy, n: dx.Count() }

    ' Digger stroke: one row, 9 px wide, on the row under the feet.
    dx = []
    dy = []
    for c = -4 to 4
        dx.Push(c)
        dy.Push(0)
    end for
    masks.dig = { dx: dx, dy: dy, n: dx.Count() }

    ' Bomber crater: integer ellipse rx 8, ry 10.
    dx = []
    dy = []
    for d = -10 to 10
        for c = -8 to 8
            if c * c * 100 + d * d * 64 <= 6400
                dx.Push(c)
                dy.Push(d)
            end if
        end for
    end for
    masks.blast = { dx: dx, dy: dy, n: dx.Count() }

    return masks
end function
