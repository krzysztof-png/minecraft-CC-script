--------------------------------------------------------------------------------
--                         UNIWERSALNY KLIENT KOLEJOWY                        --
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

    write("Podaj nazwe posterunku: ")
    local nazwa = read()
    if nazwa == "" then nazwa = "Posterunek_" .. MOJE_ID end

    print("\nWybierz tryb pracy i detekcji:")
    print(" [1] OBSERVER (Sygnal Redstone / Train Observer)")
    print(" [2] STACJA   (Create Train Station - pelne dane)")
    print(" [3] SYGNAL   (Train Signal - listBlockingTrainNames)")
    print(" [4] BEACON   (Tylko status online)")
    write("Wybor [1-4]: ")

    local tryb = "OBSERVER"
    while true do
        local _, ch = os.pullEvent("char")
        if ch == "1" then tryb = "OBSERVER"; break end
        if ch == "2" then tryb = "STACJA";   break end
        if ch == "3" then tryb = "SYGNAL";   break end
        if ch == "4" then tryb = "BEACON";   break end
    end
    print(tryb)

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

-- Inicjalizacja peryferiów Create
local stationPeri = nil
local signalPeri = nil

if config.tryb == "STACJA" then
    stationPeri = peripheral.find("create:station") or peripheral.find("Create_Station") or peripheral.find("train_station")
end

if config.tryb == "SYGNAL" then
    signalPeri = peripheral.find("train_signal") or peripheral.find("Create_TrainSignal")
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

-- Pobieranie aktualnej nazwy pociągu w zależności od modułu
local function pobierzNazwePociagu()
    if config.tryb == "STACJA" and stationPeri then
        if stationPeri.getTrainName then
            return stationPeri.getTrainName()
        elseif stationPeri.hasTrain and stationPeri.hasTrain() then
            return "Pociag w peronie"
        end
    elseif config.tryb == "SYGNAL" and signalPeri then
        if signalPeri.listBlockingTrainNames then
            local trains = signalPeri.listBlockingTrainNames()
            if #trains > 0 then return trains[1] end
        end
    end
    return nil
end

local function rysujEkran(serverId, statusInfo)
    term.clear()
    term.setCursorPos(1, 1)
    print("========================================")
    print(" KLIENT:  " .. config.nazwaKlienta)
    print(" MOJE ID: #" .. MOJE_ID)
    print(" TRYB:    " .. config.tryb .. (config.tryb == "OBSERVER" and (" (" .. config.stronaRedstone .. ")") or ""))
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
local loopTimer = os.startTimer(0.1) -- Pętla szybkiego odpytywania dla Stacji / Sygnałów
local bylSygnalRedstone = false
local ostatniWykrytyPociag = nil

while true do
    local event, p1, p2, p3 = os.pullEvent()

    -- 1. Heartbeat
    if event == "timer" and p1 == pingTimer then
        local statusPayload = "WOLNY"
        local aktualnyPociag = pobierzNazwePociagu()

        if aktualnyPociag then
            statusPayload = aktualnyPociag
        elseif bylSygnalRedstone then
            statusPayload = "PRZEJAZD"
        end

        rednet.send(serverId, {
            typ = "PING",
            nazwa = config.nazwaKlienta,
            tryb = config.tryb,
            status = statusPayload,
            pociag = aktualnyPociag
        }, PROTOKOL)

        pingTimer = os.startTimer(config.interwalPing)

    -- 2. Cykliczny polling dla Stacji / Sygnałów Create
    elseif event == "timer" and p1 == loopTimer then
        if config.tryb == "STACJA" or config.tryb == "SYGNAL" then
            local pociag = pobierzNazwePociagu()
            if pociag and pociag ~= ostatniWykrytyPociag then
                ostatniWykrytyPociag = pociag
                local czasGry = textutils.formatTime(os.time(), true)

                rednet.send(serverId, {
                    typ = "PRZEJAZD_POCIAGU",
                    nazwa = config.nazwaKlienta,
                    tryb = config.tryb,
                    pociag = pociag,
                    czas = czasGry
                }, PROTOKOL)

                rysujEkran(serverId, "Wykryto: " .. pociag)
            elseif not pociag and ostatniWykrytyPociag then
                ostatniWykrytyPociag = nil
                rysujEkran(serverId, "Sekcja zwolniona")
            end
        end
        loopTimer = os.startTimer(0.1)

    -- 3. Detekcja Train Observera (Redstone)
    elseif event == "redstone" and config.tryb == "OBSERVER" then
        local jestSygnal = czySygnalRedstone()

        if jestSygnal and not bylSygnalRedstone then
            bylSygnalRedstone = true
            local czasGry = textutils.formatTime(os.time(), true)

            rednet.send(serverId, {
                typ = "PRZEJAZD_POCIAGU",
                nazwa = config.nazwaKlienta,
                tryb = config.tryb,
                pociag = "Przejazd przez detektor",
                czas = czasGry
            }, PROTOKOL)

            rysujEkran(serverId, "Wykryto przejazd o " .. czasGry)

        elseif not jestSygnal and bylSygnalRedstone then
            bylSygnalRedstone = false
            rysujEkran(serverId, "Detektor zwolniony")
        end
    end
end
