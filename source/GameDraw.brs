' =============================================================================
' SHEEPFALL for Roku - composing one frame of a stage.
'
' Draw order follows the web renderer: backdrop, decor behind the ground,
' terrain, hazards, sheepfolds, hatch frames, contact shadows, sheep, hatch
' trapdoors, bomber countdowns, particles, decor in front, then the overlays.
'
' Fill-rate is the scarce resource on a small Roku, so:
'   * the far backdrop layer is opaque and drawn with blending off, which also
'     replaces a full-screen clear;
'   * the stage is a few 2x nearest-neighbour blits of pre-painted chunks;
'   * everything that scrolls is culled to the visible world range;
'   * sheep are single blits from a pre-mirrored atlas (no per-sprite scaling).
'
' World pixel (x, y) maps to screen (x * 2 - camPx, y * 2).
' =============================================================================

sub GameDraw(scr as object)
    g = m
    a = g.app.assets
    sim = g.sim
    camPx = g.camPx
    level = g.level
    animMs = g.animMs
    tick = sim.tick
    x0 = camPx \ 2 - 40
    x1 = camPx \ 2 + 680

    ' ---- backdrop
    layers = g.biome.layers
    far = layers[0]
    scr.SetAlphaEnable(false)
    ox = -(Int(camPx * far.factor) mod 2048)
    scr.DrawScaledObject(ox, 0, 2.0, 2.0, far.reg)
    if ox + 2048 < 1280 then scr.DrawScaledObject(ox + 2048, 0, 2.0, 2.0, far.reg)
    scr.SetAlphaEnable(true)
    for li = 1 to g.scenery
        l = layers[li]
        ox = -(Int(camPx * l.factor) mod 2048)
        scr.DrawScaledObject(ox, l.top * 2, 2.0, 2.0, l.reg)
        if ox + 2048 < 1280 then scr.DrawScaledObject(ox + 2048, l.top * 2, 2.0, 2.0, l.reg)
    end for

    ' ---- decor behind the ground
    decor = g.decor
    for each d in decor
        if not d.front and d.x > x0 - 60 and d.x < x1 + 60 then GameDrawDecor(scr, d, camPx, animMs)
    end for

    ' ---- the stage itself
    TpDraw(g.tp, scr, camPx, 1280)

    ' ---- hazards, sheepfolds, hatch frames
    for each z in g.hazards
        if z.x + z.w > x0 and z.x < x1 then GameDrawHazard(g, scr, z, camPx, tick, animMs)
    end for
    bspr = g.biome.spr
    boff = g.biome.off
    key = "exit." + ((animMs \ 714) mod g.biome.exitFrames).ToStr()
    reg = bspr[key]
    o = boff[key]
    for each e in level.exits
        if e[0] > x0 - 30 and e[0] < x1 + 30 then scr.DrawObject(e[0] * 2 - camPx + o[0], e[1] * 2 + o[1], reg)
    end for
    for each e in level.ent
        if e[0] > x0 - 30 and e[0] < x1 + 30
            key = "hatch.r"
            if e[2] < 0 then key = "hatch.l"
            o = boff[key]
            scr.DrawObject(e[0] * 2 - camPx + o[0], e[1] * 2 + o[1], bspr[key])
        end if
    end for

    ' ---- sheep
    GameDrawSheep(g, scr, a, camPx, x0, x1)

    ' ---- hatch trapdoors over the sheep, so a new sheep drops out of the box
    last = g.biome.doorSteps - 1
    for each e in level.ent
        if e[0] > x0 - 30 and e[0] < x1 + 30
            open = (tick - e[4]) / 17.0
            if open < 0 then open = 0
            if open > 1 then open = 1
            key = "doors." + Int(open * last + 0.5).ToStr()
            if bspr[key] <> invalid
                o = boff[key]
                scr.DrawObject(e[0] * 2 - camPx + o[0], e[1] * 2 + o[1], bspr[key])
            end if
        end if
    end for

    ParticlesDraw(g.particles, scr, camPx)

    for each d in decor
        if d.front and d.x > x0 - 60 and d.x < x1 + 60 then GameDrawDecor(scr, d, camPx, animMs)
    end for

    if g.backdrop
        ' the menu sits on top: dim the scene a little, and close off the strip
        ' under the playfield where a stage would show its toolbar
        scr.DrawRect(0, 0, 1280, 640, &h0a120c70)
        scr.DrawRect(0, 640, 1280, 80, &h161e1aff)
        scr.DrawRect(0, 640, 1280, 2, &h3f5146ff)
        return
    end if

    GameDrawOverlays(g, scr, a)
    HudRender(g.hud, g)
    HudDraw(g.hud, g, scr)
    if g.modal <> invalid then GameDrawModal(g, scr, a)
