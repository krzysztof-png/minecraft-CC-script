--------------------------------------------------------------------------------
--                KONTROLER TABLICY CREATE (DISPLAY BOARD)                    --
--------------------------------------------------------------------------------
local PROTOKOL     = "kolej_net"
local SERWER_HOST  = "centrala_glowna"
local TYTUL_TABLICY = "--- RUCH POCIAGOW ---"

-- Inicjalizacja modemu Rednet
local modem = peripheral.find("modem")
if not modem then
    error("Blad: Nie znaleziono modemu Rednet!")
end
rednet.open(peripheral.getName(modem))

-- Szukanie podłączonej tablicy Display Board (bezpośrednio lub po kablu)
local function znajdzTablice()
    local b = peripheral.find("create:display_board") 
           or peripheral.find("display_board")
           or peripheral.find("Create_DisplayBoard")
    if b then return b end
    for _, name in ipairs(peripheral.getNames()) do
        if name:find("display_board") or name:find("display") then
            return peripheral.wrap(name)
        end
    end
    return nil
end

local board = znajdzTablice()
if not board then
    error("Blad: Brak polaczenia z Create Display Board!")
end

-- Pobieranie wymiarów tablicy (domyślnie 4 linie jeśli funkcja nie istnieje)
local maxLinii = 4
local pcallLinii = pcall(function() maxLinii = board.getLineCount() end)

-- Bezpieczne wpisywanie tekstu w linię tablicy (kompatybilność indeksów 0 i 1)
local function ustawLinie(nr, tekst)
    local sukces = pcall(function() board.setLine(nr, tekst) end)
    if not sukces then
        pcall(function() board.setLine(nr - 1, tekst) end)
    end
end

local function wyczyscTablice()
    if board.clear then
        pcall(function() board.clear() end)
    else
        for i = 1, maxLinii do ustawLinie(i, "") end
    end
end

local listaPrzejazdow = {}

local function odswiezTablice()
    local czasGry = textutils.formatTime(os.time(), true)
    
    -- Linia 1: Nagłówek i czas gry
    ustawLinie(1, TYTUL_TABLICY)
    
    -- Kolejne linie: Historia ostatnich przejazdów
    for i = 2, maxLinii do
        local wpis = listaPrzejazdow[i - 1]
        if wpis then
            ustawLinie(i, string.format("%s %s", wpis.czas, wpis.punkt))
        else
            ustawLinie(i, "--- OCZEKIWANIE ---")
        end
    end
end

-- Inicjalizacja ekranu komputera
term.clear()
term.setCursorPos(1, 1)
print("========================================")
print("      STEROWNIK DISPLAY BOARD (CREATE)  ")
print("========================================")
print("Szukanie centrali...")

local serverId = rednet.lookup(PROTOKOL, SERWER_HOST)
while not serverId do
    sleep(1.5)
    serverId = rednet.lookup(PROTOKOL, SERWER_HOST)
end

print("Polaczono z serwerem #" .. serverId)
wyczyscTablice()
odswiezTablice()

local zegarTimer = os.startTimer(5) -- Odświeżanie czasu co kilka sekund

while true do
    local event, p1, p2, p3 = os.pullEvent()

    -- 1. Odbiór meldunków o przejeździe pociągu
    if event == "rednet_message" and p3 == PROTOKOL then
        local senderId, msg = p1, p2
        if type(msg) == "table" then
            if msg.typ == "PRZEJAZD_POCIAGU" or (msg.typ == "NOWY_LOG" and msg.kategoria == "PRZEJAZD") then
                local czas = msg.czas or textutils.formatTime(os.time(), true)
                local punkt = msg.nazwa or msg.punkt or ("KM_" .. senderId)
                
                table.insert(listaPrzejazdow, 1, { czas = czas, punkt = punkt })
                if #listaPrzejazdow > (maxLinii - 1) then
                    table.remove(listaPrzejazdow)
                end

                print(string.format("[%s] Aktualizacja tablicy: %s", czas, punkt))
                odswiezTablice()
            end
        end

    -- 2. Cykliczny zegar
    elseif event == "timer" and p1 == zegarTimer then
        odswiezTablice()
        zegarTimer = os.startTimer(5)
    end
end
