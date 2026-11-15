' =============================================================================
' SHEEPFALL for Roku - cosmetic particles: debris, wool puffs, sparkles, weather.
'
' They never touch the simulation. The web game allows 900 particles; a Roku
' pays for every draw call from BrightScript, so this system is capped (64 at
' full effects, 24 reduced) and bursts are proportionally smaller.
'
' Positions are world pixels, speeds world pixels per second.
'   kind 0 square (colour)    1 sprite (fades by swapping to nothing at the end)
'        2 rain streak        3 snow / mote
' =============================================================================

function ParticlesNew(biomeName as string, level as integer, colors as object) as object
    ps = {
        list: []
        biome: biomeName
        level: level          ' 0 off, 1 reduced, 2 full
        cap: 64
        weatherAcc: 0.0
        debris: []
    }
    if level = 1 then ps.cap = 24
    for each c in colors.debris
        ps.debris.Push(GfxHex(c))
    end for
    return ps
end function

sub ParticlesAdd(ps as object, kind as integer, x as float, y as float, vx as float, vy as float, life as float, grav as float, size as integer, color as integer, sprite as dynamic)
    if ps.list.Count() >= ps.cap then ps.list.Shift()
    ps.list.Push({ k: kind, x: x, y: y, vx: vx, vy: vy, life: life, max: life, g: grav, size: size, color: color, sprite: sprite })
end sub

' n particles thrown outward from (x, y).
sub ParticlesBurst(ps as object, kind as integer, x as float, y as float, n as integer, speed as float, life as float, grav as float, up as float, size as integer, color as integer, sprite as dynamic)
    if ps.level = 0 then return
    if ps.level = 1 then n = (n + 2) \ 3
    for i = 1 to n
        ang = Rnd(0) * 6.2832
        v = speed * (0.3 + Rnd(0) * 0.7)
        ParticlesAdd(ps, kind, x, y, Cos(ang) * v, Sin(ang) * v - up, life * (0.6 + Rnd(0) * 0.6), grav, size, color, sprite)
    end for
end sub

sub ParticlesOnEvents(ps as object, events as object, spr as object)
    if ps.level = 0 then return
    for each e in events
        k = e.k
        if k = 6
            ' excavate: a few chips of whatever was dug
            n = 2 + e.cells \ 16
            if n > 5 then n = 5
            dy = 4
            if e.kind = 2 then dy = 0
            ParticlesBurst(ps, 0, e.x + e.dir * 3, e.y - dy, n, 40.0, 0.7, 120.0, 25.0, 2, ps.debris[e.mat], invalid)
        else if k = 5
            ParticlesBurst(ps, 0, e.x + 3, e.y, 2, 10.0, 0.5, -5.0, 0.0, 2, &hfff0d2c8, invalid)
        else if k = 9
            ParticlesBurst(ps, 1, e.x, e.y - 5, 7, 30.0, 0.9, -10.0, 0.0, 0, 0, spr["p.puff"])
            ParticlesBurst(ps, 0, e.x, e.y - 5, 4, 70.0, 1.2, 90.0, 40.0, 3, &hff7aa8ff, invalid)
            ParticlesBurst(ps, 0, e.x, e.y - 5, 4, 70.0, 1.2, 90.0, 40.0, 3, &hffd25eff, invalid)
            ParticlesBurst(ps, 0, e.x, e.y - 5, 3, 70.0, 1.2, 90.0, 40.0, 3, &h7cc3eaff, invalid)
            ParticlesBurst(ps, 0, e.x, e.y - 3, 5, 60.0, 0.9, 140.0, 40.0, 2, ps.debris[1], invalid)
        else if k = 10
            ParticlesBurst(ps, 1, e.x, e.y - 8, 3, 25.0, 0.8, -20.0, 0.0, 0, 0, spr["p.star"])
            ParticlesAdd(ps, 1, e.x, e.y - 12, 0.0, -14.0, 1.0, 0.0, 0, 0, spr["p.heart"])
        else if k = 11
            if e.cause = 1
                ParticlesBurst(ps, 1, e.x, e.y - 3, 4, 8.0, 1.2, -30.0, 0.0, 0, 0, spr["p.bubble"])
            else if e.cause = 2
                ParticlesBurst(ps, 1, e.x, e.y - 6, 5, 12.0, 1.3, -25.0, 0.0, 0, 0, spr["p.smoke"])
            else if e.cause = 0 or e.cause = 3 or e.cause = 4
                ParticlesBurst(ps, 1, e.x, e.y - 3, 5, 22.0, 0.8, -6.0, 0.0, 0, 0, spr["p.puff"])
                ParticlesBurst(ps, 1, e.x, e.y - 8, 2, 20.0, 0.6, -10.0, 0.0, 0, 0, spr["p.star"])
            end if
        else if k = 7
            ParticlesBurst(ps, 0, e.x, e.y, 4, 40.0, 0.35, 60.0, 0.0, 2, &hfff6b0ff, invalid)
        else if k = 1
            ParticlesBurst(ps, 0, e.x, e.y - 10, 2, 6.0, 0.5, -4.0, 0.0, 2, &hfff8e6b4, invalid)
        end if
    end for
