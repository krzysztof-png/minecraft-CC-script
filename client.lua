--------------------------------------------------------------------------------
--                     UNIVERSAL RAILWAY CLIENT (client.lua)                  --
--------------------------------------------------------------------------------
local CONFIG_FILE = "client_config.json"
local PROTOKOL    = "kolej_net"
local SERWER_HOST = "centrala_glowna"
local MOJE_ID     = os.getComputerID()

local function wczytajConfig()
    if fs.exists(CONFIG_FILE) then
        local f = fs.open(CONFIG_FILE, "r")
        local tresc = f.readAll()
        f.close()
        return textutils.unserializeJSON(tresc)
    end
    return nil
end

local function zapiszConfig(cfg)
    local f = fs.open(CONFIG_FILE, "w")
    f.write(textutils.serializeJSON(cfg))
    f.close()
end

--------------------------------------------------------------------------------
--    POBIERANIE WSZYSTKICH NAZW PERYFERII (BEZPOŚREDNIE + KABLOWE WIRED NET)   --
--------------------------------------------------------------------------------
local function pobierzWszystkieNazwyPeryferii()
    local nazwySet = {}

    -- 1. Nazwy bezpośrednie
    for _, name in ipairs(peripheral.getNames()) do
        nazwySet[name] = true
    end

    -- 2. Nazwy zdalne z modemów przewodowych (Wired Modem getNamesRemote)
    for _, name in ipairs(peripheral.getNames()) do
        local dev = peripheral.wrap(name)
        if dev and dev.getNamesRemote then
            local ok, remotes = pcall(dev.getNamesRemote)
            if ok and remotes and type(remotes) == "table" then
                for _, rName in ipairs(remotes) do
                    nazwySet[rName] = true
                end
            end
        end
    end

    local lista = {}
    for n, _ in pairs(nazwySet) do
        table.insert(lista, n)
    end
    table.sort(lista)
    return lista
end

local function wyszukajSygnalyKolejowe()
    local lista = {}
    for _, name in ipairs(pobierzWszystkieNazwyPeryferii()) do
        local dev = peripheral.wrap(name)
        if dev then
            local isWireless = false
            if dev.isWireless then pcall(function() isWireless = dev.isWireless() end) end
            if not isWireless then
                table.insert(lista, name)
            end
        end
    end
    table.sort(lista)
    return lista
end

