--------------------------------------------------------------------------------
--    DWUSTRONNY WYŚWIETLACZ 3x1 (Z INTEGRACJĄ KREATORA STACJI)               --
--                       electric_display.lua                                 --
--------------------------------------------------------------------------------
local CONFIG_FILE = "electric_config.json"
local PROTOKOL    = "kolej_net"
local SERWER_HOST = "centrala_glowna"
local MOJE_ID     = os.getComputerID()

local tts = fs.exists("tts.lua") and dofile("tts.lua") or nil
local stationWizard = fs.exists("station_wizard.lua") and dofile("station_wizard.lua") or nil

-- 1. Inicjalizacja modemu oraz głośnika
local modem = peripheral.find("modem")
if not modem then
    error("Blad: Nie znaleziono modemu bezprzewodowego/ender!")
end
rednet.open(peripheral.getName(modem))

local speaker = peripheral.find("speaker")

local function zagrajGongDworcowy()
    if not speaker then return end
    pcall(function()
        speaker.playNote("chime", 1.0, 7)
        sleep(0.18)
        speaker.playNote("chime", 1.0, 12)
        sleep(0.18)
        speaker.playNote("chime", 1.0, 16)
    end)
end

--------------------------------------------------------------------------------
--                KREATOR KONFIGURACJI EKRANÓW (TOR LEWY / PRAWY)              --
--------------------------------------------------------------------------------
local function wczytajConfig()
    if fs.exists(CONFIG_FILE) then
        local f = fs.open(CONFIG_FILE, "r")
        local tresc = f.readAll()
        f.close()
        return textutils.unserializeJSON(tresc)
    end
    return nil
end

local function zapiszConfig(cfg)
    local f = fs.open(CONFIG_FILE, "w")
    f.write(textutils.serializeJSON(cfg))
    f.close()
end

local function pobierzWszystkieNazwyPeryferii()
    local nazwySet = {}
    for _, name in ipairs(peripheral.getNames()) do
        nazwySet[name] = true
        local dev = peripheral.wrap(name)
        if dev and dev.getNamesRemote then
            local ok, remotes = pcall(dev.getNamesRemote)
            if ok and remotes and type(remotes) == "table" then
                for _, rName in ipairs(remotes) do
                    nazwySet[rName] = true
                end
            end
        end
    end
    local lista = {}
    for n, _ in pairs(nazwySet) do table.insert(lista, n) end
    table.sort(lista)
    return lista
end

local function wyszukajDostepneMonitory()
    local lista = {}
    for _, name in ipairs(pobierzWszystkieNazwyPeryferii()) do
        if name ~= peripheral.getName(modem) then
            local t = (peripheral.getType(name) or ""):lower()
            if t:find("monitor") or (peripheral.wrap(name).write and not t:find("computer") and not t:find("drive")) then
                table.insert(lista, name)
            end
        end
    end
    return lista
end

