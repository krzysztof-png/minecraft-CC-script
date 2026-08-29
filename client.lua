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
    print(" [3] SIGNAL   (Train Signal - listBlockingTrainNames)")
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

-- Inicjalizacja modemu
local modem = peripheral.find("modem")
if not modem then
    error("Error: Wireless modem not detected!")
end
rednet.open(peripheral.getName(modem))

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
            return "Train at platform"
        end
    elseif dev.isTrainPresent then
        local ok, res = pcall(dev.isTrainPresent)
        if ok and res == true then
            return "Train detected"
        end
    end

    return nil
end

local function skanujPeryferia()
    local lista = {}
    for _, name in ipairs(peripheral.getNames()) do
        if name ~= peripheral.getName(modem) then
            local pType = peripheral.getType(name) or ""
            local dev = peripheral.wrap(name)

            if dev then
                local tLower = pType:lower()
                local jestStacja = tLower:find("station") or dev.getTrainName ~= nil or dev.getStationName ~= nil
                local jestSygnal = tLower:find("signal") or dev.listBlockingTrainNames ~= nil
                local jestObserver = tLower:find("observer") or tLower:find("target")

                if config.tryb == "AUTO" then
                    if jestStacja or jestSygnal or jestObserver then
                        table.insert(lista, { name = name, dev = dev, type = pType })
                    end
                elseif config.tryb == "STACJA" and jestStacja then
                    table.insert(lista, { name = name, dev = dev, type = pType })
                elseif config.tryb == "SYGNAL" and jestSygnal then
                    table.insert(lista, { name = name, dev = dev, type = pType })
                elseif config.tryb == "OBSERVER" and jestObserver then
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

    -- 2. Heartbeat PING
    elseif event == "timer" and p1 == pingTimer then
        serverId = pobierzServerId()

        local glownyPociag = nil
        for _, item in ipairs(znanePeryferia) do
            local pName = pobierzNazweZPeryferium(item.name, item.dev)
            if pName then
                glownyPociag = pName
                break
            end
        end

        local statusPayload = glownyPociag or (bylSygnalRedstone and "PRZEJAZD" or "WOLNY")

        if serverId then
            rednet.send(serverId, {
                typ = "PING",
                nazwa = config.nazwaKlienta,
                tryb = config.tryb,
                status = statusPayload,
                pociag = glownyPociag,
                peryferia = #znanePeryferia
            }, PROTOKOL)
        end

        pingTimer = os.startTimer(config.interwalPing)

    -- 3. Detection from Create station / signal peripherals
    elseif event == "timer" and p1 == loopTimer then
        serverId = pobierzServerId()

        if config.tryb == "STACJA" or config.tryb == "SYGNAL" or config.tryb == "AUTO" then
            local jakakolwiekDetekcja = false

            for _, item in ipairs(znanePeryferia) do
                local periKey = item.name
                local pociag = pobierzNazweZPeryferium(item.name, item.dev)
                local staryPociag = ostatnieWykrytePociagi[periKey]

                if pociag then
                    jakakolwiekDetekcja = true
                    if pociag ~= staryPociag then
                        ostatnieWykrytePociagi[periKey] = pociag
                        local czasGry = textutils.formatTime(os.time(), true)

                        local nazwaStacji = nil
                        if item.dev.getStationName then
                            local ok, sName = pcall(item.dev.getStationName)
                            if ok and sName and #sName > 0 then nazwaStacji = sName end
                        end

                        local punktOpis = config.nazwaKlienta
                        if nazwaStacji then
                            punktOpis = punktOpis .. " (" .. nazwaStacji .. ")"
                        elseif #znanePeryferia > 1 then
                            punktOpis = punktOpis .. " [" .. periKey .. "]"
                        end

                        if serverId then
                            rednet.send(serverId, {
                                typ = "PRZEJAZD_POCIAGU",
                                nazwa = punktOpis,
                                tryb = config.tryb,
                                pociag = pociag,
                                czas = czasGry,
                                peryferium = periKey
                            }, PROTOKOL)
                        end

                        rysujEkran(serverId, "Detected: " .. pociag, #znanePeryferia)
                    end
                else
                    if staryPociag then
                        ostatnieWykrytePociagi[periKey] = nil
                        rysujEkran(serverId, "Section cleared (" .. periKey .. ")", #znanePeryferia)
                    end
                end
            end

            if not jakakolwiekDetekcja and ostatnioWykrytyGlowny then
                ostatnioWykrytyGlowny = nil
            end
        end

        loopTimer = os.startTimer(0.1)

    -- 4. Redstone Signal Detection (Observer / Detector)
    elseif event == "redstone" and (config.tryb == "OBSERVER" or config.tryb == "AUTO") then
        serverId = pobierzServerId()
        local jestSygnal = czySygnalRedstone()

        if jestSygnal and not bylSygnalRedstone then
            bylSygnalRedstone = true
            local czasGry = textutils.formatTime(os.time(), true)

            if serverId then
                rednet.send(serverId, {
                    typ = "PRZEJAZD_POCIAGU",
                    nazwa = config.nazwaKlienta,
                    tryb = config.tryb,
                    pociag = "Passed Redstone detector",
                    czas = czasGry
                }, PROTOKOL)
            end

            rysujEkran(serverId, "Passage detected (RS) at " .. czasGry, #znanePeryferia)

        elseif not jestSygnal and bylSygnalRedstone then
            bylSygnalRedstone = false
            rysujEkran(serverId, "Redstone detector cleared", #znanePeryferia)
        end

    -- 5. Remote Rednet command handler (REBOOT / REBOOT_ALL)
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
        end
    end
end
