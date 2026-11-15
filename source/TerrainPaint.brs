' =============================================================================
' SHEEPFALL for Roku - terrain presentation.
'
' The web game shades every terrain pixel in software and re-synthesises the
' area around each edit. BrightScript cannot afford per-pixel work on a whole
' stage, so this painter works from the same two facts the collision mask is
' built from:
'
'   1. INITIAL PAINT comes from the stage's run-length row bands. A band is a
'      stack of identical rows, so each solid run is ONE textured blit from the
'      material sheet, and edges only exist where a band meets its neighbours.
'      Top edges, grass/snow caps, outlines and grass blades are found with
'      interval arithmetic on the run lists - a few thousand draw calls for a
'      whole stage instead of 300 000+ pixel visits.
'
'   2. EDITS (bash, mine, dig, blast, planks) repaint only the edited rectangle
'      plus a small margin, cell by cell from the live mask, merging equal
'      neighbours into runs.
'
' Both paths implement the same per-cell style rules, so an edit blends into
' the first paint seamlessly (tests/paint_check.brs proves the two paths agree
' pixel for pixel):
'
'   solid cell, open air above         -> lit top edge (grass / snow / moss cap on turf)
'   solid cell, excavated space above  -> lit lip
'   turf up to 3 cells under a sky cap -> cap rows (body, body, dark root line)
'   solid cell beside or over space    -> dark outline
'   other solid cells                  -> the material sheet
'   empty cell that used to be ground  -> cavity sheet (darker under a ceiling)
'   empty cell that was always empty   -> transparent, or a grass blade / flower
'
' The stage is stored at 1 px per world pixel in 256 px wide chunks and drawn
' 2x with nearest-neighbour scaling. Chunks are written only with raw copies
' and opaque fills (see Gfx.brs), so their alpha is exactly 0 or 255.
'
' Style codes: 0 sky   1..7 material sheet   8 cavity sheet   9 cavity shade
'              10+m top edge   20+m lip   30+m outline   40+d cap row d
'              50+s grass blade shade s   60+c flower colour c
' =============================================================================

function TerrainPaintNew(level as object, terrain as object, biome as object) as object
    tp = {}
    tp.w = level.w
    tp.h = level.h
    tp.cells = terrain.cells
    tp.stride = terrain.stride
    tp.base = terrain.base
    tp.pristine = TerrainCopyCells(terrain)
    tp.sheets = biome.sheets
    tp.cw = biome.sheetW

    ' ---- colours
    c = biome.colors
    flat = CreateObject("roArray", 70, true)
    for i = 0 to 69
        flat[i] = invalid
    end for
    flat[9] = GfxHex(c.cavityshade)
    for m = 1 to 7
        flat[10 + m] = GfxHex(c.top[m])
        flat[20 + m] = GfxHex(c.lip[m])
        flat[30 + m] = GfxHex(c.edge[m])
    end for
    tp.capN = c.cap.Count()
    for d = 0 to tp.capN - 1
        flat[40 + d] = GfxHex(c.cap[d])
    end for
    tp.bladeN = c.blades.Count()
    for i = 0 to tp.bladeN - 1
        flat[50 + i] = GfxHex(c.blades[i])
    end for
    tp.flowerN = c.flowers.Count()
    for i = 0 to tp.flowerN - 1
        flat[60 + i] = GfxHex(c.flowers[i])
    end for
    tp.flat = flat
    tp.miniSolid = GfxHex(c.minimap)
    tp.miniSteel = GfxHex(c.minimapsteel)
    tp.miniSky = &h101820FF

    ' ---- per-column grass tables (period 256): blade height 0..3, shade, flower
    bladeH = CreateObject("roArray", 256, true)
    bladeS = CreateObject("roArray", 256, true)
    bladeF = CreateObject("roArray", 256, true)
    seed = 12345
    for i = 0 to 255
        seed = (seed * 1103 + 12849) mod 65536
        r = seed mod 100
        hgt = 0
        if tp.bladeN > 0
            if r >= 18 then hgt = 1
            if r >= 50 then hgt = 2
            if r >= 86 then hgt = 3
        end if
        bladeH[i] = hgt
        seed = (seed * 1103 + 12849) mod 65536
        shade = 0
        if tp.bladeN > 0 then shade = seed mod tp.bladeN
        bladeS[i] = shade
        seed = (seed * 1103 + 12849) mod 65536
        flower = -1
        if tp.flowerN > 0 and seed mod 100 < 4 then flower = seed mod tp.flowerN
        bladeF[i] = flower
    end for
    tp.bladeH = bladeH
    tp.bladeS = bladeS
    tp.bladeF = bladeF

    ' ---- chunk bitmaps (transparent) and the transparent eraser strip
    n = (tp.w + tp.cw - 1) \ tp.cw
    chunks = []
    regs = []
    for i = 0 to n - 1
        bmp = CreateObject("roBitmap", { width: tp.cw, height: tp.h, AlphaEnable: false })
        bmp.Clear(0)
        chunks.Push(bmp)
        reg = CreateObject("roRegion", bmp, 0, 0, tp.cw, tp.h)
        reg.SetScaleMode(0)
        regs.Push(reg)
    end for
    tp.chunks = chunks
    tp.regs = regs
    eraser = CreateObject("roBitmap", { width: tp.cw, height: 32, AlphaEnable: false })
    eraser.Clear(0)
    tp.eraser = eraser

    ' ---- minimap: 1/8 scale
    tp.miniScale = 8
    tp.miniW = (tp.w + 7) \ 8
    tp.miniH = tp.h \ 8
    mini = CreateObject("roBitmap", { width: tp.miniW, height: tp.miniH, AlphaEnable: false })
    mini.Clear(tp.miniSky)
    tp.mini = mini

    TpPaintBands(tp, level.rows)
    for each bmp in chunks
        bmp.Finish()
    end for
    mini.Finish()
    return tp
