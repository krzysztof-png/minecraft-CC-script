-- Szukanie wyświetlacza (Display Link / Display Board)
local dev = peripheral.find("create:display_link")
         or peripheral.find("create:display_board")
         or peripheral.wrap("back")

if not dev then
    error("Nie znaleziono wyswietlacza!")
end

local w, h = dev.getSize()

local function pisz(linia, tekst)
    if linia > h then return end
    local formatowany = string.format("%-" .. w .. "s", tekst):sub(1, w)
    
    if dev.setLine then
        dev.setLine(linia, formatowany)
    elseif dev.setCursorPos and dev.write then
        dev.setCursorPos(1, linia)
        dev.write(formatowany)
    end
end

-- Czyszczenie tablicy
if dev.clear then dev.clear() end

-- Wypisanie testowej tablicy odjazdów
local czas = textutils.formatTime(os.time(), true)

pisz(1, "TEST SYSTEMU [" .. czas .. "]")
pisz(2, "1. BAZA GLOWNA   OK")
pisz(3, "2. RAFINERIA   OPUZ")
pisz(4, "3. KOPALNIA      --")

print(string.format("Wyslano test na wyswietlacz (%dx%d)", w, h))
