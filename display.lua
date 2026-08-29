--------------------------------------------------------------------------------
--                CREATE DISPLAY BOARD CONTROLLER (display.lua)               --
--------------------------------------------------------------------------------
local PROTOKOL      = "kolej_net"
local SERWER_HOST   = "centrala_glowna"
local TYTUL_TABLICY = "DEPARTURES"

-- 1. Modem Initialization
local modem = peripheral.find("modem")
if not modem then
    error("Error: Wireless or Ender modem not found!")
end
rednet.open(peripheral.getName(modem))

-- 2. Peripheral Discovery (Display Link / Display Board / Monitor)
local function znajdzWyswietlacz()
    for _, name in ipairs(peripheral.getNames()) do
        if name ~= peripheral.getName(modem) then
            local dev = peripheral.wrap(name)
            if dev and (dev.write or dev.setLine or dev.update) then
                local t = (peripheral.getType(name) or ""):lower()
                if not t:find("modem") and not t:find("drive") and not t:find("computer") and not t:find("turtle") then
                    return dev, name, t
                end
            end
        end
    end

    return term.native(), "terminal", "terminal"
end

local display, dispName, dispType = znajdzWyswietlacz()

local function pobierzWymiary()
    if display and display.getSize then
        local w, h = pcall(display.getSize)
        if w and h and type(w) == "number" and w > 0 then
            return w, h
        end
    end
    local w, h = term.getSize()
    return w or 32, h or 6
end

local szerokosc, wysokosc = pobierzWymiary()

-- Update Create display board buffer / flaps (display.update())
local function odswiezFlapyTablicy()
    if not display then return end
    if display.update then pcall(display.update) end
    if display.flush then pcall(display.flush) end
    if display.render then pcall(display.render) end
    if display.updateBoard then pcall(display.updateBoard) end
end

-- Write single line without immediate update()
local function wypiszWierszBezUpdate(nrLinii, tekst)
    if not display or nrLinii < 1 or nrLinii > wysokosc then return end

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

    -- 1. setCursorPos + write (Create Display Link standard)
    if display.setCursorPos and display.write then
        pcall(display.setCursorPos, 1, nrLinii)
        pcall(display.write, sformatowany)
    end

    -- 2. setLine (1-indexed and 0-indexed fallback)
    if display.setLine then
        local ok = pcall(display.setLine, nrLinii, sformatowany)
        if not ok and (nrLinii - 1) >= 0 then
            pcall(display.setLine, nrLinii - 1, sformatowany)
        end
    end

    -- 3. setRow
    if display.setRow then
        local ok = pcall(display.setRow, nrLinii, sformatowany)
        if not ok and (nrLinii - 1) >= 0 then
            pcall(display.setRow, nrLinii - 1, sformatowany)
        end
    end
end

-- Write line with immediate update()
local function wypiszWiersz(nrLinii, tekst)
    wypiszWierszBezUpdate(nrLinii, tekst)
    odswiezFlapyTablicy()
end

local function wyczyscTablice()
    if display.clear then
        pcall(display.clear)
    end
    for i = 1, wysokosc do
        wypiszWierszBezUpdate(i, "")
    end
    odswiezFlapyTablicy()
end

local historiaPrzejazdow = {}
local trybManualny = false

local function odswiezTablice()
    if trybManualny then return end

    if display.clear then
        pcall(display.clear)
    end

    local czasGry = textutils.formatTime(os.time(), true)
    local naglowek = string.format("%s [%s]", TYTUL_TABLICY, czasGry)
    wypiszWierszBezUpdate(1, naglowek)

    for i = 2, wysokosc do
        local wpis = historiaPrzejazdow[i - 1]
        if wpis then
            wypiszWierszBezUpdate(i, string.format("%s %s", wpis.czas, wpis.punkt))
        else
            wypiszWierszBezUpdate(i, "")
        end
    end

    odswiezFlapyTablicy()
end

-- 3. Computer Console Interface & Server Connection
term.clear()
term.setCursorPos(1, 1)
print("========================================")
print("      CREATE DISPLAY CONTROLLER         ")
print("========================================")
print(string.format("Detected Device: %s (%s)", dispName or "Native", dispType or "Terminal"))
print(string.format("Board Size:      %d x %d (chars x rows)", szerokosc, wysokosc))
print("Searching for central server...")

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

print("Connected to central server #" .. serverId)
wyczyscTablice()
odswiezTablice()

-- Register display and download initial train database
rednet.send(serverId, {
    typ = "PING",
    nazwa = "Tablica_" .. os.getComputerID(),
    tryb = "DISPLAY",
    status = string.format("%dx%d", szerokosc, wysokosc)
}, PROTOKOL)
rednet.send(serverId, { typ = "POBIERZ_BAZE" }, PROTOKOL)

