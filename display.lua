--------------------------------------------------------------------------------
--            OFICJALNY STEROWNIK CREATE DISPLAY BOARD (display.lua)          --
--------------------------------------------------------------------------------
local PROTOKOL     = "kolej_net"
local SERWER_HOST  = "centrala_glowna"
local TYTUL_TABLICY = "--- RUCH POCIAGOW ---"

-- 1. Inicjalizacja modemu
local modem = peripheral.find("modem")
if not modem then
    error("Blad: Nie znaleziono modemu!")
end
rednet.open(peripheral.getName(modem))

-- 2. Wyszukanie Display Board (bezpośrednio lub przez Wired Modem)
local board = peripheral.find("Create_DisplayBoard") or peripheral.find("create:display_board")
if not board then
    error("Blad: Brak podlaczonej tablicy Display Board!")
end

local maxLinii = board.getLineCount()

local function wyczyscTablice()
    board.clear()
end

local listaPrzejazdow = {}

local function odswiezTablice()
    local czasGry = textutils.formatTime(os.time(), true)
    
    -- Linia 1: Nagłówek
    board.setLine(1, TYTUL_TABLICY .. " [" .. czasGry .. "]")
    
    -- Linie 2..N: Historia meldunków o pociągach
    for i = 2, maxLinii do
        local wpis = listaPrzejazdow[i - 1]
        if wpis then
            board.setLine(i, string.format("%s %s", wpis.czas, wpis.punkt))
        else
            board.setLine(i, "")
        end
    end
end

-- 3. Inicjalizacja i połączenie z serwerem
term.clear()
term.setCursorPos(1, 1)
print("========================================")
print("    CREATE DISPLAY BOARD CONTROLLER     ")
print("========================================")
print("Wykryto wierszy na tablicy: " .. maxLinii)
print("Szukanie serwera centralnego...")

local serverId = rednet.lookup(PROTOKOL, SERWER_HOST)
while not serverId do
    sleep(1.5)
    serverId = rednet.lookup(PROTOKOL, SERWER_HOST)
end

print("Polaczono z centrala #" .. serverId)
wyczyscTablice()
odswiezTablice()

local zegarTimer = os.startTimer(4)

while true do
    local event, p1, p2, p3 = os.pullEvent()

    -- Odbiór meldunków o przejeździe składów
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

                print(string.format("[%s] Odnotowano przejazd: %s", czas, punkt))
                odswiezTablice()
            end
        end

    -- Cykliczne odświeżanie czasu gry na tablicy
    elseif event == "timer" and p1 == zegarTimer then
        odswiezTablice()
        zegarTimer = os.startTimer(4)
    end
end
