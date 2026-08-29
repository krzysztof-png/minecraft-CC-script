--------------------------------------------------------------------------------
--         ELEKTRONICZNA TABLICA ODJAZDÓW 3x1 BLOKÓW (electric_display.lua)      --
--------------------------------------------------------------------------------
local PROTOKOL      = "kolej_net"
local SERWER_HOST   = "centrala_glowna"
local TYTUL_TABLICY = "ODJAZDY"
local MOJE_ID       = os.getComputerID()

-- 1. Inicjalizacja modemu
local modem = peripheral.find("modem")
if not modem then
    error("Blad: Nie znaleziono modemu bezprzewodowego/ender!")
end
rednet.open(peripheral.getName(modem))

--------------------------------------------------------------------------------
--              WYSZUKANIE I KONFIGURACJA MONITOROW/TABLIC 3x1                --
--------------------------------------------------------------------------------
local function znajdzWyswietlacz3x1()
    -- 1. Szukanie zewnętrznego monitora ComputerCraft
    local mon = peripheral.find("monitor")
    if mon then
        -- Dla ekranu 3x1 bloków w CC zalecany skala tekstu to 0.5 lub 1.0 dla wysokiej czytelności
        pcall(function() mon.setTextScale(0.5) end)
        return mon, peripheral.getName(mon), "monitor"
    end

    -- 2. Szukanie dedykowanych wyświetlaczy Create
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

    -- 3. Fallback: Ekran komputera
    return term.native(), "terminal", "terminal"
end

local display, dispName, dispType = znajdzWyswietlacz3x1()

local function pobierzWymiary()
    if display and display.getSize then
        local ok, w, h = pcall(display.getSize)
        if ok and w and h and w > 0 and h > 0 then
            return w, h
        end
    end
    local w, h = term.getSize()
    return w or 26, h or 5
end

local szerokosc, wysokosc = pobierzWymiary()
local isColor = display.isColor and display.isColor() or false

-- Odświeżenie bufora/płatków tablicy
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

-- Rysowanie pojedynczego wiersza tablicy 3x1
local function wypiszWiersz(nrLinii, tekst, jestNaglowkiem)
    if not display or nrLinii < 1 or nrLinii > wysokosc then return end

    local sformatowany = string.format("%-" .. szerokosc .. "s", tekst):sub(1, szerokosc)

    if jestNaglowkiem then
        setC(colors.yellow, colors.blue)
    else
        setC(colors.white, colors.black)
    end

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
        wypiszWiersz(i, "", false)
    end
    odswiezFlapyTablicy()
end

--------------------------------------------------------------------------------
--                STAN TABLICY I PRZEWIJANIE DŁUGICH NAZW                     --
--------------------------------------------------------------------------------
local historiaPrzejazdow = {}
local trybManualny = false
local scrollOffset = 0

