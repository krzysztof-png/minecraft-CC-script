--------------------------------------------------------------------------------
--                SELF-UPDATING BOOTSTRAPPER & RUNNER (startup.lua)             --
--------------------------------------------------------------------------------
local GITHUB_BASE = "https://raw.githubusercontent.com/krzysztof-png/minecraft-CC-script/main/"
local CONFIG_FILE = "system_config.json"

if not http then
    error("Error: HTTP API is disabled in ComputerCraft config!")
end

local function pobierzZGitHuba(nazwaPliku)
    local unikalnyCzas = os.epoch("utc")
    local url = GITHUB_BASE .. nazwaPliku .. "?nocache=" .. unikalnyCzas
    
    local naglowki = {
        ["Cache-Control"] = "no-cache, no-store, must-revalidate",
        ["Pragma"] = "no-cache",
        ["Expires"] = "0"
    }

    local res = http.get(url, naglowki)
    if res then
        local zawartosc = res.readAll()
        res.close()
        return zawartosc
    end
    return nil
end

local function czytajPlikLokalny(sciezka)
    if fs.exists(sciezka) then
        local f = fs.open(sciezka, "r")
        local tresc = f.readAll()
        f.close()
        return tresc
    end
    return nil
end

local function zapiszPlikLokalny(sciezka, dane)
    local f = fs.open(sciezka, "w")
    f.write(dane)
    f.close()
end

-- 1. SELF-UPDATE: Check for startup.lua updates
print("Checking bootloader updates (startup.lua)...")
local zdalnyStartup = pobierzZGitHuba("startup.lua")

if zdalnyStartup and #zdalnyStartup > 0 then
    local lokalnyStartup = czytajPlikLokalny("startup.lua")
    if lokalnyStartup ~= zdalnyStartup then
        print("[!] New version of startup.lua detected! Updating...")
        zapiszPlikLokalny("startup.lua", zdalnyStartup)
        print("[OK] Bootloader updated. Rebooting...")
        sleep(1)
        os.reboot()
    end
end

-- 2. CONFIGURATION & ROLE SELECTION WIZARD
local function wczytajConfig()
    local tresc = czytajPlikLokalny(CONFIG_FILE)
    return tresc and textutils.unserializeJSON(tresc) or nil
end

local function wybierzRole()
    term.clear()
    term.setCursorPos(1, 1)
    print("========================================")
    print("     RAILWAY SYSTEM INITIALIZATION      ")
    print("========================================")
    print("Select this computer's role:")
    print(" [1] Central Server (server.lua)")
    print(" [2] Station Client (client.lua)")
    print(" [3] Mobile Log Terminal (log.lua)")
    print(" [4] Display Board Controller (display.lua)")
    print(" [5] 3x1 Electric Display (electric_display.lua)")
    print(" [6] Platform & Track Display (platform_display.lua)")
    print("----------------------------------------")
    write("Your selection [1-6]: ")

    local rola = nil
    while not rola do
        local event, char = os.pullEvent("char")
        if char == "1" then rola = "server" end
        if char == "2" then rola = "client" end
        if char == "3" then rola = "log" end
        if char == "4" then rola = "display" end
        if char == "5" then rola = "electric_display" end
        if char == "6" then rola = "platform_display" end
    end

    local cfg = { rola = rola }
    zapiszPlikLokalny(CONFIG_FILE, textutils.serializeJSON(cfg))
    return cfg
end

local config = wczytajConfig()
if not config or not config.rola then
    config = wybierzRole()
else
    print("Role: " .. config.rola .. " (Press [R] to change)")
    local timer = os.startTimer(1.5)
    while true do
        local event, p1 = os.pullEvent()
        if event == "key" and p1 == keys.r then
            config = wybierzRole()
            break
        elseif event == "timer" and p1 == timer then
            break
        end
    end
end

-- 3. DOWNLOAD TARGET SCRIPT & DEPENDENCIES
local docelowyPlik = config.rola .. ".lua"
print("Downloading update: " .. docelowyPlik .. "...")

local zdalnySkrypt = pobierzZGitHuba(docelowyPlik)
if zdalnySkrypt and #zdalnySkrypt > 0 then
    zapiszPlikLokalny(docelowyPlik, zdalnySkrypt)
    print("[OK] Updated successfully.")
else
    print("[!] No GitHub connection. Attempting offline launch...")
    if not fs.exists(docelowyPlik) then
        error("Critical error: Missing file " .. docelowyPlik .. " on disk!")
    end
end

-- Download TTS, Audio Player & Station Wizard modules for display and client roles
if config.rola:find("display") or config.rola == "client" or config.rola == "server" then
    local zdalnyTTS = pobierzZGitHuba("tts.lua")
    if zdalnyTTS and #zdalnyTTS > 0 then
        zapiszPlikLokalny("tts.lua", zdalnyTTS)
    end
    local zdalnyAudio = pobierzZGitHuba("audio_player.lua")
    if zdalnyAudio and #zdalnyAudio > 0 then
        zapiszPlikLokalny("audio_player.lua", zdalnyAudio)
    end
    local zdalnyWizard = pobierzZGitHuba("station_wizard.lua")
    if zdalnyWizard and #zdalnyWizard > 0 then
        zapiszPlikLokalny("station_wizard.lua", zdalnyWizard)
    end
end

sleep(0.5)

-- 4. LAUNCH
term.clear()
term.setCursorPos(1, 1)
shell.run(docelowyPlik)
