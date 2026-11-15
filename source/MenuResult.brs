' =============================================================================
' SHEEPFALL for Roku - stage results.
'
' A win records progress (never downgrading an earlier result), awards a medal
' and shows the NEXT stage's code. A loss never touches progress and offers a
' gentle hint or a verified solution to watch.
' =============================================================================

function MenuResultNew(app as object, level as object, result as object, win as dynamic, opts as object) as object
    s = { kind: "result", app: app, animated: true, update: MenuAnimUpdate, draw: MenuResultDraw, onKey: MenuResultKey }
    s.level = level
    s.result = result
    s.win = win
    s.opts = opts
    s.lesson = LevelIsLesson(level.id)
    s.showHint = false
    s.nextId = ""
    buttons = []
    if s.lesson
        buttons.Push({ id: "lessons", label: "More lessons", face: "btn.green" })
        buttons.Push({ id: "retry", label: "Retry", face: "btn.cream" })
        if not result.won then buttons.Push({ id: "solution", label: "Show me", face: "btn.cream" })
    else if result.won
        if win <> invalid then s.nextId = win.nextId
        if s.nextId <> ""
            buttons.Push({ id: "next", label: "Continue", face: "btn.green" })
        else
            buttons.Push({ id: "finale", label: "Finale", face: "btn.green" })
        end if
        buttons.Push({ id: "retry", label: "Replay", face: "btn.cream" })
        buttons.Push({ id: "myrun", label: "Watch my run", face: "btn.cream" })
        buttons.Push({ id: "stages", label: "Stage Select", face: "btn.cream" })
    else
        buttons.Push({ id: "retry", label: "Retry", face: "btn.green" })
        buttons.Push({ id: "brief", label: "Level Brief", face: "btn.cream" })
        buttons.Push({ id: "hint", label: "Hint", face: "btn.cream" })
        buttons.Push({ id: "stages", label: "Stage Select", face: "btn.cream" })
    end if
    s.buttons = buttons
    s.sel = 0
    return s
end function

sub MenuResultKey(code as integer, pressed as boolean)
    if not pressed then return
    s = m
    app = s.app
    id = s.level.id
    viaCode = s.opts.viaCode = true
    n = s.buttons.Count()
    if code = 4
        s.sel = (s.sel + n - 1) mod n
        AudioPlay(app.audio, "ui")
    else if code = 5
        s.sel = (s.sel + 1) mod n
        AudioPlay(app.audio, "ui")
    else if code = 0
        if s.lesson
            AppShowMenu(app, MenuHelpNew(app, id))
        else
            AppShowMenu(app, MenuStagesNew(app, id))
        end if
    else if code = 6
        choice = s.buttons[s.sel].id
        AudioPlay(app.audio, "assign")
        if choice = "next"
            AppShowMenu(app, MenuBriefNew(app, s.nextId, false))
        else if choice = "finale"
            AppShowMenu(app, MenuEndingNew(app))
        else if choice = "retry"
            AppStartStage(app, id, { replay: invalid, viaCode: viaCode, from: s.opts.from })
        else if choice = "myrun"
            AppStartStage(app, id, { replay: s.result.inputs, viaCode: viaCode, from: s.opts.from })
        else if choice = "solution"
            AppStartStage(app, id, { replay: s.level.sol, viaCode: viaCode, from: s.opts.from })
        else if choice = "brief"
            AppShowMenu(app, MenuBriefNew(app, id, viaCode))
        else if choice = "lessons"
            AppShowMenu(app, MenuHelpNew(app, id))
        else if choice = "stages"
            AppShowMenu(app, MenuStagesNew(app, id))
        else if choice = "hint"
            if s.showHint
                ' second press: the whole answer
                AppStartStage(app, id, { replay: s.level.sol, viaCode: viaCode, from: s.opts.from })
            else
                s.showHint = true
                s.buttons[s.sel].label = "Show a solution"
            end if
        end if
    end if
end sub

