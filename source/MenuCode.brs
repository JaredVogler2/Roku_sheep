' =============================================================================
' SHEEPFALL for Roku - stage code entry.
'
' Every stage has a permanent code (SHP-XXXX-XXXX-C). Entering one opens that
' stage with no saved game, on any device - the same codes as the web game.
' The on-screen keyboard only offers the 30 symbols codes can contain (no I, L,
' O, U, 0 or 1), so most typing mistakes cannot be made at all. Characters
' typed on a keyboard or the Roku mobile app are accepted too.
' =============================================================================

function MenuCodeNew(app as object) as object
    s = { kind: "code", app: app, animated: false, update: MenuStaticUpdate, draw: MenuCodeDraw, onKey: MenuCodeKey, onChar: MenuCodeChar }
    s.text = ""          ' the 9 symbols after SHP
    s.row = 0
    s.col = 0
    s.message = ""
    s.bad = false
    s.alphabet = CodeAlphabet()
    return s
end function

sub MenuCodeAdd(s as object, ch as string)
    ' someone typing the whole code starts with its SHP prefix: let it scroll out
    if Len(s.text) >= 9 and Left(s.text, 3) = "SHP" then s.text = Mid(s.text, 4)
    if Len(s.text) >= 9 then return
    s.text = s.text + ch
    s.message = ""
    AudioPlay(s.app.audio, "ui")
    ' the code is complete: move to OPEN so one more OK submits it
    if Len(s.text) = 9
        s.row = 3
        s.col = 2
    end if
end sub

sub MenuCodeDelete(s as object)
    if Len(s.text) > 0 then s.text = Left(s.text, Len(s.text) - 1)
    s.message = ""
    AudioPlay(s.app.audio, "ui")
end sub

sub MenuCodeSubmit(s as object)
    app = s.app
    check = CodeCheck(app.index, "SHP" + s.text)
    if not check.ok
        s.message = check.message
        s.bad = true
        AudioPlay(app.audio, "reject")
        return
    end if
    AudioPlay(app.audio, "fanfare")
    viaCode = not ProgressIsUnlocked(app.progress, check.stageId)
    AppShowMenu(app, MenuBriefNew(app, check.stageId, viaCode))
end sub

sub MenuCodeChar(ch as integer)
    s = m
    if ch = 8 or ch = 127
        MenuCodeDelete(s)
    else if ch = 13 or ch = 10
        MenuCodeSubmit(s)
    else
        c = UCase(Chr(ch))
        a = Asc(c)
        if (a >= 65 and a <= 90) or (a >= 48 and a <= 57) then MenuCodeAdd(s, c)
    end if
end sub

sub MenuCodeKey(code as integer, pressed as boolean)
    if not pressed then return
    s = m
    app = s.app
    if code = 0
        AppShowMenu(app, MenuMainNew(app))
    else if code = 2
        if s.row > 0
            ' from the action row back up into the letters
            if s.row = 3
                above = [1, 4, 8]
                s.col = above[s.col]
            end if
            s.row = s.row - 1
        end if
    else if code = 3
        if s.row < 2
            s.row = s.row + 1
        else if s.row = 2
            s.row = 3
            if s.col <= 2
                s.col = 0
            else if s.col <= 5
                s.col = 1
            else
                s.col = 2
            end if
        end if
    else if code = 4
        if s.col > 0 then s.col = s.col - 1
    else if code = 5
        maxCol = 9
        if s.row = 3 then maxCol = 2
        if s.col < maxCol then s.col = s.col + 1
    else if code = 8
        MenuCodeDelete(s)
    else if code = 13
        MenuCodeSubmit(s)
    else if code = 6
        if s.row < 3
            MenuCodeAdd(s, Mid(s.alphabet, s.row * 10 + s.col + 1, 1))
        else if s.col = 0
            MenuCodeDelete(s)
        else if s.col = 1
            s.text = ""
            s.message = ""
            AudioPlay(app.audio, "ui")
        else
            MenuCodeSubmit(s)
        end if
    end if
end sub

sub MenuCodeDraw(scr as object)
    s = m
    app = s.app
    a = app.assets
    f = app.fonts
    AppBackdropDraw(app, scr)
    GfxNine(scr, a.nine["panel.cream"], 230, 36, 820, 600)
    ink = MenuInk()
    GfxTextCentered(scr, "Enter Stage Code", 640, 56, ink, f.head)
    GfxTextCentered(scr, "Codes open a stage on any device - no saved game needed.", 640, 106, MenuMuted(), f.small)

    ' ---- the code so far: SHP - XXXX - XXXX - C
    slot = 48
    gapW = 26
    pw = f.head.GetOneLineWidth("SHP", 400)
    total = pw + gapW + 9 * (slot + 6) - 6 + 2 * gapW
    x = 640 - total \ 2
    y = 148
    scr.DrawText("SHP", x, y + 6, MenuMuted(), f.head)
    x = x + pw
    scr.DrawRect(x + 8, y + 28, gapW - 16, 4, MenuMuted())
    x = x + gapW
    n = Len(s.text)
    for i = 0 to 8
        if i = 4 or i = 8
            scr.DrawRect(x + 2, y + 28, gapW - 16, 4, MenuMuted())
            x = x + gapW - 6
        end if
        col = &hfffdf6ff
        if i = n then col = &hffe38fff
        scr.DrawRect(x, y, slot, 60, &h4f321dff)
        scr.DrawRect(x + 3, y + 3, slot - 6, 54, col)
        if i < n
            ch = Mid(s.text, i + 1, 1)
            scr.DrawText(ch, x + (slot - f.head.GetOneLineWidth(ch, 100)) \ 2, y + 7, ink, f.head)
        end if
        x = x + slot + 6
    end for

    ' ---- message
    if s.message <> ""
        ty = 220
        for each ln in GfxWrap(s.message, f.small, 740)
            GfxTextCentered(scr, ln, 640, ty, &hb3261aff, f.small)
            ty = ty + 25
        end for
    end if

    ' ---- keyboard: 3 rows of 10 symbols, then Delete / Clear / Open
    kx = 640 - (10 * 66 - 6) \ 2
    for r = 0 to 2
        for c = 0 to 9
            ch = Mid(s.alphabet, r * 10 + c + 1, 1)
            x = kx + c * 66
            y = 282 + r * 62
            GfxNine(scr, a.nine["btn.cream"], x, y, 60, 56)
            scr.DrawText(ch, x + (60 - f.big.GetOneLineWidth(ch, 100)) \ 2, y + 7, ink, f.big)
        end for
    end for
    labels = ["Delete", "Clear", "Open stage"]
    faces = ["btn.cream", "btn.cream", "btn.green"]
    xs = [kx, kx + 206, kx + 412]
    ws = [200, 200, 242]
    for i = 0 to 2
        AppDrawButton(app, scr, xs[i], 476, ws[i], 56, labels[i], faces[i], false)
    end for
    if s.row < 3
        GfxNine(scr, a.nine["focus.nine"], kx + s.col * 66 - 6, 282 + s.row * 62 - 6, 72, 68)
    else
        GfxNine(scr, a.nine["focus.nine"], xs[s.col] - 6, 470, ws[s.col] + 12, 68)
    end if
    GfxTextCentered(scr, "Codes never use I, L, O, U, zero or one.", 640, 552, MenuMuted(), f.small)
    GfxTextCentered(scr, "Finished a stage? Its results screen shows the next stage's code.", 640, 580, MenuMuted(), f.small)
    AppDrawHints(app, scr, "OK  Type      Rewind  Delete      Play/Pause  Open stage      Back  Menu")
end sub
