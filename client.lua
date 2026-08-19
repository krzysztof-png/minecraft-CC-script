--------------------------------------------------------------------------------
--                         KONFIGURACJA KLIENTA                               --
--------------------------------------------------------------------------------
local CONFIG = {
    nazwaKlienta = "Posterunek_01",   -- Unikalna nazwa punktu / stacji
    protokol     = "kolej_net",       -- Nazwa protokołu sieciowego
    serwerNazwa  = "centrala_glowna", -- Identyfikator serwera (hostname)

    -- TRYBY DZIAŁANIA:
    -- "OBSERVER" - Czujnik przejazdu (Train Observer na redstone)
    -- "STACJA"   - Terminal peronowy Create (wymaga Train Station)
    -- "BEACON"   - Zwykły węzeł meldunkowy / wskaźnik obecności
    tryb = "OBSERVER",

    -- Opcje dla trybu OBSERVER:
    stronaRedstone = "auto", -- "auto", "top", "bottom", "left", "right", "front", "back"

    -- Częstotliwość heartbeat / ping (w sekundach)
    interwalPing = 2
}
--------------------------------------------------------------------------------

-- Inicjalizacja modemu
local modem = peripheral.find("modem")
if not modem then
    error("Blad: Nie wykryto modemu (Wireless/Ender Modem)!")
end
rednet.open(peripheral.getName(modem))

local stationPeripheral = nil
if CONFIG.tryb == "STACJA" then
    stationPeripheral = peripheral.find("create:station") or peripheral.find("Create_Station")
end

local function czySygnalRedstone()
    if CONFIG.stronaRedstone == "auto" then
        for _, side in ipairs(rs.getSides()) do
            if rs.getInput(side) then return true end
        end
        return false
    else
        return rs.getInput(CONFIG.stronaRedstone)
    end
end

-- Rysowanie interfejsu klienta
local function rysujEkran(serverId, statusInfo)
    term.clear()
    term.setCursorPos(1, 1)
    print("========================================")
    print(" KLIENT: " .. CONFIG.nazwaKlienta)
    print(" TRYB:   " .. CONFIG.tryb)
    print(" SERWER: " .. (serverId and ("ID #" .. serverId) or "Szukanie..."))
    print("========================================")
    print("Status: " .. (statusInfo or "Dziala stabilnie"))
    print("----------------------------------------")
end

-- Główna pętla
rysujEkran(nil, "Laczenie z centrala...")
local serverId = rednet.lookup(CONFIG.protokol, CONFIG.serwerNazwa)
while not serverId do
    sleep(1.5)
    serverId = rednet.lookup(CONFIG.protokol, CONFIG.serwerNazwa)
end

rysujEkran(serverId, "Polaczono z centrala")

local pingTimer = os.startTimer(CONFIG.interwalPing)
local bylSygnalRedstone = false

while true do
    local event, p1, p2, p3 = os.pullEvent()

    -- 1. Obsługa interwału wysyłania PING / Heartbeat
    if event == "timer" and p1 == pingTimer then
        local statusPayload = "OK"
        if CONFIG.tryb == "STACJA" and stationPeripheral then
            statusPayload = stationPeripheral.hasTrain() and "POCIAG_NA_PERONIE" or "WOLNY"
        end

        rednet.send(serverId, {
            typ = "PING",
            nazwa = CONFIG.nazwaKlienta,
            tryb = CONFIG.tryb,
            status = statusPayload
        }, CONFIG.protokol)

        pingTimer = os.startTimer(CONFIG.interwalPing)

    -- 2. Obsługa detekcji pociągu przez Train Observer (Redstone)
    elseif event == "redstone" and CONFIG.tryb == "OBSERVER" then
        local jestSygnal = czySygnalRedstone()

        if jestSygnal and not bylSygnalRedstone then
            bylSygnalRedstone = true
            local czasGry = textutils.formatTime(os.time(), true)

            rednet.send(serverId, {
                typ = "PRZEJAZD_POCIAGU",
                nazwa = CONFIG.nazwaKlienta,
                czas = czasGry
            }, CONFIG.protokol)

            rysujEkran(serverId, "Wykryto przejazd o " .. czasGry)

        elseif not jestSygnal and bylSygnalRedstone then
            bylSygnalRedstone = false
        end

    -- 3. Odbieranie rozkazów lub potwierdzeń od serwera
    elseif event == "rednet_message" and p3 == CONFIG.protokol then
        local senderId, msg = p1, p2
        if type(msg) == "table" and msg.odp then
            -- Możliwość reakcji na polecenia z centrali (np. wysłanie pociągu)
            if msg.rozkaz == "WYSLIJ_POCIAG" and CONFIG.tryb == "STACJA" and stationPeripheral then
                -- Kod wgrywania rozkładu / odprawy
            end
        end
    end
end
