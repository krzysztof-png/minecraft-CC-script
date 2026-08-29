--------------------------------------------------------------------------------
--        ENGLISH TEXT-TO-SPEECH (TTS) SYNTHESIZER FOR COMPUTERCRAFT           --
--------------------------------------------------------------------------------
local tts = {}

local speaker = peripheral.find("speaker")

-- Phonetic pitch & instrument mapping for English speech synthesis
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

-- Digit pronunciations in English
local DIGITS = {
    ["0"] = "zero", ["1"] = "one", ["2"] = "two", ["3"] = "three", ["4"] = "four",
    ["5"] = "five", ["6"] = "six", ["7"] = "seven", ["8"] = "eight", ["9"] = "nine"
}

-- Station Announcement Chime (Gong)
function tts.chime()
    if not speaker then return end
    pcall(function()
        speaker.playNote("chime", 1.0, 7)
        sleep(0.16)
        speaker.playNote("chime", 1.0, 12)
        sleep(0.16)
        speaker.playNote("chime", 1.0, 16)
        sleep(0.3)
    end)
end

-- Play a single word or text string via TTS synthesizer
function tts.speak(text)
    if not speaker or not text or #text == 0 then return end

    -- Expand digits to English words
    local expanded = text:gsub("%d", function(digit)
        return " " .. (DIGITS[digit] or "") .. " "
    end):lower()

    for i = 1, #expanded do
        local char = expanded:sub(i, i)
        local ph = PHONEMES[char]

        if ph then
            if ph.pause then
                sleep(ph.pause)
            elseif ph.inst and ph.pitch then
                pcall(function()
                    speaker.playNote(ph.inst, 0.8, ph.pitch)
                end)
                sleep(ph.dur or 0.08)
            end
        end
    end
end

-- Standard Railway Announcement in English: Chime + Announcement
function tts.announceTrain(trainName, platform, track)
    if not speaker then return end
    tts.chime()
    
    local msg = "attention passengers train " .. (trainName or "express") .. " arriving at platform " .. (platform or "one") .. " track " .. (track or "one")
    tts.speak(msg)
end

return tts
