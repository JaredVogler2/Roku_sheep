' =============================================================================
' SHEEPFALL for Roku - How to Play: the remote, the rules, and one small
' playable lesson for each of the eight skills (the web game's own lessons).
' =============================================================================

function MenuHelpNew(app as object, focusLesson as string) as object
    s = { kind: "help", app: app, animated: false, update: MenuStaticUpdate, draw: MenuHelpDraw, onKey: MenuHelpKey }
    s.lessons = [
        { id: "lesson-climber", skill: 0, blurb: "Scales sheer walls. Kept for the whole stage." }
        { id: "lesson-floater", skill: 1, blurb: "Opens on long drops. Kept for the whole stage." }
        { id: "lesson-bomber", skill: 2, blurb: "Five-second fuse, then a crater." }
        { id: "lesson-blocker", skill: 3, blurb: "Stands firm and turns the flock around." }
        { id: "lesson-builder", skill: 4, blurb: "Lays twelve rising planks." }
        { id: "lesson-basher", skill: 5, blurb: "Tunnels straight ahead." }
        { id: "lesson-miner", skill: 6, blurb: "Digs diagonally down and forward." }
        { id: "lesson-digger", skill: 7, blurb: "Digs straight down." }
    ]
    s.sel = 0
    for i = 0 to 7
        if s.lessons[i].id = focusLesson then s.sel = i
    end for
    return s
end function

sub MenuHelpKey(code as integer, pressed as boolean)
    if not pressed then return
    s = m
    app = s.app
    if code = 2
        s.sel = (s.sel + 7) mod 8
        AudioPlay(app.audio, "ui")
    else if code = 3
        s.sel = (s.sel + 1) mod 8
        AudioPlay(app.audio, "ui")
    else if code = 0
        AppShowMenu(app, MenuMainNew(app))
    else if code = 6
        AudioPlay(app.audio, "assign")
        AppStartStage(app, s.lessons[s.sel].id, { replay: invalid, viaCode: false, from: "help" })
    else if code = 13
        level = LevelLoad(s.lessons[s.sel].id)
        if level <> invalid
            AudioPlay(app.audio, "assign")
            AppStartStage(app, level.id, { replay: level.sol, viaCode: false, from: "help" })
        end if
    end if
end sub

sub MenuHelpDraw(scr as object)
    s = m
    app = s.app
    a = app.assets
    f = app.fonts
    AppBackdropDraw(app, scr)
    GfxNine(scr, a.nine["panel.cream"], 44, 22, 1192, 620)
    ink = MenuInk()
    muted = MenuMuted()
    barn = &h8f2d1dff
    scr.DrawText("How to Play", 84, 42, ink, f.head)

    ' ---- the rules, in three lines
    y = 96
    y = GfxParagraph(scr, "Sheep walk until something stops them: they turn at walls and fall off edges. Give a few of them skills to carve, bridge and block a safe way from the hatch to the sheepfold. Each stage says how many must get home, and the clock is always running.", 84, y, 560, ink, f.small, 5)

    ' ---- the remote
    y = y + 12
    scr.DrawText("Your remote", 84, y, barn, f.bodyB)
    y = y + 38
    rows = [
        ["Arrows", "Move the cursor. The view follows it."]
        ["OK", "Give the skill to the ringed sheep."]
        ["Rewind / Fast Fwd", "Previous / next skill."]
        ["Play/Pause", "Pause - you can still aim and assign."]
        ["Instant Replay", "Speed: 1x, 2x, 4x, 1/2x."]
        ["* (Options)", "Jump to the toolbar and back."]
        ["Down at the bottom", "Toolbar: rate, skills, nuke."]
        ["Back", "Pause menu: resume, restart, quit."]
    ]
    for each r in rows
        w = f.tiny.GetOneLineWidth(r[0], 400) + 20
        GfxNine(scr, a.nine["pill.dark"], 84, y - 2, w, 30)
        scr.DrawText(r[0], 94, y + 3, &hfffaf0ff, f.tiny)
        scr.DrawText(GfxFit(r[1], f.small, 380), 276, y, ink, f.small)
        y = y + 36
    end for

    ' ---- one lesson per skill
    x = 684
    scr.DrawText("Practise a skill", x, 42 + 12, barn, f.bodyB)
    labels = SimSkillLabels()
    y = 96
    for i = 0 to 7
        l = s.lessons[i]
        face = "btn.cream"
        if i = s.sel then face = "btn.gold"
        GfxNine(scr, a.nine[face], x, y, 512, 58)
        if i = s.sel then GfxNine(scr, a.nine["focus.nine"], x - 6, y - 6, 524, 70)
        scr.DrawObject(x + 14, y + 10, a.spr["skill." + l.skill.ToStr()])
        scr.DrawText(labels[l.skill], x + 60, y + 4, ink, f.bodyB)
        scr.DrawText(GfxFit(l.blurb, f.tiny, 430), x + 60, y + 31, muted, f.tiny)
        y = y + 64
    end for
    AppDrawHints(app, scr, "OK  Try the lesson      Play/Pause  Watch it done      Back  Menu")
end sub
