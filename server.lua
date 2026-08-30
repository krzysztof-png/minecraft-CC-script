--------------------------------------------------------------------------------
--                         KONFIGURACJA MONITORA                              --
--------------------------------------------------------------------------------
local STRONA_MONITORA = "right"
local SKALA_TEKSTU    = 0.8

local function znajdzMonitor()
    local dev = (peripheral.getType(STRONA_MONITORA) == "monitor" and peripheral.wrap(STRONA_MONITORA)) or peripheral.find("monitor")
    if dev then
        pcall(function() dev.setTextScale(SKALA_TEKSTU) end)
        return dev
    end
    return nil
end

local monitorPeri = znajdzMonitor()

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

--------------------------------------------------------------------------------
--                         KONFIGURACJA SERWERA                               --
--------------------------------------------------------------------------------
local PROTOKOL     = "kolej_net"
local NAZWA_HOSTA  = "centrala_glowna"
local TIMEOUT_SEK  = 6
local MAX_LOGOW    = 8
local DB_FILE      = "transit_logs.json"
local START_EPOCH  = os.epoch("utc")

local modem = peripheral.find("modem")
if not modem then
    error("Blad: Nie wykryto modemu (Wireless/Ender Modem)!")
end
rednet.open(peripheral.getName(modem))
rednet.host(PROTOKOL, NAZWA_HOSTA)

local klienci = {}
local logiZdarzen = {}

-- === BAZA DANYCH PRZEJAZDÓW ===
local function wczytajBazePrzejazdow()
    if not fs.exists(DB_FILE) then return {} end
    local f = fs.open(DB_FILE, "r")
    local data = textutils.unserializeJSON(f.readAll()) or {}
    f.close()
    return data
end

local function zapiszPrzejazdDoBazy(rekord)
    local db = wczytajBazePrzejazdow()
    table.insert(db, rekord)
    local f = fs.open(DB_FILE, "w")
    f.write(textutils.serializeJSON(db))
    f.close()
end

local function pobierzUptime()
    local sekundy = math.floor((os.epoch("utc") - START_EPOCH) / 1000)
    local godziny = math.floor(sekundy / 3600)
    local minuty  = math.floor((sekundy % 3600) / 60)
    return string.format("%02dh %02dm", godziny, minuty)
end

local function dodajLog(tekst, kategoria, meta)
    local godzina = textutils.formatTime(os.time(), true)
    local wpis = {
        tekst = tekst,
        godzina = godzina,
        kategoria = kategoria or "INFO",
        punkt = meta and meta.punkt or nil,
        pociag = meta and meta.pociag or nil
    }
    
    table.insert(logiZdarzen, 1, wpis)
    if #logiZdarzen > MAX_LOGOW then
        table.remove(logiZdarzen)
    end

    rednet.broadcast({
        typ = "NOWY_LOG",
        tekst = string.format("[%s] %s", godzina, tekst),
        kategoria = wpis.kategoria,
        punkt = wpis.punkt,
        pociag = wpis.pociag,
        czas = godzina
    }, PROTOKOL)
end