end sub

sub GameDrawDecor(scr as object, d as object, camPx as integer, animMs as integer)
    f = 0
    n = d.frames.Count()
    if n > 1 then f = (animMs \ d.ms) mod n
    o = d.offs[f]
    if d.s = 1
        scr.DrawObject(d.x * 2 - camPx + o[0], d.y * 2 + o[1], d.frames[f])
    else
        scr.DrawScaledObject(d.x * 2 - camPx + Int(o[0] * d.s), d.y * 2 + Int(o[1] * d.s), d.s + 0.0, d.s + 0.0, d.frames[f])
    end if
end sub

sub GameDrawSheep(g as object, scr as object, a as object, camPx as integer, x0 as integer, x1 as integer)
    sim = g.sim
    frames = a.sheepFrames
    spr = a.spr
    alpha = g.alpha
    anim5 = g.animMs \ 200
    animOf = g.animOf
    shadow = spr["shadow"]
    targetId = g.targetId
    ' contact shadows first, so no sheep is ever under another sheep's shadow
    if g.particles.level > 0
        for each s in sim.sheep
            if s.fate = 0 and s.x > x0 and s.x < x1
                st = s.state
                if st = 1 or (st >= 5 and st <= 11)
                    scr.DrawObject(Int((s.px + (s.x - s.px) * alpha) * 2) - camPx - 12, Int((s.py + (s.y - s.py) * alpha) * 2) - 2, shadow)
                end if
            end if
        end for
    end if
    for each s in sim.sheep
        st = s.state
        if st <> 18 and s.x > x0 and s.x < x1
            ' position, interpolated between the last two ticks unless the sheep jumped
            ddx = s.x - s.px
            ddy = s.y - s.py
            if ddx > 6 or ddx < -6 or ddy > 6 or ddy < -6
                sx = s.x * 2 - camPx
                sy = s.y * 2
            else
                sx = Int((s.px + ddx * alpha) * 2) - camPx
                sy = Int((s.py + ddy * alpha) * 2)
            end if
            if st <= 12
                variant = 0
                if s.canClimb then variant = 1
                if s.canFloat then variant = variant + 2
                t = s.stateTicks
                if st = 1
                    f = s.x and 7
                else if st = 0
                    f = t mod 2
                else if st = 4
                    f = anim5 mod 4
                else if st = 2
                    f = t mod 8
                else if st = 3
                    f = t
                    if f > 5 then f = 5
                else if st = 5
                    f = anim5 mod 6
                else if st = 6
                    f = t mod 16
                else if st = 7
                    f = anim5 mod 4
                else if st = 8
                    f = (t + 3) mod 8
                else if st = 9
                    f = (t + 5) mod 10
                else if st = 10 or st = 11
                    f = t mod 4
                else
                    f = (t * 6) \ 10
                    if f > 5 then f = 5
                end if
                fr = frames[animOf[st]][variant][f]
                if s.id = targetId
                    ' ring centred on the body: gold with reticle ticks when the skill in hand can be given
                    name = "ring.grey"
                    if g.targetOk then name = "ring.gold"
                    ro = a.off[name]
                    scr.DrawObject(sx + ro[0], sy - 14 + ro[1], spr[name])
                end if
                if st = 12
                    ' walking into the fold: fade out
                    fade = 255 - t * 25
                    if fade < 0 then fade = 0
                    if s.dir > 0
                        scr.DrawScaledObject(sx + fr[1], sy + fr[2], 1.0, 1.0, fr[0], &hffffff00 or fade)
                    else
                        scr.DrawScaledObject(sx + fr[4], sy + fr[2], 1.0, 1.0, fr[3], &hffffff00 or fade)
                    end if
                else
                    if s.dir > 0
                        scr.DrawObject(sx + fr[1], sy + fr[2], fr[0])
                    else
                        scr.DrawObject(sx + fr[4], sy + fr[2], fr[3])
                    end if
                    bt = s.bomberTicks
                    if bt > 0
                        ' fizzing fuse spark and the countdown above the head
                        col = &hffd25eff
                        if (g.animMs \ 80) mod 2 = 0 then col = &hff6a1aff
                        scr.DrawRect(sx - s.dir * 4 - 1, sy - 27, 3, 3, col)
                        scr.DrawObject(sx - 9, sy - 58, spr["digit." + ((bt + 16) \ 17).ToStr()])
                    end if
                end if
            else if st = 13 or st = 17
                ' splat / crushed: a flat wool pancake that fades
                fade = 255 - s.stateTicks * 18
                if fade > 0 then scr.DrawScaledObject(sx - 17, sy - 9, 1.0, 1.0, spr["splat"], &hffffff00 or fade)
            else if st = 14
                ' drowning: sinks and fades
                fade = 255 - s.stateTicks * 14
                fr = frames[1][0][0]
                if fade > 0
                    if s.dir > 0
                        scr.DrawScaledObject(sx + fr[1], sy + fr[2] + s.stateTicks, 1.0, 1.0, fr[0], &hffffff00 or fade)
                    else
                        scr.DrawScaledObject(sx + fr[4], sy + fr[2] + s.stateTicks, 1.0, 1.0, fr[3], &hffffff00 or fade)
                    end if
                end if
            else if st = 15
                ' burning: a sooty "oh no" that fades
                fade = 255 - s.stateTicks * 15
                fr = frames[11][0][s.stateTicks mod 4]
                if fade > 0
                    if s.dir > 0
                        scr.DrawScaledObject(sx + fr[1], sy + fr[2], 1.0, 1.0, fr[0], &h4a444a00 or fade)
                    else
                        scr.DrawScaledObject(sx + fr[4], sy + fr[2], 1.0, 1.0, fr[3], &h4a444a00 or fade)
                    end if
                end if
            end if
        end if
    end for
