--------------------------------------------------------------------------------
--            POPRAWIONY STEROWNIK WYŚWIETLACZA CREATE (display.lua)          --
--------------------------------------------------------------------------------
local PROTOKOL      = "kolej_net"
local SERWER_HOST   = "centrala_glowna"
local TYTUL_TABLICY = "ODJAZDY"

-- 1. Inicjalizacja modemu
local modem = peripheral.find("modem")
if not modem then
    error("Blad: Nie znaleziono modemu bezprzewodowego/ender!")
end
rednet.open(peripheral.getName(modem))

-- 2. Wyszukanie wyświetlacza (Display Link / Display Board / Monitor)
local function znajdzWyswietlacz()
    -- 1. Szukanie dedykowanych urządzeń Create po typie
    for _, name in ipairs(peripheral.getNames()) do
        if name ~= peripheral.getName(modem) then
            local t = (peripheral.getType(name) or ""):lower()
            if t:find("display") or t:find("board") or t:find("target") then
                local dev = peripheral.wrap(name)
                if dev and dev.getSize then
                    return dev, name, t
                end
            end
        end
    end

    -- 2. Szukanie standardowego monitora ComputerCraft
    local mon = peripheral.find("monitor")
    if mon and mon.getSize then
        pcall(function() mon.setTextScale(1.0) end)
        return mon, peripheral.getName(mon), "monitor"
    end

    -- 3. Szukanie peryferium z metodami pisania po wierszach
    for _, name in ipairs(peripheral.getNames()) do
        if name ~= peripheral.getName(modem) then
            local dev = peripheral.wrap(name)
            if dev and (dev.setLine or dev.setRow or dev.updateLine or dev.writeLine) then
                return dev, name, peripheral.getType(name) or "display"
            end
        end
    end

    -- 4. Szukanie dowolnego peryferium z getSize (wykluczając modemy, napędy, komputery, żółwie)
    for _, name in ipairs(peripheral.getNames()) do
        if name ~= peripheral.getName(modem) then
            local t = (peripheral.getType(name) or ""):lower()
            if not t:find("modem") and not t:find("drive") and not t:find("computer") and not t:find("turtle") then
                local dev = peripheral.wrap(name)
                if dev and dev.getSize and (dev.write or dev.setLine or dev.setCursorPos) then
                    return dev, name, t
                end
            end
        end
    end

    -- 5. Domyślny fallback: Ekran komputera
    return term.native(), "terminal", "terminal"
end

local display, dispName, dispType = znajdzWyswietlacz()
local szerokosc, wysokosc = display.getSize()

-- Odświeżenie płatków/bufora wyświetlacza Create
local function odswiezFlapyTablicy()
    if not display then return end
    if display.update then pcall(display.update) end
    if display.flush then pcall(display.flush) end
    if display.render then pcall(display.render) end
    if display.updateBoard then pcall(display.updateBoard) end
end