local function rysujJednostkeTerminala()
    local w, h = term.getSize()
    local isColor = term.isColor()

    local function setC(fg, bg)
        if isColor then
            if fg then term.setTextColor(fg) end
            if bg then term.setBackgroundColor(bg) end
        end
    end

    setC(C.text, C.bg)
    term.clear()
    term.setCursorPos(1, 1)

    setC(C.header_fg, C.header_bg)
    local title = " CENTRALA KOLEJOWA - MONITOR SYSTEMU "
    local pad = math.max(0, math.floor((w - #title) / 2))
    print(string.rep(" ", pad) .. title .. string.rep(" ", w - #title - pad))

    setC(C.subtext, C.bg)
    local uptimeStr = string.format(" Uptime: %-10s | Czas gry: %s", pobierzUptime(), textutils.formatTime(os.time(), true))
    print(uptimeStr .. string.rep(" ", math.max(0, w - #uptimeStr)))

    setC(C.border, C.bg)
    print(string.rep("=", w))

    setC(C.table_head, C.bg)
    print(string.format("%-4s | %-13s | %-8s | %-16s", "ID", "POSTERUNEK", "TRYB", "STATUS / POCIAG"))
    
    setC(C.border, C.bg)
    print(string.rep("-", w))

    local teraz = os.clock()
    local onlineCount = 0

    for id, dane in pairs(klienci) do
        local online = (teraz - dane.lastSeen) <= TIMEOUT_SEK
        local statusStr = online and dane.status or "OFFLINE"
        if online then onlineCount = onlineCount + 1 end

        setC(C.text, C.bg)
        io.write(string.format("#%-3d | %-13s | %-8s | ", 
            id, 
            (dane.nazwa or ""):sub(1, 13), 
            (dane.tryb or ""):sub(1, 8)
        ))

        if online then
            if statusStr == "WOLNY" or statusStr == "OK" then
                setC(C.status_on, C.bg)
            else
                setC(C.log_pass, C.bg)
            end
        else
            setC(C.status_off, C.bg)
        end
        print(string.format("%-16s", statusStr:sub(1, 16)))
    end

    if next(klienci) == nil then
        setC(C.subtext, C.bg)
        print("  Oczekiwanie na rejestracje wezlow sieci...")
    end

    setC(C.border, C.bg)
    print(string.rep("-", w))
    setC(C.table_head, C.bg)
    print("OSTATNIE ZDARZENIA I TELEMETRIA:")

    if #logiZdarzen == 0 then
        setC(C.subtext, C.bg)
        print("  Brak zarejestrowanych zdarzen.")
    else
        for _, log in ipairs(logiZdarzen) do
            setC(C.subtext, C.bg)
            io.write(string.format(" [%s] ", log.godzina))

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

    setC(C.border, C.bg)
    print(string.rep("-", w))
    setC(C.subtext, C.bg)
    io.write("Aktywne wezly: ")
    setC(C.status_on, C.bg)
    io.write(tostring(onlineCount))
    setC(C.subtext, C.bg)
    print(" | [C] Reset logow | [X] Reboot sieci")
end

local function odswiezInterfejs()
    -- 1. Zawsze rysuj na natywnym ekranie komputera
    term.redirect(term.native())
    rysujJednostkeTerminala()

    -- 2. Jeśli jest podłączony zewnętrzny monitor, rysuj również na nim
    if not monitorPeri then
        monitorPeri = znajdzMonitor()
    end

    if monitorPeri then
        local ok, err = pcall(function()
            term.redirect(monitorPeri)
            rysujJednostkeTerminala()
        end)
        if not ok then
            monitorPeri = nil
        end
    end

    term.redirect(term.native())
end

local timerOdswiezania = os.startTimer(1)
dodajLog("Serwer glowny uruchomiony.", "SYSTEM")
odswiezInterfejs()

while true do
    local event, p1, p2, p3 = os.pullEvent()

    -- 1. Obsługa pakietów Rednet
    if event == "rednet_message" and p3 == PROTOKOL then
        local senderId, msg = p1, p2

        if type(msg) == "table" then
            if klienci[senderId] then
                klienci[senderId].lastSeen = os.clock()
            end

            -- Heartbeat i meldowanie
            if msg.typ == "PING" then
                klienci[senderId] = {
                    nazwa    = msg.nazwa or ("Klient_" .. senderId),
                    tryb     = msg.tryb or "BEACON",
                    status   = msg.status or "OK",
                    pociag   = msg.pociag or nil,
                    lastSeen = os.clock()
                }
                rednet.send(senderId, { odp = "PONG_OK" }, PROTOKOL)
                rednet.broadcast({ typ = "SYNC_KLIENCI", klienci = klienci }, PROTOKOL)

            -- Wykrycie i identyfikacja pociągu
            elseif msg.typ == "PRZEJAZD_POCIAGU" then
                local punkt = msg.nazwa or ("ID #" .. senderId)
                local pociagNazwa = msg.pociag or "Nieznany pociag"
                local opoznienie = tonumber(msg.opoznienie) or 0
                local stacjaId = msg.idStacji or "ST"
                local torNum = msg.tor or "1"
                local opoznienieStr = (opoznienie > 0) and string.format(" (+%d min)", opoznienie) or ""
                
                dodajLog(string.format("[%s-T%s] %s: %s%s", stacjaId, torNum, punkt, pociagNazwa, opoznienieStr), "PRZEJAZD", { punkt = punkt, pociag = pociagNazwa, stacja = stacjaId, tor = torNum, opoznienie = opoznienie })

                -- Zapis do bazy danych
                local rekord = {
                    id = os.epoch("utc"),
                    timestamp = os.date("!%Y-%m-%d %H:%M:%S"),
                    czas_gry = msg.czas or textutils.formatTime(os.time(), true),
                    posterunek = punkt,
                    posterunek_id = senderId,
                    idStacji = stacjaId,
                    tor = torNum,
                    tryb_detekcji = msg.tryb or "OBSERVER",
                    nazwa_pociagu = pociagNazwa,
                    opoznienie = opoznienie
                }
                zapiszPrzejazdDoBazy(rekord)
                rednet.broadcast({ typ = "PRZEJAZD_POCIAGU", nazwa = punkt, pociag = pociagNazwa, idStacji = stacjaId, tor = torNum, opoznienie = opoznienie, czas = msg.czas }, PROTOKOL)
                odswiezInterfejs()

            -- Pobieranie danych
            elseif msg.typ == "POBIERZ_DANE" then
                rednet.send(senderId, {
                    typ = "PELNE_DANE",
                    klienci = klienci,
                    logi = logiZdarzen,
                    uptime = pobierzUptime()
                }, PROTOKOL)

            elseif msg.typ == "POBIERZ_LOGI" then
                rednet.send(senderId, {
                    typ = "HISTORIA_LOGOW",
                    logi = logiZdarzen
                }, PROTOKOL)

            elseif msg.typ == "POBIERZ_BAZE" then
                rednet.send(senderId, {
                    typ = "BAZA_PRZEJAZDOW",
                    baza = wczytajBazePrzejazdow()
                }, PROTOKOL)

            elseif msg.typ == "ALARM" then
                dodajLog("ALARM: " .. (msg.nazwa or senderId) .. " -> " .. tostring(msg.powod), "ALARM")
                odswiezInterfejs()

            elseif msg.typ == "ZAPISZ_STACJE" and msg.stacja then
                local sId = msg.idStacji or msg.stacja.id or msg.stacja.kod or msg.stacja.nazwa
                local stacje = wczytajWszystkieStacje()
                stacje[sId] = msg.stacja
                msg.stacja.id = sId

                local f = fs.open("network_stations.json", "w")
                f.write(textutils.serializeJSON(stacje))
                f.close()

                dodajLog("Multi-Stacja Zapisano: " .. (msg.stacja.nazwa or sId), "SYSTEM")
                rednet.broadcast({ typ = "SYNC_STACJA", idStacji = sId, stacja = msg.stacja, stacje = stacje }, PROTOKOL)
                odswiezInterfejs()

            elseif msg.typ == "POBIERZ_STACJE" then
                local stacje = {}
                if fs.exists("network_stations.json") then
                    local f = fs.open("network_stations.json", "r")
                    stacje = textutils.unserializeJSON(f.readAll()) or {}
                    f.close()
                end
                local sId = msg.idStacji
                local targetStacja = sId and stacje[sId] or nil
                rednet.send(senderId, { typ = "SYNC_STACJA", idStacji = sId, stacja = targetStacja, stacje = stacje }, PROTOKOL)

            elseif msg.typ == "ZAPYTANIE_TABLICA" or msg.typ == "USTAW_TEKST_TABLICY" or msg.typ == "TEST_TABLICY" or msg.typ == "WYCZYSC_TABLICE" or msg.typ == "RESET_TABLICY" then
                rednet.broadcast(msg, PROTOKOL)

            elseif msg.typ == "REBOOT_ALL" or (msg.typ == "REBOOT" and (not msg.targetId and not msg.targetTryb or msg.targetId == os.getComputerID() or msg.targetTryb == "SERVER")) then
                dodajLog("Zdalny REBOOT serwera od #" .. senderId, "ALARM")
                odswiezInterfejs()
                rednet.broadcast(msg, PROTOKOL)
                sleep(0.5)
                os.reboot()
            end
        end

    -- 2. Cykliczny timer odświeżania ekranu
    elseif event == "timer" and p1 == timerOdswiezania then
        odswiezInterfejs()
        timerOdswiezania = os.startTimer(1)

    -- 3. Czyszczenie logów oraz zdalny restart
    elseif event == "key" then
        if p1 == keys.c then
            logiZdarzen = {}
            dodajLog("Wyczyszczono rejestr zdarzen.", "SYSTEM")
            odswiezInterfejs()
        elseif p1 == keys.x then
            dodajLog("Restart sieci z serwera...", "ALARM")
            odswiezInterfejs()
            rednet.broadcast({ typ = "REBOOT" }, PROTOKOL)
            sleep(0.5)
            os.reboot()
        end
    end
end
