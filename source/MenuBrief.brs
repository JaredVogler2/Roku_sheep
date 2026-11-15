' =============================================================================
' SHEEPFALL for Roku - stage brief: everything needed to plan before the hatch
' opens. A miniature of the real collision geometry, the quota, the clock, the
' skills on offer, the shepherd's note and the stage's own code.
' =============================================================================

function MenuBriefNew(app as object, id as string, viaCode as boolean) as object
    s = { kind: "brief", app: app, animated: false, update: MenuStaticUpdate, draw: MenuBriefDraw, onKey: MenuBriefKey }
    s.id = id
    s.viaCode = viaCode
    s.level = LevelLoad(id)
    s.done = app.progress.data.done[id]
    buttons = [{ id: "back", label: "Back", face: "btn.cream" }]
    ' a verified solution may be watched once the stage has been beaten
    if s.done <> invalid then buttons.Push({ id: "watch", label: "Watch a solution", face: "btn.cream" })
    buttons.Push({ id: "play", label: "Let's Graze!", face: "btn.green" })
    s.buttons = buttons
    s.sel = buttons.Count() - 1
    s.thumbs = []
    s.thumbNote = ""
    if s.level <> invalid then MenuBriefBuildMap(s)
    return s
end function

' Paints the miniature once into small bitmaps (the brief is redrawn on every
' key press, the map is not). A very wide stage is shown as two strips, west
' half above east half, so its details stay readable.
sub MenuBriefBuildMap(s as object)
    level = s.level
    colors = s.app.assets.art.biomes[level.theme].terrain.colors
    boxW = 520
    boxH = 250
    strips = 1
    if level.w > 1300 then strips = 2
    span = (level.w + strips - 1) \ strips
    stripH = (boxH - (strips - 1) * 8) \ strips
    sc = boxW / span
    if stripH / level.h < sc then sc = stripH / level.h
    tw = Int(span * sc)
    th = Int(level.h * sc)
    fullW = Int(level.w * sc)
    y = 126
    for k = 0 to strips - 1
        bmp = CreateObject("roBitmap", { width: tw, height: th, AlphaEnable: true })
        bmp.Clear(&h101820ff)
        TerrainDrawThumb(bmp, level, colors, -k * tw, 0, fullW, th)
        bmp.Finish()
        s.thumbs.Push({ bmp: bmp, x: 96 + (boxW - tw) \ 2, y: y, w: tw, h: th })
        y = y + th + 8
    end for
    s.mapBottom = y - 8
    if strips = 2 then s.thumbNote = "West half above, east half below."
end sub

sub MenuBriefKey(code as integer, pressed as boolean)
    if not pressed then return
    s = m
    app = s.app
    n = s.buttons.Count()
    if code = 4
        if s.sel > 0 then s.sel = s.sel - 1
        AudioPlay(app.audio, "ui")
    else if code = 5
        if s.sel < n - 1 then s.sel = s.sel + 1
        AudioPlay(app.audio, "ui")
    else if code = 0
        AppShowMenu(app, MenuStagesNew(app, s.id))
    else if code = 6 or code = 13
        choice = s.buttons[s.sel].id
        if code = 13 then choice = "play"
        if s.level = invalid then choice = "back"
        AudioPlay(app.audio, "assign")
        if choice = "back"
            AppShowMenu(app, MenuStagesNew(app, s.id))
        else if choice = "watch"
            AppStartStage(app, s.id, { replay: s.level.sol, viaCode: s.viaCode, from: "stages" })
        else
            AppStartStage(app, s.id, { replay: invalid, viaCode: s.viaCode, from: "stages" })
        end if
    end if
end sub

