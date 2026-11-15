' =============================================================================
' SHEEPFALL for Roku - small drawing helpers on top of ifDraw2D.
'
' House rules that keep the picture identical on every Roku GPU:
'   * Colours are 32-bit RGBA integers (&hRRGGBBAA).
'   * Off-screen bitmaps whose TRANSPARENCY matters (the terrain chunks, the
'     mirrored sheep atlas) are written with alpha blending disabled - raw
'     copies and opaque fills only - so their alpha channel is always exactly
'     what was written, never the result of a blend.
'   * Off-screen bitmaps that are blended into (the HUD bar, a stage miniature)
'     start from an opaque fill and are copied to the screen with blending off,
'     so their alpha channel is never looked at.
'   * A bitmap is never modified after it has been used as a draw source in the
'     same frame (Roku OS 16 enforces this); all off-screen painting happens
'     before the frame is composed.
' =============================================================================

' "#rrggbb" (or "rrggbb") + alpha 0..255 -> RGBA integer.
function GfxHex(hexText as string, alpha = 255 as integer) as integer
    h = hexText
    if Left(h, 1) = "#" then h = Mid(h, 2)
    ba = CreateObject("roByteArray")
    ba.FromHexString(h)
    if ba.Count() < 3 then return alpha
    return (ba[0] << 24) or (ba[1] << 16) or (ba[2] << 8) or alpha
end function

function GfxRgba(r as integer, g as integer, b as integer, a as integer) as integer
    return (r << 24) or (g << 16) or (b << 8) or a
end function

' Replace the alpha byte of an RGBA colour.
function GfxWithAlpha(color as integer, alpha as integer) as integer
    return (color and &hFFFFFF00) or alpha
end function

' ---- text -------------------------------------------------------------------

function GfxTextWidth(font as object, text as string) as integer
    return font.GetOneLineWidth(text, 4000)
end function

sub GfxText(scr as object, text as string, x as integer, y as integer, color as integer, font as object)
    scr.DrawText(text, x, y, color, font)
end sub

sub GfxTextCentered(scr as object, text as string, cx as integer, y as integer, color as integer, font as object)
    scr.DrawText(text, cx - font.GetOneLineWidth(text, 4000) \ 2, y, color, font)
end sub

sub GfxTextRight(scr as object, text as string, rx as integer, y as integer, color as integer, font as object)
    scr.DrawText(text, rx - font.GetOneLineWidth(text, 4000), y, color, font)
end sub

' Text with a dark drop edge, for captions that sit directly on the playfield.
sub GfxTextShadow(scr as object, text as string, x as integer, y as integer, color as integer, font as object)
    scr.DrawText(text, x + 2, y + 2, &h1c1108d0, font)
    scr.DrawText(text, x, y, color, font)
end sub

' Greedy word wrap. Returns an array of lines no wider than maxWidth.
function GfxWrap(text as string, font as object, maxWidth as integer) as object
    lines = []
    for each para in text.Split(Chr(10))
        words = para.Split(" ")
        cur = ""
        for each w in words
            if cur = ""
                trial = w
            else
                trial = cur + " " + w
            end if
            if font.GetOneLineWidth(trial, 4000) <= maxWidth or cur = ""
                cur = trial
            else
                lines.Push(cur)
                cur = w
            end if
        end for
        lines.Push(cur)
    end for
    return lines
end function

' Draws wrapped text and returns the y just below the last line.
function GfxParagraph(scr as object, text as string, x as integer, y as integer, maxWidth as integer, color as integer, font as object, lineGap = 4 as integer) as integer
    lh = font.GetOneLineHeight() + lineGap
    for each ln in GfxWrap(text, font, maxWidth)
        scr.DrawText(ln, x, y, color, font)
        y = y + lh
    end for
    return y
end function

' Shortens text with an ellipsis until it fits.
function GfxFit(text as string, font as object, maxWidth as integer) as string
    if font.GetOneLineWidth(text, 4000) <= maxWidth then return text
    t = text
    while Len(t) > 1 and font.GetOneLineWidth(t + "...", 4000) > maxWidth
        t = Left(t, Len(t) - 1)
    end while
    return t + "..."
end function

' ---- shapes -----------------------------------------------------------------

' Rectangle outline of the given thickness.
sub GfxFrame(scr as object, x as integer, y as integer, w as integer, h as integer, t as integer, color as integer)
    scr.DrawRect(x, y, w, t, color)
    scr.DrawRect(x, y + h - t, w, t, color)
    scr.DrawRect(x, y + t, t, h - 2 * t, color)
    scr.DrawRect(x + w - t, y + t, t, h - 2 * t, color)
end sub

' ---- nine-slice -------------------------------------------------------------

' Prepares the nine regions of a square nine-slice sprite inside an atlas bitmap.
function GfxNineMake(bmp as object, x as integer, y as integer, size as integer, inset as integer) as object
    mid = size - 2 * inset
    xs = [x, x + inset, x + size - inset]
    ys = [y, y + inset, y + size - inset]
    ws = [inset, mid, inset]
    regs = []
    for row = 0 to 2
        for col = 0 to 2
            r = CreateObject("roRegion", bmp, xs[col], ys[row], ws[col], ws[row])
            regs.Push(r)
        end for
    end for
    return { regs: regs, inset: inset, mid: mid }
end function

' Draws a nine-slice stretched to (w, h): corners 1:1, edges and centre scaled.
sub GfxNine(scr as object, nine as object, x as integer, y as integer, w as integer, h as integer)
    i = nine.inset
    r = nine.regs
    mw = w - 2 * i
    mh = h - 2 * i
    if mw < 1 then mw = 1
    if mh < 1 then mh = 1
    sx = mw / nine.mid
    sy = mh / nine.mid
    scr.DrawObject(x, y, r[0])
    scr.DrawScaledObject(x + i, y, sx, 1.0, r[1])
    scr.DrawObject(x + i + mw, y, r[2])
    scr.DrawScaledObject(x, y + i, 1.0, sy, r[3])
    scr.DrawScaledObject(x + i, y + i, sx, sy, r[4])
    scr.DrawScaledObject(x + i + mw, y + i, 1.0, sy, r[5])
    scr.DrawObject(x, y + i + mh, r[6])
    scr.DrawScaledObject(x + i, y + i + mh, sx, 1.0, r[7])
    scr.DrawObject(x + i + mw, y + i + mh, r[8])
end sub
