--------------------------------------------------------------------------------
--            MOBILNY MONITOR KOLEJOWY (POCKET PC - 3 KARTY + BAZA)           --
--------------------------------------------------------------------------------
local PROTOKOL     = "kolej_net"
local SERWER_HOST  = "centrala_glowna"
local TIMEOUT_SEK  = 6

local modem = peripheral.find("modem")
if not modem then
    error("Brak modemu! Wytworz Pocket Computer z modemem.")
end
rednet.open(peripheral.getName(modem))

local aktywnaKarta = 1 -- 1: Węzły, 2: Logi na żywo, 3: Baza przejazdów, 4: Tablica Create
local klienci = {}
local logi = {}
local bazaPrzejazdow = {}
local wykryteTablice = {} -- { [id] = { szer, wys, typDisp } }
local MAX_LOGOW = 16
local trybRebootConfirm = false

local function dodajWpis(tekst, kolor)
    table.insert(logi, 1, { tekst = tekst, kolor = kolor or colors.white })
    if #logi > MAX_LOGOW then
        table.remove(logi)
    end
end

-- Rysowanie paska zakładek (góra ekranu: 26 znaków szerokości)
local function rysujPasekKart()
    term.setCursorPos(1, 1)
    
    -- Karta 1: Węzły
    if aktywnaKarta == 1 then
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        term.write("[1]WEZLY")
    else
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.lightGray)
        term.write("1:Wezly ")
    end

    -- Karta 2: Logi
    if aktywnaKarta == 2 then
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        term.write("[2]LOGI")
    else
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.lightGray)
        term.write("2:Logi ")
    end

    -- Karta 3: Baza
    if aktywnaKarta == 3 then
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        term.write("[3]BAZA")
    else
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.lightGray)
        term.write("3:Baza ")
    end

    -- Karta 4: Tablica
    if aktywnaKarta == 4 then
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        term.write("[4]TAB")
    else
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.lightGray)
        term.write("4:Tab")
    end

    term.setBackgroundColor(colors.black)
end

-- Modalna edycja wiersza tablicy
local function edytujWierszModal(serverId)
    term.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    print("====== EDYCJA WIERSZA ======")
    term.setBackgroundColor(colors.black)

    print("\nNumer wiersza (np. 1, 2...):")
    term.setTextColor(colors.yellow)
    write("> ")
    term.setTextColor(colors.white)
    local liniaStr = read()
    local nr = tonumber(liniaStr)

    if not nr or nr < 1 then
        term.setTextColor(colors.red)
        print("\n[!] Nieprawidlowy numer wiersza!")
        sleep(1)
        return
    end

    print("\nTekst do wyslania:")
    term.setTextColor(colors.yellow)
    write("> ")
    term.setTextColor(colors.white)
    local tekst = read()

    dodajWpis(string.format("Wyslano L%d: %s", nr, tekst), colors.yellow)
    rednet.broadcast({ typ = "USTAW_TEKST_TABLICY", linia = nr, tekst = tekst }, PROTOKOL)
    if serverId then
        rednet.send(serverId, { typ = "USTAW_TEKST_TABLICY", linia = nr, tekst = tekst }, PROTOKOL)
    end

    term.setTextColor(colors.green)
    print("\n[OK] Wyslano tekst do tablicy!")
    sleep(1.2)
end

