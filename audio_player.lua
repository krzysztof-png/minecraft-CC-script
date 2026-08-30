--------------------------------------------------------------------------------
--         PROFESJONALNY ODTWARZACZ PLIKÓW AUDIO DFPWM/WAV (audio_player.lua)    --
--------------------------------------------------------------------------------
local audioPlayer = {}

-- Próba załadowania natywnej biblioteki DFPWM z CC: Tweaked
local dfpwm = nil
pcall(function() dfpwm = require("cc.audio.dfpwm") end)
if not dfpwm then
    pcall(function() dfpwm = _G.dfpwm end)
end

local speaker = peripheral.find("speaker")

--------------------------------------------------------------------------------
-- 1. ODTWARZANIE LOKALNEGO PLIKU AUDIO (.dfpwm / .wav)                      --
--------------------------------------------------------------------------------
function audioPlayer.playFile(filePath, volume)
    if not speaker then
        return false, "Brak podlaczonego glosnika (speaker)!"
    end

    if not dfpwm then
        return false, "Brak biblioteki cc.audio.dfpwm w tym profilu CC!"
    end

    if not fs.exists(filePath) then
        return false, "Plik nie istnieje: " .. tostring(filePath)
    end

    local file = fs.open(filePath, "rb")
    if not file then
        return false, "Nie mozna otworzyc pliku: " .. tostring(filePath)
    end

    local decoder = dfpwm.make_decoder()
    local chunkSize = 16 * 1024

    while true do
        local chunk = file.read(chunkSize)
        if not chunk or #chunk == 0 then
            break
        end

        local buffer = decoder(chunk)
        
        -- Odtwarzanie bufora audio z uwzględnieniem zdarzenia opróżnienia bufora głośnika
        while not speaker.playAudio(buffer, volume or 1.0) do
            local event, pName = os.pullEvent("speaker_audio_empty")
        end
    end

    file.close()
    return true, "Odtwarzanie zakonczone powodzeniem."
end

--------------------------------------------------------------------------------
-- 2. POBIERANIE I ODTWARZANIE AUDIO Z ADRESU URL (HTTP STREAMING)             --
--------------------------------------------------------------------------------
function audioPlayer.playURL(url, localSavePath, volume)
    if not http then
        return false, "API HTTP jest wylaczone!"
    end

    print("Pobieranie pliku audio z URL...")
    local response = http.get(url, nil, true)
    if not response then
        return false, "Blad pobierania z URL: " .. tostring(url)
    end

    local data = response.readAll()
    response.close()

    if not data or #data == 0 then
        return false, "Pobrany plik jest pusty!"
    end

    local tempPath = localSavePath or ("temp_audio_" .. os.epoch("utc") .. ".dfpwm")
    local f = fs.open(tempPath, "wb")
    f.write(data)
    f.close()

    print("Odtwarzanie strumienia audio...")
    local ok, err = audioPlayer.playFile(tempPath, volume)

    -- Usunięcie tymczasowego pliku jeśli nie podano własnej ścieżki zapisu
    if not localSavePath and fs.exists(tempPath) then
        fs.delete(tempPath)
    end

    return ok, err
end

--------------------------------------------------------------------------------
-- 3. INTERFEJS KONSOLOWY I URUCHAMIANIE Z LINI POLECEŃ                       --
--------------------------------------------------------------------------------
local args = { ... }
if #args > 0 then
    term.clear()
    term.setCursorPos(1, 1)
    print("========================================")
    print("       CC: TWEAKED AUDIO PLAYER         ")
    print("========================================")

    local target = args[1]
    local vol = tonumber(args[2]) or 1.0

    if target:sub(1, 4) == "http" then
        print("Uruchamianie strumienia z URL: " .. target)
        local ok, err = audioPlayer.playURL(target, nil, vol)
        print("Wynik: " .. tostring(err or ok))
    else
        print("Odtwarzanie pliku lokalnego: " .. target)
        local ok, err = audioPlayer.playFile(target, vol)
        print("Wynik: " .. tostring(err or ok))
    end
end

return audioPlayer
