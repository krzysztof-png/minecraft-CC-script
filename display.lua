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
    -- 1. Szukanie dedykowanych urządzeń Create
    local dev = peripheral.find("create:display_board")
             or peripheral.find("Create_DisplayBoard")
             or peripheral.find("create:display_link")
             or peripheral.find("Create_DisplayLink")
             or peripheral.find("display_board")
             or peripheral.find("display_link")
             or peripheral.find("create_target")

    if dev and dev.getSize then return dev end

    -- 2. Szukanie standardowego monitora ComputerCraft
    local mon = peripheral.find("monitor")
    if mon and mon.getSize then
        pcall(function() mon.setTextScale(1.0) end)
        return mon
    end

    -- 3. Szukanie dowolnego innego peryferium z metodą getSize
    for _, side in ipairs(peripheral.getNames()) do
        if side ~= peripheral.getName(modem) then
            local p = peripheral.wrap(side)
            if p and type(p.getSize) == "function" then
                return p
            end
        end
    end

    -- 4. Domyślny fallback: Ekran komputera
    return term.native()
end

local display = znajdzWyswietlacz()
local szerokosc, wysokosc = display.getSize()

-- Funkcja bezpiecznego zapisu wiersza
local function wypiszWiersz(nrLinii, tekst)
    if nrLinii < 1 or nrLinii > wysokosc then return end

    local sformatowany = string.format("%-" .. szerokosc .. "s", tekst):sub(1, szerokosc)

    if display.setTextColor then
        pcall(function()
            if nrLinii == 1 then
                display.setTextColor(colors.yellow or colors.white)
            else
                display.setTextColor(colors.white)
            end
        end)
    end

    if display.setLine then
        pcall(function() display.setLine(nrLinii, sformatowany) end)
    elseif display.setCursorPos and display.write then
        pcall(function()
            display.setCursorPos(1, nrLinii)
            display.write(sformatowany)
        end)
    end
end

local function wyczyscTablice()
    if display.clear then
        pcall(function() display.clear() end)
    else
        for i = 1, wysokosc do wypiszWiersz(i, "") end
    end
end

local historiaPrzejazdow = {}

local function odswiezTablice()
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
end

-- 3. Interfejs konsoli komputera i łączenie z serwerem
term.clear()
term.setCursorPos(1, 1)
print("========================================")
print("      CREATE DISPLAY CONTROLLER         ")
print("========================================")
print(string.format("Typ wyswietlacza: %s", peripheral.getType(display) or "Ekran komputera"))
print(string.format("Rozmiar tablicy:  %d x %d (znaki x wiersze)", szerokosc, wysokosc))
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

-- Pobranie historii przejazdów z bazy danych serwera przy starcie
rednet.send(serverId, { typ = "POBIERZ_BAZE" }, PROTOKOL)

local zegarTimer = os.startTimer(2)
local rescanTimer = os.startTimer(5)

while true do
    local event, p1, p2, p3 = os.pullEvent()

    -- Odbiór meldunków i danych z sieci
    if event == "rednet_message" and p3 == PROTOKOL then
        local senderId, msg = p1, p2
        if type(msg) == "table" then
            if msg.typ == "PRZEJAZD_POCIAGU" or (msg.typ == "NOWY_LOG" and msg.kategoria == "PRZEJAZD") then
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

            elseif msg.typ == "REBOOT" or msg.typ == "REBOOT_ALL" then
                print("Otrzymano zdalne polecenie REBOOT!")
                sleep(0.5)
                os.reboot()
            end
        end

    -- Cykliczny re-skan peryferium wyświetlacza (na przypadek podłączenia w trakcie)
    elseif event == "timer" and p1 == rescanTimer then
        local nowyDisp = znajdzWyswietlacz()
        if nowyDisp ~= display then
            display = nowyDisp
            szerokosc, wysokosc = display.getSize()
            wyczyscTablice()
            odswiezTablice()
        end
        pobierzServerId()
        rescanTimer = os.startTimer(5)

    -- Cykliczne odświeżanie zegara
    elseif event == "timer" and p1 == zegarTimer then
        odswiezTablice()
        zegarTimer = os.startTimer(2)
    end
end
