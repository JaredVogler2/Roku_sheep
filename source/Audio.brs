' =============================================================================
' SHEEPFALL for Roku - sound.
'
' The web game synthesises everything live with WebAudio. A Roku has no
' synthesiser, so tools/build-audio.mts renders the same voices offline:
'   * effects  -> short 16-bit PCM .wav files, played with roAudioResource
'                 (cached in memory, mixed over the music by the device)
'   * music    -> one looping .mp3 per track, played with roAudioPlayer
'
' A Roku mixes only MaxSimulStreams() effects at once (usually two), so every
' effect has a priority and a minimum gap: a crowd of 80 sheep stays pleasant
' and the sounds that matter (a rescue bell, a rejected command) always play.
' Audio never feeds back into the simulation.
' =============================================================================

function AudioNew(sfxVolume as integer, musicOn as boolean) as object
    a = {
        sfxVolume: sfxVolume
        musicOn: musicOn
        track: ""
        wanted: ""
        sounds: {}
        clock: CreateObject("roTimespan")
        streams: []
        player: invalid
    }
    ' name -> [file, duration ms, priority, minimum gap ms]
    table = {
        ui: ["ui", 80, 1, 30]
        rate: ["rate", 70, 1, 40]
        assign: ["assign", 180, 3, 30]
        reject: ["reject", 220, 3, 120]
        hatch: ["hatch", 770, 2, 300]
        plank: ["plank", 120, 1, 50]
        plankwarn0: ["plankwarn0", 200, 2, 60]
        plankwarn1: ["plankwarn1", 200, 2, 60]
        plankwarn2: ["plankwarn2", 200, 2, 60]
        crumble: ["crumble", 190, 1, 60]
        shovel: ["shovel", 140, 1, 80]
        pick: ["pick", 150, 1, 60]
        ting: ["ting", 380, 2, 100]
        chute: ["chute", 150, 1, 80]
        pip1: ["pip1", 100, 2, 50]
        pip2: ["pip2", 100, 2, 50]
        pip3: ["pip3", 100, 2, 50]
        pip4: ["pip4", 100, 2, 50]
        pip5: ["pip5", 100, 2, 50]
        pop: ["pop", 380, 4, 50]
        bell0: ["bell0", 720, 4, 90]
        bell1: ["bell1", 720, 4, 90]
        bell2: ["bell2", 720, 4, 90]
        bleat0: ["bleat0", 520, 2, 350]
        bleat1: ["bleat1", 520, 2, 350]
        poof: ["poof", 340, 2, 80]
        splash: ["splash", 440, 3, 100]
        sizzle: ["sizzle", 490, 3, 100]
        nukearm: ["nukearm", 300, 4, 100]
        fanfare: ["fanfare", 1420, 5, 500]
        sigh: ["sigh", 1020, 5, 500]
    }
    nStreams = 1
    for each name in table
        e = table[name]
        res = CreateObject("roAudioResource", "pkg:/audio/sfx-" + e[0] + ".wav")
        if res <> invalid
            a.sounds[name] = { res: res, ms: e[1], prio: e[2], gap: e[3], last: -100000 }
            n = res.MaxSimulStreams()
            if n > nStreams then nStreams = n
        end if
    end for
    if nStreams > 4 then nStreams = 4
    for i = 0 to nStreams - 1
        a.streams.Push({ until: 0, prio: 0 })
    end for
    return a
end function

' Plays an effect if it is allowed to: volume on, not repeated too quickly,
' and a mixer stream is free or holds something less important.
sub AudioPlay(a as object, name as string)
    if a.sfxVolume <= 0 then return
    s = a.sounds[name]
    if s = invalid then return
    now = a.clock.TotalMilliseconds()
    if now - s.last < s.gap then return
    pick = -1
    lowest = 100
    for i = 0 to a.streams.Count() - 1
        st = a.streams[i]
        if st.until <= now
            pick = i
            exit for
        end if
        if st.prio < lowest
            lowest = st.prio
            pick = i
        end if
    end for
    if pick < 0 then return
    st = a.streams[pick]
    if st.until > now and st.prio > s.prio then return
    s.last = now
    st.until = now + s.ms
    st.prio = s.prio
    s.res.Trigger(a.sfxVolume, pick)
end sub

' Starts (or keeps) a looping music track. "" stops the music.
sub AudioMusic(a as object, track as string)
    a.wanted = track
    if not a.musicOn then track = ""
    if track = a.track then return
    a.track = track
    if a.player <> invalid then a.player.Stop()
    if track = "" then return
    if a.player = invalid then a.player = CreateObject("roAudioPlayer")
    if a.player = invalid then return
    a.player.ClearContent()
    a.player.AddContent({ url: "pkg:/audio/music-" + track + ".mp3", streamformat: "mp3" })
    a.player.SetLoop(true)
    a.player.Play()
end sub

sub AudioSetMusicOn(a as object, isOn as boolean)
    a.musicOn = isOn
    AudioMusic(a, a.wanted)
end sub

sub AudioStop(a as object)
    if a.player <> invalid then a.player.Stop()
    a.track = ""
end sub
