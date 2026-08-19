--------------------------------------------------------------------------------
--                MOBILNY TERMINAL LOGOW (POCKET COMPUTER)                    --
--------------------------------------------------------------------------------
local PROTOKOL    = "kolej_net"
local SERWER_HOST = "centrala_glowna"
local MAX_LOGOW   = 16 -- Liczba wierszy mieszczących się na ekranie pocket

local modem = peripheral.find("modem")
if not modem then
    error("Brak modemu! Wytworz Pocket Computer z modemem.")
end
rednet.open(peripheral.getName(modem))

local logi = {}

local function dodajWpis(tekst, kolor)
    table.insert(logi, 1, { tekst = tekst, kolor = kolor or colors.white })
    if #logi > MAX_LOGOW then
        table.remove(logi)
    end
end

local function odswiezEkran(statusSerwera)
    term.clear()
    term.setCursorPos(1, 1)
    
    -- Nagłówek
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.yellow)
    term.clearLine()
    term.write(" TERMINAL: LOGI LIVE")
    
    term.setBackgroundColor(colors.black)
    term.setCursorPos(1, 2)
    term.setTextColor(colors.lightGray)
    print("Serwer: " .. (statusSerwera or "Szukanie..."))
    print(string.rep("-", 26))

    -- Wyświetlanie logów od najnowszego (od góry do dołu)
    for i = 1, #logi do
        local wpis = logi[i]
        term.setTextColor(wpis.kolor)
        -- Automatyczne obcinanie tekstu do szerokości ekranu Pocket (26 znaków)
        print(wpis.tekst:sub(1, 26))
    end

    -- Pasek dolny
    term.setCursorPos(1, 20)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write("[C] Clear | [Q] Wyjscie")
    term.setBackgroundColor(colors.black)
end

-- Łączenie z serwerem
odswiezEkran("Laczenie...")
local serverId = rednet.lookup(PROTOKOL, SERWER_HOST)
while not serverId do
    sleep(1.5)
    serverId = rednet.lookup(PROTOKOL, SERWER_HOST)
end

dodajWpis("Polaczono z serwerem #" .. serverId, colors.green)
odswiezEkran("ONLINE (#" .. serverId .. ")")

-- Pobranie historii zdarzeń z serwera
rednet.send(serverId, { typ = "POBIERZ_LOGI" }, PROTOKOL)

while true do
    local event, p1, p2, p3 = os.pullEvent()

    -- 1. Odbiór logów przez Rednet
    if event == "rednet_message" and p3 == PROTOKOL then
        local senderId, msg = p1, p2
        if type(msg) == "table" then
            if msg.typ == "NOWY_LOG" then
                local kolor = colors.white
                if msg.kategoria == "PRZEJAZD" then kolor = colors.lightBlue end
                if msg.kategoria == "ALARM"    then kolor = colors.red end
                if msg.kategoria == "SYSTEM"   then kolor = colors.yellow end

                dodajWpis(msg.tekst, kolor)
                odswiezEkran("ONLINE (#" .. serverId .. ")")

            elseif msg.typ == "HISTORIA_LOGOW" and type(msg.logi) == "table" then
                for i = #msg.logi, 1, -1 do
                    dodajWpis(msg.logi[i], colors.lightGray)
                end
                odswiezEkran("ONLINE (#" .. serverId .. ")")
            end
        end

    -- 2. Obsługa klawiatury Pocket PC
    elseif event == "key" then
        if p1 == keys.c then
            logi = {}
            dodajWpis("Wyczyszczono ekran.", colors.orange)
            odswiezEkran("ONLINE (#" .. serverId .. ")")
        elseif p1 == keys.q then
            term.clear()
            term.setCursorPos(1, 1)
            print("Wylaczono terminal.")
            break
        end
    end
end
