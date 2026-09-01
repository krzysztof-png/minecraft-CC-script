--------------------------------------------------------------------------------
--                MOBILNY TERMINAL DIAGNOSTYCZNY (log.lua)                    --
--                      ADAPTACYJNY DLA POCKET PC (26x20)                     --
--------------------------------------------------------------------------------
local PROTOKOL    = "kolej_net"
local SERWER_HOST = "centrala_glowna"
local TIMEOUT_SEK = 6

local modem = peripheral.find("modem")
if not modem then
    error("Blad: Nie znaleziono modemu (Wireless/Ender Modem)!")
end
rednet.open(peripheral.getName(modem))

local logi = {}
local klienci = {}
local bazaPrzejazdow = {}
local wykryteTablice = {}

local aktywnaKarta = 1 -- 1: URZĄDZENIA, 2: TELEMETRIA, 3: BAZA, 4: TABLICE, 5: CMD
local trybRebootConfirm = false
local rebootTargetTyp = nil
local rebootSingleId = nil

local function dodajWpis(tekst, kolor)
    local godz = textutils.formatTime(os.time(), true)
    table.insert(logi, 1, { tekst = string.format("[%s] %s", godz, tekst), kolor = kolor or colors.white })
    if #logi > 25 then table.remove(logi) end
end

local function rysujPasekKart()
    term.setCursorPos(1, 1)
    local k = { "[1]WEZ", "[2]LOG", "[3]BAZ", "[4]TAB", "[5]CMD" }
    for i = 1, 5 do
        if i == aktywnaKarta then
            term.setBackgroundColor(colors.blue)
            term.setTextColor(colors.yellow)
        else
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white)
        end
        write(k[i])
    end
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