-- Funkcja bezpiecznego zapisu wiersza (obsługuje 1-index oraz 0-index w Create)
local function wypiszWiersz(nrLinii, tekst)
    if not display or nrLinii < 1 or nrLinii > wysokosc then return end

    local sformatowany = string.format("%-" .. szerokosc .. "s", tekst):sub(1, szerokosc)
    local sukces = false
    local errLast = nil

    if display.setTextColor then
        pcall(function()
            if nrLinii == 1 then
                display.setTextColor(colors.yellow or colors.white)
            else
                display.setTextColor(colors.white)
            end
        end)
    end

    -- 1. Metoda setLine (1-indexed oraz 0-indexed)
    if display.setLine then
        local ok, err = pcall(display.setLine, nrLinii, sformatowany)
        if ok then sukces = true else errLast = err end

        if not sukces and (nrLinii - 1) >= 0 then
            local ok0, err0 = pcall(display.setLine, nrLinii - 1, sformatowany)
            if ok0 then sukces = true else errLast = err0 end
        end
    end

    -- 2. Metoda setRow (1-indexed oraz 0-indexed)
    if not sukces and display.setRow then
        local ok, err = pcall(display.setRow, nrLinii, sformatowany)
        if ok then sukces = true else
            local ok0 = pcall(display.setRow, nrLinii - 1, sformatowany)
            if ok0 then sukces = true end
        end
    end

    -- 3. Metody alternatywne (updateLine / writeLine / setText)
    if not sukces and display.updateLine then
        local ok = pcall(display.updateLine, nrLinii, sformatowany)
        if ok then sukces = true end
    end
    if not sukces and display.writeLine then
        local ok = pcall(display.writeLine, nrLinii, sformatowany)
        if ok then sukces = true end
    end
    if not sukces and display.setText then
        local ok = pcall(display.setText, nrLinii, sformatowany)
        if ok then sukces = true end
    end

    -- 4. Metoda setCursorPos + write (dla CC Monitor / term.native)
    if not sukces and display.setCursorPos and display.write then
        local ok1 = pcall(display.setCursorPos, 1, nrLinii)
        local ok2, err2 = pcall(display.write, sformatowany)
        if ok1 and ok2 then sukces = true else errLast = err2 end
    end

    if not sukces and errLast then
        print(string.format("[OSTRZEZENIE] Blad zapisu wiersza %d: %s", nrLinii, tostring(errLast)))
    end
end

local function wyczyscTablice()
    if display.clear then
        pcall(function() display.clear() end)
    else
        for i = 1, wysokosc do wypiszWiersz(i, "") end
    end
    odswiezFlapyTablicy()
end

local historiaPrzejazdow = {}
local trybManualny = false

local function odswiezTablice()
    if trybManualny then return end

    local czasGry = textutils.formatTime(os.time(), true)
    local naglowek = string.format("%s [%s]", TYTUL_TABLICY, czasGry)
    wypiszWiersz(1, naglowek)

    for i = 2, wysokosc do
        local wpis = historiaPrzejazdow[i - 1]
        if wpis then
            wypiszWiersz(i, string.format("%s %s", wpis.czas, wpis.punkt))
        else
            wypiszWiersz(i, "")
        end
    end
    odswiezFlapyTablicy()
end

-- 3. Interfejs konsoli komputera i łączenie z serwerem
term.clear()
term.setCursorPos(1, 1)
print("========================================")
print("      CREATE DISPLAY CONTROLLER         ")
print("========================================")
print(string.format("Wykryty urzadzenie: %s (%s)", dispName or "Natywny", dispType or "Terminal"))
print(string.format("Rozmiar tablicy:    %d x %d (znaki x wiersze)", szerokosc, wysokosc))
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

-- Pobranie historii przejazdów z bazy danych serwera przy starcie i wysłanie PING
rednet.send(serverId, {
    typ = "PING",
    nazwa = "Tablica_" .. os.getComputerID(),
    tryb = "DISPLAY",
    status = string.format("%dx%d", szerokosc, wysokosc)
}, PROTOKOL)
rednet.send(serverId, { typ = "POBIERZ_BAZE" }, PROTOKOL)

local zegarTimer = os.startTimer(2)
local pingTimer = os.startTimer(2)
local rescanTimer = os.startTimer(5)