end sub

' ------------------------------------------------------------------ hazards

' Ticks until a periodic hazard next turns lethal (0 if lethal now).
function GameHazardWait(z as object, tick as integer) as integer
    if z.period <= 0 then return 0
    ph = (((tick + z.offset) mod z.period) + z.period) mod z.period
    if ph < z.phase then return 0
    return z.period - ph
end function

' A horizontally tiled strip from the shared atlas, cut to `w` pixels.
sub GameDrawStrip(g as object, scr as object, name as string, x as integer, y as integer, w as integer, h as integer, scaleY as float)
    a = g.app.assets
    r = a.art.common.sprites[name]
    tw = r[2]
    th = r[3]
    if h > th then h = th
    full = a.spr[name]
    cx = x
    while w > 0
        if cx + tw > 0 and cx < 1280
            if w >= tw and h = th
                reg = full
            else
                ' a cut piece of the strip: made once, then kept for the rest of the stage
                pw = w
                if pw > tw then pw = tw
                key = name + "/" + pw.ToStr() + "/" + h.ToStr()
                reg = g.strips[key]
                if reg = invalid
                    reg = CreateObject("roRegion", a.commonBmp, r[0], r[1], pw, h)
                    g.strips[key] = reg
                end if
            end if
            if scaleY = 1.0
                scr.DrawObject(cx, y, reg)
            else
                scr.DrawScaledObject(cx, y, 1.0, scaleY, reg)
            end if
        end if
        cx = cx + tw
        w = w - tw
    end while
end sub