end function

' ---------------------------------------------------------------- primitives

' Copies a rectangle of a material sheet (0 = cavity, 1..7 = material) into the stage.
sub TpTex(tp as object, sheetIndex as integer, x as integer, y as integer, w as integer, h as integer)
    cw = tp.cw
    sheet = tp.sheets[sheetIndex]
    k = x \ cw
    lx = x - k * cw
    while w > 0
        lw = cw - lx
        if lw > w then lw = w
        reg = CreateObject("roRegion", sheet, lx, y, lw, h)
        tp.chunks[k].DrawObject(lx, y, reg)
        w = w - lw
        lx = 0
        k = k + 1
    end while
end sub

sub TpFlat(tp as object, x as integer, y as integer, w as integer, h as integer, color as integer)
    cw = tp.cw
    k = x \ cw
    lx = x - k * cw
    while w > 0
        lw = cw - lx
        if lw > w then lw = w
        tp.chunks[k].DrawRect(lx, y, lw, h, color)
        w = w - lw
        lx = 0
        k = k + 1
    end while
end sub

' Back to transparent: a raw copy from the eraser strip (never a blended fill).
sub TpErase(tp as object, x as integer, y as integer, w as integer, h as integer)
    cw = tp.cw
    k = x \ cw
    lx = x - k * cw
    while w > 0
        lw = cw - lx
        if lw > w then lw = w
        reg = CreateObject("roRegion", tp.eraser, 0, 0, lw, h)
        tp.chunks[k].DrawObject(lx, y, reg)
        w = w - lw
        lx = 0
        k = k + 1
    end while
end sub

' ------------------------------------------------------------ interval lists
' An interval list is a flat array [a0, b0, a1, b1, ...] of disjoint, sorted,
' half-open ranges [a, b).

' [a, b) minus every range of `cut`.
function IvSubtract(a as integer, b as integer, cut as object) as object
    out = []
    n = cut.Count()
    i = 0
    while i < n and a < b
        ca = cut[i]
        cb = cut[i + 1]
        if cb <= a
            ' entirely left of what remains
        else if ca >= b
            exit while
        else
            if ca > a
                out.Push(a)
                out.Push(ca)
            end if
            a = cb
        end if
        i = i + 2
    end while
    if a < b
        out.Push(a)
        out.Push(b)
    end if
    return out
end function

function IvIntersect(p as object, q as object) as object
    out = []
    i = 0
    j = 0
    np = p.Count()
    nq = q.Count()
    while i < np and j < nq
        lo = p[i]
        if q[j] > lo then lo = q[j]
        hi = p[i + 1]
        if q[j + 1] < hi then hi = q[j + 1]
        if lo < hi
            out.Push(lo)
            out.Push(hi)
        end if
        if p[i + 1] < q[j + 1]
            i = i + 2
        else
            j = j + 2
        end if
    end while
    return out
end function

' ------------------------------------------------------------- initial paint

