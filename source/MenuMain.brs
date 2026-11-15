' =============================================================================
' SHEEPFALL for Roku - title screen, credits and the finale.
'
' Menu scenes come in two kinds:
'   animated  the living backdrop keeps playing behind a light panel
'             (title, results, finale)
'   static    drawn only when something changes (a key press, a scene change);
'             between presses the app sleeps instead of redrawing 60 times a
'             second. The backdrop simply holds its current frame behind them.
' Every key press on a static scene redraws it, so a scene never has to
' remember to ask.
' =============================================================================

sub MenuAnimUpdate(dtMs as integer)
    AppBackdropUpdate(m.app, dtMs)
end sub

sub MenuStaticUpdate(dtMs as integer)
end sub

function MenuInk() as integer
    return &h3b2a1cff
end function

function MenuMuted() as integer
    return &h6b5440ff
end function

' ------------------------------------------------------------------- title

function MenuMainNew(app as object) as object
    s = { kind: "main", app: app, animated: true, update: MenuAnimUpdate, draw: MenuMainDraw, onKey: MenuMainKey }
    p = app.progress
    items = []
    if ProgressHasAny(p)
        id = ProgressContinueId(p)
        items.Push({ id: "continue", label: "Continue - " + LevelStageLabel(id), face: "btn.green", stage: id })
        items.Push({ id: "new", label: "New Game", face: "btn.cream", stage: app.index.order[0] })
    else
        items.Push({ id: "new", label: "Play", face: "btn.green", stage: app.index.order[0] })
    end if
    items.Push({ id: "code", label: "Enter Stage Code", face: "btn.gold" })
    items.Push({ id: "stages", label: "Stage Select", face: "btn.cream" })
    items.Push({ id: "help", label: "How to Play", face: "btn.cream" })
    items.Push({ id: "settings", label: "Settings", face: "btn.cream" })
    items.Push({ id: "credits", label: "Credits", face: "btn.cream" })
    s.items = items
    s.sel = 0
    s.done = p.data.done.Count()
    return s
end function

sub MenuMainKey(code as integer, pressed as boolean)
    if not pressed then return
    s = m
    app = s.app
    n = s.items.Count()
    if code = 2
        s.sel = (s.sel + n - 1) mod n
        AudioPlay(app.audio, "ui")
    else if code = 3
        s.sel = (s.sel + 1) mod n
        AudioPlay(app.audio, "ui")
    else if code = 0
        ' Back on the home screen leaves the app
        app.quit = true
    else if code = 6
        app.notice = ""
        item = s.items[s.sel]
        AudioPlay(app.audio, "assign")
        if item.id = "continue" or item.id = "new"
            viaCode = not ProgressIsUnlocked(app.progress, item.stage)
            AppShowMenu(app, MenuBriefNew(app, item.stage, viaCode))
        else if item.id = "code"
            AppShowMenu(app, MenuCodeNew(app))
        else if item.id = "stages"
            AppShowMenu(app, MenuStagesNew(app, ProgressContinueId(app.progress)))
        else if item.id = "help"
            AppShowMenu(app, MenuHelpNew(app, ""))
        else if item.id = "settings"
            AppShowMenu(app, MenuSettingsNew(app))
        else if item.id = "credits"
            AppShowMenu(app, MenuCreditsNew(app))
        end if
    end if
end sub

sub MenuMainDraw(scr as object)
    s = m
    app = s.app
    a = app.assets
    f = app.fonts
    AppBackdropDraw(app, scr)
    logo = a.spr["logo"]
    scr.DrawObject(640 - logo.GetWidth() \ 2, 30, logo)
    tag = "Tiny sheep. Unstoppable hooves. 120 stages to bring them home."
    GfxTextShadow(scr, tag, 640 - f.body.GetOneLineWidth(tag, 1200) \ 2, 154, &hfff8e7ff, f.body)
    n = s.items.Count()
    y = 206
    if n < 7 then y = 206 + (7 - n) * 30
    for i = 0 to n - 1
        item = s.items[i]
        AppDrawButton(app, scr, 430, y, 420, 52, item.label, item.face, i = s.sel)
        y = y + 60
    end for
    if app.notice <> ""
        y = 632
        lines = GfxWrap(app.notice, f.small, 1000)
        w = 0
        for each ln in lines
            lw = f.small.GetOneLineWidth(ln, 1200)
            if lw > w then w = lw
        end for
        h = lines.Count() * 26 + 16
        GfxNine(scr, a.nine["pill.red"], 640 - w \ 2 - 22, 694 - h, w + 44, h)
        ty = 694 - h + 8
        for each ln in lines
            GfxTextCentered(scr, ln, 640, ty, &hffffffff, f.small)
            ty = ty + 26
        end for
    else
        note = "Progress saves on this Roku. Stage codes work anywhere - write them down!"
        if s.done > 0 then note = s.done.ToStr() + " of 120 stages cleared. Stage codes work anywhere - write them down!"
        AppDrawHints(app, scr, note)
    end if