sub GameDrawHazard(g as object, scr as object, z as object, camPx as integer, tick as integer, animMs as integer)
    x = z.x * 2 - camPx
    y = z.y * 2
    w = z.w * 2
    h = z.h * 2
    wait = GameHazardWait(z, tick)
    isOn = wait = 0
    soon = wait > 0 and wait < 20
    kind = z.kind
    if kind = "water"
        ' periodic water that is not lethal right now has drained to a low pool
        top = y
        if z.period > 0 and not isOn
            scr.DrawRect(x, y, w, 2, &hc8ecff50)
            if z.below and not soon
                scr.DrawRect(x, y, w, h, &h283c5030)
                return
            end if
            if soon
                top = y + Int(h * 0.45)
            else
                top = y + Int(h * 0.78)
            end if
            scr.DrawRect(x, y, w, top - y, &h283c5030)
        end if
        depth = y + h - top
        GameDrawStrip(g, scr, "water." + ((animMs \ 300) mod 8).ToStr(), x, top, w, depth, 1.0)
        ' body: light at the surface, deep blue below
        body = depth - 14
        if body > 0
            cols = [&h60bef0e2, &h4a9ad8e8, &h2e78c4ee, &h245ca8f2, &h183c84f6, &h0e2860f8]
            n = 6
            if body < 36 then n = 3
            band = body \ n
            by = top + 14
            for i = 0 to n - 1
                bh = band
                if i = n - 1 then bh = y + h - by
                ci = i
                if n = 3 then ci = i * 2
                scr.DrawRect(x, by, w, bh, cols[ci])
                by = by + bh
            end for
        end if
    else if kind = "lava"
        ' heat haze above the pool
        scr.DrawRect(x, y - 32, w, 12, &hff8c3210)
        scr.DrawRect(x, y - 20, w, 10, &hff8c3224)
        scr.DrawRect(x, y - 10, w, 12, &hff8c3240)
        GameDrawStrip(g, scr, "lava." + ((animMs \ 220) mod 4).ToStr(), x, y, w, h, 1.0)
        body = h - 16
        if body > 0
            scr.DrawRect(x, y + 16, w, body \ 2, &hf05a14ff)
            scr.DrawRect(x, y + 16 + body \ 2, w, body - body \ 2, &h9a2408ff)
        end if
    else if kind = "fire" or kind = "steam" or kind = "lightning"
        base = &h5b4a3cff
        if kind = "lightning" then base = &h4a5260ff
        scr.DrawRect(x - 2, y + h - 6, w + 4, 6, base)
        if kind = "lightning"
            scr.DrawRect(x + w \ 2 - 2, y - 12, 4, 12, &h9aa4b2ff)
            scr.DrawRect(x + w \ 2 - 3, y - 18, 6, 6, &hffd25eff)
        end if
        if soon
            ' a quick warning flicker just before it fires
            if (animMs \ 90) mod 2 = 0
                col = &hff783c50
                if kind = "steam" then col = &hfff03c50
                scr.DrawRect(x, y, w, h, col)
            end if
        end if
        if isOn
            if kind = "fire"
                scr.DrawRect(x - 12, y - 8, w + 24, h + 8, &hff961e1c)
                GameDrawStrip(g, scr, "fire." + ((animMs \ 90) mod 6).ToStr(), x, y, w, 80, h / 80.0)
            else if kind = "steam"
                puff = g.app.assets.spr["p.steam"]
                for i = 0 to 5
                    py = y + h - ((animMs * 6 \ 100 + i * 18) mod h)
                    px = x + w \ 2 + Int(Sin(i + animMs / 200.0) * w * 0.3)
                    scr.DrawObject(px - 13, py - 13, puff)
                end for
            else
                lx = x + w \ 2
                ly = y
                seed = animMs \ 83
                while ly < y + h
                    nx = x + w \ 2 + Int(Sin(ly * 1.55 + seed) * w * 0.35)
                    scr.DrawLine(lx, ly, nx, ly + 8, &hfff6c8ff)
                    scr.DrawLine(lx + 1, ly, nx + 1, ly + 8, &hfff6c8ff)
                    scr.DrawLine(lx - 1, ly, nx - 1, ly + 8, &hffffffa0)
                    lx = nx
                    ly = ly + 8
                end while
            end if
        end if
    else if kind = "spikes"
        GameDrawStrip(g, scr, "spikes", x, y, w, 24, h / 24.0)
    else if kind = "crush"
        ' iron press on chains: raised while safe, trembles just before, slammed while lethal
        by = y - 24
        if isOn
            by = y + h - 20
        else if soon
            by = by + ((animMs \ 40) mod 3) - 1
        end if
        chainLen = by - (y - 80)
        if chainLen > 0
            chain = g.app.assets.spr["chain"]
            scr.DrawScaledObject(x + 2, y - 80, 1.0, chainLen / 128.0, chain)
            scr.DrawScaledObject(x + w - 8, y - 80, 1.0, chainLen / 128.0, chain)
        end if
        scr.DrawRect(x - 3, by - 1, w + 6, 22, &h1e2126ff)
        if soon
            scr.DrawRect(x - 2, by, w + 4, 10, &he0644cff)
            scr.DrawRect(x - 2, by + 10, w + 4, 10, &h8f2d1dff)
        else
            scr.DrawRect(x - 2, by, w + 4, 10, &h9aa3adff)
            scr.DrawRect(x - 2, by + 10, w + 4, 10, &h4a5260ff)
        end if
        scr.DrawRect(x - 2, by, w + 4, 2, &hffffff5a)
        sx = x
        while sx < x + w
            scr.DrawRect(sx, by + 15, 4, 5, &hffd25eff)
            sx = sx + 8
        end while
    else if kind = "pit"
        band = h \ 5
        if band > 0
            alphas = [&h00000018, &h00000048, &h00000080, &h000000b0, &h000000d8]
            for i = 0 to 4
                bh = band
                if i = 4 then bh = h - 4 * band
                scr.DrawRect(x, y + i * band, w, bh, alphas[i])
            end for
        end if
    end if
