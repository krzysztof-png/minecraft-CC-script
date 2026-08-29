--------------------------------------------------------------------------------
--      PROFESJONALNA ELEKTRONICZNA TABLICA 3x1 (electric_display.lua)           --
--------------------------------------------------------------------------------
local PROTOKOL      = "kolej_net"
local SERWER_HOST   = "centrala_glowna"
local TYTUL_TABLICY = "ODJAZDY / DEPARTURES"
local NAZWA_STACJI  = "STACJA CENTRALNA"
local MOJE_ID       = os.getComputerID()

-- 1. Inicjalizacja modemu
local modem = peripheral.find("modem")
if not modem then
    error("Blad: Nie znaleziono modemu bezprzewodowego/ender!")
end
rednet.open(peripheral.getName(modem))

--------------------------------------------------------------------------------
--                WYKRYWANIE I ADAPTACJA MONITORA / DISP 3x1                  --
--------------------------------------------------------------------------------
local function znajdzWyswietlacz3x1()
    local mon = peripheral.find("monitor")
    if mon then
        -- Automatyczna najlepsza skala tekstu dla 3x1 bloków w CC (0.5)
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

local display, dispName, dispType = znajdzWyswietlacz3x1()

local function pobierzWymiary()
    if display and display.getSize then
        local ok, w, h = pcall(display.getSize)
        if ok and w and h and type(w) == "number" and w > 0 then
            return w, h
        end
    end
    local w, h = term.getSize()
    return w or 26, h or 6
end

local szerokosc, wysokosc = pobierzWymiary()
local isColor = display.isColor and display.isColor() or false

-- Odświeżenie płatków / bufora ekranu
local function odswiezFlapyTablicy()
    if not display then return end
    if display.update then pcall(display.update) end
    if display.flush then pcall(display.flush) end
    if display.render then pcall(display.render) end
end

local function setC(fg, bg)
    if display.setTextColor then pcall(display.setTextColor, fg or colors.white) end
    if display.setBackgroundColor then pcall(display.setBackgroundColor, bg or colors.black) end
end

-- Rysowanie kolorowego tekstu na wybranej pozycji
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
--            STAN I PROFESJONALNY UKŁAD GRAFICZNY 3x1                         --
--------------------------------------------------------------------------------
local historiaPrzejazdow = {}
local trybManualny = false
local scrollOffset = 0