sub TpPaintBands(tp as object, rows as object)
    w = tp.w
    h = tp.h
    flat = tp.flat
    ' ---- decode the bands into run tables
    bands = []
    rowBand = CreateObject("roArray", h, true)
    y = 0
    for each r in rows
        runs = []
        solid = []
        turf = []
        x = 0
        n = r.Count()
        k = 1
        while k < n
            mat = r[k]
            x1 = x + r[k + 1]
            if mat >= 1 and mat <= 7
                runs.Push([x, x1, mat])
                ns = solid.Count()
                if ns > 0 and solid[ns - 1] = x
                    solid[ns - 1] = x1
                else
                    solid.Push(x)
                    solid.Push(x1)
                end if
                if mat = 3
                    turf.Push(x)
                    turf.Push(x1)
                end if
            end if
            x = x1
            k = k + 2
        end while
        bi = bands.Count()
        for yy = y to y + r[0] - 1
            rowBand[yy] = bi
        end for
        bands.Push({ y: y, h: r[0], runs: runs, solid: solid, turf: turf })
        y = y + r[0]
    end for
    nb = bands.Count()

    ' ---- pass A: material sheets, side and bottom outlines, minimap
    mini = tp.mini
    for bi = 0 to nb - 1
        b = bands[bi]
        y0 = b.y
        bh = b.h
        y1 = y0 + bh - 1
        my0 = y0 \ 8
        mh = y1 \ 8 - my0 + 1
        for each seg in b.runs
            TpTex(tp, seg[2], seg[0], y0, seg[1] - seg[0], bh)
            mcol = tp.miniSolid
            if seg[2] = 5 then mcol = tp.miniSteel
            mx0 = seg[0] \ 8
            mini.DrawRect(mx0, my0, (seg[1] - 1) \ 8 - mx0 + 1, mh, mcol)
        end for
        ' outline the two ends of every stretch of solid ground
        runs = b.runs
        nr = runs.Count()
        for i = 0 to nr - 1
            seg = runs[i]
            leftOpen = true
            if i > 0 then leftOpen = runs[i - 1][1] <> seg[0]
            if leftOpen then TpFlat(tp, seg[0], y0, 1, bh, flat[30 + seg[2]])
            rightOpen = true
            if i < nr - 1 then rightOpen = runs[i + 1][0] <> seg[1]
            if rightOpen then TpFlat(tp, seg[1] - 1, y0, 1, bh, flat[30 + seg[2]])
        end for
        ' outline the underside where the next band is open
        below = []
        if bi < nb - 1 then below = bands[bi + 1].solid
        for each seg in runs
            pieces = IvSubtract(seg[0], seg[1], below)
            i = 0
            while i < pieces.Count()
                TpFlat(tp, pieces[i], y1, pieces[i + 1] - pieces[i], 1, flat[30 + seg[2]])
                i = i + 2
            end while
        end for
    end for

    ' ---- pass B: lit top edges, caps and grass, where a band is open above
    cells = tp.cells
    stride = tp.stride
    base = tp.base
    capN = tp.capN
    bladeH = tp.bladeH
    bladeS = tp.bladeS
    bladeF = tp.bladeF
    hasBlades = tp.bladeN > 0
    for bi = 1 to nb - 1
        b = bands[bi]
        y0 = b.y
        above = bands[bi - 1].solid
        for each seg in b.runs
            pieces = IvSubtract(seg[0], seg[1], above)
            np = pieces.Count()
            mat = seg[2]
            i = 0
            while i < np
                pa = pieces[i]
                pb = pieces[i + 1]
                if mat <> 3
                    TpFlat(tp, pa, y0, pb - pa, 1, flat[10 + mat])
                else
                    TpFlat(tp, pa, y0, pb - pa, 1, flat[40])
                    ' cap rows continue down through turf only
                    cur = [pa, pb]
                    d = 1
                    while d < capN and y0 + d < h and cur.Count() > 0
                        cur = IvIntersect(cur, bands[rowBand[y0 + d]].turf)
                        j = 0
                        while j < cur.Count()
                            TpFlat(tp, cur[j], y0 + d, cur[j + 1] - cur[j], 1, flat[40 + d])
                            j = j + 2
                        end while
                        d = d + 1
                    end while
                    ' grass blades (and the odd flower) in the open air above
                    if hasBlades
                        for x = pa to pb - 1
                            col = x and 255
                            hb = bladeH[col]
                            if hb > 0
                                kk = 0
                                cc = cells[(y0 - 1) * stride + x + base]
                                while kk < hb and (cc = 0 or cc = 8)
                                    kk = kk + 1
                                    cc = cells[(y0 - 1 - kk) * stride + x + base]
                                end while
                                if kk > 0
                                    TpFlat(tp, x, y0 - kk, 1, kk, flat[50 + bladeS[col]])
                                    if kk = hb and bladeF[col] >= 0 then TpFlat(tp, x, y0 - kk, 1, 1, flat[60 + bladeF[col]])
                                end if
                            end if
                        end for
                    end if
                end if
                i = i + 2
            end while
        end for
    end for
