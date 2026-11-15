' =============================================================================
' SHEEPFALL for Roku - the in-game HUD bar.
'
' One bar under the playfield holds everything the web game spreads over a top
' bar and a bottom toolbar: honest counters (saved / required, time, out, in
' the hatch, lost), the release rate, the eight skills with their stock, and
' pause / speed / rewind / finish / nuke / menu.
'
' Text is the expensive thing to draw from BrightScript, so the bar is painted
' into an off-screen bitmap only when one of its numbers changes (about once a
' second) and copied to the screen each frame with one opaque blit. The focus
' frame is drawn on top separately, so moving focus costs nothing.
'
' Layout (1280 x 720): the bar is y 640..719, but everything that matters sits
' inside x 44..1236, y 644..703 - the action-safe area of a TV that overscans.
' =============================================================================

function HudNew(g as object) as object
    hud = {
        bmp: CreateObject("roBitmap", { width: 1280, height: 80, AlphaEnable: true })
        last: []
        tools: []
        finishShown: false
        valid: false
    }
    HudLayout(hud, g, false)
    return hud
end function

' Builds the list of focusable tools, left to right.
sub HudLayout(hud as object, g as object, finishShown as boolean)
    tools = []
    isReplay = g.replay <> invalid
    if not isReplay
        tools.Push({ id: "slower", kind: "rate", x: 344, w: 36, skill: -1 })
        tools.Push({ id: "faster", kind: "rate", x: 424, w: 36, skill: -1 })
        for i = 0 to 7
            tools.Push({ id: "skill", kind: "skill", x: 468 + i * 58, w: 56, skill: i })
        end for
    end if
    ctl = ["pause", "speed"]
    if not isReplay
        if g.assist then ctl.Push("rewind")
        if finishShown then ctl.Push("finish")
        ctl.Push("nuke")
    end if
    ctl.Push("menu")
    x = 1236 - ctl.Count() * 48 + 2
    for each id in ctl
        tools.Push({ id: id, kind: "ctl", x: x, w: 46, skill: -1 })
        x = x + 48
    end for
    hud.tools = tools
    hud.finishShown = finishShown
    hud.valid = false
end sub

function HudFindTool(hud as object, id as string, skill as integer) as integer
    for i = 0 to hud.tools.Count() - 1
        t = hud.tools[i]
        if t.id = id and t.skill = skill then return i
    end for
    return -1
end function