sub MenuResultDraw(scr as object)
    s = m
    app = s.app
    a = app.assets
    f = app.fonts
    r = s.result
    level = s.level
    AppBackdropDraw(app, scr)
    px = 170
    pw = 940
    GfxNine(scr, a.nine["panel.cream"], px, 70, pw, 520)
    ink = MenuInk()
    muted = MenuMuted()
    green = &h3f8f3aff
    red = &hb3261aff
    y = 96
    if s.lesson
        if r.won
            GfxTextCentered(scr, "Lesson complete!", 640, y, green, f.head)
        else
            GfxTextCentered(scr, "Try that lesson again", 640, y, red, f.head)
        end if
        GfxTextCentered(scr, level.title, 640, y + 62, muted, f.body)
        GfxTextCentered(scr, "Rescued " + r.saved.ToStr() + " of " + r.total.ToStr() + " (needed " + r.required.ToStr() + ").", 640, y + 120, ink, f.bodyB)
    else if r.won
        p = LevelParseId(level.id)
        title = "Flock home!"
        if p <> invalid
            if p.number = 30 and s.nextId <> "" then title = LevelActInfo(p.act).name + " complete!"
        end if
        GfxTextCentered(scr, title, 640, y, green, f.head)
        GfxTextCentered(scr, LevelStageLabel(level.id) + "  -  " + level.title, 640, y + 50, muted, f.small)
        ' rescued line with the medal
        pct = Int(100 * r.saved / r.total + 0.5)
        line = "Rescued " + r.saved.ToStr() + " / " + r.total.ToStr() + " (" + pct.ToStr() + "%)  -  needed " + r.required.ToStr()
        medalNames = ["bronze", "silver", "gold"]
        medal = 1
        if s.win <> invalid then medal = s.win.earned
        lw = f.bodyB.GetOneLineWidth(line, 900)
        lx = 640 - (lw + 44) \ 2
        scr.DrawText(line, lx, y + 88, ink, f.bodyB)
        scr.DrawObject(lx + lw + 14, y + 82, a.spr["medal." + medalNames[medal - 1]])
        secs = (r.ticks + 16) \ 17
        sub2 = UCase(Left(medalNames[medal - 1], 1)) + Mid(medalNames[medal - 1], 2) + " medal  -  time used " + (secs \ 60).ToStr() + ":" + Pad2(secs mod 60)
        GfxTextCentered(scr, sub2, 640, y + 124, muted, f.small)
        ' the next stage's code
        by = y + 164
        GfxNine(scr, a.nine["btn.gold"], 330, by, 620, 150)
        if s.nextId <> ""
            nextStage = app.index.byId[s.nextId]
            GfxTextCentered(scr, "BARN GATE UNLOCKED!  Next-stage code:", 640, by + 12, &h6b4a12ff, f.tiny)
            GfxTextCentered(scr, nextStage.code, 640, by + 36, ink, f.title)
            GfxTextCentered(scr, GfxFit("Opens " + LevelStageLabel(s.nextId) + " - " + nextStage.title, f.small, 580), 640, by + 104, &h6b4a12ff, f.small)
        else
            GfxTextCentered(scr, "THE FINAL FOLD IS HOME!", 640, by + 12, &h6b4a12ff, f.tiny)
            GfxTextCentered(scr, level.code, 640, by + 36, ink, f.title)
            GfxTextCentered(scr, "The Grand Sheepfall can always be replayed with this code.", 640, by + 104, &h6b4a12ff, f.small)
        end if
        GfxTextCentered(scr, "Write it down! The code opens the stage on any device, even with no saved game.", 640, by + 162, muted, f.small)
    else
        GfxTextCentered(scr, "Not this time...", 640, y, red, f.head)
        GfxTextCentered(scr, LevelStageLabel(level.id) + "  -  " + level.title, 640, y + 50, muted, f.small)
        reason = "Not enough sheep were rescued."
        if r.reason = "not-enough-left" then reason = "Not enough sheep are left to reach the quota."
        if r.reason = "time-expired" then reason = "Time ran out before enough sheep were home."
        GfxTextCentered(scr, reason, 640, y + 96, ink, f.bodyB)
        GfxTextCentered(scr, "Rescued " + r.saved.ToStr() + " of " + r.total.ToStr() + "; this stage needs " + r.required.ToStr() + ".", 640, y + 138, ink, f.body)
        GfxTextCentered(scr, "Your unlocked stages and codes are safe.", 640, y + 172, muted, f.small)
        if s.showHint
            by = y + 216
            GfxNine(scr, a.nine["btn.gold"], 250, by, 780, 150)
            hint = level.hint
            if hint = "" then hint = "No gentle hint for this one - but a verified winning run can be watched."
            scr.DrawText("GENTLER HINT", 278, by + 12, &h6b4a12ff, f.tiny)
            ty = GfxParagraph(scr, hint, 278, by + 34, 724, ink, f.small, 5)
            scr.DrawText("Press OK again to watch a verified solution (spoiler: the whole answer).", 278, by + 116, &h6b4a12ff, f.tiny)
        end if
    end if

    ' ---- buttons in one centred row
    n = s.buttons.Count()
    ws = []
    total = 0
    for each b in s.buttons
        w = f.bodyB.GetOneLineWidth(b.label, 600) + 52
        ws.Push(w)
        total = total + w
    end for
    total = total + (n - 1) * 14
    x = 640 - total \ 2
    for i = 0 to n - 1
        b = s.buttons[i]
        AppDrawButton(app, scr, x, 512, ws[i], 54, b.label, b.face, i = s.sel)
        x = x + ws[i] + 14
    end for
    AppDrawHints(app, scr, "Left / Right  Choose      OK  Select      Back  Stage Select")
end sub
