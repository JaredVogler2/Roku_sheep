' =============================================================================
' SHEEPFALL for Roku - stage content: campaign index, stage files, access codes.
'
' Stage files are produced by tools/build-levels.mts from the web game's
' authored stages. Each pkg:/levels/<id>.json holds the stage facts, the
' collision mask as run-length row bands, and the recorded winning solution.
'
' Stage ids ("meadow-01" .. "storm-30") and access codes are permanent: they are
' the same as the web game's, so a code written down there opens the same stage
' here and vice versa.
' =============================================================================

function LevelsActs() as object
    return [
        { id: "meadow", number: 1, name: "Meadow Morning", short: "Meadow", biome: "meadow", tagline: "Dew, daisies and a flock that will not stop walking." }
        { id: "hill", number: 2, name: "Rolling Hills", short: "Hills", biome: "hills", tagline: "Golden wheat, canals and very few spare planks." }
        { id: "cave", number: 3, name: "Cavern Echoes", short: "Caves", biome: "caverns", tagline: "Glowing seams, cold steel and long way down." }
        { id: "storm", number: 4, name: "Storm Highlands", short: "Storm", biome: "storm", tagline: "Thunder over the summit. Bring every sheep home." }
    ]
end function

' Loads pkg:/levels/index.json and builds the lookup tables used by the menus.
function LevelsLoadIndex() as object
    idx = ParseJson(ReadAsciiFile("pkg:/levels/index.json"))
    if idx = invalid then return invalid
    byId = {}
    byCode = {}
    order = []
    n = 0
    for each st in idx.stages
        st.order = n
        byId[st.id] = st
        byCode[CodeNormalize(st.code)] = st.id
        order.Push(st.id)
        n = n + 1
    end for
    for each st in idx.lessons
        st.order = -1
        byId[st.id] = st
    end for
    idx.byId = byId
    idx.byCode = byCode
    idx.order = order
    return idx
end function

' Reads and parses one stage file. Returns invalid if it is missing or damaged.
function LevelLoad(id as string) as object
    text = ReadAsciiFile("pkg:/levels/" + id + ".json")
    if text = "" then return invalid
    level = ParseJson(text)
    if level = invalid then return invalid
    if level.rows = invalid or level.w = invalid then return invalid
    return level
end function

function LevelIsLesson(id as string) as boolean
    return Left(id, 7) = "lesson-" or Left(id, 5) = "menu-"
end function

' "meadow-07" -> { act: "meadow", number: 7 }, or invalid.
function LevelParseId(id as string) as object
    p = Instr(1, id, "-")
    if p <= 1 then return invalid
    act = Left(id, p - 1)
    if act <> "meadow" and act <> "hill" and act <> "cave" and act <> "storm" then return invalid
    n = Mid(id, p + 1).ToInt()
    if n < 1 or n > 30 then return invalid
    return { act: act, number: n }
end function

function LevelActInfo(actId as string) as object
    for each a in LevelsActs()
        if a.id = actId then return a
    end for
    return invalid
end function

function LevelStageLabel(id as string) as string
    p = LevelParseId(id)
    if p = invalid then return ""
    a = LevelActInfo(p.act)
    num = p.number.ToStr()
    if p.number < 10 then num = "0" + num
    return a.short + " " + num
end function

function LevelRequiredPercent(level as object) as integer
    return Int(100 * level.req / level.total + 0.5)
end function

' ------------------------------------------------------------- access codes
' Readable base-30 alphabet without I, L, O, U, 0 and 1. A code is
' SHP-XXXX-XXXX-C where C is a position-weighted check symbol. Decoding is a
' static reverse lookup: no account, saves, server or network involved.

function CodeAlphabet() as string
    return "ABCDEFGHJKMNPQRSTVWXYZ23456789"
end function

' Upper-cases and strips everything but letters and digits; a bare 9-symbol
' body gets its SHP prefix back. Returns 12 symbols for a well-shaped code.
function CodeNormalize(text as string) as string
    up = UCase(text)
    out = ""
    for i = 1 to Len(up)
        ch = Mid(up, i, 1)
        a = Asc(ch)
        if (a >= 65 and a <= 90) or (a >= 48 and a <= 57) then out = out + ch
    end for
    if Len(out) = 9 then out = "SHP" + out
    return out
end function

function CodeFormat(normalized as string) as string
    s = CodeNormalize(normalized)
    if Len(s) <> 12 then return s
    return Left(s, 3) + "-" + Mid(s, 4, 4) + "-" + Mid(s, 8, 4) + "-" + Mid(s, 12, 1)
end function

' Check symbol: alphabet[(sum(value(body[i]) * (i + 1)) + 17) mod 30].
function CodeCheckSymbol(body8 as string) as string
    alpha = CodeAlphabet()
    sum = 0
    for i = 1 to Len(body8)
        sum = sum + (Instr(1, alpha, Mid(body8, i, 1)) - 1) * i
    end for
    return Mid(alpha, ((sum + 17) mod 30) + 1, 1)
end function

' Validates what the player entered.
' Returns { ok: true, stageId, code } or { ok: false, message }.
function CodeCheck(idx as object, text as string) as object
    bad = "That code doesn't open a sheepfold. Check the letters and try again."
    s = CodeNormalize(text)
    if Len(s) = 0 then return { ok: false, message: "Enter a stage code like SHP-XXXX-XXXX-X." }
    if Len(s) <> 12 or Left(s, 3) <> "SHP" then return { ok: false, message: bad + " Codes have 9 symbols after SHP." }
    body = Mid(s, 4)
    alpha = CodeAlphabet()
    for i = 1 to 9
        ch = Mid(body, i, 1)
        if Instr(1, alpha, ch) = 0
            hint = ""
            if ch = "O" or ch = "0"
                hint = " Codes never use the letter O or zero."
            else if ch = "I" or ch = "L" or ch = "1"
                hint = " Codes never use I, L or the digit one."
            else if ch = "U"
                hint = " Codes never use the letter U."
            end if
            return { ok: false, message: bad + hint }
        end if
    end for
    if CodeCheckSymbol(Left(body, 8)) <> Mid(body, 9, 1) then return { ok: false, message: bad + " One symbol looks mistyped." }
    id = idx.byCode[s]
    ' A well-formed code with a valid checksum but an unknown body is still rejected.
    if id = invalid then return { ok: false, message: bad }
    return { ok: true, stageId: id, code: CodeFormat(s) }
end function
