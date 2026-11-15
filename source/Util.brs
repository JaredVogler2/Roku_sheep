' =============================================================================
' SHEEPFALL for Roku - small shared helpers.
' =============================================================================

' Values read back from JSON may be boxed (roInt, roString...); these checks
' accept both the intrinsic and the boxed spelling.
function IsInt(v as dynamic) as boolean
    t = type(v)
    return t = "Integer" or t = "roInt" or t = "roInteger" or t = "LongInteger"
end function

function IsStr(v as dynamic) as boolean
    t = type(v)
    return t = "String" or t = "roString"
end function

function IsArr(v as dynamic) as boolean
    return type(v) = "roArray"
end function

function IsAA(v as dynamic) as boolean
    return type(v) = "roAssociativeArray"
end function

function ClampInt(v as integer, lo as integer, hi as integer) as integer
    if v < lo then return lo
    if v > hi then return hi
    return v
end function

' "7" -> "07"
function Pad2(n as integer) as string
    if n < 10 and n >= 0 then return "0" + n.ToStr()
    return n.ToStr()
end function

' Ticks (17 per second) -> "m:ss", rounded up like the web HUD clock.
function ClockText(ticks as integer) as string
    if ticks < 0 then ticks = 0
    s = (ticks + 16) \ 17
    return (s \ 60).ToStr() + ":" + Pad2(s mod 60)
end function
