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

-- 2. Wyszukanie wyświetlacza (Display Link / Display Board)
local function znajdzWyswietlacz()
    -- Szukanie po typach Create
    local dev = peripheral.find("create:display_link")
             or peripheral.find("Create_DisplayLink")
             or peripheral.find("create:display_board")
             or peripheral.find("Create_DisplayBoard")
    if dev and dev.getSize then return dev end

    -- Szukanie po dowolnej podłączonej ściance/kablu z metodą getSize
    for _, side in ipairs(peripheral.getNames()) do
        local p = peripheral.wrap(side)
        if p and type(p.getSize) == "function" and side ~= peripheral.getName(modem) then
            return p
        end
    end
    return nil
end

local display = znajdzWyswietlacz()
if not display then
    error("Blad: Nie wykryto Display Linka ani Display Boarda! Sprawdz podlaczenie.")
end

-- Pobranie wymiarów tablicy (szerokość znaków, liczba wierszy)
local szerokosc, wysokosc = display.getSize()

-- Funkcja bezpiecznego zapisu wiersza
local function wypiszWiersz(nrLinii, tekst)
    if nrLinii < 1 or nrLinii > wysokosc then return end

    -- Dopasowanie długości tekstu do szerokości tablicy (obcięcie lub dopełnienie spacjami)
    local sformatowany = string.format("%-" .. szerokosc .. "s", tekst):sub(1, szerokosc)

    if display.setLine then
        pcall(function() display.setLine(nrLinii, sformatowany) end)
    elseif display.setCursorPos and display.write then
        display.setCursorPos(1, nrLinii)
        display.write(sformatowany)
    end
end

local function wyczyscTablice()
    if display.clear then
        display.clear()
    else
        for i = 1, wysokosc do wypiszWiersz(i, "") end
    end
end

local historiaPrzejazdow = {}

local function odswiezTablice()
    local czasGry = textutils.formatTime(os.time(), true)

    -- Linia 1: Nagłówek dopasowany do szerokości tablicy
    local naglowek = string.format("%s [%s]", TYTUL_TABLICY, czasGry)
    wypiszWiersz(1, naglowek)

    -- Kolejne linie: Historia ostatnich meldunków
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
print(string.format("Rozmiar tablicy: %d x %d (znaki x wiersze)", szerokosc, wysokosc))
print("Szukanie serwera centralnego...")

local serverId = rednet.lookup(PROTOKOL, SERWER_HOST)
while not serverId do
    sleep(1.5)
    serverId = rednet.lookup(PROTOKOL, SERWER_HOST)
end

print("Polaczono z centrala #" .. serverId)
wyczyscTablice()
odswiezTablice()

local zegarTimer = os.startTimer(3)

while true do
    local event, p1, p2, p3 = os.pullEvent()

    -- Odbiór meldunków o pociągach z sieci
    if event == "rednet_message" and p3 == PROTOKOL then
        local senderId, msg = p1, p2
        if type(msg) == "table" then
            if msg.typ == "PRZEJAZD_POCIAGU" or (msg.typ == "NOWY_LOG" and msg.kategoria == "PRZEJAZD") then
                local czas = msg.czas or textutils.formatTime(os.time(), true)
                local punkt = msg.nazwa or msg.punkt or ("KM_" .. senderId)
                local pociag = msg.pociag
                local etykieta = pociag and (punkt .. " -> " .. pociag) or punkt

                table.insert(historiaPrzejazdow, 1, { czas = czas, punkt = etykieta })
                if #historiaPrzejazdow > (wysokosc - 1) then
                    table.remove(historiaPrzejazdow)
                end

                print(string.format("[%s] Odnotowano: %s", czas, etykieta))
                odswiezTablice()
            end
        end

    -- Cykliczne odświeżanie zegara
    elseif event == "timer" and p1 == zegarTimer then
        odswiezTablice()
        zegarTimer = os.startTimer(3)
    end
end
