' =============================================================================
' SHEEPFALL for Roku - saved progress and settings.
'
' Account-free, stored in the device registry (section "sheepfall", one compact
' JSON value - the registry gives a channel only 16 KB). Absent or damaged data
' never blocks stage 1 or code entry: every read is guarded and falls back to
' defaults. Stages completed in order and stages opened with a code are tracked
' apart, so a code never pretends earlier stages were beaten.
'
'   done    { stageId: [bestRescued, bestTicks, medal] }   medal 1 bronze, 2 silver, 3 gold
'   last    last played stage id            unlocked  furthest stage opened by play
'   visits  [stage ids opened with a code]  set       settings
' =============================================================================

function ProgressDefaults() as object
    return {
        v: 1
        done: {}
        last: ""
        unlocked: "meadow-01"
        visits: []
        set: ProgressDefaultSettings()
    }
end function

function ProgressDefaultSettings() as object
    ' every setting is a small integer (switches are 0 / 1) so stored values are easy to validate
    return {
        sfx: 70          ' effects volume 0 / 40 / 70 / 100
        music: 1
        tutorials: 1
        assist: 0        ' Assisted Mode: adds Rewind (not part of the original rules)
        effects: 2       ' particles and weather: 0 off, 1 reduced, 2 full
        minimap: 1
        codes: 0         ' show the codes of every unlocked stage in Stage Select
        cursor: 1        ' cursor speed: 0 slow, 1 normal, 2 fast
        scenery: 2       ' backdrop detail: 0 sky only, 1 two layers, 2 all layers
    }
end function

function ProgressSettingMax() as object
    return { sfx: 100, music: 1, tutorials: 1, assist: 1, effects: 2, minimap: 1, codes: 1, cursor: 2, scenery: 2 }
end function

function ProgressLoad(index as object) as object
    p = { data: ProgressDefaults(), warning: "", index: index }
    sec = CreateObject("roRegistrySection", "sheepfall")
    p.sec = sec
    if sec = invalid then return p
    if not sec.Exists("progress") then return p
    parsed = ParseJson(sec.Read("progress"))
    ok = false
    if IsAA(parsed)
        if IsInt(parsed.v) and IsAA(parsed.done)
            if parsed.v = 1 then ok = true
        end if
    end if
    if not ok
        p.warning = "Saved progress was damaged and has been reset. Your stage codes still open any stage."
        return p
    end if
    d = ProgressDefaults()
    ' keep only stages that exist, with sane numbers
    for each id in parsed.done
        e = parsed.done[id]
        if index.byId[id] <> invalid and IsArr(e)
            if e.Count() = 3
                if IsInt(e[0]) and IsInt(e[1]) and IsInt(e[2]) then d.done[id] = [e[0], e[1], ClampInt(e[2], 1, 3)]
            end if
        end if
    end for
    if IsStr(parsed.last)
        if index.byId[parsed.last] <> invalid then d.last = parsed.last
    end if
    if IsStr(parsed.unlocked)
        if index.byId[parsed.unlocked] <> invalid then d.unlocked = parsed.unlocked
    end if
    if IsArr(parsed.visits)
        for each id in parsed.visits
            if IsStr(id)
                if index.byId[id] <> invalid then d.visits.Push(id)
            end if
        end for
    end if
    if IsAA(parsed.set)
        maxOf = ProgressSettingMax()
        for each key in maxOf
            v = parsed.set[key]
            if IsInt(v) then d.set[key] = ClampInt(v, 0, maxOf[key])
        end for
    end if
    p.data = d
    return p
end function

sub ProgressSave(p as object)
    if p.sec = invalid then return
    p.sec.Write("progress", FormatJson(p.data))
    p.sec.Flush()
end sub

function ProgressIsCompleted(p as object, id as string) as boolean
    return p.data.done[id] <> invalid
end function

' Available in normal progress: the first stage, a completed stage, or the successor of one.
function ProgressIsUnlocked(p as object, id as string) as boolean
    st = p.index.byId[id]
    if st = invalid then return false
    if st.order = 0 then return true
    if st.order < 0 then return true
    if p.data.done[id] <> invalid then return true
    prev = p.index.order[st.order - 1]
    return p.data.done[prev] <> invalid
end function

function ProgressIsVisited(p as object, id as string) as boolean
    for each v in p.data.visits
        if v = id then return true
    end for
    return false
end function

function ProgressCanOpen(p as object, id as string) as boolean
    return ProgressIsUnlocked(p, id) or ProgressIsVisited(p, id)
end function

' Stage for CONTINUE: the last one played if still unfinished, else the furthest unlocked.
function ProgressContinueId(p as object) as string
    last = p.data.last
    if last <> ""
        if ProgressCanOpen(p, last) and not ProgressIsCompleted(p, last) then return last
    end if
    if p.index.byId[p.data.unlocked] <> invalid then return p.data.unlocked
    return p.index.order[0]
end function

function ProgressHasAny(p as object) as boolean
    return p.data.done.Count() > 0 or p.data.last <> ""
end function

sub ProgressRecordPlayed(p as object, id as string, viaCode as boolean)
    p.data.last = id
    if viaCode and not ProgressIsVisited(p, id) then p.data.visits.Push(id)
    ProgressSave(p)
end sub

function ProgressMedal(saved as integer, required as integer, total as integer) as integer
    if saved >= total then return 3
    half = (total - required + 1) \ 2
    if saved >= required + half then return 2
    return 1
end function

' Called only after a genuine win. Never downgrades earlier results.
' Returns { medal, improved, nextId } (nextId is "" after the final stage).
function ProgressRecordWin(p as object, id as string, saved as integer, required as integer, total as integer, ticks as integer) as object
    medal = ProgressMedal(saved, required, total)
    prev = p.data.done[id]
    improved = false
    if prev = invalid
        p.data.done[id] = [saved, ticks, medal]
        improved = true
    else
        if saved > prev[0]
            prev[0] = saved
            improved = true
        end if
        if ticks < prev[1] then prev[1] = ticks
        if medal > prev[2]
            prev[2] = medal
            improved = true
        end if
    end if
    nextId = ""
    st = p.index.byId[id]
    if st <> invalid and st.order >= 0 and st.order + 1 < p.index.order.Count()
        nextId = p.index.order[st.order + 1]
        cur = p.index.byId[p.data.unlocked]
        curOrder = 0
        if cur <> invalid then curOrder = cur.order
        if st.order + 1 > curOrder then p.data.unlocked = nextId
    end if
    ProgressSave(p)
    return { medal: p.data.done[id][2], earned: medal, improved: improved, nextId: nextId }
end function

sub ProgressResetCampaign(p as object)
    keep = p.data.set
    p.data = ProgressDefaults()
    p.data.set = keep
    ProgressSave(p)
end sub

function ProgressCountDone(p as object, actId as string) as integer
    n = 0
    prefix = actId + "-"
    for each id in p.data.done
        if Left(id, Len(prefix)) = prefix then n = n + 1
    end for
    return n
end function
