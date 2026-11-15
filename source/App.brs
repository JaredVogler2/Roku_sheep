' =============================================================================
' SHEEPFALL for Roku - application shell: start-up, main loop, scene changes.
'
' The game is drawn with the 2D API (roScreen, double buffered, 1280 x 720).
' One loop drives everything:
'
'     read remote events -> scene.update(dt) -> scene.draw(screen) -> SwapBuffers
'
' SwapBuffers waits for the display, so the loop runs at the TV's refresh rate
' and never spins. A scene is a plain associative array with update / draw /
' onKey (and optionally onChar) functions; exactly one scene is current.
'
' Menus are drawn over a "living backdrop": the real engine replaying a small
' recorded stage, exactly as the web game's title screen does.
'
' `driver` is invalid on a device. The automated smoke test passes an object
' that feeds scripted key presses and a fixed frame time, so the whole app can
' be exercised in a simulator without a remote (see tests/smoke_main.brs).
' =============================================================================

sub AppMain(args as dynamic, driver as dynamic)
    screen = CreateObject("roScreen", true, 1280, 720)
    if screen = invalid then return
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    screen.SetAlphaEnable(true)

    reg = CreateObject("roFontRegistry")
    fonts = {
        tiny: reg.GetDefaultFont(16, true, false)
        count: reg.GetDefaultFont(20, true, false)
        big: reg.GetDefaultFont(28, true, false)
        small: reg.GetDefaultFont(20, false, false)
        body: reg.GetDefaultFont(24, false, false)
        bodyB: reg.GetDefaultFont(24, true, false)
        head: reg.GetDefaultFont(36, true, false)
        title: reg.GetDefaultFont(52, true, false)
    }

    ' something on screen straight away, while the art loads
    for i = 1 to 2
        screen.Clear(&h21392bff)
        GfxTextCentered(screen, "SHEEPFALL", 640, 300, &hfff8e7ff, fonts.title)
        GfxTextCentered(screen, "Opening the gate...", 640, 372, &hc9d9c0ff, fonts.body)
        screen.SwapBuffers()
    end for

    app = {
        screen: screen
        port: port
        driver: driver
        fonts: fonts
        scene: invalid
        bg: invalid
        quit: false
        dirty: 2
        notice: ""
        onGameEnd: AppOnGameEnd
        ' session-only ceilings, lowered automatically if this Roku cannot hold the frame rate
        quality: { scenery: 2, effects: 2 }
    }
    app.assets = AssetsLoad()
    app.index = LevelsLoadIndex()
    if app.assets = invalid or app.index = invalid
        AppFatal(app, "The game files could not be read. Please remove and reinstall SHEEPFALL.")
        return
    end if
    app.progress = ProgressLoad(app.index)
    app.notice = app.progress.warning
    set = app.progress.data.set
    app.audio = AudioNew(set.sfx, set.music = 1)

    ' deep links arrive at launch (args) or while running (roInput)
    app.input = CreateObject("roInput")
    if app.input <> invalid then app.input.SetMessagePort(port)

    AppShowMenu(app, MenuMainNew(app))
    if IsAA(args)
        if args.contentId <> invalid then AppOpenLink(app, args.contentId)
    end if
    AppSignalLaunchComplete()

    clock = CreateObject("roTimespan")
    last = clock.TotalMilliseconds()
    while not app.quit
        ' ---- time and input
        if driver = invalid
            msg = port.GetMessage()
            while msg <> invalid
                AppHandleMessage(app, msg)
                msg = port.GetMessage()
            end while
            now = clock.TotalMilliseconds()
            dt = now - last
            ' SwapBuffers normally paces the loop to the display; never spin if it returns at once
            if dt < 4
                sleep(4 - dt)
                now = clock.TotalMilliseconds()
                dt = now - last
            end if
            last = now
        else
            dt = driver.advance(app)
        end if
        if dt < 0 then dt = 0
        if dt > 250 then dt = 250
        if app.quit then exit while

        ' ---- one frame
        scene = app.scene
        scene.update(dt)
        ' update may have switched scenes (stage finished, menu choice): draw the new one
        scene = app.scene
        if scene.animated or app.dirty > 0
            ' a static menu is drawn twice after a change, once into each buffer
            if app.dirty > 0 then app.dirty = app.dirty - 1
            scene.draw(screen)
            if driver <> invalid then driver.drawn(app)
            screen.SwapBuffers()
        else if driver = invalid
            ' nothing has changed on a static menu: sleep until the remote does something
            msg = wait(100, port)
            if msg <> invalid then AppHandleMessage(app, msg)
            last = clock.TotalMilliseconds()
        else
            driver.drawn(app)
        end if
    end while
    AudioStop(app.audio)
end sub

sub AppHandleMessage(app as object, msg as object)
    t = type(msg)
    if t = "roUniversalControlEvent"
        ch = msg.GetChar()
        code = msg.GetInt()
        if ch > 0
            ' a character typed on a keyboard or in the Roku mobile app
            if msg.IsPress() then AppChar(app, ch)
        else if code >= 100
            AppKey(app, code - 100, false)
        else
            AppKey(app, code, true)
        end if
    else if t = "roInputEvent"
        if msg.IsInput()
            info = msg.GetInfo()
            if IsAA(info)
                if info.contentId <> invalid then AppOpenLink(app, info.contentId)
            end if
        end if
    end if
end sub

sub AppKey(app as object, code as integer, pressed as boolean)
    app.dirty = 2
    app.scene.onKey(code, pressed)
end sub

sub AppChar(app as object, ch as integer)
    app.dirty = 2
    if app.scene.onChar <> invalid then app.scene.onChar(ch)
