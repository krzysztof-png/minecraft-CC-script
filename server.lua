--------------------------------------------------------------------------------
--                         KONFIGURACJA MONITORA                              --
--------------------------------------------------------------------------------
local STRONA_MONITORA = "right"
local SKALA_TEKSTU    = 0.8 -- W CC wartości to wielokrotności 0.5 (zostanie zaokrąglona)

local targetTerm = term.current()
if peripheral.getType(STRONA_MONITORA) == "monitor" then
    local mon = peripheral.wrap(STRONA_MONITORA)
    pcall(function() mon.setTextScale(SKALA_TEKSTU) end)
    term.redirect(mon)
    targetTerm = mon
end

local isColor = term.isColor()

--------------------------------------------------------------------------------
--                         PALETA KOLORÓW I STYLE                             --
--------------------------------------------------------------------------------
local C = {
    bg          = colors.black,
    header_bg   = colors.blue,
    header_fg   = colors.white,
    table_head  = colors.yellow,
    text        = colors.white,
    subtext     = colors.lightGray,
    border      = colors.gray,
    status_on   = colors.green,
    status_off  = colors.red,
    log_info    = colors.lightBlue,
    log_pass    = colors.orange,
    log_alarm   = colors.red,
    log_sys     = colors.purple
}

-- Funkcja pomocnicza do bezpiecznego kolorowania tekstu
local function setC(fg, bg)
    if isColor then
        if fg then term.setTextColor(fg) end
        if bg then term.setBackgroundColor(bg) end
    end
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
    local wpis = {
        tekst = tekst,
        godzina = godzina,
        kategoria = kategoria or "INFO"
    }
    
    table.insert(logiZdarzen, 1, wpis)
    if #logiZdarzen > MAX_LOGOW then
        table.remove(logiZdarzen)
    end

    -- Rozsyłanie wpisu na żywo do Pocket PC
    rednet.broadcast({
        typ = "NOWY_LOG",
        tekst = string.format("[%s] %s", godzina, tekst),
        kategoria = wpis.kategoria
    }, PROTOKOL)
end

-- Rysowanie głównego interfejsu serwera / monitora
local function odswiezInterfejs()
    local w, h = term.getSize()
    setC(C.text, C.bg)
    term.clear()
    term.setCursorPos(1, 1)

    -- Nagłówek górny
    setC(C.header_fg, C.header_bg)
    local title = " CENTRALA KOLEJOWA - MONITOR SYSTEMU "
    local pad = math.max(0, math.floor((w - #title) / 2))
    print(string.rep(" ", pad) .. title .. string.rep(" ", w - #title - pad))

    -- Pasek informacyjny
    setC(C.subtext, C.bg)
    local uptimeStr = string.format(" Uptime: %-10s | Czas gry: %s", pobierzUptime(), textutils.formatTime(os.time(), true))
    print(uptimeStr .. string.rep(" ", math.max(0, w - #uptimeStr)))

    -- Separator
    setC(C.border, C.bg)
    print(string.rep("=", w))

    -- Nagłówki tabeli
    setC(C.table_head, C.bg)
    print(string.format("%-4s | %-14s | %-9s | %-8s", "ID", "NAZWA", "TRYB", "STATUS"))
    
    setC(C.border, C.bg)
    print(string.rep("-", w))

    local teraz = os.clock()
    local onlineCount = 0

    -- Wypisanie zarejestrowanych węzłów
    for id, dane in pairs(klienci) do
        local online = (teraz - dane.lastSeen) <= TIMEOUT_SEK
        local statusStr = online and dane.status or "OFFLINE"
        if online then onlineCount = onlineCount + 1 end

        -- ID i Nazwa
        setC(C.text, C.bg)
        io.write(string.format("#%-3d | %-14s | %-9s | ", 
            id, 
            dane.nazwa:sub(1, 14), 
            dane.tryb:sub(1, 9)
        ))

        -- Kolorowany status
        if online then
            setC(C.status_on, C.bg)
        else
            setC(C.status_off, C.bg)
        end
        print(string.format("%-8s", statusStr:sub(1, 8)))
    end

    if next(klienci) == nil then
        setC(C.subtext, C.bg)
        print("  Oczekiwanie na rejestracje wezlow sieci...")
    end

    -- Sekcja Logów
    setC(C.border, C.bg)
    print(string.rep("-", w))
    setC(C.table_head, C.bg)
    print("OSTATNIE ZDARZENIA I TELEMETRIA:")

    if #logiZdarzen == 0 then
        setC(C.subtext, C.bg)
        print("  Brak zarejestrowanych zdarzen.")
    else
        for _, log in ipairs(logiZdarzen) do
            -- Czas zdarzenia
            setC(C.subtext, C.bg)
            io.write(string.format(" [%s] ", log.godzina))

            -- Dobór koloru według kategorii zdarzenia
            if log.kategoria == "ALARM" then
                setC(C.log_alarm, C.bg)
            elseif log.kategoria == "PRZEJAZD" then
                setC(C.log_pass, C.bg)
            elseif log.kategoria == "SYSTEM" then
                setC(C.log_sys, C.bg)
            else
                setC(C.log_info, C.bg)
            end
            print(log.tekst)
        end
    end

    -- Stopka
    setC(C.border, C.bg)
    print(string.rep("-", w))
    setC(C.subtext, C.bg)
    io.write("Aktywne wezly: ")
    setC(C.status_on, C.bg)
    io.write(tostring(onlineCount))
    setC(C.subtext, C.bg)
    print(" | [C] Reset logow")
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