local function odswiezTablice()
    if trybManualny then return end

    local czasGry = textutils.formatTime(os.time(), true)
    
    -- Nagłówek elektroniczny dla 3x1: np. | ODJAZDY [14:35] |
    local naglowek = string.format(" %s [%s] ", TYTUL_TABLICY, czasGry)
    local pad = math.max(0, math.floor((szerokosc - #naglowek) / 2))
    local pelnyNaglowek = string.rep(" ", pad) .. naglowek .. string.rep(" ", szerokosc - #naglowek - pad)
    
    wypiszWiersz(1, pelnyNaglowek, true)

    -- Wiersze 2..wysokosc: Lista odjazdów
    for i = 2, wysokosc do
        local wpis = historiaPrzejazdow[i - 1]
        if wpis then
            local surowyTekst = string.format("%s %s", wpis.czas, wpis.punkt)
            
            -- Płynny przewijany tekst dla nazw dłuższych niż szerokość ekranu 3x1
            local wyswietlany = surowyTekst
            if #surowyTekst > szerokosc then
                local rozszerzony = surowyTekst .. "   " .. surowyTekst
                local startIdx = (scrollOffset % (#surowyTekst + 3)) + 1
                wyswietlany = rozszerzony:sub(startIdx, startIdx + szerokosc - 1)
            end

            wypiszWiersz(i, wyswietlany, false)
        else
            wypiszWiersz(i, "", false)
        end
    end

    odswiezFlapyTablicy()
end

--------------------------------------------------------------------------------
--                      KONSOLA I OBSŁUGA REDNET                               --
--------------------------------------------------------------------------------
term.clear()
term.setCursorPos(1, 1)
print("========================================")
print(" ELEKTRONICZNA TABLICA 3x1 (PKP/CREATE) ")
print("========================================")
print(string.format("Urządzenie: %s (%s)", dispName, dispType))
print(string.format("Rozmiar:    %d x %d znakow", szerokosc, wysokosc))
print("Szukanie serwera centralnego...")

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
odswiezTablice()

-- Rejestracja tablicy i pobranie danych początkowych
rednet.send(serverId, {
    typ = "PING",
    nazwa = "Tablica_3x1_#" .. MOJE_ID,
    tryb = "DISPLAY_3X1",
    status = string.format("%dx%d", szerokosc, wysokosc)
}, PROTOKOL)
rednet.send(serverId, { typ = "POBIERZ_BAZE" }, PROTOKOL)

local zegarTimer = os.startTimer(0.5) -- Odświeżanie co 0.5s dla płynnego animowania przewijania
local pingTimer = os.startTimer(2.0)
local rescanTimer = os.startTimer(5.0)

while true do
    local event, p1, p2, p3 = os.pullEvent()

    -- Odbiór komunikatów sieciowych
    if event == "rednet_message" and p3 == PROTOKOL then
        local senderId, msg = p1, p2
        if type(msg) == "table" then
            if msg.typ == "PRZEJAZD_POCIAGU" or (msg.typ == "NOWY_LOG" and msg.kategoria == "PRZEJAZD") then
                trybManualny = false
                local czas = msg.czas or textutils.formatTime(os.time(), true)
                local punkt = msg.nazwa or msg.punkt or ("KM_" .. senderId)
                local pociag = msg.pociag
                local etykieta = (pociag and pociag ~= "") and (punkt .. "->" .. pociag) or punkt

                table.insert(historiaPrzejazdow, 1, { czas = czas, punkt = etykieta })
                if #historiaPrzejazdow > (wysokosc - 1) then
                    table.remove(historiaPrzejazdow)
                end

                print(string.format("[%s] Odnotowano: %s", czas, etykieta))
                scrollOffset = 0
                odswiezTablice()

            elseif msg.typ == "BAZA_PRZEJAZDOW" and msg.baza then
                if not trybManualny then
                    historiaPrzejazdow = {}
                    for i = #msg.baza, math.max(1, #msg.baza - (wysokosc - 2)), -1 do
                        local r = msg.baza[i]
                        local czas = r.czas_gry or (r.timestamp and r.timestamp:sub(12,16)) or "--:--"
                        local punkt = r.posterunek or "Trasa"
                        local pociag = r.nazwa_pociagu
                        local etykieta = (pociag and pociag ~= "") and (punkt .. "->" .. pociag) or punkt
                        table.insert(historiaPrzejazdow, { czas = czas, punkt = etykieta })
                    end
                    scrollOffset = 0
                    odswiezTablice()
                end

            elseif msg.typ == "ZAPYTANIE_TABLICA" then
                rednet.send(senderId, {
                    typ = "ODPOWIEDZ_TABLICA",
                    id = MOJE_ID,
                    szer = szerokosc,
                    wys = wysokosc,
                    typDisp = "Tablica_3x1 (" .. dispType .. ")"
                }, PROTOKOL)

            elseif msg.typ == "USTAW_TEKST_TABLICY" then
                trybManualny = true
                local nr = tonumber(msg.linia) or 1
                local txt = msg.tekst or ""
                wypiszWiersz(nr, txt, nr == 1)
                odswiezFlapyTablicy()
                print(string.format("[MANUAL 3x1] Wiersz %d: %s", nr, txt))

            elseif msg.typ == "TEST_TABLICY" then
                trybManualny = true
                wyczyscTablice()
                wypiszWiersz(1, string.format("TEST 3x1 [%dx%d]", szerokosc, wysokosc), true)
                for l = 2, wysokosc do
                    wypiszWiersz(l, string.format("%d. TEST 3x1 %s", l - 1, textutils.formatTime(os.time(), true)), false)
                end
                odswiezFlapyTablicy()
                print("[TEST 3x1] Wyslano wzorzec testowy.")

            elseif msg.typ == "WYCZYSC_TABLICE" then
                trybManualny = true
                wyczyscTablice()
                print("[MANUAL] Wyczyszczono tablice 3x1.")

            elseif msg.typ == "RESET_TABLICY" then
                trybManualny = false
                wyczyscTablice()
                scrollOffset = 0
                odswiezTablice()
                if serverId then rednet.send(serverId, { typ = "POBIERZ_BAZE" }, PROTOKOL) end
                print("[RESET 3x1] Przywrocono tryb ODJAZDY.")

            elseif msg.typ == "REBOOT" or msg.typ == "REBOOT_ALL" then
                print("Otrzymano zdalne polecenie REBOOT!")
                sleep(0.5)
                os.reboot()
            end
        end

    -- Heartbeat PING
    elseif event == "timer" and p1 == pingTimer then
        serverId = pobierzServerId()
        if serverId then
            rednet.send(serverId, {
                typ = "PING",
                nazwa = "Tablica_3x1_#" .. MOJE_ID,
                tryb = "DISPLAY_3X1",
                status = string.format("%dx%d", szerokosc, wysokosc)
            }, PROTOKOL)
        end
        pingTimer = os.startTimer(2.0)

    -- Skanowanie w poszukiwaniu wyświetlacza
    elseif event == "timer" and p1 == rescanTimer then
        local nDisp, nName, nType = znajdzWyswietlacz3x1()
        if nDisp ~= display then
            display = nDisp
            dispName = nName
            dispType = nType
            szerokosc, wysokosc = pobierzWymiary()
            wyczyscTablice()
            if not trybManualny then odswiezTablice() end
        end
        pobierzServerId()
        rescanTimer = os.startTimer(5.0)

    -- Zegar i animacja przewijania tekstu (Co 0.5 sekundy)
    elseif event == "timer" and p1 == zegarTimer then
        scrollOffset = scrollOffset + 1
        if not trybManualny then odswiezTablice() end
        zegarTimer = os.startTimer(0.5)
    end
end
