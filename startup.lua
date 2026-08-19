--------------------------------------------------------------------------------
--                SELF-UPDATING BOOTSTRAPPER & RUNNER                         --
--------------------------------------------------------------------------------
local GITHUB_BASE = "https://raw.githubusercontent.com/krzysztof-png/minecraft-CC-script/main/"
local CONFIG_FILE = "system_config.json"

if not http then
    error("Blad: API HTTP w ComputerCraft jest wylaczone!")
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

-- 1. SAMOAKTUALIZACJA: Sprawdzanie nowej wersji startup.lua
print("Sprawdzanie aktualizacji bootloadera (startup.lua)...")
local zdalnyStartup = pobierzZGitHuba("startup.lua")

if zdalnyStartup and #zdalnyStartup > 0 then
    local lokalnyStartup = czytajPlikLokalny("startup.lua")
    if lokalnyStartup ~= zdalnyStartup then
        print("[!] Wykryto nowa wersje startup.lua! Aktualizowanie...")
        zapiszPlikLokalny("startup.lua", zdalnyStartup)
        print("[OK] Zaktualizowano bootloader. Restart...")
        sleep(1)
        os.reboot()
    end
end

-- 2. KONFIGURACJA I WYBÓR ROLI
local function wczytajConfig()
    local tresc = czytajPlikLokalny(CONFIG_FILE)
    return tresc and textutils.unserializeJSON(tresc) or nil
end

local function wybierzRole()
    term.clear()
    term.setCursorPos(1, 1)
    print("========================================")
    print("      INICJALIZACJA SYSTEMU KOLEI       ")
    print("========================================")
    print("Wybierz role tego komputera:")
    print(" [1] Serwer Centralny (server.lua)")
    print(" [2] Klient / Posterunek (client.lua)")
    print(" [3] Mobilny Terminal Logow (log.lua)")
    print("----------------------------------------")
    write("Twoj wybor [1/2/3]: ")

    local rola = nil
    while not rola do
        local event, char = os.pullEvent("char")
        if char == "1" then rola = "server" end
        if char == "2" then rola = "client" end
        if char == "3" then rola = "log" end
    end

    local cfg = { rola = rola }
    zapiszPlikLokalny(CONFIG_FILE, textutils.serializeJSON(cfg))
    return cfg
end

local config = wczytajConfig()
if not config or not config.rola then
    config = wybierzRole()
else
    print("Rola: " .. config.rola .. " (Wcisnij [R] by zmienic)")
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

-- 3. POBIERANIE WŁAŚCIWEGO SKRYPTU (server.lua / client.lua / log.lua)
local docelowyPlik = config.rola .. ".lua"
print("Pobieranie aktualizacji: " .. docelowyPlik .. "...")

local zdalnySkrypt = pobierzZGitHuba(docelowyPlik)
if zdalnySkrypt and #zdalnySkrypt > 0 then
    zapiszPlikLokalny(docelowyPlik, zdalnySkrypt)
    print("[OK] Zaktualizowano pomyslnie.")
else
    print("[!] Brak polaczenia z GitHubem. Proba uruchomienia wersji offline...")
    if not fs.exists(docelowyPlik) then
        error("Blad krytyczny: Brak pliku " .. docelowyPlik .. " na dysku!")
    end
end

sleep(0.5)

-- 4. URUCHOMIENIE
term.clear()
term.setCursorPos(1, 1)
shell.run(docelowyPlik)
