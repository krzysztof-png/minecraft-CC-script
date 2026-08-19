local modem = peripheral.find("modem")
if not modem then
    error("Blad: Nie znaleziono modemu na obudowie!")
end
rednet.open(peripheral.getName(modem))
rednet.host("stacje_kolejowe", "serwer_glowny")

local TIMEOUT = 6 -- Liczba sekund do uznania stacji za rozłączoną
local stacje = {}

local function odswiezEkran()
    term.clear()
    term.setCursorPos(1, 1)
    print("========================================")
    print("      CENTRALA: POLACZONE STACJE        ")
    print("========================================")
    print(string.format("%-5s | %-16s | %-8s", "ID", "NAZWA STACJI", "STATUS"))
    print("----------------------------------------")

    local teraz = os.clock()
    local aktywne = 0

    for id, dane in pairs(stacje) do
        if (teraz - dane.lastPing) <= TIMEOUT then
            aktywne = aktywne + 1
            print(string.format("#%-4d | %-16s | ONLINE (%s)", id, dane.nazwa, dane.ostatniaGodzina))
        end
    end

    if aktywne == 0 then
        print("  Brak aktywnych stacji w zasiegu...")
    end

    print("----------------------------------------")
    print("Lacznie polaczonych: " .. aktywne)
    print("Czas serwera: " .. textutils.formatTime(os.time(), true))
end

local timerId = os.startTimer(1)
odswiezEkran()

while true do
    local event, p1, p2, p3 = os.pullEvent()

    if event == "rednet_message" then
        local senderId, msg, protocol = p1, p2, p3
        if protocol == "stacje_kolejowe" and type(msg) == "table" and msg.typ == "PING" then
            stacje[senderId] = {
                nazwa = msg.nazwa or ("Stacja_" .. senderId),
                lastPing = os.clock(),
                ostatniaGodzina = textutils.formatTime(os.time(), true)
            }
            rednet.send(senderId, { status = "PONG", czas = os.time() }, "stacje_kolejowe")
            odswiezEkran()
        end

    elseif event == "timer" and p1 == timerId then
        odswiezEkran()
        timerId = os.startTimer(1)
    end
end
