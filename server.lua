--------------------------------------------------------------------------------
--                         KONFIGURACJA MONITORA                              --
--------------------------------------------------------------------------------
local STRONA_MONITORA = "right"
local SKALA_TEKSTU    = 0.8 -- CC obsługuje kroki co 0.5 (np. 0.5, 1.0), 0.8 zaokrągli do najbliższej

if peripheral.getType(STRONA_MONITORA) == "monitor" then
    local mon = peripheral.wrap(STRONA_MONITORA)
    pcall(function() mon.setTextScale(SKALA_TEKSTU) end)
    term.redirect(mon)
    term.clear()
    term.setCursorPos(1, 1)
end
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--                         KONFIGURACJA SERWERA                               --
--------------------------------------------------------------------------------
local PROTOKOL     = "kolej_net"
local NAZWA_HOSTA  = "centrala_glowna"
local TIMEOUT_SEK  = 6   -- Czas w sekundach po którym stacja przechodzi w Offline
local MAX_LOGOW    = 6   -- Maksymalna liczba ostatnich zdarzeń na ekranie
--------------------------------------------------------------------------------

local modem = peripheral.find("modem")
if not modem then
    error("Blad: Nie wykryto modemu (Wireless/Ender Modem)!")
end
rednet.open(peripheral.getName(modem))
rednet.host(PROTOKOL, NAZWA_HOSTA)

local klienci = {}
local logiZdarzen = {}

local function dodajLog(tekst)
    local godzina = textutils.formatTime(os.time(), true)
    table.insert(logiZdarzen, 1, string.format("[%s] %s", godzina, tekst))
    if #logiZdarzen > MAX_LOGOW then
        table.remove(logiZdarzen)
    end
end

local function odswiezInterfejs()
    term.clear()
    term.setCursorPos(1, 1)
    print("==================================================")
    print("         CENTRALA KOLEJOWA - MONITOR SYSTEMU      ")
    print("==================================================")
    print(string.format("%-4s | %-14s | %-9s | %-8s", "ID", "NAZWA", "TRYB", "STATUS"))
    print("--------------------------------------------------")

    local teraz = os.clock()
    local onlineCount = 0

    for id, dane in pairs(klienci) do
        local online = (teraz - dane.lastSeen) <= TIMEOUT_SEK
        local statusStr = online and dane.status or "OFFLINE"
        if online then onlineCount = onlineCount + 1 end

        print(string.format("#%-3d | %-14s | %-9s | %-8s", 
            id, 
            dane.nazwa:sub(1, 14), 
            dane.tryb:sub(1, 9), 
            statusStr:sub(1, 8)
        ))
    end

    if next(klienci) == nil then
        print("  Oczekiwanie na polaczenia stacji / klientow...")
    end

    print("--------------------------------------------------")
    print("OSTATNIE ZDARZENIA I PRZEJAZDY:")
    for _, log in ipairs(logiZdarzen) do
        print(" " .. log)
    end
    print("--------------------------------------------------")
    print(string.format("Aktywne wezly: %d | Czas: %s", onlineCount, textutils.formatTime(os.time(), true)))
end

-- Timer odświeżania interfejsu (co 1 sekundę)
local timerOdswiezania = os.startTimer(1)
dodajLog("Serwer glowny uruchomiony.")
odswiezInterfejs()

while true do
    local event, p1, p2, p3 = os.pullEvent()

    -- 1. Obsługa wiadomości Rednet (wielozdarzeniowość)
    if event == "rednet_message" and p3 == PROTOKOL then
        local senderId, msg = p1, p2

        if type(msg) == "table" then
            -- Rejestracja / Aktualizacja stanu węzła
            if msg.typ == "PING" then
                klienci[senderId] = {
                    nazwa    = msg.nazwa or ("Klient_" .. senderId),
                    tryb     = msg.tryb or "BEACON",
                    status   = msg.status or "ONLINE",
                    lastSeen = os.clock()
                }
                rednet.send(senderId, { odp = "PONG_OK" }, PROTOKOL)

            -- Wykrycie przejazdu pociągu przez Train Observer
            elseif msg.typ == "PRZEJAZD_POCIAGU" then
                local punkt = msg.nazwa or ("ID #" .. senderId)
                dodajLog("PRZEJAZD: Pociag minal " .. punkt)
                odswiezInterfejs()

            -- Obsługa zdarzeń awaryjnych / customowych
            elseif msg.typ == "ALARM" then
                dodajLog("ALARM ze stacji " .. (msg.nazwa or senderId) .. ": " .. tostring(msg.powod))
                odswiezInterfejs()
            end
        end

    -- 2. Timer cykliczny UI i sprawdzanie timeoutów
    elseif event == "timer" and p1 == timerOdswiezania then
        odswiezInterfejs()
        timerOdswiezania = os.startTimer(1)

    -- 3. Obsługa klawiatury na serwerze (np. czyszczenie logów)
    elseif event == "key" then
        if p1 == keys.c then
            logiZdarzen = {}
            dodajLog("Wyczyszczono rejestr zdarzen.")
            odswiezInterfejs()
        end
    end
end