sub MenuBriefDraw(scr as object)
    s = m
    app = s.app
    a = app.assets
    f = app.fonts
    level = s.level
    AppBackdropDraw(app, scr)
    GfxNine(scr, a.nine["panel.cream"], 56, 24, 1168, 616)
    ink = MenuInk()
    muted = MenuMuted()
    if level = invalid
        GfxTextCentered(scr, "This stage could not be loaded.", 640, 300, ink, f.body)
        AppDrawButton(app, scr, 540, 560, 200, 52, "Back", "btn.green", true)
        return
    end if

    ' ---- heading
    p = LevelParseId(s.id)
    act = LevelActInfo(p.act)
    badge = "Act " + act.number.ToStr() + "  -  " + act.name + "  -  Stage " + Pad2(p.number)
    if level.remix <> "" then badge = badge + "  -  Remix"
    scr.DrawText(badge, 96, 46, &h8f2d1dff, f.tiny)
    scr.DrawText(GfxFit(level.title, f.head, 1080), 96, 66, ink, f.head)

    ' ---- miniature map
    for each t in s.thumbs
        scr.DrawRect(t.x - 4, t.y - 4, t.w + 8, t.h + 8, &h4f321dff)
    end for
    scr.SetAlphaEnable(false)
    for each t in s.thumbs
        scr.DrawObject(t.x, t.y, t.bmp)
    end for
    scr.SetAlphaEnable(true)
    y = s.mapBottom + 14
    if s.thumbNote <> ""
        scr.DrawText(s.thumbNote, 96, y - 6, muted, f.tiny)
        y = y + 16
    end if

    ' ---- facts under the map
    secs = (level.time + 16) \ 17
    rate = level.rate.ToStr()
    if level.minrate < 99 and level.minrate <> level.rate then rate = rate + " (min " + level.minrate.ToStr() + ")"
    facts = [
        ["Sheep", level.total.ToStr()]
        ["Rescue", level.req.ToStr() + " (" + LevelRequiredPercent(level).ToStr() + "%)"]
        ["Time", (secs \ 60).ToStr() + ":" + Pad2(secs mod 60)]
        ["Release rate", rate]
    ]
    x = 96
    for each fact in facts
        scr.DrawText(fact[0], x, y, muted, f.tiny)
        scr.DrawText(fact[1], x, y + 18, ink, f.bodyB)
        w1 = f.tiny.GetOneLineWidth(fact[0], 600)
        w2 = f.bodyB.GetOneLineWidth(fact[1], 600)
        if w2 > w1 then w1 = w2
        x = x + w1 + 30
    end for

    ' ---- description and the shepherd's note on the right
    rx = 650
    rw = 540
    font = f.body
    gap = 6
    lines = GfxWrap(level.desc, font, rw)
    if lines.Count() > 6
        font = f.small
        gap = 5
        lines = GfxWrap(level.desc, font, rw)
    end if
    ry = 126
    lh = font.GetOneLineHeight() + gap
    for each ln in lines
        scr.DrawText(ln, rx, ry, ink, font)
        ry = ry + lh
    end for
    if level.hint <> ""
        ry = ry + 10
        scr.DrawText("Shepherd's note", rx, ry, &h8f2d1dff, f.tiny)
        ry = GfxParagraph(scr, level.hint, rx, ry + 22, rw, muted, f.small, 5)
    end if

    ' ---- skills on offer
    labels = SimSkillLabels()
    x = 96
    y = 474
    scr.DrawText("Skills", x, y - 22, muted, f.tiny)
    any = false
    for i = 0 to 7
        n = level.skills[i]
        if n > 0
            any = true
            txt = labels[i] + " " + n.ToStr()
            w = f.count.GetOneLineWidth(txt, 400) + 58
            GfxNine(scr, a.nine["pill.dark"], x, y, w, 40)
            scr.DrawObject(x + 10, y + 6, a.spr["skillsm." + i.ToStr()])
            scr.DrawText(txt, x + 44, y + 7, &hfffaf0ff, f.count)
            x = x + w + 8
        end if
    end for
    if not any then scr.DrawText("None - this flock needs no help.", x, y + 6, ink, f.small)

    ' ---- code and best result
    y = 528
    scr.DrawText("Stage code", 96, y, muted, f.tiny)
    note = "Opens this stage on any device, even with no saved game."
    if s.done <> invalid
        medals = ["bronze", "silver", "gold"]
        note = "Best so far: " + s.done[0].ToStr() + " rescued, " + medals[s.done[2] - 1] + " medal."
    else if s.viaCode
        note = "Opened with a code. Earlier stages stay locked until you beat them."
    end if
    nx = 96 + f.tiny.GetOneLineWidth("Stage code", 400) + 16
    scr.DrawText(GfxFit(note, f.tiny, 1188 - nx), nx, y, muted, f.tiny)
    cw = f.bodyB.GetOneLineWidth(level.code, 600) + 40
    GfxNine(scr, a.nine["btn.gold"], 96, 552, cw, 54)
    scr.DrawText(level.code, 116, 552 + (54 - 7 - f.bodyB.GetOneLineHeight()) \ 2, ink, f.bodyB)

    ' ---- buttons, right-aligned
    x = 1188
    i = s.buttons.Count() - 1
    while i >= 0
        b = s.buttons[i]
        w = f.bodyB.GetOneLineWidth(b.label, 600) + 56
        x = x - w
        AppDrawButton(app, scr, x, 552, w, 54, b.label, b.face, i = s.sel)
        x = x - 14
        i = i - 1
    end while
    AppDrawHints(app, scr, "OK  Select      Play/Pause  Start now      Back  Stage Select")
end sub
