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
    print(" [5] AUTO     (Wszystkie wykryte czujniki/stacje)")
    write("Wybor [1-5]: ")

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

--------------------------------------------------------------------------------
--                 DYNAMISZNE SKANOWANIE I PARSOWANIE PERYFERIOW               --
--------------------------------------------------------------------------------

-- Pomocnicza czyszcząca nazwę pociągu
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

-- Odczyt nazwy pociągu z pojedynczego peryferium
local function pobierzNazweZPeryferium(name, dev)
    if not dev then return nil end

    -- 1. Metoda listBlockingTrainNames (Track Signal / Signal)
    if dev.listBlockingTrainNames then
        local ok, res = pcall(dev.listBlockingTrainNames)
        if ok and res then
            local parsed = czyscNazwePociagu(res)
            if parsed then return parsed end
        end
    end

    -- 2. Metoda getTrainName (Train Station / Target)
    if dev.getTrainName then
        local ok, res = pcall(dev.getTrainName)
        if ok and res then
            local parsed = czyscNazwePociagu(res)
            if parsed then return parsed end
        end
    end

    -- 3. Metoda getPresentTrainName (Alternatywna nazwa stacji)
    if dev.getPresentTrainName then
        local ok, res = pcall(dev.getPresentTrainName)
        if ok and res then
            local parsed = czyscNazwePociagu(res)
            if parsed then return parsed end
        end
    end

    -- 4. Metoda getPresentTrain (Tabela danych pociągu)
    if dev.getPresentTrain then
        local ok, res = pcall(dev.getPresentTrain)
        if ok and res then
            local parsed = czyscNazwePociagu(res)
            if parsed then return parsed end
        end
    end

    -- 5. Obecność pociągu bez bezpośredniej nazwy (hasTrain / isTrainPresent)
    if dev.hasTrain then
        local ok, res = pcall(dev.hasTrain)
        if ok and res == true then
            return "Pociag w peronie"
        end
    elseif dev.isTrainPresent then
        local ok, res = pcall(dev.isTrainPresent)
        if ok and res == true then
            return "Pociag wykryty"
        end
    end

    return nil
end

-- Skanowanie wszystkich dostępnych stacji i sygnałów podłączonych do komputera
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
    print(" KLIENT:  " .. config.nazwaKlienta)
    print(" MOJE ID: #" .. MOJE_ID)
    print(" TRYB:    " .. config.tryb .. (iloscPeryferii and (" (Czujniki: " .. iloscPeryferii .. ")") or ""))
    print(" SERWER:  " .. (serverId and ("ID #" .. serverId) or "Szukanie..."))
    print("========================================")
    print("Status: " .. (statusInfo or "OK"))
    print("Czas gry: " .. textutils.formatTime(os.time(), true))
    print("----------------------------------------")
end

--------------------------------------------------------------------------------
--                       ŁĄCZENIE I PĘTLA GŁÓWNA                               --
--------------------------------------------------------------------------------

rysujEkran(nil, "Laczenie z centrala...", 0)
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

rysujEkran(serverId, "Polaczono z centrala", 0)

local pingTimer = os.startTimer(config.interwalPing)
local loopTimer = os.startTimer(0.1)
local scanTimer = os.startTimer(2.0)

local bylSygnalRedstone = false
local znanePeryferia = skanujPeryferia()
local ostatnieWykrytePociagi = {} -- { [periName] = "Nazwa Pociągu" }
local ostatnioWykrytyGlowny = nil

while true do
    local event, p1, p2, p3 = os.pullEvent()

    -- 1. Cykliczny re-skan podłączonych urządzeń
    if event == "timer" and p1 == scanTimer then
        znanePeryferia = skanujPeryferia()
        scanTimer = os.startTimer(2.0)

    -- 2. Heartbeat (PING)
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

    -- 3. Detekcja z peryferiów stacyjnych / sygnałowych Create
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

                        -- Nazwa punktu: Klient + opis stacji (jeśli znana)
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

                        rysujEkran(serverId, "Wykryto: " .. pociag, #znanePeryferia)
                    end
                else
                    if staryPociag then
                        ostatnieWykrytePociagi[periKey] = nil
                        rysujEkran(serverId, "Sekcja zwolniona (" .. periKey .. ")", #znanePeryferia)
                    end
                end
            end

            if not jakakolwiekDetekcja and ostatnioWykrytyGlowny then
                ostatnioWykrytyGlowny = nil
            end
        end

        loopTimer = os.startTimer(0.1)

    -- 4. Detekcja sygnału Redstone (Observer / Detector)
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
                    pociag = "Przejazd przez detektor Redstone",
                    czas = czasGry
                }, PROTOKOL)
            end

            rysujEkran(serverId, "Wykryto przejazd (RS) o " .. czasGry, #znanePeryferia)

        elseif not jestSygnal and bylSygnalRedstone then
            bylSygnalRedstone = false
            rysujEkran(serverId, "Detektor Redstone zwolniony", #znanePeryferia)
        end
    end
end

