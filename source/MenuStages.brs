' =============================================================================
' SHEEPFALL for Roku - stage select: four acts of thirty stages.
'
' A 6 x 5 grid per act. Left / Right past the edge of the grid (or Rewind /
' Fast Forward) changes act. A stage can be opened when it was unlocked by
' play or visited with its code; the two are tracked apart, so a code never
' pretends earlier stages were beaten.
' =============================================================================

function MenuStagesNew(app as object, focusId as string) as object
    s = { kind: "stages", app: app, animated: false, update: MenuStaticUpdate, draw: MenuStagesDraw, onKey: MenuStagesKey }
    s.acts = LevelsActs()
    s.act = 0
    s.sel = 0
    s.note = ""
    p = LevelParseId(focusId)
    if p <> invalid
        for i = 0 to 3
            if s.acts[i].id = p.act then s.act = i
        end for
        s.sel = p.number - 1
    end if
    return s
end function

function MenuStagesId(s as object) as string
    return s.app.index.order[s.act * 30 + s.sel]
end function

sub MenuStagesKey(code as integer, pressed as boolean)
    if not pressed then return
    s = m
    app = s.app
    col = s.sel mod 6
    row = s.sel \ 6
    s.note = ""
    moved = true
    if code = 2
        if row > 0 then row = row - 1
    else if code = 3
        if row < 4 then row = row + 1
    else if code = 4
        if col > 0
            col = col - 1
        else if s.act > 0
            s.act = s.act - 1
            col = 5
        end if
    else if code = 5
        if col < 5
            col = col + 1
        else if s.act < 3
            s.act = s.act + 1
            col = 0
        end if
    else if code = 8
        if s.act > 0 then s.act = s.act - 1
    else if code = 9
        if s.act < 3 then s.act = s.act + 1
    else
        moved = false
    end if
    if moved
        s.sel = row * 6 + col
        AudioPlay(app.audio, "ui")
        return
    end if
    if code = 0
        AppShowMenu(app, MenuMainNew(app))
    else if code = 6
        id = MenuStagesId(s)
        if ProgressCanOpen(app.progress, id)
            AudioPlay(app.audio, "assign")
            AppShowMenu(app, MenuBriefNew(app, id, not ProgressIsUnlocked(app.progress, id)))
        else
            AudioPlay(app.audio, "reject")
            s.note = "Locked. Finish the stage before it, or enter this stage's code from the main menu."
        end if
    end if
end sub

sub MenuStagesDraw(scr as object)
    s = m
    app = s.app
    a = app.assets
    f = app.fonts
    p = app.progress
    idx = app.index
    AppBackdropDraw(app, scr)
    GfxNine(scr, a.nine["panel.dark"], 36, 18, 1208, 622)
    ink = MenuInk()

    ' ---- act tabs
    for i = 0 to 3
        act = s.acts[i]
        x = 52 + i * 296
        face = "btn.cream"
        if i = s.act then face = "btn.gold"
        GfxNine(scr, a.nine[face], x, 34, 288, 58)
        scr.DrawText(GfxFit(act.number.ToStr() + "  " + act.name, f.count, 208), x + 16, 49, ink, f.count)
        GfxTextRight(scr, ProgressCountDone(p, act.id).ToStr() + "/30", x + 272, 50, MenuMuted(), f.small)
    end for

    ' ---- the grid
    medals = ["bronze", "silver", "gold"]
    base = s.act * 30
    for i = 0 to 29
        id = idx.order[base + i]
        st = idx.byId[id]
        x = 57 + (i mod 6) * 196
        y = 104 + (i \ 6) * 92
        done = p.data.done[id]
        open = ProgressCanOpen(p, id)
        face = "btn.locked"
        col = &h7d7466ff
        if done <> invalid
            face = "btn.cream"
            col = ink
        else if open
            face = "btn.gold"
            col = ink
        end if
        GfxNine(scr, a.nine[face], x, y, 186, 82)
        scr.DrawText(Pad2(i + 1), x + 14, y + 6, col, f.big)
        if done <> invalid
            scr.DrawObject(x + 142, y + 8, a.spr["medal." + medals[done[2] - 1]])
        else if not open
            scr.DrawObject(x + 144, y + 10, a.spr["lock"])
        end if
        scr.DrawText(GfxFit(st.title, f.tiny, 158), x + 14, y + 46, col, f.tiny)
    end for
    x = 57 + (s.sel mod 6) * 196
    y = 104 + (s.sel \ 6) * 92
    GfxNine(scr, a.nine["focus.nine"], x - 6, y - 6, 198, 94)

    ' ---- the focused stage
    id = MenuStagesId(s)
    st = idx.byId[id]
    done = p.data.done[id]
    open = ProgressCanOpen(p, id)
    cream = &hfffaf0ff
    scr.DrawText(GfxFit(LevelStageLabel(id) + "  -  " + st.title, f.bodyB, 700), 62, 568, cream, f.bodyB)
    line = "Rescue " + st.req.ToStr() + " of " + st.total.ToStr()
    if done <> invalid
        line = line + "   -   Best " + done[0].ToStr() + " rescued, " + medals[done[2] - 1] + " medal"
    else if not open
        line = line + "   -   Locked"
    else if not ProgressIsUnlocked(p, id)
        line = line + "   -   Opened with a code"
    end if
    scr.DrawText(line, 62, 602, &hc9d9c0ff, f.small)
    if open and (p.data.set.codes = 1 or done <> invalid)
        GfxTextRight(scr, "Code  " + st.code, 1216, 570, &hffd25eff, f.bodyB)
    end if
    if s.note <> ""
        w = f.small.GetOneLineWidth(s.note, 1240) + 44
        GfxNine(scr, a.nine["pill.red"], 640 - w \ 2, 652, w, 38)
        scr.DrawText(s.note, 640 - w \ 2 + 22, 658, &hffffffff, f.small)
    else
        AppDrawHints(app, scr, "OK  Open stage      Rewind / Fast Forward  Change act      Back  Menu")
    end if
end sub