local function odswiezEkran(serverId)
    term.clear()
    rysujPasekKart()

    term.setCursorPos(1, 2)
    term.setTextColor(colors.lightGray)
    local statusSerwera = serverId and ("SRV #" .. serverId) or "LACZENIE..."
    print(string.format("Stan: %-8s Czas: %s", statusSerwera, textutils.formatTime(os.time(), true)))
    print(string.rep("-", 26))

    -- ================= KARTA 1: URZĄDZENIA =================
    if aktywnaKarta == 1 then
        term.setTextColor(colors.yellow)
        print(string.format("%-4s %-12s %s", "ID", "POSTERUNEK", "STATUS"))
        term.setTextColor(colors.white)

        local teraz = os.clock()
        local count = 0
        for id, dane in pairs(klienci) do
            count = count + 1
            local online = (teraz - (dane.lastSeen or 0)) <= TIMEOUT_SEK
            local numId = tonumber(id) or id

            if online then
                term.setTextColor(colors.green)
                local statusDisplay = dane.status or "OK"
                print(string.format("#%-3s %-12s %s", tostring(numId), (dane.nazwa or ""):sub(1,12), statusDisplay:sub(1,7)))
            else
                term.setTextColor(colors.red)
                print(string.format("#%-3s %-12s OFFLINE", tostring(numId), (dane.nazwa or ""):sub(1,12)))
            end
        end

        if count == 0 then
            term.setTextColor(colors.gray)
            print("\n Brak zarejestrowanych")
            print(" wezlow w sieci.")
        end

    -- ================= KARTA 2: LOGI TELEMETRII =============
    elseif aktywnaKarta == 2 then
        if #logi == 0 then
            term.setTextColor(colors.gray)
            print("\n Brak wpisow w pamieci.")
        else
            for i = 1, math.min(#logi, 15) do
                local wpis = logi[i]
                term.setTextColor(wpis.kolor)
                print(wpis.tekst:sub(1, 26))
            end
        end

    -- ================= KARTA 3: BAZA POCIĄGÓW ===============
    elseif aktywnaKarta == 3 then
        term.setTextColor(colors.yellow)
        print(string.format("%-5s %-11s %-8s", "CZAS", "POCIAG", "POSTER"))
        term.setTextColor(colors.white)

        if #bazaPrzejazdow == 0 then
            term.setTextColor(colors.gray)
            print("\n Baza przejazdow jest")
            print(" pusta. Wcisnij [R].")
        else
            for i = 1, math.min(#bazaPrzejazdow, 14) do
                local r = bazaPrzejazdow[i]
                local czasStr = r.czas_gry or (r.timestamp and r.timestamp:sub(12,16)) or "--:--"
                local pociagStr = (r.nazwa_pociagu or "Pociag"):sub(1,11)
                local punktStr = (r.posterunek or "Trasa"):sub(1,8)
                
                term.setTextColor((r.opoznienie and r.opoznienie > 0) and colors.orange or colors.white)
                print(string.format("%-5s %-11s %-8s", czasStr, pociagStr, punktStr))
            end
        end

    -- ================= KARTA 4: ZARZĄDZANIE TABLICAMI ========
    elseif aktywnaKarta == 4 then
        term.setTextColor(colors.yellow)
        print(" ZARZADZANIE TABLICAMI ")
        term.setTextColor(colors.white)
        print(" [E] Edytuj wiersz tablicy")
        print(" [S] Skanuj tablice w sieci")
        print(" [T] Wyslij wzorzec test")
        print(" [C] Wyczysc tablice")
        print(" [R] Przywroc tryb ODJAZDY")
        print(string.rep("-", 26))
        term.setTextColor(colors.cyan)
        print(" TABLICE W SIECI:")
        term.setTextColor(colors.white)
        
        local count = 0
        for id, t in pairs(wykryteTablice) do
            count = count + 1
            print(string.format(" #%-3d %-9s %dx%d", id, (t.typDisp or "Disp"):sub(1,9), t.szer or 0, t.wys or 0))
        end
        if count == 0 then
            term.setTextColor(colors.gray)
            print(" Brak informacji o tablicy.")
            print(" Wcisnij [S] aby skanowac.")
        end

    -- ================= KARTA 5: REBOOT MANAGER ==============
    elseif aktywnaKarta == 5 then
        term.setTextColor(colors.red)
        print(" === ZDARZENIA I REBOOT ===")
        term.setTextColor(colors.white)
        print(" [1] Reboot CALEJ sieci")
        print(" [2] Reboot SERWERA")
        print(" [3] Reboot TABLIC")
        print(" [4] Reboot POSTERUNKOW")
        print(" [5] Reboot WYBRANEGO ID")
        print(" [6] Wyslij ALARM testowy")
        print(" [7] Kreator Stacji SRK")
        print(" [8] Zdalna Konfig. Node")
        print(string.rep("-", 26))
        term.setTextColor(colors.lightGray)
        print(" Wybierz opcje [1-8]")
    end

    -- Okno dialogowe potwierdzenia Rebootu
    if trybRebootConfirm then
        term.setCursorPos(1, 7)
        term.setBackgroundColor(colors.red)
        term.setTextColor(colors.white)
        print("==========================")
        local celTxt = "   RESTART: " .. tostring(rebootTargetTyp) .. " "
        if rebootTargetTyp == "SINGLE" then celTxt = string.format("   RESTART ID #%d   ", rebootSingleId or 0) end
        print(celTxt)
        print("  Potwierdzasz operacje?  ")
        print("   [T] TAK     [N] NIE    ")
        print("==========================")
        term.setBackgroundColor(colors.black)
    end
end

local function edytujWierszModal(serverId)
    term.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    print("==========================")
    print("  EDYCJA TABLICY PALCOWEJ ")
    print("==========================")
    term.setBackgroundColor(colors.black)

    write("Numer Linii [1-5]: ")
    local linia = tonumber(read()) or 1
    write("Tekst: ")
    local tekst = read()

    local msg = {
        typ = "USTAW_TEKST_TABLICY",
        linia = linia,
        tekst = tekst
    }

    if serverId then rednet.send(serverId, msg, PROTOKOL) end
    rednet.broadcast(msg, PROTOKOL)

    dodajWpis(string.format("Ustawiono L%d: %s", linia, tekst), colors.yellow)
    print("Wyslano polecenie zmiana wiersza!")
    sleep(1)
end

local function restartWybranegoIDModal(serverId)
    term.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.red)
    term.setTextColor(colors.white)
    print("==========================")
    print(" RESTART DEDYKOWANEGO ID  ")
    print("==========================")
    term.setBackgroundColor(colors.black)

    write("Wpisz ID komputera: #")
    local tId = tonumber(read())
    if tId then
        rebootSingleId = tId
        rebootTargetTyp = "SINGLE"
        trybRebootConfirm = true
    else
        print("Blad: Nieprawidlowy numer ID!")
        sleep(1)
    end
end

local function otworzZdalnaKonfiguracjeModal(serverId)
    term.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    print("==========================")
    print(" ZDALNA KONFIGURACJA NODE ")
    print("==========================")
    term.setBackgroundColor(colors.black)

    write("Wpisz ID komputera: #")
    term.setTextColor(colors.yellow)
    local targetId = tonumber(read())
    term.setTextColor(colors.white)

    if not targetId then
        print("[!] Anulowano.")
        sleep(1.0)
        return
    end

    print(string.format("\nZdalna ROLA (Autostart) #%d:", targetId))
    print(" [1] Central Server")
    print(" [2] Client Detekcji")
    print(" [3] Tablica 3x1")
    print(" [4] Tablica Peron")
    print(" [5] Tablica Glowna")
    print(" [6] Pocket PC")
    write("Wybór [1-6, puste=bez zm]: ")
    
    local selectedRole = nil
    local chRola = read()
    if chRola == "1" then selectedRole = "server" end
    if chRola == "2" then selectedRole = "client" end
    if chRola == "3" then selectedRole = "electric_display" end
    if chRola == "4" then selectedRole = "platform_display" end
    if chRola == "5" then selectedRole = "display" end
    if chRola == "6" then selectedRole = "log" end

    print("\nZdalna Stacja ID [GD/SP]:")
    write("Kod stacji [puste=bez zm]: ")
    term.setTextColor(colors.yellow)
    local inputStacja = read()
    term.setTextColor(colors.white)

    print("\nRestartowac komputer?")
    write(" [T] TAK  [N] NIE [dom. T]: ")
    local chReboot = read():lower()
    local doReboot = (chReboot ~= "n")

    local sysCfg = selectedRole and { rola = selectedRole } or nil
    local nodeCfg = (inputStacja ~= "") and { stacja = inputStacja, idStacji = inputStacja } or nil

    local payload = {
        typ = "USTAW_CONFIG_WEEZLA",
        targetId = targetId,
        systemConfig = sysCfg,
        nodeConfig = nodeCfg,
        reboot = doReboot
    }

    if serverId then rednet.send(serverId, payload, PROTOKOL) end
    rednet.send(targetId, payload, PROTOKOL)
    rednet.broadcast(payload, PROTOKOL)

    term.setTextColor(colors.green)
    print(string.format("\nWyslano konfiguracje do ID #%d!", targetId))
    term.setTextColor(colors.white)
    sleep(1.5)
end

local function wykonajReboot(serverId)
    trybRebootConfirm = false
    if rebootTargetTyp == "ALL" then
        dodajWpis("Wysylanie REBOOT CALEJ SIECE", colors.red)
        rednet.broadcast({ typ = "REBOOT_ALL" }, PROTOKOL)
        if serverId then rednet.send(serverId, { typ = "REBOOT_ALL" }, PROTOKOL) end
        sleep(0.5)
        os.reboot()

    elseif rebootTargetTyp == "SERVER" then
        dodajWpis("Wysylanie REBOOT SERWERA...", colors.red)
        if serverId then rednet.send(serverId, { typ = "REBOOT", targetId = serverId }, PROTOKOL) end

    elseif rebootTargetTyp == "DISPLAY" then
        dodajWpis("Wysylanie REBOOT TABLIC...", colors.orange)
        rednet.broadcast({ typ = "REBOOT", targetTryb = "DISPLAY" }, PROTOKOL)

    elseif rebootTargetTyp == "CLIENT" then
        dodajWpis("Wysylanie REBOOT POSTERUNKOW", colors.orange)
        rednet.broadcast({ typ = "REBOOT", targetTryb = "CLIENT" }, PROTOKOL)

    elseif rebootTargetTyp == "SINGLE" and rebootSingleId then
        dodajWpis(string.format("Wysylanie REBOOT do #%d...", rebootSingleId), colors.yellow)
        rednet.send(rebootSingleId, { typ = "REBOOT", targetId = rebootSingleId }, PROTOKOL)
        rednet.broadcast({ typ = "REBOOT", targetId = rebootSingleId }, PROTOKOL)
        if rebootSingleId == os.getComputerID() then
            sleep(0.5)
            os.reboot()
        end
    end
end

-- Inicjalizacja połączenia
local serverId = nil
local lastServerCheck = os.clock()

local function pobierzServerId()
    if not serverId or (os.clock() - lastServerCheck > 10) then
        lastServerCheck = os.clock()
        local id = rednet.lookup(PROTOKOL, SERWER_HOST)
        if id then serverId = id end
    end
    return serverId
end

odswiezEkran(nil)
serverId = pobierzServerId()
while not serverId do
    sleep(1.5)
    serverId = pobierzServerId()
end

dodajWpis("Polaczono z centrala #" .. serverId, colors.green)
rednet.send(serverId, { typ = "POBIERZ_DANE" }, PROTOKOL)
rednet.send(serverId, { typ = "POBIERZ_BAZE" }, PROTOKOL)
rednet.broadcast({ typ = "ZAPYTANIE_TABLICA" }, PROTOKOL)

local timerOdswiezania = os.startTimer(1)
local timerPing = os.startTimer(3)

while true do
    local event, p1, p2, p3 = os.pullEvent()

    -- 1. Odbiór danych sieciowych
    if event == "rednet_message" and p3 == PROTOKOL then
        local senderId, msg = p1, p2
        if type(msg) == "table" then
            if msg.typ == "SYNC_KLIENCI" and msg.klienci then
                klienci = msg.klienci
                odswiezEkran(serverId)
            elseif msg.typ == "NOWY_LOG" then
                local kolor = colors.white
                if msg.kategoria == "PRZEJAZD" then kolor = colors.lightBlue end
                if msg.kategoria == "ALARM"    then kolor = colors.red end
                if msg.kategoria == "SYSTEM"   then kolor = colors.yellow end
                dodajWpis(msg.tekst, kolor)
                
                if msg.kategoria == "PRZEJAZD" and serverId then
                    rednet.send(serverId, { typ = "POBIERZ_BAZE" }, PROTOKOL)
                end
                odswiezEkran(serverId)

            elseif msg.typ == "PELNE_DANE" then
                if msg.klienci then klienci = msg.klienci end
                if msg.logi then
                    logi = {}
                    for _, l in ipairs(msg.logi) do
                        local txt = type(l) == "table" and (string.format("[%s] %s", l.godzina, l.tekst)) or tostring(l)
                        table.insert(logi, { tekst = txt, kolor = colors.lightGray })
                    end
                end
                odswiezEkran(serverId)

            elseif msg.typ == "BAZA_PRZEJAZDOW" and msg.baza then
                bazaPrzejazdow = msg.baza
                odswiezEkran(serverId)

            elseif msg.typ == "ODPOWIEDZ_TABLICA" then
                wykryteTablice[senderId] = {
                    szer = msg.szer or 0,
                    wys = msg.wys or 0,
                    typDisp = msg.typDisp or "Disp"
                }
                dodajWpis(string.format("Tablica #%d: %dx%d", senderId, msg.szer or 0, msg.wys or 0), colors.lime)
                odswiezEkran(serverId)

            elseif msg.typ == "REBOOT" or msg.typ == "REBOOT_ALL" then
                local targetId = msg.targetId
                local targetTryb = msg.targetTryb
                local myId = os.getComputerID()

                if not targetId and not targetTryb then
                    term.clear()
                    term.setCursorPos(1, 1)
                    print("Zdalny restart komputera...")
                    sleep(0.5)
                    os.reboot()
                elseif targetId and targetId == myId then
                    term.clear()
                    term.setCursorPos(1, 1)
                    print("Dedykowany restart komputera #" .. myId)
                    sleep(0.5)
                    os.reboot()
                end
            end
        end

    -- 2. Cykliczny timer odświeżania zegara i timeoutów
    elseif event == "timer" and p1 == timerOdswiezania then
        odswiezEkran(serverId)
        timerOdswiezania = os.startTimer(1)

    elseif event == "timer" and p1 == timerPing then
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
                nazwa = "Pocket_PC_" .. os.getComputerID(),
                tryb = "POCKET",
                rola = (sysCfg and sysCfg.rola) or "log",
                status = "ONLINE",
                systemConfig = sysCfg
            }, PROTOKOL)
        end
        timerPing = os.startTimer(3)

    -- 3. Obsługa klawiatury
    elseif event == "key" then
        if trybRebootConfirm then
            if p1 == keys.t or p1 == keys.y then
                wykonajReboot(serverId)
                odswiezEkran(serverId)
            elseif p1 == keys.n or p1 == keys.backspace or p1 == keys.delete then
                trybRebootConfirm = false
                odswiezEkran(serverId)
            end
        else
            if p1 == keys.one or p1 == keys.numPad1 then
                if aktywnaKarta == 5 then
                    rebootTargetTyp = "ALL"
                    trybRebootConfirm = true
                else
                    aktywnaKarta = 1
                end
                odswiezEkran(serverId)
            elseif p1 == keys.two or p1 == keys.numPad2 then
                if aktywnaKarta == 5 then
                    rebootTargetTyp = "SERVER"
                    trybRebootConfirm = true
                else
                    aktywnaKarta = 2
                end
                odswiezEkran(serverId)
            elseif p1 == keys.three or p1 == keys.numPad3 then
                if aktywnaKarta == 5 then
                    rebootTargetTyp = "DISPLAY"
                    trybRebootConfirm = true
                else
                    aktywnaKarta = 3
                    if serverId then rednet.send(serverId, { typ = "POBIERZ_BAZE" }, PROTOKOL) end
                end
                odswiezEkran(serverId)
            elseif p1 == keys.four or p1 == keys.numPad4 then
                if aktywnaKarta == 5 then
                    rebootTargetTyp = "CLIENT"
                    trybRebootConfirm = true
                else
                    aktywnaKarta = 4
                    rednet.broadcast({ typ = "ZAPYTANIE_TABLICA" }, PROTOKOL)
                    if serverId then rednet.send(serverId, { typ = "ZAPYTANIE_TABLICA" }, PROTOKOL) end
                end
                odswiezEkran(serverId)
            elseif p1 == keys.five or p1 == keys.numPad5 then
                if aktywnaKarta == 5 then
                    restartWybranegoIDModal(serverId)
                else
                    aktywnaKarta = 5
                end
                odswiezEkran(serverId)
            elseif p1 == keys.six or p1 == keys.numPad6 then
                if aktywnaKarta == 5 then
                    dodajWpis("Wyslano sygnal ALARM!", colors.red)
                    rednet.broadcast({ typ = "ALARM", nazwa = "Terminal_Pocket", powod = "Sygnal Alarmowy z Pocket PC" }, PROTOKOL)
                    if serverId then rednet.send(serverId, { typ = "ALARM", nazwa = "Terminal_Pocket", powod = "Sygnal Alarmowy" }, PROTOKOL) end
                end
                odswiezEkran(serverId)
            elseif p1 == keys.seven or p1 == keys.numPad7 then
                if aktywnaKarta == 5 then
                    term.clear()
                    term.setCursorPos(1, 1)
                    term.setTextColor(colors.white)
                    term.setBackgroundColor(colors.black)
                    if fs.exists("station_wizard.lua") then
                        shell.run("station_wizard.lua")
                    end
                end
                odswiezEkran(serverId)
            elseif p1 == keys.eight or p1 == keys.numPad8 then
                if aktywnaKarta == 5 then
                    otworzZdalnaKonfiguracjeModal(serverId)
                end
                odswiezEkran(serverId)
            elseif p1 == keys.tab then
                aktywnaKarta = (aktywnaKarta % 5) + 1
                if aktywnaKarta == 3 and serverId then
                    rednet.send(serverId, { typ = "POBIERZ_BAZE" }, PROTOKOL)
                elseif aktywnaKarta == 4 then
                    rednet.broadcast({ typ = "ZAPYTANIE_TABLICA" }, PROTOKOL)
                end
                odswiezEkran(serverId)
            elseif p1 == keys.r and aktywnaKarta == 3 and serverId then
                rednet.send(serverId, { typ = "POBIERZ_BAZE" }, PROTOKOL)
            elseif p1 == keys.c and aktywnaKarta == 2 then
                logi = {}
                dodajWpis("Wyczyszczono logi lokalne.", colors.orange)
                odswiezEkran(serverId)
            elseif p1 == keys.e and aktywnaKarta == 4 then
                edytujWierszModal(serverId)
                odswiezEkran(serverId)
            elseif p1 == keys.s and aktywnaKarta == 4 then
                dodajWpis("Skanowanie tablic w sieci...", colors.yellow)
                rednet.broadcast({ typ = "ZAPYTANIE_TABLICA" }, PROTOKOL)
                if serverId then rednet.send(serverId, { typ = "ZAPYTANIE_TABLICA" }, PROTOKOL) end
                odswiezEkran(serverId)
            elseif p1 == keys.t and aktywnaKarta == 4 then
                dodajWpis("Wyslano wzorzec testowy.", colors.cyan)
                rednet.broadcast({ typ = "TEST_TABLICY" }, PROTOKOL)
                if serverId then rednet.send(serverId, { typ = "TEST_TABLICY" }, PROTOKOL) end
                odswiezEkran(serverId)
            elseif p1 == keys.x then
                rebootTargetTyp = "ALL"
                trybRebootConfirm = true
                odswiezEkran(serverId)
            elseif p1 == keys.q then
                term.clear()
                term.setCursorPos(1, 1)
                print("Wylaczono mobilny monitor.")
                break
            end
        end

    -- 4. Obsługa znaku wpisywanego (dla potwierdzenia T/N)
    elseif event == "char" and trybRebootConfirm then
        local ch = p1:lower()
        if ch == "t" or ch == "y" then
            wykonajReboot(serverId)
            odswiezEkran(serverId)
        else
            trybRebootConfirm = false
            odswiezEkran(serverId)
        end

    -- 5. Obsługa dotykowa (kliknięcia na Pocket PC)
    elseif event == "mouse_click" then
        local button, x, y = p1, p2, p3

        if trybRebootConfirm then
            if y >= 7 and y <= 11 then
                if x >= 3 and x <= 11 then
                    wykonajReboot(serverId)
                    odswiezEkran(serverId)
                elseif x >= 13 and x <= 22 then
                    trybRebootConfirm = false
                    odswiezEkran(serverId)
                end
            else
                trybRebootConfirm = false
                odswiezEkran(serverId)
            end
        else
            -- 1. Kliknięcie na pasek zakładek (Góra: y == 1)
            if y == 1 then
                if x <= 5 then
                    aktywnaKarta = 1
                elseif x <= 10 then
                    aktywnaKarta = 2
                elseif x <= 15 then
                    aktywnaKarta = 3
                    if serverId then rednet.send(serverId, { typ = "POBIERZ_BAZE" }, PROTOKOL) end
                elseif x <= 20 then
                    aktywnaKarta = 4
                    rednet.broadcast({ typ = "ZAPYTANIE_TABLICA" }, PROTOKOL)
                else
                    aktywnaKarta = 5
                end
                odswiezEkran(serverId)

            -- 2. Kliknięcie na dolny pasek (Dół: y == 20)
            elseif y == 20 then
                if x >= 12 and x <= 20 then
                    rebootTargetTyp = "ALL"
                    trybRebootConfirm = true
                    odswiezEkran(serverId)
                elseif x >= 23 then
                    term.clear()
                    term.setCursorPos(1, 1)
                    print("Wylaczono mobilny monitor.")
                    break
                end

            -- 3. Dotykowe akcje na Karcie 4 (Tablica)
            elseif aktywnaKarta == 4 then
                if y == 4 then
                    dodajWpis("Skanowanie tablic w sieci...", colors.yellow)
                    rednet.broadcast({ typ = "ZAPYTANIE_TABLICA" }, PROTOKOL)
                    if serverId then rednet.send(serverId, { typ = "ZAPYTANIE_TABLICA" }, PROTOKOL) end
                    odswiezEkran(serverId)
                elseif y == 5 then
                    edytujWierszModal(serverId)
                    odswiezEkran(serverId)
                elseif y == 6 then
                    dodajWpis("Wyslano wzorzec testowy.", colors.cyan)
                    rednet.broadcast({ typ = "TEST_TABLICY" }, PROTOKOL)
                    if serverId then rednet.send(serverId, { typ = "TEST_TABLICY" }, PROTOKOL) end
                    odswiezEkran(serverId)
                elseif y == 7 then
                    dodajWpis("Wyczyszczono tablice.", colors.orange)
                    rednet.broadcast({ typ = "WYCZYSC_TABLICE" }, PROTOKOL)
                    if serverId then rednet.send(serverId, { typ = "WYCZYSC_TABLICE" }, PROTOKOL) end
                    odswiezEkran(serverId)
                elseif y == 8 then
                    dodajWpis("Przywrocono tryb ODJAZDY.", colors.green)
                    rednet.broadcast({ typ = "RESET_TABLICY" }, PROTOKOL)
                    if serverId then rednet.send(serverId, { typ = "RESET_TABLICY" }, PROTOKOL) end
                    odswiezEkran(serverId)
                end

            -- 4. Dotykowe akcje na Karcie 5 (Reboot Manager)
            elseif aktywnaKarta == 5 then
                if y == 5 then -- [1] Reboot CAŁEJ sieci
                    rebootTargetTyp = "ALL"
                    trybRebootConfirm = true
                    odswiezEkran(serverId)
                elseif y == 6 then -- [2] Reboot SERWERA
                    rebootTargetTyp = "SERVER"
                    trybRebootConfirm = true
                    odswiezEkran(serverId)
                elseif y == 7 then -- [3] Reboot TABLIC
                    rebootTargetTyp = "DISPLAY"
                    trybRebootConfirm = true
                    odswiezEkran(serverId)
                elseif y == 8 then -- [4] Reboot POSTERUNKOW
                    rebootTargetTyp = "CLIENT"
                    trybRebootConfirm = true
                    odswiezEkran(serverId)
                elseif y == 9 then -- [5] Reboot WYBRANEGO ID
                    restartWybranegoIDModal(serverId)
                    odswiezEkran(serverId)
                elseif y == 10 then -- [6] Alarm Testowy
                    dodajWpis("Wyslano sygnal ALARM!", colors.red)
                    rednet.broadcast({ typ = "ALARM", nazwa = "Terminal_Pocket", powod = "Sygnal Alarmowy z Pocket PC" }, PROTOKOL)
                    if serverId then rednet.send(serverId, { typ = "ALARM", nazwa = "Terminal_Pocket", powod = "Sygnal Alarmowy" }, PROTOKOL) end
                    odswiezEkran(serverId)
                elseif y == 11 then -- [7] Kreator Stacji SRK
                    term.clear()
                    term.setCursorPos(1, 1)
                    term.setTextColor(colors.white)
                    term.setBackgroundColor(colors.black)
                    if fs.exists("station_wizard.lua") then
                        shell.run("station_wizard.lua")
                    end
                elseif y == 12 then -- [8] Zdalna Konfiguracja Node
                    otworzZdalnaKonfiguracjeModal(serverId)
                    odswiezEkran(serverId)
                end
            end
        end
    end
end