local function odswiezTablicePro()
    if trybManualny then return end

    local czasGry = textutils.formatTime(os.time(), true)

    -- LINIA 1: Pasek nagłówkowy stacji (Granatowe tło, Złote litery)
    local naglowek = string.format(" %s | %s ", NAZWA_STACJI, czasGry)
    if #naglowek < szerokosc then
        local spacja = math.floor((szerokosc - #naglowek) / 2)
        naglowek = string.rep(" ", spacja) .. naglowek .. string.rep(" ", szerokosc - #naglowek - spacja)
    end
    wypiszWiersz(1, naglowek:sub(1, szerokosc), colors.yellow, colors.blue)

    -- LINIA 2: Kolumny Nagłówkowe (jeśli wysokość ekranu pozwala)
    local startRow = 2
    if wysokosc >= 6 then
        local headerCols = string.format("%-5s %-15s %s", "CZAS", "POCIAG / RELACJA", "TOR")
        wypiszWiersz(2, headerCols:sub(1, szerokosc), colors.lightGray, colors.gray)
        startRow = 3
    end

    -- Wiersze Odjazdów (z podziałem na Czas | Nazwa/Relacja | Status)
    local maxWierszy = wysokosc - startRow + 1
    if wysokosc >= 7 then maxWierszy = maxWierszy - 1 end -- miejsce na dolny pasek komunikatów

    for i = 1, maxWierszy do
        local currRow = startRow + i - 1
        local wpis = historiaPrzejazdow[i]

        if wpis then
            local czasStr = (wpis.czas or "--:--"):sub(1, 5)
            local rawRelacja = (wpis.punkt or "Trasa")
            if wpis.pociag and wpis.pociag ~= "" then
                rawRelacja = rawRelacja .. " -> " .. wpis.pociag
            end

            -- Maksymalna szerokość dla nazwy pociągu (zostawiamy miejsce na czas i tor)
            local szerRelacji = szerokosc - 9
            local relacjaWyswietlana = rawRelacja

            if #rawRelacja > szerRelacji then
                local rozszerzona = rawRelacja .. "   " .. rawRelacja
                local startIdx = ((scrollOffset + i * 2) % (#rawRelacja + 3)) + 1
                relacjaWyswietlana = rozszerzona:sub(startIdx, startIdx + szerRelacji - 1)
            else
                relacjaWyswietlana = string.format("%-" .. szerRelacji .. "s", rawRelacja)
            end

            local statusTor = (i == 1 and "T1 WJEZDZA") or "T" .. i
            local wierszTekst = string.format("%-5s %s %-3s", czasStr, relacjaWyswietlana:sub(1, szerRelacji), statusTor:sub(1,3))

            -- Kolorowanie wierszy: 1. odjazd na żółto (LED), kolejne na biało
            local kolorFru = (i == 1) and colors.yellow or colors.white
            local kolorBgu = (i % 2 == 0) and colors.black or colors.black
            wypiszWiersz(currRow, wierszTekst:sub(1, szerokosc), kolorFru, kolorBgu)
        else
            wypiszWiersz(currRow, "", colors.gray, colors.black)
        end
    end

    -- DOLNY PASEK KOMUNIKATÓW (dla monitorów >= 7 wierszy)
    if wysokosc >= 7 then
        local baner = " *** BEZPIECZENSTWO NA TORACH: ZACHOWAJ OSTROZNOSC PRZY WJEZDZIE POCIAGU *** "
        local startB = (scrollOffset % (#baner + 1)) + 1
        local banerWyswietlany = (baner .. baner):sub(startB, startB + szerokosc - 1)
        wypiszWiersz(wysokosc, banerWyswietlany, colors.orange, colors.black)
    end

    odswiezFlapyTablicy()
end

--------------------------------------------------------------------------------
--                   KONSOLA I OBSŁUGA REDNET                                 --
--------------------------------------------------------------------------------
term.clear()
term.setCursorPos(1, 1)
print("========================================")
print("  PROFESJONALNA TABLICA ELEKTRONICZNA  ")
print("========================================")
print(string.format("Urzadzenie: %s (%s)", dispName, dispType))
print(string.format("Rozdzielczosc: %d x %d znakow", szerokosc, wysokosc))
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
odswiezTablicePro()

rednet.send(serverId, {
    typ = "PING",
    nazwa = "Tablica_3x1_PRO_#" .. MOJE_ID,
    tryb = "DISPLAY_3X1",
    status = string.format("%dx%d", szerokosc, wysokosc)
}, PROTOKOL)
rednet.send(serverId, { typ = "POBIERZ_BAZE" }, PROTOKOL)

local zegarTimer = os.startTimer(0.4) -- Odświeżanie co 0.4s dla najwyższej płynności
local pingTimer = os.startTimer(2.0)
local rescanTimer = os.startTimer(5.0)

while true do
    local event, p1, p2, p3 = os.pullEvent()

    if event == "rednet_message" and p3 == PROTOKOL then
        local senderId, msg = p1, p2
        if type(msg) == "table" then
            if msg.typ == "PRZEJAZD_POCIAGU" or (msg.typ == "NOWY_LOG" and msg.kategoria == "PRZEJAZD") then
                trybManualny = false
                local czas = msg.czas or textutils.formatTime(os.time(), true)
                local punkt = msg.nazwa or msg.punkt or ("KM_" .. senderId)
                local pociag = msg.pociag

                table.insert(historiaPrzejazdow, 1, { czas = czas, punkt = punkt, pociag = pociag })
                if #historiaPrzejazdow > 8 then table.remove(historiaPrzejazdow) end

                print(string.format("[%s] Odnotowano pro 3x1: %s", czas, punkt))
                scrollOffset = 0
                odswiezTablicePro()

            elseif msg.typ == "BAZA_PRZEJAZDOW" and msg.baza then
                if not trybManualny then
                    historiaPrzejazdow = {}
                    for i = #msg.baza, math.max(1, #msg.baza - 7), -1 do
                        local r = msg.baza[i]
                        local czas = r.czas_gry or (r.timestamp and r.timestamp:sub(12,16)) or "--:--"
                        local punkt = r.posterunek or "Trasa"
                        local pociag = r.nazwa_pociagu
                        table.insert(historiaPrzejazdow, { czas = czas, punkt = punkt, pociag = pociag })
                    end
                    scrollOffset = 0
                    odswiezTablicePro()
                end

            elseif msg.typ == "ZAPYTANIE_TABLICA" then
                rednet.send(senderId, {
                    typ = "ODPOWIEDZ_TABLICA",
                    id = MOJE_ID,
                    szer = szerokosc,
                    wys = wysokosc,
                    typDisp = "Tablica_3x1_PRO (" .. dispType .. ")"
                }, PROTOKOL)

            elseif msg.typ == "USTAW_TEKST_TABLICY" then
                trybManualny = true
                local nr = tonumber(msg.linia) or 1
                local txt = msg.tekst or ""
                wypiszWiersz(nr, txt, colors.yellow, colors.black)
                odswiezFlapyTablicy()
                print(string.format("[MANUAL PRO] Wiersz %d: %s", nr, txt))

            elseif msg.typ == "TEST_TABLICY" then
                trybManualny = true
                wyczyscTablice()
                wypiszWiersz(1, string.format("TEST PRO 3x1 [%dx%d]", szerokosc, wysokosc), colors.yellow, colors.blue)
                for l = 2, wysokosc do
                    wypiszWiersz(l, string.format("%d. TEST PRO %s", l - 1, textutils.formatTime(os.time(), true)), colors.white, colors.black)
                end
                odswiezFlapyTablicy()
                print("[TEST PRO] Wyslano wzorzec testowy.")

            elseif msg.typ == "WYCZYSC_TABLICE" then
                trybManualny = true
                wyczyscTablice()
                print("[MANUAL] Wyczyszczono tablice pro 3x1.")

            elseif msg.typ == "RESET_TABLICY" then
                trybManualny = false
                wyczyscTablice()
                scrollOffset = 0
                odswiezTablicePro()
                if serverId then rednet.send(serverId, { typ = "POBIERZ_BAZE" }, PROTOKOL) end
                print("[RESET PRO] Przywrocono tryb ODJAZDY.")

            elseif msg.typ == "REBOOT" or msg.typ == "REBOOT_ALL" then
                print("Otrzymano zdalne polecenie REBOOT!")
                sleep(0.5)
                os.reboot()
            end
        end

    elseif event == "timer" and p1 == pingTimer then
        serverId = pobierzServerId()
        if serverId then
            rednet.send(serverId, {
                typ = "PING",
                nazwa = "Tablica_3x1_PRO_#" .. MOJE_ID,
                tryb = "DISPLAY_3X1",
                status = string.format("%dx%d", szerokosc, wysokosc)
            }, PROTOKOL)
        end
        pingTimer = os.startTimer(2.0)

    elseif event == "timer" and p1 == rescanTimer then
        local nDisp, nName, nType = znajdzWyswietlacz3x1()
        if nDisp ~= display then
            display = nDisp
            dispName = nName
            dispType = nType
            szerokosc, wysokosc = pobierzWymiary()
            wyczyscTablice()
            if not trybManualny then odswiezTablicePro() end
        end
        pobierzServerId()
        rescanTimer = os.startTimer(5.0)

    elseif event == "timer" and p1 == zegarTimer then
        scrollOffset = scrollOffset + 1
        if not trybManualny then odswiezTablicePro() end
        zegarTimer = os.startTimer(0.4)
    end
end
