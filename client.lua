local NAZWA_STACJI = "Stacja_01" -- Zmień na np. Stacja_02 na drugim kliencie

-- Wykrywanie modemu
local modemSide = nil
for _, side in ipairs(rs.getSides()) do
    if peripheral.getType(side) == "modem" then
        modemSide = side
        break
    end
end

if not modemSide then
    error("Blad: Nie znaleziono modemu!")
end

rednet.open(modemSide)

term.clear()
term.setCursorPos(1, 1)
print("Szukanie serwera...")

local serverId = rednet.lookup("siec_kolejowa", "Główny Serwer")
while not serverId do
    print("Serwer niedostepny. Ponawiam za 3s...")
    sleep(3)
    serverId = rednet.lookup("siec_kolejowa", "Główny Serwer")
end

print("Polaczono z serwerem ID: " .. serverId)
print("Nacisnij [1] Wyslij Ping | [2] Wyslij Status | [Q] Wyjdz")

while true do
    local event, key = os.pullEvent("key")
    
    if key == keys.one then
        -- Wysyłanie PING
        print("Wysylanie PING...")
        rednet.send(serverId, { typ = "PING", nazwa = NAZWA_STACJI }, "siec_kolejowa")
        local id, resp = rednet.receive("siec_kolejowa", 2)
        if resp then
            print("Odpowiedz: " .. tostring(resp.odp))
        else
            print("Brak odpowiedzi (timeout)")
        end
        
    elseif key == keys.two then
        -- Wysyłanie przykładowych danych/statusu
        print("Wysylanie raportu...")
        rednet.send(serverId, { 
            typ = "ZAPYTANIE", 
            nazwa = NAZWA_STACJI, 
            dane = "Pociag gotowy do odjazdu" 
        }, "siec_kolejowa")
        
        local id, resp = rednet.receive("siec_kolejowa", 2)
        if resp then
            print("Serwer odpowiedzial: " .. tostring(resp.odp))
        end
        
    elseif key == keys.q then
        print("Zamykanie klienta...")
        break
    end
end
