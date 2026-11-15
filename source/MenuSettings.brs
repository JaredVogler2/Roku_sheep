' =============================================================================
' SHEEPFALL for Roku - settings. Every change applies at once and is saved.
' Nothing here changes the rules of a stage except Assisted Mode, which says so.
' =============================================================================

function MenuSettingsNew(app as object) as object
    s = { kind: "settings", app: app, animated: false, update: MenuStaticUpdate, draw: MenuSettingsDraw, onKey: MenuSettingsKey }
    s.rows = [
        { key: "sfx", label: "Sound effects", values: [0, 40, 70, 100], names: ["Off", "Quiet", "Normal", "Loud"], help: "Bleats, bells, shovels and bangs." }
        { key: "music", label: "Music", values: [0, 1], names: ["Off", "On"], help: "A looping tune for each biome." }
        { key: "tutorials", label: "Tutorial cards", values: [0, 1], names: ["Off", "On"], help: "Short tips shown before the stages that introduce something new." }
        { key: "cursor", label: "Cursor speed", values: [0, 1, 2], names: ["Slow", "Normal", "Fast"], help: "How quickly the cursor sweeps while an arrow is held." }
        { key: "minimap", label: "Minimap", values: [0, 1], names: ["Off", "On"], help: "A small map of the whole stage, shown when it is wider than the screen." }
        { key: "effects", label: "Effects", values: [0, 1, 2], names: ["Off", "Reduced", "Full"], help: "Dust, sparkles, shadows and weather. Purely cosmetic." }
        { key: "scenery", label: "Scenery detail", values: [0, 1, 2], names: ["Sky only", "Medium", "Full"], help: "Parallax backdrop layers. Lower it if the picture stutters on an older Roku." }
        { key: "codes", label: "Codes in Stage Select", values: [0, 1], names: ["Beaten stages", "All open stages"], help: "Which stages show their code in Stage Select." }
        { key: "assist", label: "Assisted Mode", values: [0, 1], names: ["Off", "On"], help: "Adds a Rewind button that steps a stage back a few seconds. Not part of the original rules." }
        { key: "reset", label: "Reset campaign progress", values: [0], names: [""], help: "Forgets completed stages and medals. Settings are kept, and stage codes always work." }
    ]
    s.sel = 0
    s.confirmReset = false
    s.note = ""
    return s
end function

function MenuSettingsIndex(row as object, value as integer) as integer
    for i = 0 to row.values.Count() - 1
        if row.values[i] = value then return i
    end for
    return 0
end function

sub MenuSettingsKey(code as integer, pressed as boolean)
    if not pressed then return
    s = m
    app = s.app
    set = app.progress.data.set
    n = s.rows.Count()
    row = s.rows[s.sel]
    if code = 2 or code = 3
        if code = 2
            s.sel = (s.sel + n - 1) mod n
        else
            s.sel = (s.sel + 1) mod n
        end if
        s.confirmReset = false
        s.note = ""
        AudioPlay(app.audio, "ui")
    else if code = 0
        AppShowMenu(app, MenuMainNew(app))
    else if code = 4 or code = 5 or code = 6
        if row.key = "reset"
            if code <> 6 then return
            if s.confirmReset
                ProgressResetCampaign(app.progress)
                s.confirmReset = false
                s.note = "Campaign progress has been reset."
                AudioPlay(app.audio, "pop")
            else
                s.confirmReset = true
                s.note = "Press OK again to erase completed stages and medals."
                AudioPlay(app.audio, "nukearm")
            end if
            return
        end if
        count = row.values.Count()
        i = MenuSettingsIndex(row, set[row.key])
        if code = 4
            if i > 0 then i = i - 1
        else if code = 5
            if i < count - 1 then i = i + 1
        else
            i = (i + 1) mod count
        end if
        set[row.key] = row.values[i]
        ProgressSave(app.progress)
        ' apply at once
        if row.key = "sfx"
            app.audio.sfxVolume = set.sfx
            AudioPlay(app.audio, "bell0")
        else if row.key = "music"
            AudioSetMusicOn(app.audio, set.music = 1)
        else
            AudioPlay(app.audio, "ui")
            if row.key = "effects" or row.key = "scenery"
                ' the living backdrop shows these two: rebuild it with the new choice
                app.bg = invalid
                AppShowMenu(app, s)
            end if
        end if
    end if
end sub

sub MenuSettingsDraw(scr as object)
    s = m
    app = s.app
    a = app.assets
    f = app.fonts
    set = app.progress.data.set
    AppBackdropDraw(app, scr)
    GfxNine(scr, a.nine["panel.cream"], 210, 22, 860, 620)
    ink = MenuInk()
    muted = MenuMuted()
    GfxTextCentered(scr, "Settings", 640, 40, ink, f.head)
    y = 96
    for i = 0 to s.rows.Count() - 1
        row = s.rows[i]
        focused = i = s.sel
        face = "btn.cream"
        if focused then face = "btn.gold"
        if row.key = "reset" then face = "btn.red"
        GfxNine(scr, a.nine[face], 250, y, 780, 46)
        if focused then GfxNine(scr, a.nine["focus.nine"], 244, y - 6, 792, 58)
        col = ink
        if row.key = "reset" then col = &hffffffff
        scr.DrawText(row.label, 272, y + 6, col, f.bodyB)
        if row.key <> "reset"
            idx = MenuSettingsIndex(row, set[row.key])
            value = row.names[idx]
            vw = f.body.GetOneLineWidth(value, 400)
            vx = 1008 - 26 - vw
            scr.DrawText(value, vx, y + 6, ink, f.body)
            if focused
                ' arrows show which way the value can still move
                if idx > 0 then scr.DrawText("<", vx - 26, y + 6, &h8f2d1dff, f.bodyB)
                if idx < row.values.Count() - 1 then scr.DrawText(">", 1008 - 18, y + 6, &h8f2d1dff, f.bodyB)
            end if
        end if
        y = y + 50
    end for
    text = s.rows[s.sel].help
    col = muted
    if s.note <> ""
        text = s.note
        col = &hb3261aff
    end if
    ty = y + 4
    for each ln in GfxWrap(text, f.small, 760)
        GfxTextCentered(scr, ln, 640, ty, col, f.small)
        ty = ty + 24
    end for
    AppDrawHints(app, scr, "Left / Right  Change      Up / Down  Choose      Back  Menu")
end sub