end sub

' ----------------------------------------------------------------- overlays

sub GameDrawOverlays(g as object, scr as object, a as object)
    f = g.app.fonts
    sim = g.sim
    level = g.level
    camPx = g.camPx

    ' ---- minimap (only when the stage is wider than the screen)
    if g.showMinimap and g.maxCam > 0
        tp = g.tp
        ms = 1
        if tp.miniW * 2 <= 400 then ms = 2
        mw = tp.miniW * ms
        mh = tp.miniH * ms
        mx = 1232 - mw
        my = 34
        scr.DrawRect(mx - 3, my - 3, mw + 6, mh + 6, &h0c110ed0)
        scr.SetAlphaEnable(false)
        if ms = 1
            scr.DrawObject(mx, my, tp.mini)
        else
            scr.DrawScaledObject(mx, my, 2.0, 2.0, tp.mini)
        end if
        scr.SetAlphaEnable(true)
        k = ms / 8.0
        for each z in g.hazards
            col = &ha0302aff
            if GameHazardWait(z, sim.tick) = 0 then col = &hff4a3aff
            zw = Int(z.w * k)
            zh = Int(z.h * k)
            if zw < 1 then zw = 1
            if zh < 1 then zh = 1
            scr.DrawRect(mx + Int(z.x * k), my + Int(z.y * k), zw, zh, col)
        end for
        for each e in level.ent
            scr.DrawRect(mx + Int(e[0] * k) - 2, my + Int(e[1] * k) - 3, 4, 3, &hffd25eff)
        end for
        for each e in level.exits
            scr.DrawRect(mx + Int(e[0] * k) - 2, my + Int(e[1] * k) - 4, 4, 4, &h5dff7aff)
        end for
        for each s in sim.sheep
            if s.fate = 0 then scr.DrawRect(mx + Int(s.x * k), my + Int((s.y - 4) * k), 2, 2, &hffffffff)
        end for
        ' the part of the stage on screen
        vx = mx + Int(camPx / 2.0 * k)
        vw = Int(640 * k)
        GfxFrame(scr, vx, my - 1, vw, mh + 2, 1, &hffffffff)
    end if

    ' ---- stage title for the first seconds
    if g.titleMs > 0
        label = level.title
        if not g.lesson then label = LevelStageLabel(level.id) + " - " + level.title
        if g.replay <> invalid then label = "Replay - " + level.title
        w = f.body.GetOneLineWidth(label, 1200) + 36
        GfxNine(scr, a.nine["pill.dark"], 48, 34, w, 44)
        scr.DrawText(label, 66, 42, &hfffaf0ff, f.body)
    end if

    isReplay = g.replay <> invalid
    ' ---- cursor
    if not isReplay and g.focusTool < 0 and sim.phase = 0
        ' an open crosshair; over a sheep the ring does the pointing and the cursor shrinks to a bead
        name = "cursor.idle"
        if g.targetId >= 0 then name = "cursor.hot"
        AssetsDraw(scr, a, name, Int(g.curX * 2) - camPx, Int(g.curY * 2))
    end if

    ' ---- info line: the tool in hand and the sheep under the cursor
    if not isReplay
        text = "No skills on this stage"
        if g.anySkills then text = "No skill selected"
        if g.selected >= 0 then text = SimSkillLabels()[g.selected] + "  x" + sim.stock[g.selected].ToStr()
        if g.targetId >= 0 and g.targetId < sim.sheep.Count()
            text = text + "   >   #" + (g.targetId + 1).ToStr() + " " + GameDescribeSheep(sim.sheep[g.targetId])
        end if
        tx = 66
        if g.selected >= 0 then tx = 96
        w = f.small.GetOneLineWidth(text, 1200) + tx - 48 + 20
        GfxNine(scr, a.nine["pill.dark"], 48, 596, w, 38)
        if g.selected >= 0 then scr.DrawObject(58, 601, a.spr["skillsm." + g.selected.ToStr()])
        scr.DrawText(text, tx, 602, &hfffaf0ff, f.small)
    end if

    ' ---- pause banner, toast
    if g.paused and g.modal = invalid
        GfxTextShadow(scr, "PAUSED", 640 - f.title.GetOneLineWidth("PAUSED", 800) \ 2, 250, &hfff8e7ff, f.title)
        hint = "Play/Pause resumes. You can still aim and press OK."
        if isReplay then hint = "Play/Pause resumes."
        GfxTextShadow(scr, hint, 640 - f.small.GetOneLineWidth(hint, 1200) \ 2, 306, &hfff8e7ff, f.small)
    end if
    if g.toastMs > 0 and g.toast <> ""
        w = f.body.GetOneLineWidth(g.toast, 1200) + 44
        name = "pill.dark"
        if g.toastBad then name = "pill.red"
        GfxNine(scr, a.nine[name], 640 - w \ 2, 540, w, 46)
        scr.DrawText(g.toast, 640 - w \ 2 + 22, 549, &hffffffff, f.body)
    end if