-- Rysowanie zawartości ekranu
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
            local online = (teraz - dane.lastSeen) <= TIMEOUT_SEK
            
            if online then
                term.setTextColor(colors.green)
                local statusDisplay = dane.status or "OK"
                print(string.format("#%-3d %-12s %s", id, (dane.nazwa or ""):sub(1,12), statusDisplay:sub(1,7)))
            else
                term.setTextColor(colors.red)
                print(string.format("#%-3d %-12s OFFLINE", id, (dane.nazwa or ""):sub(1,12)))
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
        print(string.format("%-5s %-10s %s", "CZAS", "PUNKT", "SKLAD"))
        print(string.rep("-", 26))

        if #bazaPrzejazdow == 0 then
            term.setTextColor(colors.gray)
            print("\n Brak historii przejazdow.")
            print(" [R] Pobierz z serwera")
        else
            local startIdx = math.max(1, #bazaPrzejazdow - 12)
            for i = #bazaPrzejazdow, startIdx, -1 do
                local r = bazaPrzejazdow[i]
                local czasStr = (r.czas_gry or (r.timestamp and r.timestamp:sub(12,16)) or "--:--"):sub(1,5)
                local punktStr = (r.posterunek or "Trasa"):sub(1, 9)
                local pociagStr = (r.nazwa_pociagu or r.train_model or "Pociag"):sub(1, 10)

                term.setTextColor(colors.cyan)
                io.write(string.format("%-5s ", czasStr))
                term.setTextColor(colors.white)
                io.write(string.format("%-9s ", punktStr))
                term.setTextColor(colors.orange)
                print(pociagStr)
            end
        end

    -- ================= KARTA 4: TESTOWANIE TABLICY =========
    elseif aktywnaKarta == 4 then
        term.setTextColor(colors.yellow)
        print(" --- STEROWANIE TABLICA ---")
        term.setTextColor(colors.white)
        print(" [S] Skanuj tablice w sieci")
        print(" [E] Edycja wiersza tablicy")
        print(" [T] Wykonaj test wzorca")
        print(" [C] Wyczysc cala tablice")
        print(" [R] Przywroc tryb ODJAZDY")
        print(string.rep("-", 26))

        term.setTextColor(colors.cyan)
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
    end

    -- Okno dialogowe potwierdzenia Rebootu
    if trybRebootConfirm then
        term.setCursorPos(1, 8)
        term.setBackgroundColor(colors.red)
        term.setTextColor(colors.white)
        print("==========================")
        print("  RESTART CALOSCI SIECI   ")
        print("  SERWER + WSZYSTKIE KL   ")
        print("  Potwierdz [T]ak / [N]ie ")
        print("==========================")
        term.setBackgroundColor(colors.black)
    end

    -- Dolny pasek informacyjny
    term.setCursorPos(1, 20)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write("[1/2/3/4] | [X]Reboot | [Q]")
    term.setBackgroundColor(colors.black)
end

-- Inicjalizacja połączenia
odswiezEkran(nil)
local serverId = rednet.lookup(PROTOKOL, SERWER_HOST)
while not serverId do
    sleep(1.5)
    serverId = rednet.lookup(PROTOKOL, SERWER_HOST)
end

dodajWpis("Polaczono z centrala #" .. serverId, colors.green)
rednet.send(serverId, { typ = "POBIERZ_DANE" }, PROTOKOL)
rednet.send(serverId, { typ = "POBIERZ_BAZE" }, PROTOKOL)
rednet.broadcast({ typ = "ZAPYTANIE_TABLICA" }, PROTOKOL)

local timerOdswiezania = os.startTimer(1)

while true do
    local event, p1, p2, p3 = os.pullEvent()

    -- 1. Odbiór danych sieciowych
    if event == "rednet_message" and p3 == PROTOKOL then
        local senderId, msg = p1, p2
        if type(msg) == "table" then
            if msg.typ == "NOWY_LOG" then
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

            elseif msg.typ == "SYNC_KLIENCI" and msg.klienci then
                klienci = msg.klienci
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
                term.clear()
                term.setCursorPos(1, 1)
                print("Zdalny restart komputera...")
                sleep(0.5)
                os.reboot()
            end
        end

    -- 2. Cykliczny timer odświeżania zegara i timeoutów
    elseif event == "timer" and p1 == timerOdswiezania then
        odswiezEkran(serverId)
        timerOdswiezania = os.startTimer(1)

    -- 3. Obsługa klawiatury
    elseif event == "key" then
        if trybRebootConfirm then
            if p1 == keys.t or p1 == keys.y then
                trybRebootConfirm = false
                dodajWpis("Wysylanie REBOOT...", colors.red)
                odswiezEkran(serverId)
                rednet.broadcast({ typ = "REBOOT_ALL" }, PROTOKOL)
                if serverId then
                    rednet.send(serverId, { typ = "REBOOT_ALL" }, PROTOKOL)
                end
                sleep(0.5)
                os.reboot()
            else
                trybRebootConfirm = false
                odswiezEkran(serverId)
            end
        else
            if p1 == keys.one or p1 == keys.numPad1 then
                aktywnaKarta = 1
                odswiezEkran(serverId)
            elseif p1 == keys.two or p1 == keys.numPad2 then
                aktywnaKarta = 2
                odswiezEkran(serverId)
            elseif p1 == keys.three or p1 == keys.numPad3 then
                aktywnaKarta = 3
                if serverId then rednet.send(serverId, { typ = "POBIERZ_BAZE" }, PROTOKOL) end
                odswiezEkran(serverId)
            elseif p1 == keys.four or p1 == keys.numPad4 then
                aktywnaKarta = 4
                rednet.broadcast({ typ = "ZAPYTANIE_TABLICA" }, PROTOKOL)
                if serverId then rednet.send(serverId, { typ = "ZAPYTANIE_TABLICA" }, PROTOKOL) end
                odswiezEkran(serverId)
            elseif p1 == keys.tab then
                aktywnaKarta = (aktywnaKarta % 4) + 1
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

            -- Akcje na Karcie 4 (Tablica)
            elseif aktywnaKarta == 4 then
                if p1 == keys.e then
                    edytujWierszModal(serverId)
                    odswiezEkran(serverId)
                elseif p1 == keys.s then
                    dodajWpis("Skanowanie tablic w sieci...", colors.yellow)
                    rednet.broadcast({ typ = "ZAPYTANIE_TABLICA" }, PROTOKOL)
                    if serverId then rednet.send(serverId, { typ = "ZAPYTANIE_TABLICA" }, PROTOKOL) end
                    odswiezEkran(serverId)
                elseif p1 == keys.t then
                    dodajWpis("Wyslano wzorzec testowy.", colors.cyan)
                    rednet.broadcast({ typ = "TEST_TABLICY" }, PROTOKOL)
                    if serverId then rednet.send(serverId, { typ = "TEST_TABLICY" }, PROTOKOL) end
                    odswiezEkran(serverId)
                elseif p1 == keys.c then
                    dodajWpis("Wyczyszczono tablice.", colors.orange)
                    rednet.broadcast({ typ = "WYCZYSC_TABLICE" }, PROTOKOL)
                    if serverId then rednet.send(serverId, { typ = "WYCZYSC_TABLICE" }, PROTOKOL) end
                    odswiezEkran(serverId)
                elseif p1 == keys.r then
                    dodajWpis("Przywrocono tryb ODJAZDY.", colors.green)
                    rednet.broadcast({ typ = "RESET_TABLICY" }, PROTOKOL)
                    if serverId then rednet.send(serverId, { typ = "RESET_TABLICY" }, PROTOKOL) end
                    odswiezEkran(serverId)
                elseif p1 == keys.x then
                    trybRebootConfirm = true
                    odswiezEkran(serverId)
                elseif p1 == keys.q then
                    term.clear()
                    term.setCursorPos(1, 1)
                    print("Wylaczono mobilny monitor.")
                    break
                end
            elseif p1 == keys.x then
                trybRebootConfirm = true
                odswiezEkran(serverId)
            elseif p1 == keys.q then
                term.clear()
                term.setCursorPos(1, 1)
                print("Wylaczono mobilny monitor.")
                break
            end
        end

    -- 4. Obsługa znaku wpisywanego (dla pewności potwierdzenia T/N)
    elseif event == "char" and trybRebootConfirm then
        local ch = p1:lower()
        if ch == "t" or ch == "y" then
            trybRebootConfirm = false
            dodajWpis("Wysylanie REBOOT...", colors.red)
            odswiezEkran(serverId)
            rednet.broadcast({ typ = "REBOOT_ALL" }, PROTOKOL)
            if serverId then
                rednet.send(serverId, { typ = "REBOOT_ALL" }, PROTOKOL)
            end
            sleep(0.5)
            os.reboot()
        else
            trybRebootConfirm = false
            odswiezEkran(serverId)
        end

    -- 5. Obsługa dotykowa (kliknięcia na Pocket PC)
    elseif event == "mouse_click" then
        if trybRebootConfirm then
            trybRebootConfirm = false
            odswiezEkran(serverId)
        else
            local button, x, y = p1, p2, p3
            if y == 1 then
                if x <= 7 then
                    aktywnaKarta = 1
                elseif x <= 13 then
                    aktywnaKarta = 2
                elseif x <= 19 then
                    aktywnaKarta = 3
                    if serverId then rednet.send(serverId, { typ = "POBIERZ_BAZE" }, PROTOKOL) end
                else
                    aktywnaKarta = 4
                    rednet.broadcast({ typ = "ZAPYTANIE_TABLICA" }, PROTOKOL)
                end
                odswiezEkran(serverId)
            end
        end
    end
end
