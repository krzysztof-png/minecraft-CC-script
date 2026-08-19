--------------------------------------------------------------------------------
--                         UNIWERSALNY KLIENT KOLEJOWY                       --
--------------------------------------------------------------------------------
local CONFIG_FILE = "client_config.json"
local PROTOKOL    = "kolej_net"
local SERWER_HOST = "centrala_glowna"
local MOJE_ID     = os.getComputerID()

local function wczytajConfig()
    if fs.exists(CONFIG_FILE) then
        local f = fs.open(CONFIG_FILE, "r")
        local dane = textutils.unserializeJSON(f.readAll())
        f.close()
        return dane
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
    print("       KREATOR KONFIGURACJI KLIENTA     ")
    print("       (ID Twojego komputera: #" .. MOJE_ID .. ")")
    print("========================================")

    -- 1. Nazwa stacji / posterunku
    write("Podaj nazwe punktu: ")
    local nazwa = read()
    if nazwa == "" then nazwa = "Posterunek_" .. MOJE_ID end

    -- 2. Wybór trybu pracy
    print("\nWybierz tryb pracy:")
    print(" [1] OBSERVER (Train Observer / Redstone)")
    print(" [2] STACJA   (Create Train Station)")
    print(" [3] BEACON   (Zwykly wezel statusowy)")
    write("Wybor [1-3]: ")

    local tryb = "OBSERVER"
    while true do
        local _, ch = os.pullEvent("char")
        if ch == "1" then tryb = "OBSERVER"; break end
        if ch == "2" then tryb = "STACJA";   break end
        if ch == "3" then tryb = "BEACON";   break end
    end
    print(tryb)

    -- 3. Strona sygnału dla trybu OBSERVER
    local stronaRS = "auto"
    if tryb == "OBSERVER" then
        print("\nStrona wejscia Redstone:")
        print(" [1] Auto (dowolna strona)")
        print(" [2] Back (tyl)")
        print(" [3] Left (lewo)")
        print(" [4] Right (prawo)")
        print(" [5] Top / Bottom")
        write("Wybor [1-5]: ")

        while true do
            local _, ch = os.pullEvent("char")
            if ch == "1" then stronaRS = "auto";   break end
            if ch == "2" then stronaRS = "back";   break end
            if ch == "3" then stronaRS = "left";   break end
            if ch == "4" then stronaRS = "right";  break end
            if ch == "5" then stronaRS = "top";    break end
        end
        print(stronaRS)
    end

    local cfg = {
        nazwaKlienta = nazwa,
        tryb = tryb,
        stronaRedstone = stronaRS,
        interwalPing = 2
    }
    zapiszConfig(cfg)
    return cfg
end

-- Sprawdzanie i wczytywanie konfiguracji
local config = wczytajConfig()
if not config then
    config = kreatorKonfiguracji()
else
    print("ID: #" .. MOJE_ID .. " | Punkt: " .. config.nazwaKlienta .. " | Tryb: " .. config.tryb)
    print("Przytrzymaj [R] by zmienic konfiguracje...")
    local timer = os.startTimer(1.5)
    while true do
        local event, p1 = os.pullEvent()
        if event == "key" and p1 == keys.r then
            config = kreatorKonfiguracji()
            break
        elseif event == "timer" and p1 == timer then
            break
        end
    end
end

-- Inicjalizacja modemu
local modem = peripheral.find("modem")
if not modem then
    error("Blad: Nie wykryto modemu!")
end
rednet.open(peripheral.getName(modem))

local stationPeripheral = nil
if config.tryb == "STACJA" then
    stationPeripheral = peripheral.find("create:station") or peripheral.find("Create_Station")
end

local function czySygnalRedstone()
    if config.stronaRedstone == "auto" then
        for _, side in ipairs(rs.getSides()) do
            if rs.getInput(side) then return true end
        end
        return false
    else
        return rs.getInput(config.stronaRedstone)
    end
end

local function rysujEkran(serverId, statusInfo)
    term.clear()
    term.setCursorPos(1, 1)
    print("========================================")
    print(" KLIENT:  " .. config.nazwaKlienta)
    print(" MOJE ID: #" .. MOJE_ID)
    print(" TRYB:    " .. config.tryb .. " (" .. config.stronaRedstone .. ")")
    print(" SERWER:  " .. (serverId and ("ID #" .. serverId) or "Szukanie..."))
    print("========================================")
    print("Status: " .. (statusInfo or "OK"))
    print("Czas gry: " .. textutils.formatTime(os.time(), true))
    print("----------------------------------------")
end

rysujEkran(nil, "Laczenie z centrala...")
local serverId = rednet.lookup(PROTOKOL, SERWER_HOST)
while not serverId do
    sleep(1.5)
    serverId = rednet.lookup(PROTOKOL, SERWER_HOST)
end

rysujEkran(serverId, "Polaczono z centrala")

local pingTimer = os.startTimer(config.interwalPing)
local bylSygnalRedstone = false

while true do
    local event, p1, p2, p3 = os.pullEvent()

    -- 1. Heartbeat do serwera
    if event == "timer" and p1 == pingTimer then
        local statusPayload = "OK"
        if config.tryb == "STACJA" and stationPeripheral then
            statusPayload = stationPeripheral.hasTrain() and "POCIAG" or "WOLNY"
        end

        rednet.send(serverId, {
            typ = "PING",
            nazwa = config.nazwaKlienta,
            tryb = config.tryb,
            status = statusPayload
        }, PROTOKOL)

        pingTimer = os.startTimer(config.interwalPing)

    -- 2. Wykrywanie Train Observera (Redstone)
    elseif event == "redstone" and config.tryb == "OBSERVER" then
        local jestSygnal = czySygnalRedstone()

        if jestSygnal and not bylSygnalRedstone then
            bylSygnalRedstone = true
            local czasGry = textutils.formatTime(os.time(), true)

            rednet.send(serverId, {
                typ = "PRZEJAZD_POCIAGU",
                nazwa = config.nazwaKlienta,
                czas = czasGry
            }, PROTOKOL)

            rysujEkran(serverId, "Wykryto pociag o " .. czasGry)

        elseif not jestSygnal and bylSygnalRedstone then
            bylSygnalRedstone = false
        end

    -- 3. Potwierdzenia z serwera
    elseif event == "rednet_message" and p3 == PROTOKOL then
        local _, msg = p1, p2
        if type(msg) == "table" and msg.odp == "PONG_OK" then
            -- Polaczenie aktywne
        end
    end
end