end sub

' Advances every particle and adds weather for the visible world range [x0, x1].
sub ParticlesUpdate(ps as object, dtMs as integer, x0 as float, x1 as float)
    if ps.level = 0 then return
    dt = dtMs / 1000.0
    if dt > 0.1 then dt = 0.1
    ' ---- weather (full effects only)
    if ps.level = 2
        ps.weatherAcc = ps.weatherAcc + dt
        gap = 0.4
        if ps.biome = "storm" then gap = 0.045
        if ps.biome = "caverns" then gap = 0.55
        n = 0
        while ps.weatherAcc > gap and n < 4
            ps.weatherAcc = ps.weatherAcc - gap
            n = n + 1
            x = x0 + Rnd(0) * (x1 - x0)
            if ps.biome = "storm"
                if Rnd(0) < 0.75
                    ParticlesAdd(ps, 2, x + 30, -5.0, -40.0, 260.0, 1.4, 0.0, 0, &hc8d7eb70, invalid)
                else
                    ParticlesAdd(ps, 3, x, -5.0, -8.0, 22.0, 9.0, 0.0, 2, &hffffffd8, invalid)
                end if
            else if ps.biome = "caverns"
                col = &h9ff7eac0
                if Rnd(0) < 0.5 then col = &he2b6ffc0
                ParticlesAdd(ps, 3, x, Rnd(0) * 300.0, (Rnd(0) - 0.5) * 6, (Rnd(0) - 0.5) * 6, 4.0, 0.0, 2, col, invalid)
            else
                col = &hffffffd0
                if ps.biome = "hills"
                    col = &hf2d27ad0
                else if Rnd(0) < 0.5
                    col = &hffc2d6d0
                end if
                ParticlesAdd(ps, 3, x, Rnd(0) * 180.0, 6 + Rnd(0) * 6, 3 + Rnd(0) * 4, 7.0, 0.0, 2, col, invalid)
            end if
        end while
        if ps.weatherAcc > gap then ps.weatherAcc = 0.0
    end if
    ' ---- motion
    list = ps.list
    kept = []
    for each p in list
        p.life = p.life - dt
        if p.life > 0 and p.y < 340
            p.vy = p.vy + p.g * dt
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            kept.Push(p)
        end if
    end for
    ps.list = kept
end sub

sub ParticlesDraw(ps as object, scr as object, camPx as integer)
    if ps.level = 0 then return
    for each p in ps.list
        x = Int(p.x * 2) - camPx
        y = Int(p.y * 2)
        if x > -32 and x < 1312 and y < 640
            k = p.k
            if k = 0
                scr.DrawRect(x, y, p.size, p.size, p.color)
            else if k = 1
                reg = p.sprite
                scr.DrawObject(x - reg.GetWidth() \ 2, y - reg.GetHeight() \ 2, reg)
            else if k = 2
                scr.DrawLine(x, y, x + 1, y + 8, p.color)
            else
                scr.DrawRect(x, y, p.size, p.size, p.color)
            end if
        end if
    end for
end sub

sub ParticlesClear(ps as object)
    ps.list = []
end sub