local function kreatorKonfiguracji()
    term.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    print("========================================")
    print("   KONFIGURACJA ELEKTRONICZNA 3x1 2xTOR ")
    print("========================================")
    term.setBackgroundColor(colors.black)

    local stacjaData = stationWizard and stationWizard.wczytaj and stationWizard.wczytaj() or nil

    local stacja = (stacjaData and stacjaData.nazwa) or "Centralna"
    if not stacjaData then
        print("\nNazwa Stacji (np. Centralna):")
        term.setTextColor(colors.yellow)
        write("> ")
        term.setTextColor(colors.white)
        stacja = read()
        if stacja == "" then stacja = "Stacja_" .. MOJE_ID end
    else
        print("\nWczytano Stacje: " .. stacja .. " (Kod: " .. (stacjaData.kod or "ST") .. ")")
    end

    print("\nNumer Peronu (np. 1, 2...):")
    term.setTextColor(colors.yellow)
    write("> ")
    term.setTextColor(colors.white)
    local peron = read()
    if peron == "" then peron = "1" end

    print("\nRozmiar Napisow / Skala Tekstu:")
    print(" [1] Drobny / Maly tekst (Skala 0.5) - DUZO TRESCI [DOMYSLNY]")
    print(" [2] Sredni tekst (Skala 0.75)")
    print(" [3] Duzy tekst (Skala 1.0)")
    write("Wybór [1-3, domyslnie 1]: ")
    
    local skala = 0.5
    local inputSkala = read()
    if inputSkala == "2" then skala = 0.75 end
    if inputSkala == "3" then skala = 1.0 end

    local monitory = wyszukajDostepneMonitory()

    print("\n--- MONITORY W SIECI ---")
    if #monitory == 0 then
        term.setTextColor(colors.red)
        print("Nie znaleziono zewnetrznych monitorow!")
        print("Uzyty zostanie ekran komputera jako lewy tor.")
    else
        for idx, mName in ipairs(monitory) do
            print(string.format(" [%d] %s", idx, mName))
        end
    end

    print("\nWybierz nazwe/tor dla LEWEJ STRONY (np. Tor 1, 2...):")
    term.setTextColor(colors.yellow)
    write("Numer toru lewego [np. 1]: ")
    term.setTextColor(colors.white)
    local torLewy = read()
    if torLewy == "" then torLewy = "1" end

    local monLewyName = monitory[1] or "terminal"
    if #monitory > 1 then
        write(string.format("Wybierz monitor dla Toru %s [1-%d, domyslny 1]: ", torLewy, #monitory))
        local idxL = tonumber(read()) or 1
        monLewyName = monitory[idxL] or monitory[1]
    end

    print("\nWybierz nazwe/tor dla PRAWEJ STRONY (np. Tor 2, 3...):")
    term.setTextColor(colors.yellow)
    write("Numer toru prawego [np. 2]: ")
    term.setTextColor(colors.white)
    local torPrawy = read()
    if torPrawy == "" then torPrawy = "2" end

    local monPrawyName = monitory[2] or monLewyName
    if #monitory > 1 then
        write(string.format("Wybierz monitor dla Toru %s [1-%d, domyslny 2]: ", torPrawy, #monitory))
        local idxP = tonumber(read()) or 2
        monPrawyName = monitory[idxP] or monitory[2]
    end

    local cfg = {
        stacja = stacja,
        peron = peron,
        skalaTekstu = skala,
        torLewy = torLewy,
        monLewy = monLewyName,
        torPrawy = torPrawy,
        monPrawy = monPrawyName
    }
    zapiszConfig(cfg)
    return cfg
end

local config = wczytajConfig()
if not config then
    config = kreatorKonfiguracji()
end

--------------------------------------------------------------------------------
--                PODŁĄCZENIE I PRZYGOTOWANIE MONITORÓW                       --
--------------------------------------------------------------------------------
local function InicjalizujMonitor(name, skala)
    skala = skala or config.skalaTekstu or 0.5

    if name == "terminal" or not name then
        return term.native(), "terminal", 26, 6
    end
    local dev = peripheral.wrap(name)
    if dev then
        pcall(function() dev.setTextScale(skala) end)
        local w, h = 26, 6
        if dev.getSize then
            local ok, dw, dh = pcall(dev.getSize)
            if ok and dw and dh and dw > 0 then w, h = dw, dh end
        end
        return dev, name, w, h
    end
    return term.native(), "terminal", 26, 6
end

local dispLewy, nameLewy, wLewy, hLewy = InicjalizujMonitor(config.monLewy)
local dispPrawy, namePrawy, wPrawy, hPrawy = InicjalizujMonitor(config.monPrawy)

local function setC(dev, fg, bg)
    if dev.setTextColor then pcall(dev.setTextColor, fg or colors.white) end
    if dev.setBackgroundColor then pcall(dev.setBackgroundColor, bg or colors.black) end
end

local function odswiezFlapy(dev)
    if not dev then return end
    if dev.update then pcall(dev.update) end
    if dev.flush then pcall(dev.flush) end
    if dev.render then pcall(dev.render) end
end

local function wypiszWiersz(dev, wMax, hMax, nrLinii, tekst, fg, bg)
    if not dev or nrLinii < 1 or nrLinii > hMax then return end

    local sformatowany = string.format("%-" .. wMax .. "s", tekst):sub(1, wMax)
    setC(dev, fg or colors.white, bg or colors.black)

    if dev.setCursorPos and dev.write then
        pcall(dev.setCursorPos, 1, nrLinii)
        pcall(dev.write, sformatowany)
    end

    if dev.setLine then
        local ok = pcall(dev.setLine, nrLinii, sformatowany)
        if not ok and (nrLinii - 1) >= 0 then
            pcall(dev.setLine, nrLinii - 1, sformatowany)
        end
    end
end

local function wyczyscMonitor(dev, wMax, hMax)
    setC(dev, colors.white, colors.black)
    if dev.clear then pcall(dev.clear) end
    for i = 1, hMax do
        wypiszWiersz(dev, wMax, hMax, i, "", colors.white, colors.black)
    end
    odswiezFlapy(dev)
end

--------------------------------------------------------------------------------
--        DUŻE NAPISY (LARGE TEXT 1.0) - ADAPTACYJNE RENDEROWANIE TORU        --
--------------------------------------------------------------------------------
local bazaLewy = {}
local bazaPrawy = {}
local trybManualny = false
local scrollOffset = 0

local function rysujWyswietlaczToru(dev, wMax, hMax, nrPeronu, nrToru, bazaDanych)
    if trybManualny then return end

    local czasGry = textutils.formatTime(os.time(), true)
    local isEN = (math.floor(scrollOffset / 16) % 2 == 1)

    -- LINIA 1: NAGŁÓWEK TORU
    local txtP = isEN and "P" or "PERON"
    local txtT = isEN and "T" or "TOR"
    local naglowek = string.format(" %s %s %s %s ", txtP, nrPeronu, txtT, nrToru)
    if wMax >= 18 then
        naglowek = string.format(" PERON %s | TOR %s ", nrPeronu, nrToru)
    end
    local pad = math.max(0, math.floor((wMax - #naglowek) / 2))
    local pelnyNaglowek = string.rep(" ", pad) .. naglowek .. string.rep(" ", wMax - #naglowek - pad)
    wypiszWiersz(dev, wMax, hMax, 1, pelnyNaglowek:sub(1, wMax), colors.yellow, colors.blue)

    local pociag = bazaDanych[1]

    if pociag then
        local opoznienieNum = tonumber(pociag.opoznienie) or 0
        local opoznTag = (opoznienieNum > 0) and string.format(" +%dm", opoznienieNum) or ""

        -- LINIA 2: CZAS + NAZWA POCIĄGU / SYGNATURA
        local linia2 = string.format("%s %s%s", pociag.czas or "--:--", pociag.pociag or "Pociag", opoznTag)
        local kolL2 = (opoznienieNum > 0) and colors.orange or colors.yellow
        wypiszWiersz(dev, wMax, hMax, 2, linia2:sub(1, wMax), kolL2, colors.black)

        -- LINIA 3: KIERUNEK / STACJA DOCELOWA (PŁYNNY MARQUEE SCROLL)
        local relacja = "-> " .. (pociag.punkt or "Stacja Docelowa")
        if #relacja > wMax then
            local rozszerzony = relacja .. "   " .. relacja
            local startIdx = (scrollOffset % (#relacja + 3)) + 1
            relacja = rozszerzony:sub(startIdx, startIdx + wMax - 1)
        end
        wypiszWiersz(dev, wMax, hMax, 3, relacja:sub(1, wMax), colors.white, colors.black)

        -- LINIA 4: STATUS WJAZDU / OPÓŹNIENIA
        if hMax >= 4 then
            local txtStatus = opoznienieNum > 0 and (isEN and "DELAYED" or "OPOZNIENIE")
                              or (isEN and "APPROACHING" or "WJEZDZA")
            wypiszWiersz(dev, wMax, hMax, 4, " " .. txtStatus, opoznienieNum > 0 and colors.red or colors.lime, colors.black)
        end

        -- LINIA 5: SEKTORY PERONOWE
        if hMax >= 5 then
            local txtSektor = "SEK: A B C"
            if wMax >= 18 then txtSektor = "SEKTORY: [A] [B] [C]" end
            wypiszWiersz(dev, wMax, hMax, 5, " " .. txtSektor, colors.lightBlue, colors.black)
        end
    else
        -- Brak pociągu na tym torze
        local txtBrak = isEN and "NO TRAINS" or "BRAK ODJAZDU"
        local txtWolny = isEN and ("Track " .. nrToru .. " OK") or ("Tor " .. nrToru .. " wolny")
        wypiszWiersz(dev, wMax, hMax, 2, txtBrak:sub(1, wMax), colors.lightGray, colors.black)
        wypiszWiersz(dev, wMax, hMax, 3, txtWolny:sub(1, wMax), colors.gray, colors.black)
        if hMax >= 4 then wypiszWiersz(dev, wMax, hMax, 4, " " .. czasGry, colors.yellow, colors.black) end
        if hMax >= 5 then wypiszWiersz(dev, wMax, hMax, 5, "", colors.black, colors.black) end
    end

    odswiezFlapy(dev)
end

local function odswiezObuMonitorow()
    rysujWyswietlaczToru(dispLewy, wLewy, hLewy, config.peron, config.torLewy, bazaLewy)
    if dispPrawy ~= dispLewy then
        rysujWyswietlaczToru(dispPrawy, wPrawy, hPrawy, config.peron, config.torPrawy, bazaPrawy)
    end
end

--------------------------------------------------------------------------------
--                   KONSOLA STERUJĄCA I REDNET LOOP                          --
--------------------------------------------------------------------------------
term.clear()
term.setCursorPos(1, 1)
print("========================================")
print("  STEROWNIK ELEKTRONICZNA 3x1 (2 TOR)   ")
print("========================================")
print(string.format("Stacja: %s | Peron: %s | Skala: %s", config.stacja, config.peron, tostring(config.skalaTekstu or 0.5)))
print(string.format("LEWY TOR %s:  %s (%dx%d)", config.torLewy, nameLewy, wLewy, hLewy))
print(string.format("PRAWY TOR %s: %s (%dx%d)", config.torPrawy, namePrawy, wPrawy, hPrawy))
print(string.format("Audio TTS:   %s", tts and "NATIVE ENGLISH TTS" or "Gong CC"))
print("Nacisnij [S] aby ZAMIENIC STRONY monitorow (Lewy <-> Prawy)")
print("Nacisnij [C] aby zmienic konfiguracje / skale napisow.")
print("Laczenie z centrala...")

local serverId = rednet.lookup(PROTOKOL, SERWER_HOST)
local lastServerCheck = os.clock()

local function pobierzServerId()
    if not serverId or (os.clock() - lastServerCheck > 10) then
        lastServerCheck = os.clock()
        local id = rednet.lookup(PROTOKOL, SERWER_HOST)
        if id then serverId = id end
    end
    return serverId
end

serverId = pobierzServerId()
while not serverId do
    sleep(1.5)
    serverId = pobierzServerId()
end

print("Polaczono z centrala #" .. serverId)
wyczyscMonitor(dispLewy, wLewy, hLewy)
if dispPrawy ~= dispLewy then wyczyscMonitor(dispPrawy, wPrawy, hPrawy) end
odswiezObuMonitorow()

rednet.send(serverId, {
    typ = "PING",
    nazwa = string.format("Tablica3x1_Peron%s", config.peron),
    tryb = "DISPLAY_3X1",
    status = string.format("L:T%s R:T%s", config.torLewy, config.torPrawy)
}, PROTOKOL)
rednet.send(serverId, { typ = "POBIERZ_BAZE" }, PROTOKOL)

local zegarTimer = os.startTimer(0.4)
local pingTimer = os.startTimer(2.0)

while true do
    local event, p1, p2, p3 = os.pullEvent()

    if event == "rednet_message" and p3 == PROTOKOL then
        local senderId, msg = p1, p2
        if type(msg) == "table" then
            if msg.typ == "PRZEJAZD_POCIAGU" or (msg.typ == "NOWY_LOG" and msg.kategoria == "PRZEJAZD") then
                trybManualny = false
                local czas = msg.czas or textutils.formatTime(os.time(), true)
                local punkt = msg.nazwa or msg.punkt or ("KM_" .. senderId)
                local pociag = msg.pociag or "Pociag"
                local opoznienie = msg.opoznienie or 0
                local wykrytyTor = tostring(msg.tor or msg.track or "")

                if wykrytyTor == tostring(config.torLewy) or (wykrytyTor == "" and config.torLewy == "1") then
                    table.insert(bazaLewy, 1, { czas = czas, punkt = punkt, pociag = pociag, opoznienie = opoznienie })
                    if #bazaLewy > 5 then table.remove(bazaLewy) end
                end

                if wykrytyTor == tostring(config.torPrawy) or (wykrytyTor == "" and config.torPrawy == "2") then
                    table.insert(bazaPrawy, 1, { czas = czas, punkt = punkt, pociag = pociag, opoznienie = opoznienie })
                    if #bazaPrawy > 5 then table.remove(bazaPrawy) end
                end

                if tts then
                    pcall(function() tts.announceTrain(pociag, config.peron, (wykrytyTor ~= "" and wykrytyTor or config.torLewy)) end)
                else
                    zagrajGongDworcowy()
                end

                scrollOffset = 0
                odswiezObuMonitorow()

            elseif msg.typ == "BAZA_PRZEJAZDOW" and msg.baza then
                if not trybManualny then
                    bazaLewy = {}
                    bazaPrawy = {}
                    for i = #msg.baza, 1, -1 do
                        local r = msg.baza[i]
                        local czas = r.czas_gry or (r.timestamp and r.timestamp:sub(12,16)) or "--:--"
                        local punkt = r.posterunek or "Trasa"
                        local pociag = r.nazwa_pociagu or "Pociag"
                        local opoznienie = r.opoznienie or 0
                        local torR = tostring(r.tor or "")

                        if #bazaLewy < 5 and (torR == tostring(config.torLewy) or (torR == "" and config.torLewy == "1")) then
                            table.insert(bazaLewy, { czas = czas, punkt = punkt, pociag = pociag, opoznienie = opoznienie })
                        end
                        if #bazaPrawy < 5 and (torR == tostring(config.torPrawy) or (torR == "" and config.torPrawy == "2")) then
                            table.insert(bazaPrawy, { czas = czas, punkt = punkt, pociag = pociag, opoznienie = opoznienie })
                        end
                    end
                    scrollOffset = 0
                    odswiezObuMonitorow()
                end

            elseif msg.typ == "SYNC_STACJA" and msg.stacja then
                if msg.stacja.nazwa then
                    config.stacja = msg.stacja.nazwa
                    zapiszConfig(config)
                    odswiezObuMonitorow()
                    print("[SYNC] Zaktualizowano nazwe stacji: " .. config.stacja)
                end

            elseif msg.typ == "ZAPYTANIE_TABLICA" then
                rednet.send(senderId, {
                    typ = "ODPOWIEDZ_TABLICA",
                    id = MOJE_ID,
                    szer = wLewy,
                    wys = hLewy,
                    typDisp = string.format("Peron %s (Tor %s & Tor %s)", config.peron, config.torLewy, config.torPrawy)
                }, PROTOKOL)

            elseif msg.typ == "USTAW_TEKST_TABLICY" then
                trybManualny = true
                local nr = tonumber(msg.linia) or 1
                local txt = msg.tekst or ""
                wypiszWiersz(dispLewy, wLewy, hLewy, nr, txt, colors.yellow, colors.black)
                if dispPrawy ~= dispLewy then wypiszWiersz(dispPrawy, wPrawy, hPrawy, nr, txt, colors.yellow, colors.black) end
                odswiezFlapy(dispLewy)
                if dispPrawy ~= dispLewy then odswiezFlapy(dispPrawy) end

            elseif msg.typ == "TEST_TABLICY" then
                trybManualny = true
                wyczyscMonitor(dispLewy, wLewy, hLewy)
                if dispPrawy ~= dispLewy then wyczyscMonitor(dispPrawy, wPrawy, hPrawy) end
                wypiszWiersz(dispLewy, wLewy, hLewy, 1, string.format("TEST PERON %s TOR %s", config.peron, config.torLewy), colors.yellow, colors.blue)
                if dispPrawy ~= dispLewy then wypiszWiersz(dispPrawy, wPrawy, hPrawy, 1, string.format("TEST PERON %s TOR %s", config.peron, config.torPrawy), colors.yellow, colors.blue) end
                if tts then pcall(function() tts.announceTrain("test", config.peron, config.torLewy) end) else zagrajGongDworcowy() end

            elseif msg.typ == "WYCZYSC_TABLICE" then
                trybManualny = true
                wyczyscMonitor(dispLewy, wLewy, hLewy)
                if dispPrawy ~= dispLewy then wyczyscMonitor(dispPrawy, wPrawy, hPrawy) end

            elseif msg.typ == "RESET_TABLICY" then
                trybManualny = false
                wyczyscMonitor(dispLewy, wLewy, hLewy)
                if dispPrawy ~= dispLewy then wyczyscMonitor(dispPrawy, wPrawy, hPrawy) end
                scrollOffset = 0
                odswiezObuMonitorow()

            elseif msg.typ == "USTAW_CONFIG_WEEZLA" then
                local tId = msg.targetId
                if not tId or tId == MOJE_ID then
                    if msg.systemConfig then
                        local f = fs.open("system_config.json", "w")
                        f.write(textutils.serializeJSON(msg.systemConfig))
                        f.close()
                    end
                    if msg.nodeConfig then
                        zapiszConfig(msg.nodeConfig)
                    end
                    rednet.send(senderId, { typ = "POTWIERDZENIE_CONFIG", id = MOJE_ID, ok = true }, PROTOKOL)
                    if msg.reboot ~= false then
                        print("Zdalna zmiana konfiguracji! Restart...")
                        sleep(0.5)
                        os.reboot()
                    end
                end

            elseif msg.typ == "REBOOT" or msg.typ == "REBOOT_ALL" then
                local tId = msg.targetId
                local tTryb = msg.targetTryb
                local myId = os.getComputerID()

                if not tId and not tTryb or (tId and tId == myId) or (tTryb and (tTryb == "DISPLAY" or tTryb == "PERON" or tTryb == "DISPLAY_3X1")) then
                    print("Received remote REBOOT command!")
                    sleep(0.5)
                    os.reboot()
                end
            end
        end

    elseif event == "key" and p1 == keys.s then
        local tmpMon = config.monLewy
        config.monLewy = config.monPrawy
        config.monPrawy = tmpMon

        zapiszConfig(config)

        dispLewy, nameLewy, wLewy, hLewy = InicjalizujMonitor(config.monLewy, config.skalaTekstu)
        dispPrawy, namePrawy, wPrawy, hPrawy = InicjalizujMonitor(config.monPrawy, config.skalaTekstu)

        wyczyscMonitor(dispLewy, wLewy, hLewy)
        if dispPrawy ~= dispLewy then wyczyscMonitor(dispPrawy, wPrawy, hPrawy) end
        odswiezObuMonitorow()

        print("\n[OK] Zamieniono strony monitorow miejscami (Lewy <-> Prawy)!")

    elseif event == "key" and p1 == keys.c then
        config = kreatorKonfiguracji()
        dispLewy, nameLewy, wLewy, hLewy = InicjalizujMonitor(config.monLewy, config.skalaTekstu)
        dispPrawy, namePrawy, wPrawy, hPrawy = InicjalizujMonitor(config.monPrawy, config.skalaTekstu)
        wyczyscMonitor(dispLewy, wLewy, hLewy)
        if dispPrawy ~= dispLewy then wyczyscMonitor(dispPrawy, wPrawy, hPrawy) end
        odswiezObuMonitorow()

    elseif event == "timer" and p1 == pingTimer then
        serverId = pobierzServerId()
        if serverId then
            local sysCfg = nil
            if fs.exists("system_config.json") then
                local f = fs.open("system_config.json", "r")
                sysCfg = textutils.unserializeJSON(f.readAll())
                f.close()
            end
            rednet.send(serverId, {
                typ = "PING",
                nazwa = string.format("Tablica3x1_Peron%s", config.peron),
                tryb = "DISPLAY_3X1",
                rola = (sysCfg and sysCfg.rola) or "electric_display",
                idStacji = config.stacja or "ST",
                status = string.format("L:T%s R:T%s", config.torLewy, config.torPrawy),
                systemConfig = sysCfg,
                nodeConfig = config
            }, PROTOKOL)
        end
        pingTimer = os.startTimer(2.0)

    elseif event == "timer" and p1 == zegarTimer then
        scrollOffset = scrollOffset + 1
        if not trybManualny then odswiezObuMonitorow() end
        zegarTimer = os.startTimer(0.4)
    end
end