' Repaints the bar if anything it shows has changed.
sub HudRender(hud as object, g as object)
    sim = g.sim
    finishOk = sim.saved >= sim.required and sim.phase = 0 and g.replay = invalid
    if finishOk <> hud.finishShown
        focusId = ""
        focusSkill = -1
        if g.focusTool >= 0 and g.focusTool < hud.tools.Count()
            focusId = hud.tools[g.focusTool].id
            focusSkill = hud.tools[g.focusTool].skill
        end if
        HudLayout(hud, g, finishOk)
        if focusId <> ""
            g.focusTool = HudFindTool(hud, focusId, focusSkill)
            if g.focusTool < 0 then g.focusTool = HudFindTool(hud, "pause", -1)
        end if
    end if
    paused = 0
    if g.paused then paused = 1
    armed = 0
    if g.nukeArmedMs > 0 then armed = 1 + (g.nukeArmedMs \ 250) mod 2
    vals = [sim.active, sim.waiting, sim.saved, sim.lost, (sim.timeLeft + 16) \ 17, sim.releaseRate, g.selected, paused, g.speedIndex, armed, sim.phase]
    for each n in sim.stock
        vals.Push(n)
    end for
    same = hud.valid and hud.last.Count() = vals.Count()
    if same
        for i = 0 to vals.Count() - 1
            if vals[i] <> hud.last[i]
                same = false
                exit for
            end if
        end for
    end if
    if same then return
    hud.last = vals
    hud.valid = true

    a = g.app.assets
    f = g.app.fonts
    bmp = hud.bmp
    bmp.Clear(&h161e1aff)
    bmp.DrawRect(0, 0, 1280, 2, &h3f5146ff)
    bmp.DrawRect(0, 2, 1280, 1, &h0c110eff)

    ' ---- counters. Row 1: the goal and the clock. Row 2: where the rest of the flock is.
    cream = &hfffaf0ff
    muted = &h9fb3a6ff
    savedCol = cream
    if sim.saved >= sim.required
        savedCol = &h9be37fff
    else if sim.saved + sim.active + sim.waiting < sim.required
        savedCol = &hff8a73ff
    end if
    clockCol = cream
    if sim.timeLeft < 30 * 17 then clockCol = &hff8a73ff
    x = 46
    bmp.DrawText("SAVED", x, 14, muted, f.tiny)
    x = x + f.tiny.GetOneLineWidth("SAVED", 400) + 7
    txt = sim.saved.ToStr() + "/" + sim.required.ToStr()
    bmp.DrawText(txt, x, 3, savedCol, f.big)
    x = x + f.big.GetOneLineWidth(txt, 400)
    txt = ClockText(sim.timeLeft)
    cx = 334 - f.big.GetOneLineWidth(txt, 400)
    bmp.DrawText(txt, cx, 3, clockCol, f.big)
    lw = f.tiny.GetOneLineWidth("TIME", 400)
    if cx - lw - 7 > x + 8 then bmp.DrawText("TIME", cx - lw - 7, 14, muted, f.tiny)
    x = 46
    x = HudStat(bmp, f, x, "OUT", sim.active, cream, muted)
    x = HudStat(bmp, f, x, "HATCH", sim.waiting, cream, muted)
    lostCol = cream
    if sim.lost > 0 then lostCol = &hffb7a6ff
    x = HudStat(bmp, f, x, "LOST", sim.lost, lostCol, muted)

    ' ---- tools
    spr = a.spr
    ink = &h3b2a1cff
    for each t in hud.tools
        x = t.x
        if t.kind = "skill"
            i = t.skill
            n = sim.stock[i]
            face = "tool.skill.normal"
            if i = g.selected
                face = "tool.skill.selected"
            else if n <= 0
                face = "tool.skill.empty"
            end if
            bmp.DrawObject(x, 4, spr[face])
            icon = spr["skill." + i.ToStr()]
            col = ink
            if n > 0
                bmp.DrawObject(x + 12, 8, icon)
            else
                bmp.DrawScaledObject(x + 12, 8, 1.0, 1.0, icon, &hffffff66)
                col = &h8d8474ff
            end if
            txt = Pad2(n)
            bmp.DrawText(txt, x + 28 - f.count.GetOneLineWidth(txt, 200) \ 2, 37, col, f.count)
        else if t.kind = "rate"
            bmp.DrawObject(x, 4, spr["tool.rate.normal"])
            icon = "ui.minus"
            if t.id = "faster" then icon = "ui.plus"
            bmp.DrawObject(x + 3, 17, spr[icon])
        else
            face = "tool.ctl.normal"
            icon = "ui." + t.id
            label = ""
            if t.id = "pause"
                if g.paused
                    face = "tool.ctl.active"
                    icon = "ui.play"
                end if
            else if t.id = "speed"
                icon = "ui.fast"
                label = g.speedLabel
                if g.speedIndex <> 0 then face = "tool.ctl.active"
            else if t.id = "nuke"
                face = "tool.ctl.nuke"
                if armed = 1 then face = "tool.ctl.armed"
            end if
            bmp.DrawObject(x, 4, spr[face])
            if label = ""
                bmp.DrawObject(x + 8, 17, spr[icon])
            else
                bmp.DrawObject(x + 8, 7, spr[icon])
                bmp.DrawText(label, x + 23 - f.tiny.GetOneLineWidth(label, 200) \ 2, 37, ink, f.tiny)
            end if
        end if
    end for

    ' ---- release rate read-out between its two buttons
    if g.replay = invalid
        bmp.DrawText("RATE", 402 - f.tiny.GetOneLineWidth("RATE", 200) \ 2, 8, muted, f.tiny)
        txt = Pad2(sim.releaseRate)
        bmp.DrawText(txt, 402 - f.big.GetOneLineWidth(txt, 200) \ 2, 25, cream, f.big)
    else
        bmp.DrawText("REPLAY", 344, 8, muted, f.tiny)
        bmp.DrawText(GfxFit(g.level.title, f.body, 520), 344, 27, cream, f.body)
    end if
    bmp.Finish()
end sub

' "LABEL 12" on the second row; returns the x where the next one starts.
function HudStat(bmp as object, f as object, x as integer, label as string, value as integer, color as integer, muted as integer) as integer
    bmp.DrawText(label, x, 43, muted, f.tiny)
    x = x + f.tiny.GetOneLineWidth(label, 400) + 5
    txt = value.ToStr()
    bmp.DrawText(txt, x, 38, color, f.count)
    return x + f.count.GetOneLineWidth(txt, 400) + 13
end function

' Copies the bar to the screen and draws the focus frame over the focused tool.
sub HudDraw(hud as object, g as object, scr as object)
    scr.SetAlphaEnable(false)
    scr.DrawObject(0, 640, hud.bmp)
    scr.SetAlphaEnable(true)
    if g.focusTool >= 0 and g.focusTool < hud.tools.Count()
        t = hud.tools[g.focusTool]
        name = "focus.ctl"
        if t.kind = "skill" then name = "focus.skill"
        if t.kind = "rate" then name = "focus.rate"
        AssetsDraw(scr, g.app.assets, name, t.x, 644)
    end if
end sub