while true do
    local event, p1, p2, p3 = os.pullEvent()

    -- Odbiór meldunków i danych z sieci
    if event == "rednet_message" and p3 == PROTOKOL then
        local senderId, msg = p1, p2
        if type(msg) == "table" then
            if msg.typ == "PRZEJAZD_POCIAGU" or (msg.typ == "NOWY_LOG" and msg.kategoria == "PRZEJAZD") then
                trybManualny = false
                local czas = msg.czas or textutils.formatTime(os.time(), true)
                local punkt = msg.nazwa or msg.punkt or ("KM_" .. senderId)
                local pociag = msg.pociag
                local etykieta = (pociag and pociag ~= "") and (punkt .. " -> " .. pociag) or punkt

                table.insert(historiaPrzejazdow, 1, { czas = czas, punkt = etykieta })
                if #historiaPrzejazdow > (wysokosc - 1) then
                    table.remove(historiaPrzejazdow)
                end

                print(string.format("[%s] Odnotowano: %s", czas, etykieta))
                odswiezTablice()

            elseif msg.typ == "BAZA_PRZEJAZDOW" and msg.baza then
                if not trybManualny then
                    historiaPrzejazdow = {}
                    for i = #msg.baza, math.max(1, #msg.baza - (wysokosc - 2)), -1 do
                        local r = msg.baza[i]
                        local czas = r.czas_gry or (r.timestamp and r.timestamp:sub(12,16)) or "--:--"
                        local punkt = r.posterunek or "Trasa"
                        local pociag = r.nazwa_pociagu
                        local etykieta = (pociag and pociag ~= "") and (punkt .. " -> " .. pociag) or punkt
                        table.insert(historiaPrzejazdow, { czas = czas, punkt = etykieta })
                    end
                    odswiezTablice()
                end

            elseif msg.typ == "ZAPYTANIE_TABLICA" then
                rednet.send(senderId, {
                    typ = "ODPOWIEDZ_TABLICA",
                    id = os.getComputerID(),
                    szer = szerokosc,
                    wys = wysokosc,
                    typDisp = dispType or "Display"
                }, PROTOKOL)

            elseif msg.typ == "USTAW_TEKST_TABLICY" then
                trybManualny = true
                local nr = tonumber(msg.linia) or 1
                local txt = msg.tekst or ""
                wypiszWiersz(nr, txt)
                odswiezFlapyTablicy()
                print(string.format("[MANUAL] Wiersz %d: %s", nr, txt))

            elseif msg.typ == "TEST_TABLICY" then
                trybManualny = true
                wyczyscTablice()
                wypiszWiersz(1, string.format("TEST TABLICY [%dx%d]", szerokosc, wysokosc))
                for l = 2, wysokosc do
                    wypiszWiersz(l, string.format("%d. %s TEST", l - 1, textutils.formatTime(os.time(), true)))
                end
                odswiezFlapyTablicy()
                print("[TEST] Wyslano wzorzec testowy na tablice.")

            elseif msg.typ == "WYCZYSC_TABLICE" then
                trybManualny = true
                wyczyscTablice()
                print("[MANUAL] Wyczyszczono tablice.")

            elseif msg.typ == "RESET_TABLICY" then
                trybManualny = false
                wyczyscTablice()
                odswiezTablice()
                if serverId then rednet.send(serverId, { typ = "POBIERZ_BAZE" }, PROTOKOL) end
                print("[RESET] Przywrocono tryb ODJAZDY.")

            elseif msg.typ == "REBOOT" or msg.typ == "REBOOT_ALL" then
                print("Otrzymano zdalne polecenie REBOOT!")
                sleep(0.5)
                os.reboot()
            end
        end

    -- Heartbeat PING do serwera centralnego
    elseif event == "timer" and p1 == pingTimer then
        serverId = pobierzServerId()
        if serverId then
            rednet.send(serverId, {
                typ = "PING",
                nazwa = "Tablica_" .. os.getComputerID(),
                tryb = "DISPLAY",
                status = string.format("%dx%d", szerokosc, wysokosc)
            }, PROTOKOL)
        end
        pingTimer = os.startTimer(2)

    -- Cykliczny re-skan peryferium wyświetlacza (na przypadek podłączenia w trakcie)
    elseif event == "timer" and p1 == rescanTimer then
        local nowyDisp, nName, nType = znajdzWyswietlacz()
        if nowyDisp ~= display then
            display = nowyDisp
            dispName = nName
            dispType = nType
            szerokosc, wysokosc = display.getSize()
            wyczyscTablice()
            if not trybManualny then odswiezTablice() end
        end
        pobierzServerId()
        rescanTimer = os.startTimer(5)

    -- Cykliczne odświeżanie zegara
    elseif event == "timer" and p1 == zegarTimer then
        if not trybManualny then odswiezTablice() end
        zegarTimer = os.startTimer(2)
    end
end
