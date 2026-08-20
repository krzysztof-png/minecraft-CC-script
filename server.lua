--------------------------------------------------------------------------------
--                         KONFIGURACJA MONITORA                              --
--------------------------------------------------------------------------------
local STRONA_MONITORA = "right"
local SKALA_TEKSTU    = 0.8 -- W CC wartości to wielokrotności 0.5 (zostanie zaokrąglona)

if peripheral.getType(STRONA_MONITORA) == "monitor" then
    local mon = peripheral.wrap(STRONA_MONITORA)
    pcall(function() mon.setTextScale(SKALA_TEKSTU) end)
    term.redirect(mon)
    term.clear()
    term.setCursorPos(1, 1)
end

--------------------------------------------------------------------------------
--                         KONFIGURACJA SERWERA                               --
--------------------------------------------------------------------------------
local PROTOKOL     = "kolej_net"
local NAZWA_HOSTA  = "centrala_glowna"
local TIMEOUT_SEK  = 6   -- Czas w sekundach do uznania węzła za OFFLINE
local MAX_LOGOW    = 8   -- Maksymalna liczba wpisów w historii
local START_EPOCH  = os.epoch("utc") -- Czas startu do liczenia uptime
--------------------------------------------------------------------------------

local modem = peripheral.find("modem")
if not modem then
    error("Blad: Nie wykryto modemu (Wireless/Ender Modem)!")
end
rednet.open(peripheral.getName(modem))
rednet.host(PROTOKOL, NAZWA_HOSTA)

local klienci = {}
local logiZdarzen = {}

-- Obliczanie czasu pracy od uruchomienia (godziny i minuty)
local function pobierzUptime()
    local sekundy = math.floor((os.epoch("utc") - START_EPOCH) / 1000)
    local godziny = math.floor(sekundy / 3600)
    local minuty  = math.floor((sekundy % 3600) / 60)
    return string.format("%02dh %02dm", godziny, minuty)
end

-- Funkcja dodawania wpisu i natychmiastowego broadcastu do urządzeń mobilnych
local function dodajLog(tekst, kategoria)
    local godzina = textutils.formatTime(os.time(), true)
    local wpis = string.format("[%s] %s", godzina, tekst)
    
    table.insert(logiZdarzen, 1, wpis)
    if #logiZdarzen > MAX_LOGOW then
        table.remove(logiZdarzen)
    end

    -- Rozsyłanie wpisu na żywo do Pocket PC
    rednet.broadcast({
        typ = "NOWY_LOG",
        tekst = wpis,
        kategoria = kategoria or "INFO"
    }, PROTOKOL)
end

-- Rysowanie głównego interfejsu serwera / monitora
local function odswiezInterfejs()
    term.clear()
    term.setCursorPos(1, 1)
    print("==================================================")
    print("         CENTRALA KOLEJOWA - MONITOR SYSTEMU      ")
    print(string.format(" Uptime: %-12s | Czas gry: %s", pobierzUptime(), textutils.formatTime(os.time(), true)))
    print("==================================================")
    print(string.format("%-4s | %-14s | %-9s | %-8s", "ID", "NAZWA", "TRYB", "STATUS"))
    print("--------------------------------------------------")

    local teraz = os.clock()
    local onlineCount = 0

    for id, dane in pairs(klienci) do
        local online = (teraz - dane.lastSeen) <= TIMEOUT_SEK
        local statusStr = online and dane.status or "OFFLINE"
        if online then onlineCount = onlineCount + 1 end

        print(string.format("#%-3d | %-14s | %-9s | %-8s", 
            id, 
            dane.nazwa:sub(1, 14), 
            dane.tryb:sub(1, 9), 
            statusStr:sub(1, 8)
        ))
    end

    if next(klienci) == nil then
        print("  Oczekiwanie na rejestracje wezlow sieci...")
    end

    print("--------------------------------------------------")
    print("OSTATNIE ZDARZENIA I TELEMETRIA:")
    if #logiZdarzen == 0 then
        print("  Brak zarejestrowanych zdarzen.")
    else
        for _, log in ipairs(logiZdarzen) do
            print(" " .. log)
        end
    end
    print("--------------------------------------------------")
    print(string.format("Aktywne wezly: %d | [C] Reset logow", onlineCount))
end

-- Inicjalizacja pętli
local timerOdswiezania = os.startTimer(1)
dodajLog("Serwer glowny uruchomiony.", "SYSTEM")
odswiezInterfejs()

while true do
    local event, p1, p2, p3 = os.pullEvent()

    -- 1. Obsługa pakietów Rednet
    if event == "rednet_message" and p3 == PROTOKOL then
        local senderId, msg = p1, p2

        if type(msg) == "table" then
            -- Heartbeat i meldowanie węzłów
            if msg.typ == "PING" then
                klienci[senderId] = {
                    nazwa    = msg.nazwa or ("Klient_" .. senderId),
                    tryb     = msg.tryb or "BEACON",
                    status   = msg.status or "ONLINE",
                    lastSeen = os.clock()
                }
                rednet.send(senderId, { odp = "PONG_OK" }, PROTOKOL)
                -- Synchronizacja listy urządzeń z podłączonymi Pocket PC
                rednet.broadcast({ typ = "SYNC_KLIENCI", klienci = klienci }, PROTOKOL)

            -- Sygnał z Train Observera
            elseif msg.typ == "PRZEJAZD_POCIAGU" then
                local punkt = msg.nazwa or ("ID #" .. senderId)
                dodajLog("PRZEJAZD: Pociag minal " .. punkt, "PRZEJAZD")
                odswiezInterfejs()

            -- Prośba o pełny pakiet danych (dla Pocket PC)
            elseif msg.typ == "POBIERZ_DANE" then
                rednet.send(senderId, {
                    typ = "PELNE_DANE",
                    klienci = klienci,
                    logi = logiZdarzen,
                    uptime = pobierzUptime()
                }, PROTOKOL)

            -- Prośba o samą historię logów
            elseif msg.typ == "POBIERZ_LOGI" then
                rednet.send(senderId, {
                    typ = "HISTORIA_LOGOW",
                    logi = logiZdarzen
                }, PROTOKOL)

            -- Zdarzenia awaryjne i alarmy
            elseif msg.typ == "ALARM" then
                dodajLog("ALARM: " .. (msg.nazwa or senderId) .. " -> " .. tostring(msg.powod), "ALARM")
                odswiezInterfejs()
            end
        end

    -- 2. Cykliczny timer odświeżania zegara, sprawdzania timeoutów i uptime
    elseif event == "timer" and p1 == timerOdswiezania then
        odswiezInterfejs()
        timerOdswiezania = os.startTimer(1)

    -- 3. Obsługa klawiszy na serwerze
    elseif event == "key" then
        if p1 == keys.c then
            logiZdarzen = {}
            dodajLog("Wyczyszczono rejestr zdarzen.", "SYSTEM")
            odswiezInterfejs()
        end
    end
end
