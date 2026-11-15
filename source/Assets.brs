' =============================================================================
' SHEEPFALL for Roku - art loading.
'
' All images are produced by tools/build-art.mts from the web game's procedural
' art; pkg:/images/art.json says where every sprite sits in its atlas and where
' its top-left corner goes relative to the anchor it is drawn around.
'
' Texture memory is spent deliberately:
'   * sheep.png holds right-facing poses only. The left-facing atlas is built
'     once at start-up by copying 1 px columns in reverse order, which halves
'     that part of the package (it must fit in 4 MB) and works on every
'     firmware because it uses nothing but plain raw copies.
'   * Biome art (objects, backdrops, terrain sheets) is loaded for the biome in
'     use only, and released when the biome changes.
' =============================================================================

function AssetsLoad() as object
    art = ParseJson(ReadAsciiFile("pkg:/images/art.json"))
    if art = invalid then return invalid
    a = { art: art, biomeName: "", biome: invalid }

    ' ---- shared atlas: icons, cursor, HUD buttons, particles, hazard strips, logo
    bmp = CreateObject("roBitmap", art.common.file)
    if bmp = invalid then return invalid
    a.commonBmp = bmp
    sprites = art.common.sprites
    spr = {}
    off = {}
    for each key in sprites
        r = sprites[key]
        if r[2] > 0
            spr[key] = CreateObject("roRegion", bmp, r[0], r[1], r[2], r[3])
            off[key] = [r[4], r[5]]
        end if
    end for
    a.spr = spr
    a.off = off

    ' nine-slice sources
    nineInsets = art.common.nine
    nine = {}
    for each name in ["btn.cream", "btn.green", "btn.gold", "btn.red", "btn.locked", "focus.nine", "panel.cream", "panel.dark", "pill.dark", "pill.red"]
        r = sprites[name]
        inset = nineInsets.pill
        if Left(name, 3) = "btn" then inset = nineInsets.btn
        if Left(name, 5) = "focus" then inset = nineInsets.focus
        if Left(name, 5) = "panel" then inset = nineInsets.panel
        nine[name] = GfxNineMake(bmp, r[0], r[1], r[2], inset)
    end for
    a.nine = nine

    ' ---- sheep: right-facing atlas from the package, left-facing built here
    sheepR = CreateObject("roBitmap", art.sheep.file)
    if sheepR = invalid then return invalid
    w = sheepR.GetWidth()
    h = sheepR.GetHeight()
    sheepL = CreateObject("roBitmap", { width: w, height: h, AlphaEnable: false })
    sheepL.Clear(0)
    for x = 0 to w - 1
        col = CreateObject("roRegion", sheepR, x, 0, 1, h)
        sheepL.DrawObject(w - 1 - x, 0, col)
    end for
    sheepL.Finish()
    a.sheepR = sheepR
    a.sheepL = sheepL
    ' frames[anim][variant][frame] = [regionRight, oxRight, oy, regionLeft, oxLeft]
    frames = []
    for each animFrames in art.sheep.frames
        byVariant = []
        for each variantFrames in animFrames
            list = []
            for each f in variantFrames
                rr = CreateObject("roRegion", sheepR, f[0], f[1], f[2], f[3])
                rl = CreateObject("roRegion", sheepL, w - f[0] - f[2], f[1], f[2], f[3])
                list.Push([rr, f[4], f[5], rl, -(f[4] + f[2])])
            end for
            byVariant.Push(list)
        end for
        frames.Push(byVariant)
    end for
    a.sheepFrames = frames
    a.sheepCounts = art.sheep.counts
    return a
end function

' Sprite from the shared atlas drawn with its anchor at (x, y).
sub AssetsDraw(scr as object, a as object, name as string, x as integer, y as integer)
    o = a.off[name]
    scr.DrawObject(x + o[0], y + o[1], a.spr[name])
end sub

' Makes the art of one biome current (no-op when it already is).
function AssetsUseBiome(a as object, biomeName as string) as object
    if a.biomeName = biomeName and a.biome <> invalid then return a.biome
    ' release the previous biome before loading the next one
    a.biome = invalid
    a.biomeName = ""
    info = a.art.biomes[biomeName]
    b = { name: biomeName }

    ' ---- hatch, sheepfold, decor
    objBmp = CreateObject("roBitmap", info.objects.file)
    b.objBmp = objBmp
    spr = {}
    off = {}
    sprites = info.objects.sprites
    for each key in sprites
        r = sprites[key]
        if r[2] > 0
            reg = CreateObject("roRegion", objBmp, r[0], r[1], r[2], r[3])
            reg.SetScaleMode(1)
            spr[key] = reg
            off[key] = [r[4], r[5]]
        end if
    end for
    b.spr = spr
    b.off = off
    b.decorFrames = info.objects.decorframes
    b.decorMs = info.objects.decorms
    b.doorSteps = info.objects.doorsteps
    b.exitFrames = info.objects.exitframes

    ' ---- terrain: every material tile repeated into a 256 x 320 sheet
    ter = info.terrain
    sw = ter.sheetw
    sh = ter.sheeth
    names = ["cavity", "dirt", "rock", "turf", "bridge", "steel", "onewayl", "onewayr"]
    sheets = []
    for each name in names
        t = ter.tiles[name]
        tile = CreateObject("roBitmap", t.file)
        sheet = CreateObject("roBitmap", { width: sw, height: sh, AlphaEnable: false })
        y = 0
        while y < sh
            x = 0
            while x < sw
                sheet.DrawObject(x, y, tile)
                x = x + t.w
            end while
            y = y + t.h
        end while
        sheet.Finish()
        sheets.Push(sheet)
    end for
    b.sheets = sheets
    b.sheetW = sw
    b.sheetH = sh
    b.colors = ter.colors

    ' ---- parallax backdrop
    bg = info.background
    layers = []
    for each name in ["far", "mid", "near"]
        l = bg[name]
        bmp = CreateObject("roBitmap", l.file)
        reg = CreateObject("roRegion", bmp, 0, 0, bmp.GetWidth(), bmp.GetHeight())
        reg.SetScaleMode(1)
        top = 0
        if l.top <> invalid then top = l.top
        layers.Push({ bmp: bmp, reg: reg, factor: l.factor, top: top, w: bmp.GetWidth(), h: bmp.GetHeight() })
    end for
    b.layers = layers

    a.biome = b
    a.biomeName = biomeName
    return b
end function