end sub

sub GameDrawModal(g as object, scr as object, a as object)
    f = g.app.fonts
    md = g.modal
    scr.DrawRect(0, 0, 1280, 640, &h0a120c80)
    if md.kind = "tutorial"
        lines = GfxWrap(g.level.tut[md.page], f.body, 760)
        lh = f.body.GetOneLineHeight() + 6
        h = lines.Count() * lh + 108
        y = 120
        GfxNine(scr, a.nine["panel.cream"], 220, y, 840, h)
        ty = y + 28
        for each ln in lines
            scr.DrawText(ln, 260, ty, &h3b2a1cff, f.body)
            ty = ty + lh
        end for
        last = md.page >= g.level.tut.Count() - 1
        label = "OK   Next"
        if last then label = "OK   Got it"
        bw = f.bodyB.GetOneLineWidth(label, 600) + 56
        GfxNine(scr, a.nine["btn.green"], 1020 - bw, ty + 10, bw, 50)
        GfxNine(scr, a.nine["focus.nine"], 1020 - bw - 5, ty + 5, bw + 10, 60)
        scr.DrawText(label, 1020 - bw + 28, ty + 20, &hffffffff, f.bodyB)
        page = (md.page + 1).ToStr() + " / " + g.level.tut.Count().ToStr()
        scr.DrawText(page, 260, ty + 22, &h6b5440ff, f.small)
        return
    end if
    ' pause menu
    n = md.items.Count()
    h = 150 + n * 62
    y = (640 - h) \ 2
    GfxNine(scr, a.nine["panel.cream"], 400, y, 480, h)
    GfxTextCentered(scr, "Paused", 640, y + 22, &h3b2a1cff, f.head)
    sub1 = g.level.title + " - rescue " + g.sim.required.ToStr() + " of " + g.sim.total.ToStr()
    GfxTextCentered(scr, GfxFit(sub1, f.small, 430), 640, y + 68, &h6b5440ff, f.small)
    by = y + 108
    for i = 0 to n - 1
        face = "btn.cream"
        col = &h3b2a1cff
        if md.items[i] = "Quit to menu" or md.items[i] = "Stop watching"
            face = "btn.red"
            col = &hffffffff
        else if i = 0
            face = "btn.green"
            col = &hffffffff
        end if
        GfxNine(scr, a.nine[face], 450, by, 380, 52)
        if i = md.sel then GfxNine(scr, a.nine["focus.nine"], 445, by - 5, 390, 62)
        GfxTextCentered(scr, md.items[i], 640, by + 11, col, f.bodyB)
        by = by + 62
    end for
end sub
