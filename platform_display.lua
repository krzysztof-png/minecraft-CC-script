--------------------------------------------------------------------------------
--         PROFESJONALNY WYŚWIETLACZ PERONOWY / TOROWY (platform_display.lua)    --
--------------------------------------------------------------------------------
local CONFIG_FILE = "platform_config.json"
local PROTOKOL    = "kolej_net"
local SERWER_HOST = "centrala_glowna"
local MOJE_ID     = os.getComputerID()

local tts = fs.exists("tts.lua") and dofile("tts.lua") or nil

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

local function kreatorKonfiguracji()
    term.clear()
    term.setCursorPos(1, 1)
    print("========================================")
    print("    KREATOR WYŚWIETLACZA PERONOWEGO     ")
    print("========================================")

    write("Nazwa Stacji (np. Centralna): ")
    local stacja = read()
    if stacja == "" then stacja = "Stacja_" .. MOJE_ID end

    write("Numer Peronu (np. 1, 2...): ")
    local peron = read()
    if peron == "" then peron = "1" end

    write("Numer Toru (np. 1, 2, 4...): ")
    local tor = read()
    if tor == "" then tor = "1" end

    local cfg = {
        stacja = stacja,
        peron = peron,
        tor = tor
    }
    zapiszConfig(cfg)
    return cfg
end

local config = wczytajConfig()
if not config then
    config = kreatorKonfiguracji()
end

-- 1. Inicjalizacja modemu oraz głośnika stacyjnego
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
--                     WYSZUKANIE EKRANU / MONITORÓW                          --
--------------------------------------------------------------------------------
local function znajdzWyswietlacz()
    local mon = peripheral.find("monitor")
    if mon then
        pcall(function() mon.setTextScale(0.5) end)
        return mon, peripheral.getName(mon), "monitor"
    end

    for _, name in ipairs(peripheral.getNames()) do
        if name ~= peripheral.getName(modem) then
            local dev = peripheral.wrap(name)
            if dev and (dev.write or dev.setLine or dev.update) then
                local t = (peripheral.getType(name) or ""):lower()
                if not t:find("modem") and not t:find("drive") and not t:find("computer") then
                    return dev, name, t
                end
            end
        end
    end

    return term.native(), "terminal", "terminal"
end

local display, dispName, dispType = znajdzWyswietlacz()

local function pobierzWymiary()
    if display and display.getSize then
        local ok, w, h = pcall(display.getSize)
        if ok and w and h and type(w) == "number" and w > 0 then
            return w, h
        end
    end
    local w, h = term.getSize()
    return w or 32, h or 6
end

local szerokosc, wysokosc = pobierzWymiary()

local function setC(fg, bg)
    if display.setTextColor then pcall(display.setTextColor, fg or colors.white) end
    if display.setBackgroundColor then pcall(display.setBackgroundColor, bg or colors.black) end
end

local function odswiezFlapyTablicy()
    if not display then return end
    if display.update then pcall(display.update) end
    if display.flush then pcall(display.flush) end
    if display.render then pcall(display.render) end
end

local function wypiszWiersz(nrLinii, tekst, fg, bg)
    if not display or nrLinii < 1 or nrLinii > wysokosc then return end

    local sformatowany = string.format("%-" .. szerokosc .. "s", tekst):sub(1, szerokosc)
    setC(fg or colors.white, bg or colors.black)

    if display.setCursorPos and display.write then
        pcall(display.setCursorPos, 1, nrLinii)
        pcall(display.write, sformatowany)
    end

    if display.setLine then
        local ok = pcall(display.setLine, nrLinii, sformatowany)
        if not ok and (nrLinii - 1) >= 0 then
            pcall(display.setLine, nrLinii - 1, sformatowany)
        end
    end
end

local function wyczyscTablice()
    setC(colors.white, colors.black)
    if display.clear then pcall(display.clear) end
    for i = 1, wysokosc do
        wypiszWiersz(i, "", colors.white, colors.black)
    end
    odswiezFlapyTablicy()
end

--------------------------------------------------------------------------------
--       STAN I DWUJĘZYCZNE RENDEROWANIE TABLICY PERONOWEJ                     --
--------------------------------------------------------------------------------
local historiaPrzejazdow = {}
local trybManualny = false
local scrollOffset = 0
local jezykAngielski = false

