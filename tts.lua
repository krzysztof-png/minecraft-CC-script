--------------------------------------------------------------------------------
--      MINECRAFT NARRATOR & COMPUTERCRAFT TTS SYNTHESIZER (tts.lua)            --
--------------------------------------------------------------------------------
local tts = {}

local speaker = peripheral.find("speaker")
local chatBox = peripheral.find("chatBox") or peripheral.find("chat_box") or peripheral.find("chat")
local audioPlayer = fs.exists("audio_player.lua") and dofile("audio_player.lua") or nil

-- Phonetic pitch & instrument mapping for CC Speaker fallback
local PHONEMES = {
    ["a"] = { inst = "chime", pitch = 12, dur = 0.09 },
    ["b"] = { inst = "bit",   pitch = 4,  dur = 0.06 },
    ["c"] = { inst = "snare", pitch = 14, dur = 0.06 },
    ["d"] = { inst = "bit",   pitch = 6,  dur = 0.06 },
    ["e"] = { inst = "chime", pitch = 15, dur = 0.08 },
    ["f"] = { inst = "snare", pitch = 18, dur = 0.06 },
    ["g"] = { inst = "bass",  pitch = 8,  dur = 0.08 },
    ["h"] = { inst = "snare", pitch = 10, dur = 0.05 },
    ["i"] = { inst = "chime", pitch = 17, dur = 0.08 },
    ["j"] = { inst = "bit",   pitch = 10, dur = 0.06 },
    ["k"] = { inst = "snare", pitch = 16, dur = 0.06 },
    ["l"] = { inst = "flute", pitch = 10, dur = 0.10 },
    ["m"] = { inst = "bass",  pitch = 6,  dur = 0.10 },
    ["n"] = { inst = "flute", pitch = 8,  dur = 0.10 },
    ["o"] = { inst = "chime", pitch = 9,  dur = 0.10 },
    ["p"] = { inst = "snare", pitch = 8,  dur = 0.06 },
    ["q"] = { inst = "bit",   pitch = 14, dur = 0.06 },
    ["r"] = { inst = "flute", pitch = 6,  dur = 0.10 },
    ["s"] = { inst = "snare", pitch = 20, dur = 0.08 },
    ["t"] = { inst = "hat",   pitch = 14, dur = 0.05 },
    ["u"] = { inst = "chime", pitch = 7,  dur = 0.09 },
    ["v"] = { inst = "bass",  pitch = 10, dur = 0.08 },
    ["w"] = { inst = "flute", pitch = 12, dur = 0.10 },
    ["x"] = { inst = "snare", pitch = 22, dur = 0.08 },
    ["y"] = { inst = "chime", pitch = 19, dur = 0.08 },
    ["z"] = { inst = "bit",   pitch = 16, dur = 0.08 },
    [" "] = { pause = 0.12 }
}

local DIGITS = {
    ["0"] = "zero", ["1"] = "one", ["2"] = "two", ["3"] = "three", ["4"] = "four",
    ["5"] = "five", ["6"] = "six", ["7"] = "seven", ["8"] = "eight", ["9"] = "nine"
}

-- Station Chime (Gong) with custom DFPWM audio file support
function tts.chime()
    if not speaker then return end

    if fs.exists("gong.dfpwm") and audioPlayer then
        audioPlayer.playFile("gong.dfpwm")
    else
        pcall(function()
            speaker.playNote("chime", 1.0, 7)
            sleep(0.16)
            speaker.playNote("chime", 1.0, 12)
            sleep(0.16)
            speaker.playNote("chime", 1.0, 16)
            sleep(0.3)
        end)
    end
end

-- Speaker fallback phonetics
function tts.speak(text)
    if not speaker or not text or #text == 0 then return end
    local expanded = text:gsub("%d", function(d) return " " .. (DIGITS[d] or "") .. " " end):lower()
    for i = 1, #expanded do
        local char = expanded:sub(i, i)
        local ph = PHONEMES[char]
        if ph then
            if ph.pause then sleep(ph.pause)
            elseif ph.inst and ph.pitch then
                pcall(function() speaker.playNote(ph.inst, 0.8, ph.pitch) end)
                sleep(ph.dur or 0.08)
            end
        end
    end
end

-- Railway Announcement integrating Minecraft Narrator and Custom Audio Player
function tts.announceTrain(trainName, platform, track)
    local msgText = string.format("Attention passengers: Train %s arriving at Platform %s Track %s.", 
        trainName or "Express", platform or "1", track or "1")

    -- 1. Play Station Chime Audio (DFPWM or Note synth)
    tts.chime()

    local sentToNarrator = false

    -- 2. Minecraft Narrator Integration via Commands API (/tellraw @a)
    if commands and commands.exec then
        local rawJson = textutils.serializeJSON({
            text = "[STATION ANNOUNCEMENT] " .. msgText,
            color = "yellow",
            bold = true
        })
        local ok = pcall(function() commands.exec("tellraw @a " .. rawJson) end)
        if ok then sentToNarrator = true end
    end

    -- 3. Minecraft Narrator Integration via ChatBox peripheral (Advanced Peripherals)
    if not sentToNarrator and chatBox then
        if chatBox.sendMessage then
            pcall(function() chatBox.sendMessage("[ANNOUNCEMENT] " .. msgText, "Station") end)
            sentToNarrator = true
        elseif chatBox.sendFormattedMessage then
            pcall(function() chatBox.sendFormattedMessage("{\"text\":\"[ANNOUNCEMENT] " .. msgText .. "\",\"color\":\"yellow\"}") end)
            sentToNarrator = true
        end
    end

    -- 4. Fallback: Custom audio file or CC Speaker Phonetic Synthesizer
    if not sentToNarrator then
        if fs.exists("announcement.dfpwm") and audioPlayer then
            audioPlayer.playFile("announcement.dfpwm")
        elseif speaker then
            tts.speak(msgText)
        end
    end
end

return tts
