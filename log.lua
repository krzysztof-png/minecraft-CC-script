--------------------------------------------------------------------------------
--            MOBILNY MONITOR KOLEJOWY (POCKET PC - MULTI-TAB)               --
--------------------------------------------------------------------------------
local PROTOKOL     = "kolej_net"
local SERWER_HOST  = "centrala_glowna"
local TIMEOUT_SEK  = 6

local modem = peripheral.find("modem")
if not modem then
    error("Brak modemu! Wytworz Pocket Computer z modemem.")
end
rednet.open(peripheral.getName(modem))

local aktywnaKarta = 1 -- 1: Urządzenia, 2: Logi
local klienci = {}
local logi = {}
local MAX_LOGOW = 16

local function dodajWpis(tekst, kolor)
    table.insert(logi, 1, { tekst = tekst, kolor = kolor or colors.white })
    if #logi > MAX_LOGOW then
        table.remove(logi)
    end
end

-- Rysowanie paska zakładek (góra ekranu)
local function rysujPasekKart()
    term.setCursorPos(1, 1)
    
    -- Karta 1: Urządzenia
    if aktywnaKarta == 1 then
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        term.write(" [1] WEZLY ")
    else
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.lightGray)
        term.write("  1: Wezly ")
    end

    -- Karta 2: Logi
    if aktywnaKarta == 2 then
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        term.write(" [2] LOGI ")
    else
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.lightGray)
        term.write("  2: Logi ")
    end

    -- Wypełnienie reszty paska
    term.setBackgroundColor(colors.gray)
    term.write("       ")
    term.setBackgroundColor(colors.black)
end

-- Rysowanie zawartości
local function odswiezEkran(serverId)
    term.clear()
    rysujPasekKart()

    term.setCursorPos(1, 2)
    term.setTextColor(colors.lightGray)
    local statusSerwera = serverId and ("SRV #" .. serverId) or "LACZENIE..."
    print(string.format("Stan: %-9s Czas: %s", statusSerwera, textutils.formatTime(os.time(), true)))
    print(string.rep("-", 26))

    -- ================= KARTA 1: URZĄDZENIA =================
    if aktywnaKarta == 1 then
        term.setTextColor(colors.yellow)
        print(string.format("%-4s %-12s %s", "ID", "NAZWA", "STATUS"))
        term.setTextColor(colors.white)

        local teraz = os.clock()
        local count = 0
        for id, dane in pairs(klienci) do
            count = count + 1
            local online = (teraz - dane.lastSeen) <= TIMEOUT_SEK
            
            if online then
                term.setTextColor(colors.green)
                print(string.format("#%-3d %-12s %s", id, dane.nazwa:sub(1,12), dane.status:sub(1,7)))
            else
                term.setTextColor(colors.red)
                print(string.format("#%-3d %-12s OFFLINE", id, dane.nazwa:sub(1,12)))
            end
        end

        if count == 0 then
            term.setTextColor(colors.gray)
            print("\n Brak zarejestrowanych")
            print(" urzadzen w sieci.")
        end

    -- ================= KARTA 2: DZIENNIK LOGÓW =============
    elseif aktywnaKarta == 2 then
        if #logi == 0 then
            term.setTextColor(colors.gray)
            print("\n Brak logow w pamieci.")
        else
            for i = 1, #logi do
                local wpis = logi[i]
                term.setTextColor(wpis.kolor)
                print(wpis.tekst:sub(1, 26))
            end
        end
    end

    -- Pasek dolny
    term.setCursorPos(1, 20)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write("[1/2] Karta | [Q] Wyjscie")
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
                odswiezEkran(serverId)

            elseif msg.typ == "PELNE_DANE" then
                if msg.klienci then klienci = msg.klienci end
                if msg.logi then
                    logi = {}
                    for _, l in ipairs(msg.logi) do
                        table.insert(logi, { tekst = l, kolor = colors.lightGray })
                    end
                end
                odswiezEkran(serverId)

            elseif msg.typ == "SYNC_KLIENCI" and msg.klienci then
                klienci = msg.klienci
                odswiezEkran(serverId)
            end
        end

    -- 2. Cykliczne odświeżanie zegara i timeoutów urządzeń
    elseif event == "timer" and p1 == timerOdswiezania then
        odswiezEkran(serverId)
        timerOdswiezania = os.startTimer(1)

    -- 3. Sterowanie klawiaturą
    elseif event == "key" then
        if p1 == keys.one or p1 == keys.numPad1 then
            aktywnaKarta = 1
            odswiezEkran(serverId)
        elseif p1 == keys.two or p1 == keys.numPad2 then
            aktywnaKarta = 2
            odswiezEkran(serverId)
        elseif p1 == keys.tab then
            aktywnaKarta = (aktywnaKarta == 1) and 2 or 1
            odswiezEkran(serverId)
        elseif p1 == keys.c and aktywnaKarta == 2 then
            logi = {}
            dodajWpis("Wyczyszczono logi.", colors.orange)
            odswiezEkran(serverId)
        elseif p1 == keys.q then
            term.clear()
            term.setCursorPos(1, 1)
            print("Wylaczono monitor.")
            break
        end

    -- 4. Obsługa dotykowa (kliknięcia na ekranie Pocket PC)
    elseif event == "mouse_click" then
        local button, x, y = p1, p2, p3
        if y == 1 then
            if x <= 12 then
                aktywnaKarta = 1
            else
                aktywnaKarta = 2
            end
            odswiezEkran(serverId)
        end
    end
end