local function odswiezWyświetlaczPeronowy()
    if trybManualny then return end

    local czasGry = textutils.formatTime(os.time(), true)
    jezykAngielski = (math.floor(scrollOffset / 16) % 2 == 1)

    local txtPeron = jezykAngielski and "PLATFORM" or "PERON"
    local txtTor   = jezykAngielski and "TRACK"    or "TOR"
    local naglowekPeronu = string.format(" %s %s | %s %s | %s ", txtPeron, config.peron, txtTor, config.tor, config.stacja:upper())
    
    local pad = math.max(0, math.floor((szerokosc - #naglowekPeronu) / 2))
    local pelnyNaglowek = string.rep(" ", pad) .. naglowekPeronu .. string.rep(" ", szerokosc - #naglowekPeronu - pad)
    wypiszWiersz(1, pelnyNaglowek, colors.yellow, colors.blue)

    local pociag = historiaPrzejazdow[1]

    if pociag then
        local opoznienieNum = tonumber(pociag.opoznienie) or 0
        local opoznTag = (opoznienieNum > 0) and (jezykAngielski and string.format(" [DELAY +%dm]", opoznienieNum) or string.format(" [+%d MIN]", opoznienieNum)) or ""

        local linia2 = string.format("[%s] %s%s", pociag.czas, pociag.pociag or "Pociag Osobowy", opoznTag)
        local kolLinia2 = (opoznienieNum > 0) and colors.orange or colors.yellow
        wypiszWiersz(2, linia2, kolLinia2, colors.black)

        local relacja = (jezykAngielski and "-> TO: " or "-> DO: ") .. (pociag.punkt or "Stacja Docelowa")
        if #relacja > szerokosc then
            local rozszerzony = relacja .. "   " .. relacja
            local startIdx = (scrollOffset % (#relacja + 3)) + 1
            relacja = rozszerzony:sub(startIdx, startIdx + szerokosc - 1)
        end
        wypiszWiersz(3, relacja, colors.white, colors.black)

        if wysokosc >= 4 then
            local txtStatus = opoznienieNum > 0 and (jezykAngielski and " OPOZNIENIE / DELAYED " or " OPOZNIENIE POCIAGU ")
                              or (jezykAngielski and " STATUS: APPROACHING TRACK " or " STATUS: WJEZDZA NA TOR ") .. config.tor
            wypiszWiersz(4, txtStatus, opoznienieNum > 0 and colors.red or colors.lime, colors.black)
        end
        if wysokosc >= 5 then
            local txtSektor = jezykAngielski and " SECTORS: [ A ] [ B ] [ C ]" or " SEKTORY: [ A ] [ B ] [ C ]"
            wypiszWiersz(5, txtSektor, colors.lightBlue, colors.black)
        end
    else
        local txtBrak = jezykAngielski and " NO SCHEDULED DEPARTURES" or " BRAK PLANOWANYCH ODJAZDOW"
        local txtWolny = jezykAngielski and (" Track " .. config.tor .. " clear") or (" Tor " .. config.tor .. " wolny")
        wypiszWiersz(2, txtBrak, colors.lightGray, colors.black)
        wypiszWiersz(3, txtWolny, colors.gray, colors.black)
        if wysokosc >= 4 then wypiszWiersz(4, " Czas / Time: " .. czasGry, colors.yellow, colors.black) end
        if wysokosc >= 5 then wypiszWiersz(5, "", colors.black, colors.black) end
    end

    odswiezFlapyTablicy()
end

--------------------------------------------------------------------------------
--                       KONSOLA I OBSŁUGA REDNET                               --
--------------------------------------------------------------------------------
term.clear()
term.setCursorPos(1, 1)
print("========================================")
print("    PROFESJONALNY WYŚWIETLACZ PERONOWY  ")
print("========================================")
print(string.format("Stacja:  %s | Peron: %s | Tor: %s", config.stacja, config.peron, config.tor))
print(string.format("TTS Audio: %s", tts and "ENGLISH TTS ACTIVE" or (speaker and "AKTYWNY (Gong)" or "Brak")))
print(string.format("Ekran:   %s (%dx%d)", dispName, szerokosc, wysokosc))
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
wyczyscTablice()
odswiezWyświetlaczPeronowy()

rednet.send(serverId, {
    typ = "PING",
    nazwa = string.format("Peron_%s_Tor_%s", config.peron, config.tor),
    tryb = "PERON",
    status = string.format("%dx%d", szerokosc, wysokosc)
}, PROTOKOL)
rednet.send(serverId, { typ = "POBIERZ_BAZE" }, PROTOKOL)

local zegarTimer = os.startTimer(0.5)
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

                table.insert(historiaPrzejazdow, 1, { czas = czas, punkt = punkt, pociag = pociag, opoznienie = opoznienie })
                if #historiaPrzejazdow > 5 then table.remove(historiaPrzejazdow) end

                -- Zapowiedź dźwiękowa English TTS + Gong!
                if tts then
                    pcall(function() tts.announceTrain(pociag, config.peron, config.tor) end)
                else
                    zagrajGongDworcowy()
                end

                print(string.format("[%s] Odnotowano peronowy: %s -> %s", czas, punkt, pociag))
                scrollOffset = 0
                odswiezWyświetlaczPeronowy()

            elseif msg.typ == "BAZA_PRZEJAZDOW" and msg.baza then
                if not trybManualny then
                    historiaPrzejazdow = {}
                    for i = #msg.baza, math.max(1, #msg.baza - 4), -1 do
                        local r = msg.baza[i]
                        local czas = r.czas_gry or (r.timestamp and r.timestamp:sub(12,16)) or "--:--"
                        local punkt = r.posterunek or "Trasa"
                        local pociag = r.nazwa_pociagu or "Pociag"
                        local opoznienie = r.opoznienie or 0
                        table.insert(historiaPrzejazdow, { czas = czas, punkt = punkt, pociag = pociag, opoznienie = opoznienie })
                    end
                    scrollOffset = 0
                    odswiezWyświetlaczPeronowy()
                end

            elseif msg.typ == "ZAPYTANIE_TABLICA" then
                rednet.send(senderId, {
                    typ = "ODPOWIEDZ_TABLICA",
                    id = MOJE_ID,
                    szer = szerokosc,
                    wys = wysokosc,
                    typDisp = string.format("Peron %s Tor %s", config.peron, config.tor)
                }, PROTOKOL)

            elseif msg.typ == "USTAW_TEKST_TABLICY" then
                trybManualny = true
                local nr = tonumber(msg.linia) or 1
                local txt = msg.tekst or ""
                wypiszWiersz(nr, txt, colors.yellow, colors.black)
                odswiezFlapyTablicy()
                print(string.format("[MANUAL PERON] Wiersz %d: %s", nr, txt))

            elseif msg.typ == "TEST_TABLICY" then
                trybManualny = true
                wyczyscTablice()
                wypiszWiersz(1, string.format("TEST PERON %s TOR %s", config.peron, config.tor), colors.yellow, colors.blue)
                for l = 2, wysokosc do
                    wypiszWiersz(l, string.format("%d. TEST %s", l - 1, textutils.formatTime(os.time(), true)), colors.white, colors.black)
                end
                odswiezFlapyTablicy()
                if tts then pcall(function() tts.announceTrain("test", config.peron, config.tor) end) else zagrajGongDworcowy() end

            elseif msg.typ == "WYCZYSC_TABLICE" then
                trybManualny = true
                wyczyscTablice()

            elseif msg.typ == "RESET_TABLICY" then
                trybManualny = false
                wyczyscTablice()
                scrollOffset = 0
                odswiezWyświetlaczPeronowy()
                if serverId then rednet.send(serverId, { typ = "POBIERZ_BAZE" }, PROTOKOL) end

            elseif msg.typ == "USTAW_CONFIG_WEEZLA" then
                local tId = msg.targetId
                local myId = os.getComputerID()
                if not tId or tId == myId then
                    if msg.systemConfig then
                        local f = fs.open("system_config.json", "w")
                        f.write(textutils.serializeJSON(msg.systemConfig))
                        f.close()
                    end
                    if msg.nodeConfig then
                        local f = fs.open(CONFIG_FILE, "w")
                        f.write(textutils.serializeJSON(msg.nodeConfig))
                        f.close()
                    end
                    rednet.send(senderId, { typ = "POTWIERDZENIE_CONFIG", id = myId, ok = true }, PROTOKOL)
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
                    print("Otrzymano zdalne polecenie REBOOT!")
                    sleep(0.5)
                    os.reboot()
                end
            end
        end

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
                nazwa = string.format("Peron_%s_Tor_%s", config.peron, config.tor),
                tryb = "PERON",
                rola = (sysCfg and sysCfg.rola) or "platform_display",
                idStacji = config.stacja or "ST",
                status = string.format("%dx%d", szerokosc, wysokosc),
                systemConfig = sysCfg,
                nodeConfig = config
            }, PROTOKOL)
        end
        pingTimer = os.startTimer(2.0)

    elseif event == "timer" and p1 == zegarTimer then
        scrollOffset = scrollOffset + 1
        if not trybManualny then odswiezWyświetlaczPeronowy() end
        zegarTimer = os.startTimer(0.5)
    end
end