local zegarTimer = os.startTimer(2)
local pingTimer = os.startTimer(2)
local rescanTimer = os.startTimer(5)

while true do
    local event, p1, p2, p3 = os.pullEvent()

    -- Rednet network messages
    if event == "rednet_message" and p3 == PROTOKOL then
        local senderId, msg = p1, p2
        if type(msg) == "table" then
            if msg.typ == "PRZEJAZD_POCIAGU" or (msg.typ == "NOWY_LOG" and msg.kategoria == "PRZEJAZD") then
                trybManualny = false
                local czas = msg.czas or textutils.formatTime(os.time(), true)
                local punkt = msg.nazwa or msg.punkt or ("KM_" .. senderId)
                local pociag = msg.pociag
                local etykieta = (pociag and pociag ~= "") and (punkt .. " -> " .. pociag) or punkt

                table.insert(historiaPrzejazdow, 1, { czas = czas, punkt = etykieta })
                if #historiaPrzejazdow > (wysokosc - 1) then
                    table.remove(historiaPrzejazdow)
                end

                print(string.format("[%s] Recorded: %s", czas, etykieta))
                odswiezTablice()

            elseif msg.typ == "BAZA_PRZEJAZDOW" and msg.baza then
                if not trybManualny then
                    historiaPrzejazdow = {}
                    for i = #msg.baza, math.max(1, #msg.baza - (wysokosc - 2)), -1 do
                        local r = msg.baza[i]
                        local czas = r.czas_gry or (r.timestamp and r.timestamp:sub(12,16)) or "--:--"
                        local punkt = r.posterunek or "Track"
                        local pociag = r.nazwa_pociagu
                        local etykieta = (pociag and pociag ~= "") and (punkt .. " -> " .. pociag) or punkt
                        table.insert(historiaPrzejazdow, { czas = czas, punkt = etykieta })
                    end
                    odswiezTablice()
                end

            elseif msg.typ == "ZAPYTANIE_TABLICA" then
                rednet.send(senderId, {
                    typ = "ODPOWIEDZ_TABLICA",
                    id = os.getComputerID(),
                    szer = szerokosc,
                    wys = wysokosc,
                    typDisp = dispType or "Display"
                }, PROTOKOL)

            elseif msg.typ == "USTAW_TEKST_TABLICY" then
                trybManualny = true
                local nr = tonumber(msg.linia) or 1
                local txt = msg.tekst or ""
                wypiszWiersz(nr, txt)
                print(string.format("[MANUAL] Line %d: %s", nr, txt))

            elseif msg.typ == "TEST_TABLICY" then
                trybManualny = true
                if display.clear then pcall(display.clear) end
                wypiszWierszBezUpdate(1, string.format("DISPLAY TEST [%dx%d]", szerokosc, wysokosc))
                for l = 2, wysokosc do
                    wypiszWierszBezUpdate(l, string.format("%d. %s TEST", l - 1, textutils.formatTime(os.time(), true)))
                end
                odswiezFlapyTablicy()
                print("[TEST] Test pattern sent to display.")

            elseif msg.typ == "WYCZYSC_TABLICE" then
                trybManualny = true
                wyczyscTablice()
                print("[MANUAL] Display cleared.")

            elseif msg.typ == "RESET_TABLICY" then
                trybManualny = false
                wyczyscTablice()
                odswiezTablice()
                if serverId then rednet.send(serverId, { typ = "POBIERZ_BAZE" }, PROTOKOL) end
                print("[RESET] Returned to DEPARTURES mode.")

            elseif msg.typ == "REBOOT" or msg.typ == "REBOOT_ALL" then
                print("Received remote REBOOT command!")
                sleep(0.5)
                os.reboot()
            end
        end

    -- Heartbeat PING to central server
    elseif event == "timer" and p1 == pingTimer then
        serverId = pobierzServerId()
        if serverId then
            rednet.send(serverId, {
                typ = "PING",
                nazwa = "Tablica_" .. os.getComputerID(),
                tryb = "DISPLAY",
                status = string.format("%dx%d", szerokosc, wysokosc)
            }, PROTOKOL)
        end
        pingTimer = os.startTimer(2)

    -- Periodic display peripheral re-scan
    elseif event == "timer" and p1 == rescanTimer then
        local nowyDisp, nName, nType = znajdzWyswietlacz()
        if nowyDisp ~= display then
            display = nowyDisp
            dispName = nName
            dispType = nType
            szerokosc, wysokosc = pobierzWymiary()
            wyczyscTablice()
            if not trybManualny then odswiezTablice() end
        end
        pobierzServerId()
        rescanTimer = os.startTimer(5)

    -- Clock update timer
    elseif event == "timer" and p1 == zegarTimer then
        if not trybManualny then odswiezTablice() end
        zegarTimer = os.startTimer(2)
    end
end