end sub

' ------------------------------------------------------------------- edits

' Style of one cell from the live mask and the pristine mask (see the table at the top).
function TpStyle(tp as object, x as integer, y as integer) as integer
    cells = tp.cells
    pristine = tp.pristine
    stride = tp.stride
    i = y * stride + x + tp.base
    c = cells[i]
    if c > 0 and c < 8
        up = cells[i - stride]
        if up = 0 or up = 8
            p = pristine[i - stride]
            if p > 0 and p < 8 then return 20 + c
            if c = 3 then return 40
            return 10 + c
        end if
        if c = 3
            ' cap rows: straight up through turf to a turf top under open sky
            d = 1
            capN = tp.capN
            while d < capN
                j = i - d * stride
                if cells[j] <> 3 then exit while
                up = cells[j - stride]
                if up = 0 or up = 8
                    p = pristine[j - stride]
                    if p = 0 or p = 8 then return 40 + d
                    exit while
                end if
                d = d + 1
            end while
        end if
        n = cells[i + stride]
        if n = 0 or n = 8 then return 30 + c
        n = cells[i - 1]
        if n = 0 or n = 8 then return 30 + c
        n = cells[i + 1]
        if n = 0 or n = 8 then return 30 + c
        return c
    end if
    p = pristine[i]
    if p > 0 and p < 8
        up = cells[i - stride]
        if up > 0 and up < 8 then return 9
        return 8
    end if
    ' open sky: maybe a grass blade rooted in turf just below
    if tp.bladeN > 0
        col = x and 255
        hb = tp.bladeH[col]
        k = 1
        while k <= hb
            j = i + k * stride
            n = cells[j]
            if n > 0 and n < 8
                if n = 3
                    if k = hb and tp.bladeF[col] >= 0 then return 60 + tp.bladeF[col]
                    return 50 + tp.bladeS[col]
                end if
                return 0
            end if
            p = pristine[j]
            if p > 0 and p < 8 then return 0
            k = k + 1
        end while
    end if
    return 0
end function

sub TpEmit(tp as object, x as integer, y as integer, w as integer, style as integer)
    if style = 0
        TpErase(tp, x, y, w, 1)
    else if style <= 7
        TpTex(tp, style, x, y, w, 1)
    else if style = 8
        TpTex(tp, 0, x, y, w, 1)
    else
        TpFlat(tp, x, y, w, 1, tp.flat[style])
    end if
end sub

' Repaints the stage around an edited rectangle of the mask.
' The margin covers everything whose style can depend on the edited cells:
' outlines 1 cell either side, blades 3 cells above, cap rows 4 cells below.
sub TpRepaint(tp as object, rx as integer, ry as integer, rw as integer, rh as integer)
    x0 = rx - 1
    x1 = rx + rw
    y0 = ry - 3
    y1 = ry + rh + 3
    if x0 < 0 then x0 = 0
    if y0 < 0 then y0 = 0
    if x1 > tp.w - 1 then x1 = tp.w - 1
    if y1 > tp.h - 1 then y1 = tp.h - 1
    if x0 > x1 or y0 > y1 then return
    for y = y0 to y1
        runStart = x0
        runStyle = TpStyle(tp, x0, y)
        for x = x0 + 1 to x1
            st = TpStyle(tp, x, y)
            if st <> runStyle
                TpEmit(tp, runStart, y, x - runStart, runStyle)
                runStart = x
                runStyle = st
            end if
        end for
        TpEmit(tp, runStart, y, x1 - runStart + 1, runStyle)
    end for
    TpMiniUpdate(tp, x0, y0, x1, y1)
end sub

' Refreshes the minimap cells that overlap a world rectangle by sampling the mask.
sub TpMiniUpdate(tp as object, x0 as integer, y0 as integer, x1 as integer, y1 as integer)
    cells = tp.cells
    stride = tp.stride
    base = tp.base
    mini = tp.mini
    maxX = tp.w - 1
    for my = y0 \ 8 to y1 \ 8
        for mx = x0 \ 8 to x1 \ 8
            col = tp.miniSky
            for sy = 1 to 6 step 5
                for sx = 1 to 6 step 5
                    wx = mx * 8 + sx
                    if wx > maxX then wx = maxX
                    c = cells[(my * 8 + sy) * stride + wx + base]
                    if c > 0 and c < 8
                        if c = 5
                            col = tp.miniSteel
                        else if col = tp.miniSky
                            col = tp.miniSolid
                        end if
                    end if
                end for
            end for
            mini.DrawRect(mx, my, 1, 1, col)
        end for
    end for