end sub

' Tells the OS the app is ready for input (measured by certification).
sub AppSignalLaunchComplete()
    node = CreateObject("roSGNode", "Node")
    if type(node) = "roSGNode" then node.signalBeacon("AppLaunchComplete")
end sub

sub AppFatal(app as object, text as string)
    scr = app.screen
    for i = 1 to 2
        scr.Clear(&h21392bff)
        y = 300
        for each ln in GfxWrap(text, app.fonts.body, 900)
            GfxTextCentered(scr, ln, 640, y, &hfff8e7ff, app.fonts.body)
            y = y + 34
        end for
        GfxTextCentered(scr, "Press Back to exit.", 640, y + 30, &hc9d9c0ff, app.fonts.small)
        scr.SwapBuffers()
    end for
    if app.driver <> invalid then return
    while true
        msg = wait(0, app.port)
        if type(msg) = "roUniversalControlEvent"
            if msg.GetInt() = 0 then return
        end if
    end while
end sub

' ------------------------------------------------------------- scene changes

' Shows a menu scene, making sure the living backdrop and menu music are on.
sub AppShowMenu(app as object, scene as object)
    if app.bg = invalid
        level = LevelLoad("menu-demo")
        if level <> invalid then app.bg = GameNew(app, level, { replay: level.sol, backdrop: true })
    end if
    app.scene = scene
    app.dirty = 2
    AudioMusic(app.audio, "menu")
end sub

' Starts a stage. opts: { replay: [...] or invalid, viaCode: bool, from: "stages" | "help" }
sub AppStartStage(app as object, id as string, opts as object)
    level = LevelLoad(id)
    if level = invalid
        app.notice = "That stage could not be loaded."
        AppShowMenu(app, MenuMainNew(app))
        return
    end if
    ' the backdrop stage holds biome art and stage bitmaps: release them first
    app.bg = invalid
    app.scene = invalid
    if opts.replay = invalid and not LevelIsLesson(id) then ProgressRecordPlayed(app.progress, id, opts.viaCode = true)
    g = GameNew(app, level, opts)
    app.scene = g
    app.dirty = 2
    AudioMusic(app.audio, level.music)
end sub

' Called by the stage scene when it is over (won, lost, restarted or left).
sub AppOnGameEnd(g as object, result as object)
    app = m
    level = g.level
    id = level.id
    opts = g.opts
    wasReplay = g.replay <> invalid
    if result.restart
        AppStartStage(app, id, { replay: invalid, viaCode: opts.viaCode, from: opts.from })
        return
    end if
    ' free the stage before building menus over a new backdrop
    app.scene = invalid
    if wasReplay
        ' a watched solution always returns to the stage's briefing
        if LevelIsLesson(id)
            AppShowMenu(app, MenuHelpNew(app, id))
        else
            AppShowMenu(app, MenuBriefNew(app, id, opts.viaCode = true))
        end if
        return
    end if
    if result.aborted
        if LevelIsLesson(id)
            AppShowMenu(app, MenuHelpNew(app, id))
        else
            AppShowMenu(app, MenuStagesNew(app, id))
        end if
        return
    end if
    win = invalid
    if result.won and not LevelIsLesson(id)
        win = ProgressRecordWin(app.progress, id, result.saved, result.required, result.total, result.ticks)
    end if
    AppShowMenu(app, MenuResultNew(app, level, result, win, opts))
end sub

' A deep link names a stage by its access code or its id ("meadow-07").
sub AppOpenLink(app as object, contentId as dynamic)
    if not IsStr(contentId) then return
    id = ""
    check = CodeCheck(app.index, contentId)
    if check.ok
        id = check.stageId
    else
        st = app.index.byId[LCase(contentId)]
        if st <> invalid
            if st.order >= 0 then id = st.id
        end if
    end if
    if id = "" then return
    viaCode = not ProgressIsUnlocked(app.progress, id)
    AppShowMenu(app, MenuBriefNew(app, id, viaCode))
end sub

' -------------------------------------------------- shared menu furniture

' Advances and draws the living backdrop (or a plain sky if it is unavailable).
sub AppBackdropUpdate(app as object, dtMs as integer)
    if app.bg <> invalid then app.bg.update(dtMs)
end sub

sub AppBackdropDraw(app as object, scr as object)
    if app.bg <> invalid
        app.bg.draw(scr)
    else
        scr.Clear(&h2c4a3aff)
    end if
end sub

' A row of "key  action" hints along the bottom edge of a menu.
sub AppDrawHints(app as object, scr as object, text as string)
    f = app.fonts.small
    w = f.GetOneLineWidth(text, 1200) + 44
    GfxNine(scr, app.assets.nine["pill.dark"], 640 - w \ 2, 652, w, 38)
    scr.DrawText(text, 640 - w \ 2 + 22, 658, &hfffaf0ff, f)
end sub

' A storybook button: face, optional focus frame, centred label.
sub AppDrawButton(app as object, scr as object, x as integer, y as integer, w as integer, h as integer, label as string, face as string, focused as boolean)
    a = app.assets
    GfxNine(scr, a.nine[face], x, y, w, h)
    if focused then GfxNine(scr, a.nine["focus.nine"], x - 6, y - 6, w + 12, h + 12)
    col = &h3b2a1cff
    if face = "btn.green" or face = "btn.red" then col = &hffffffff
    if face = "btn.locked" then col = &h7d7466ff
    f = app.fonts.bodyB
    scr.DrawText(label, x + (w - f.GetOneLineWidth(label, 1200)) \ 2, y + (h - 7 - f.GetOneLineHeight()) \ 2, col, f)
end sub
