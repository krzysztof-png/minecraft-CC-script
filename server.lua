-- Automatyczne wykrywanie i otwieranie modemu
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
rednet.host("siec_kolejowa", "Główny Serwer")

term.clear()
term.setCursorPos(1, 1)
print("=== SERWER AKTYWNY ===")
print("Nasluchiwanie na porcie rednet...")

local klienci = {}

while true do
    local senderId, msg, protocol = rednet.receive("siec_kolejowa")
    
    if type(msg) == "table" then
        local typ = msg.typ
        local dane = msg.dane or ""
        
        -- Rejestracja / Aktualizacja statusu klienta
        klienci[senderId] = {
            nazwa = msg.nazwa or ("Klient #" .. senderId),
            ostatni_kontakt = os.time(),
            status = dane
        }
        
        print(string.format("[%s] ID %d: %s -> %s", os.date("%T"), senderId, typ, tostring(dane)))
        
        -- Obsługa zapytań
        if typ == "PING" then
            rednet.send(senderId, { status = "OK", odp = "PONG" }, "siec_kolejowa")
            
        elseif typ == "ZAPYTANIE" then
            rednet.send(senderId, { status = "OK", odp = "Dane odebrane poprawnie" }, "siec_kolejowa")
            
        elseif typ == "ROZKAZ" then
            -- Przykład: przekazanie komendy dalej / przetworzenie
            rednet.send(senderId, { status = "OK", odp = "Rozkaz wykonany" }, "siec_kolejowa")
        end
    end
end
