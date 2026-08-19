local NAZWA_STACJI = "Stacja_Polnocna" -- Zmień nazwę dla każdego komputera

local modem = peripheral.find("modem")
if not modem then
    error("Blad: Nie znaleziono modemu!")
end
rednet.open(peripheral.getName(modem))

term.clear()
term.setCursorPos(1, 1)
print("Laczenie ze stacja glowna...")

local serverId = rednet.lookup("stacje_kolejowe", "serwer_glowny")
while not serverId do
    sleep(1)
    serverId = rednet.lookup("stacje_kolejowe", "serwer_glowny")
end

print("Polaczono z serwerem ID: " .. serverId)

while true do
    rednet.send(serverId, { typ = "PING", nazwa = NAZWA_STACJI }, "stacje_kolejowe")
    local id, odp = rednet.receive("stacje_kolejowe", 2)
    
    term.setCursorPos(1, 4)
    if odp and odp.status == "PONG" then
        print("Status: POLACZONO | Czas gry: " .. textutils.formatTime(odp.czas, true) .. "   ")
    else
        print("Status: BRAK SYGNALU SERWERA...              ")
    end
    
    sleep(2)
end