end sub

' Draws the visible chunks 2x at the given camera offset (in screen pixels).
sub TpDraw(tp as object, scr as object, camPx as integer, viewW as integer)
    span = tp.cw * 2
    first = camPx \ span
    last = (camPx + viewW - 1) \ span
    n = tp.regs.Count()
    if last > n - 1 then last = n - 1
    for k = first to last
        scr.DrawScaledObject(k * span - camPx, 0, 2.0, 2.0, tp.regs[k])
    end for
end sub

' ------------------------------------------------------------ stage thumbnail

' A miniature of the stage's real collision geometry, drawn straight from the
' row bands (used on the briefing and code screens; no mask is needed).
sub TerrainDrawThumb(scr as object, level as object, colors as object, x as integer, y as integer, w as integer, h as integer)
    sx = w / level.w
    sy = h / level.h
    cSky0 = GfxHex(colors.sky[0])
    cSky1 = GfxHex(colors.sky[2])
    scr.DrawRect(x, y, w, h \ 2, cSky0)
    scr.DrawRect(x, y + h \ 2, w, h - h \ 2, cSky1)
    cSoil = GfxHex(colors.debris[3])
    cDirt = GfxHex(colors.debris[1])
    cRock = GfxHex(colors.debris[2])
    cSteel = GfxHex(colors.debris[5])
    cArrow = GfxHex(colors.debris[6])
    cBridge = GfxHex(colors.debris[4])
    cCap = GfxHex(colors.cap[0])
    byMat = [0, cDirt, cRock, cSoil, cBridge, cSteel, cArrow, cArrow]
    wy = 0
    prevSolid = [0, level.w]
    for each r in level.rows
        ty0 = y + Int(wy * sy)
        ty1 = y + Int((wy + r[0]) * sy)
        if ty1 <= ty0 then ty1 = ty0 + 1
        if ty1 > y + h then ty1 = y + h
        solid = []
        wx = 0
        n = r.Count()
        k = 1
        while k < n
            mat = r[k]
            wx1 = wx + r[k + 1]
            if mat >= 1 and mat <= 7
                tx0 = x + Int(wx * sx)
                tx1 = x + Int(wx1 * sx)
                if tx1 <= tx0 then tx1 = tx0 + 1
                if ty0 < y + h then scr.DrawRect(tx0, ty0, tx1 - tx0, ty1 - ty0, byMat[mat])
                if mat = 3
                    pieces = IvSubtract(wx, wx1, prevSolid)
                    i = 0
                    while i < pieces.Count()
                        px0 = x + Int(pieces[i] * sx)
                        px1 = x + Int(pieces[i + 1] * sx)
                        if px1 <= px0 then px1 = px0 + 1
                        if ty0 < y + h then scr.DrawRect(px0, ty0, px1 - px0, 2, cCap)
                        i = i + 2
                    end while
                end if
                ns = solid.Count()
                if ns > 0 and solid[ns - 1] = wx
                    solid[ns - 1] = wx1
                else
                    solid.Push(wx)
                    solid.Push(wx1)
                end if
            end if
            wx = wx1
            k = k + 2
        end while
        prevSolid = solid
        wy = wy + r[0]
    end for
    ' hazards, hatches and sheepfolds
    for each z in level.haz
        col = &hff5028e6
        if z[0] = "water" then col = &h3c96e6e6
        if z[0] = "pit" then col = &h00000080
        zw = Int(z[3] * sx)
        zh = Int(z[4] * sy)
        if zw < 1 then zw = 1
        if zh < 1 then zh = 1
        scr.DrawRect(x + Int(z[1] * sx), y + Int(z[2] * sy), zw, zh, col)
    end for
    for each e in level.ent
        scr.DrawRect(x + Int(e[0] * sx) - 4, y + Int(e[1] * sy) - 7, 9, 6, &h4f321dff)
        scr.DrawRect(x + Int(e[0] * sx) - 3, y + Int(e[1] * sy) - 6, 7, 4, &hffd25eff)
    end for
    for each e in level.exits
        ex = x + Int(e[0] * sx)
        ey = y + Int(e[1] * sy)
        scr.DrawRect(ex - 5, ey - 8, 11, 9, &h4f321dff)
        scr.DrawRect(ex - 4, ey - 7, 9, 7, &hc4452fff)
        scr.DrawRect(ex - 1, ey - 4, 3, 4, &hffe08aff)
    end for
end sub