end sub

' ----------------------------------------------------------------- credits

function MenuCreditsNew(app as object) as object
    return { kind: "credits", app: app, animated: false, update: MenuStaticUpdate, draw: MenuCreditsDraw, onKey: MenuCreditsKey }
end function

sub MenuCreditsKey(code as integer, pressed as boolean)
    if not pressed then return
    if code = 0 or code = 6
        AudioPlay(m.app.audio, "ui")
        AppShowMenu(m.app, MenuMainNew(m.app))
    end if
end sub

sub MenuCreditsDraw(scr as object)
    app = m.app
    a = app.assets
    f = app.fonts
    AppBackdropDraw(app, scr)
    GfxNine(scr, a.nine["panel.cream"], 190, 40, 900, 590)
    ink = MenuInk()
    GfxTextCentered(scr, "Credits", 640, 62, ink, f.head)
    y = 122
    y = GfxParagraph(scr, "SHEEPFALL - design, code, levels, art, music and sound effects are original work created for this game. Every sprite and backdrop is drawn procedurally by the game's own art code, and every sound comes from its own synthesiser.", 236, y, 808, ink, f.small, 6)
    y = y + 12
    scr.DrawText("Inspiration", 236, y, &h8f2d1dff, f.bodyB)
    y = y + 36
    y = GfxParagraph(scr, "The crowd-guidance, terrain-carving formula pioneered by Lemmings (DMA Design / Psygnosis, 1991). SHEEPFALL is an independent homage with its own sheep, stages, codes and audio. It is not affiliated with or endorsed by the rights holders of Lemmings, and contains none of its graphics, music, levels or passwords.", 236, y, 808, ink, f.small, 6)
    y = y + 12
    scr.DrawText("On Roku", 236, y, &h8f2d1dff, f.bodyB)
    y = y + 36
    y = GfxParagraph(scr, "This edition runs the same simulation, the same 120 stages and the same stage codes as the web game, rebuilt in BrightScript for the remote. A code written down here opens the same stage there.", 236, y, 808, ink, f.small, 6)
    AppDrawButton(app, scr, 540, 556, 200, 52, "Back", "btn.green", true)
end sub

' ------------------------------------------------------------------ finale

function MenuEndingNew(app as object) as object
    s = { kind: "ending", app: app, animated: true, update: MenuAnimUpdate, draw: MenuEndingDraw, onKey: MenuEndingKey }
    s.sel = 0
    s.done = app.progress.data.done.Count()
    last = app.index.order[app.index.order.Count() - 1]
    s.code = app.index.byId[last].code
    s.last = last
    return s
end function

sub MenuEndingKey(code as integer, pressed as boolean)
    if not pressed then return
    s = m
    app = s.app
    if code = 4 or code = 5
        s.sel = 1 - s.sel
        AudioPlay(app.audio, "ui")
    else if code = 0
        AppShowMenu(app, MenuMainNew(app))
    else if code = 6
        AudioPlay(app.audio, "assign")
        if s.sel = 0
            AppShowMenu(app, MenuStagesNew(app, s.last))
        else
            AppShowMenu(app, MenuMainNew(app))
        end if
    end if
end sub

sub MenuEndingDraw(scr as object)
    s = m
    app = s.app
    a = app.assets
    f = app.fonts
    AppBackdropDraw(app, scr)
    GfxNine(scr, a.nine["panel.cream"], 210, 60, 860, 540)
    ink = MenuInk()
    GfxTextCentered(scr, "The Grand Sheepfall!", 640, 84, &h3f8f3aff, f.head)
    y = 148
    y = GfxParagraph(scr, "Through meadow mornings, golden hills, echoing caverns and the storm-lit highlands, the flock is home at last. Every sheep that kept walking, every blocker that stood firm, every twelve-plank bridge - thank you, shepherd.", 256, y, 768, ink, f.body, 6)
    y = y + 10
    GfxTextCentered(scr, "You have completed " + s.done.ToStr() + " of 120 stages.", 640, y, ink, f.bodyB)
    y = y + 50
    GfxNine(scr, a.nine["btn.gold"], 390, y, 500, 96)
    GfxTextCentered(scr, "FINAL STAGE CODE", 640, y + 10, &h6b4a12ff, f.tiny)
    GfxTextCentered(scr, s.code, 640, y + 32, ink, f.head)
    y = y + 106
    GfxTextCentered(scr, "The Grand Sheepfall can always be replayed with this code.", 640, y, MenuMuted(), f.small)
    AppDrawButton(app, scr, 400, 524, 230, 52, "Stage Select", "btn.green", s.sel = 0)
    AppDrawButton(app, scr, 650, 524, 230, 52, "Main Menu", "btn.cream", s.sel = 1)
end sub