local function kreatorKonfiguracji()
    term.clear()
    term.setCursorPos(1, 1)
    print("========================================")
    print("      CLIENT CONFIGURATION WIZARD       ")
    print("      (Your Computer ID: #" .. MOJE_ID .. ")")
    print("========================================")

    write("Enter station / detector name: ")
    local nazwa = read()
    if nazwa == "" then nazwa = "Station_" .. MOJE_ID end

    print("\nSelect operating and detection mode:")
    print(" [1] OBSERVER (Redstone Signal / Train Observer)")
    print(" [2] STATION  (Create Train Station - full data)")
    print(" [3] SIGNAL   (Create Train Signals - wired net)")
    print(" [4] BEACON   (Online status only)")
    print(" [5] AUTO     (All detected sensors / stations)")
    write("Selection [1-5]: ")

    local tryb = "AUTO"
    while true do
        local _, ch = os.pullEvent("char")
        if ch == "1" then tryb = "OBSERVER"; break end
        if ch == "2" then tryb = "STACJA";   break end
        if ch == "3" then tryb = "SYGNAL";   break end
        if ch == "4" then tryb = "BEACON";   break end
        if ch == "5" then tryb = "AUTO";     break end
    end
    print(tryb)

    local mapowanieSygnalow = {}
    local sygnaly = wyszukajSygnalyKolejowe()
    
    if #sygnaly > 0 then
        print("\n--- DETEKCJA SYGNAŁÓW (WIRED NET) ---")
        print(string.format("Wykryto %d urzadzen na kablu:", #sygnaly))
        for idx, sigName in ipairs(sygnaly) do
            write(string.format(" Sygnal '%s' -> Tor nr [domyslnie %d]: ", sigName, idx))
            local inpTor = read()
            if inpTor == "" then inpTor = tostring(idx) end
            mapowanieSygnalow[sigName] = inpTor
            print(string.format("  [OK] %s = Tor %s", sigName, inpTor))
        end
    end

    local stronaRS = "auto"
    if tryb == "OBSERVER" or tryb == "AUTO" then
        print("\nRedstone Input Side:")
        print(" [1] Auto (any side)")
        print(" [2] Back")
        print(" [3] Left")
        print(" [4] Right")
        print(" [5] Top / Bottom")
        write("Selection [1-5]: ")

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
        mapowanieSygnalow = mapowanieSygnalow,
        interwalPing = 2
    }
    zapiszConfig(cfg)
    return cfg
end

local config = wczytajConfig()
if not config then
    config = kreatorKonfiguracji()
else
    print("ID: #" .. MOJE_ID .. " | Station: " .. config.nazwaKlienta .. " | Mode: " .. config.tryb)
    print("Hold [R] to change configuration...")
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

-- Inicjalizacja modemu bezprzewodowego Rednet
local function znajdzModemBezprzewodowy()
    for _, name in ipairs(pobierzWszystkieNazwyPeryferii()) do
        local dev = peripheral.wrap(name)
        if dev and dev.isWireless and dev.isWireless() then
            return name, dev
        end
    end
    return nil, nil
end

local wirelessName, wirelessDev = znajdzModemBezprzewodowy()
if wirelessName then
    rednet.open(wirelessName)
else
    local m = peripheral.find("modem")
    if m then pcall(function() rednet.open(peripheral.getName(m)) end) end
end

--------------------------------------------------------------------------------
--             DYNAMIC PERIPHERAL SCANNING AND TRAIN PARSING                  --
--------------------------------------------------------------------------------

local function czyscNazwePociagu(val)
    if not val then return nil end
    if type(val) == "string" then
        local s = val:match("^%s*(.-)%s*$")
        if s and #s > 0 then return s end
    elseif type(val) == "table" then
        if val.name and type(val.name) == "string" and #val.name > 0 then
            return val.name:match("^%s*(.-)%s*$")
        elseif #val > 0 then
            local imiona = {}
            for _, item in ipairs(val) do
                local czyste = czyscNazwePociagu(item)
                if czyste then table.insert(imiona, czyste) end
            end
            if #imiona > 0 then
                return table.concat(imiona, ", ")
            end
        end
    end
    return nil
end

local function pobierzNazweZPeryferium(name, dev)
    if not dev then return nil end

    if dev.listBlockingTrainNames then
        local ok, res = pcall(dev.listBlockingTrainNames)
        if ok and res then
            local parsed = czyscNazwePociagu(res)
            if parsed then return parsed end
        end
    end

    if dev.getTrainName then
        local ok, res = pcall(dev.getTrainName)
        if ok and res then
            local parsed = czyscNazwePociagu(res)
            if parsed then return parsed end
        end
    end

    if dev.getPresentTrainName then
        local ok, res = pcall(dev.getPresentTrainName)
        if ok and res then
            local parsed = czyscNazwePociagu(res)
            if parsed then return parsed end
        end
    end

    if dev.getPresentTrain then
        local ok, res = pcall(dev.getPresentTrain)
        if ok and res then
            local parsed = czyscNazwePociagu(res)
            if parsed then return parsed end
        end
    end

    if dev.hasTrain then
        local ok, res = pcall(dev.hasTrain)
        if ok and res == true then
            return "Train at signal"
        end
    elseif dev.isTrainPresent then
        local ok, res = pcall(dev.isTrainPresent)
        if ok and res == true then
            return "Train detected"
        end
    elseif dev.isBlocked then
        local ok, res = pcall(dev.isBlocked)
        if ok and res == true then
            return "Train at signal"
        end
    elseif dev.getState then
        local ok, res = pcall(dev.getState)
        if ok and (res == "RED" or res == "OCCUPIED" or res == true or res == 1) then
            return "Train at signal"
        end
    end

    return nil
end

local function skanujPeryferia()
    local lista = {}
    for _, name in ipairs(pobierzWszystkieNazwyPeryferii()) do
        local dev = peripheral.wrap(name)
        if dev then
            local isWireless = false
            if dev.isWireless then pcall(function() isWireless = dev.isWireless() end) end

            if not isWireless then
                local pType = (peripheral.getType(name) or ""):lower()
                local nLower = name:lower()

                local jestStacja = pType:find("station") or nLower:find("station") or dev.getTrainName ~= nil or dev.getStationName ~= nil
                local jestSygnal = pType:find("signal") or nLower:find("signal") or nLower:find("create") 
                                   or (config.mapowanieSygnalow and config.mapowanieSygnalow[name] ~= nil)
                                   or dev.listBlockingTrainNames ~= nil or dev.hasTrain ~= nil or dev.getState ~= nil or dev.isBlocked ~= nil
                local jestObserver = pType:find("observer") or pType:find("target") or nLower:find("observer")

                if config.tryb == "AUTO" then
                    table.insert(lista, { name = name, dev = dev, type = pType })
                elseif config.tryb == "STACJA" and (jestStacja or jestSygnal) then
                    table.insert(lista, { name = name, dev = dev, type = pType })
                elseif config.tryb == "SYGNAL" then
                    table.insert(lista, { name = name, dev = dev, type = pType })
                elseif config.tryb == "OBSERVER" then
                    table.insert(lista, { name = name, dev = dev, type = pType })
                end
            end
        end
    end
    return lista
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

local function rysujEkran(serverId, statusInfo, iloscPeryferii)
    term.clear()
    term.setCursorPos(1, 1)
    print("========================================")
    print(" CLIENT:   " .. config.nazwaKlienta)
    print(" MY ID:    #" .. MOJE_ID)
    print(" MODE:     " .. config.tryb .. (iloscPeryferii and (" (Sensors: " .. iloscPeryferii .. ")") or ""))
    print(" SERVER:   " .. (serverId and ("ID #" .. serverId) or "Searching..."))
    print("========================================")
    print("Status:    " .. (statusInfo or "OK"))
    print("Game Time: " .. textutils.formatTime(os.time(), true))
    print("----------------------------------------")
end

--------------------------------------------------------------------------------
--                      CONNECTION & MAIN EVENT LOOP                           --
--------------------------------------------------------------------------------

rysujEkran(nil, "Connecting to central server...", 0)
local serverId = rednet.lookup(PROTOKOL, SERWER_HOST)
local serverLastCheck = os.clock()

local function pobierzServerId()
    if not serverId or (os.clock() - serverLastCheck > 10) then
        serverLastCheck = os.clock()
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

rysujEkran(serverId, "Connected to central server", 0)

local pingTimer = os.startTimer(config.interwalPing)
local loopTimer = os.startTimer(0.1)
local scanTimer = os.startTimer(2.0)

local bylSygnalRedstone = false
local znanePeryferia = skanujPeryferia()
local ostatnieWykrytePociagi = {}
local ostatnioWykrytyGlowny = nil

while true do
    local event, p1, p2, p3 = os.pullEvent()

    -- 1. Periodic peripheral re-scan
    if event == "timer" and p1 == scanTimer then
        znanePeryferia = skanujPeryferia()
        scanTimer = os.startTimer(2.0)

    -- 2. Heartbeat Ping
    elseif event == "timer" and p1 == pingTimer then
        serverId = pobierzServerId()
        if serverId then
            local sysCfg = nil
            if fs.exists("system_config.json") then
                local f = fs.open("system_config.json", "r")
                sysCfg = textutils.unserializeJSON(f.readAll())
                f.close()
            end
            rednet.send(serverId, {
                typ = "PING",
                nazwa = config.nazwaKlienta,
                tryb = config.tryb,
                rola = (sysCfg and sysCfg.rola) or "client",
                idStacji = config.idStacji or config.stacja or "ST",
                status = "ONLINE (" .. #znanePeryferia .. " dev)",
                pociag = ostatnioWykrytyGlowny,
                systemConfig = sysCfg,
                nodeConfig = config
            }, PROTOKOL)
        end
        pingTimer = os.startTimer(config.interwalPing)

    -- 3. Main Loop Train Detection
    elseif event == "timer" and p1 == loopTimer then
        local wykrytoWTejIteracji = false

        -- A. Detekcja z peryferii (Create Train Signals / Stations / Observers)
        for _, item in ipairs(znanePeryferia) do
            local nazwaPociagu = pobierzNazweZPeryferium(item.name, item.dev)
            if nazwaPociagu then
                wykrytoWTejIteracji = true
                if ostatnieWykrytePociagi[item.name] ~= nazwaPociagu then
                    ostatnieWykrytePociagi[item.name] = nazwaPociagu
                    ostatnioWykrytyGlowny = nazwaPociagu

                    -- Wyznaczenie numeru toru przypisanego do tego sygnału w konfiguracji
                    local wyznaczonyTor = (config.mapowanieSygnalow and config.mapowanieSygnalow[item.name]) or "1"

                    print(string.format("[%s] Train at %s (Tor %s): %s", textutils.formatTime(os.time(), true), item.name, wyznaczonyTor, nazwaPociagu))
                    rysujEkran(serverId, string.format("Train at %s (T%s): %s", item.name, wyznaczonyTor, nazwaPociagu), #znanePeryferia)

                    serverId = pobierzServerId()
                    if serverId then
                        rednet.send(serverId, {
                            typ = "PRZEJAZD_POCIAGU",
                            nazwa = config.nazwaKlienta,
                            pociag = nazwaPociagu,
                            tor = wyznaczonyTor,
                            sygnal = item.name,
                            tryb = config.tryb,
                            czas = textutils.formatTime(os.time(), true)
                        }, PROTOKOL)
                    end
                end
            else
                ostatnieWykrytePociagi[item.name] = nil
            end
        end

        -- B. Detekcja z Redstone Observera
        local jestRS = czySygnalRedstone()
        if jestRS and not bylSygnalRedstone then
            bylSygnalRedstone = true
            wykrytoWTejIteracji = true
            local nazwaPociagu = "Pociag (Redstone)"
            ostatnioWykrytyGlowny = nazwaPociagu

            print(string.format("[%s] Redstone pulse detected!", textutils.formatTime(os.time(), true)))
            rysujEkran(serverId, "Redstone pulse -> Train", #znanePeryferia)

            serverId = pobierzServerId()
            if serverId then
                rednet.send(serverId, {
                    typ = "PRZEJAZD_POCIAGU",
                    nazwa = config.nazwaKlienta,
                    pociag = nazwaPociagu,
                    tor = "1",
                    tryb = "OBSERVER",
                    czas = textutils.formatTime(os.time(), true)
                }, PROTOKOL)
            end
        elseif not jestRS and bylSygnalRedstone then
            bylSygnalRedstone = false
        end

        if not wykrytoWTejIteracji and ostatnioWykrytyGlowny then
            ostatnioWykrytyGlowny = nil
            rysujEkran(serverId, "Listening for trains...", #znanePeryferia)
        end

        loopTimer = os.startTimer(0.1)

    -- 4. Remote commands (REBOOT, USTAW_CONFIG_WEEZLA, ZAPYTANIE_CONFIG_WEEZLA)
    elseif event == "rednet_message" and p3 == PROTOKOL then
        local senderId, msg = p1, p2
        if type(msg) == "table" and (msg.typ == "REBOOT" or msg.typ == "REBOOT_ALL") then
            local tId = msg.targetId
            local tTryb = msg.targetTryb
            local myId = os.getComputerID()

            if not tId and not tTryb or (tId and tId == myId) or (tTryb and (tTryb == "CLIENT" or config.tryb:find(tTryb))) then
                term.clear()
                term.setCursorPos(1, 1)
                print("Received remote REBOOT command from #" .. tostring(senderId))
                print("Rebooting computer...")
                sleep(0.5)
                os.reboot()
            end

        elseif type(msg) == "table" and msg.typ == "USTAW_CONFIG_WEEZLA" then
            local tId = msg.targetId
            if not tId or tId == MOJE_ID then
                if msg.systemConfig then
                    local f = fs.open("system_config.json", "w")
                    f.write(textutils.serializeJSON(msg.systemConfig))
                    f.close()
                end
                if msg.nodeConfig then
                    local f = fs.open(CONFIG_FILE, "w")
                    f.write(textutils.serializeJSON(msg.nodeConfig))
                    f.close()
                end
                rednet.send(senderId, { typ = "POTWIERDZENIE_CONFIG", id = MOJE_ID, ok = true }, PROTOKOL)
                if msg.reboot ~= false then
                    term.clear()
                    term.setCursorPos(1, 1)
                    print("Zdalna zmiana konfiguracji! Restarting...")
                    sleep(0.5)
                    os.reboot()
                end
            end

        elseif type(msg) == "table" and msg.typ == "ZAPYTANIE_CONFIG_WEEZLA" then
            local tId = msg.targetId
            if not tId or tId == MOJE_ID then
                local sysCfg = nil
                if fs.exists("system_config.json") then
                    local f = fs.open("system_config.json", "r")
                    sysCfg = textutils.unserializeJSON(f.readAll())
                    f.close()
                end
                rednet.send(senderId, {
                    typ = "ODPOWIEDZ_CONFIG_WEEZLA",
                    id = MOJE_ID,
                    systemConfig = sysCfg,
                    nodeConfig = config
                }, PROTOKOL)
            end
        end
    end
end
