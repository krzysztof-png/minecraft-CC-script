--------------------------------------------------------------------------------
--                SKRYPT DIAGNOSTYCZNO-TESTOWY (test.lua)                     --
--------------------------------------------------------------------------------

-- 1. Wykrywanie urządzenia
local dev = peripheral.wrap("back")
         or peripheral.find("create:display_link")
         or peripheral.find("create:display_board")

term.clear()
term.setCursorPos(1, 1)
print("=== DIAGNOSTYKA WYSWIETLACZA ===")

if not dev then
    error("Nie znaleziono peryferium na 'back' ani w sieci!")
end

-- 2. Lista dostepnych metod peryferium
print("\nDostepne metody w API:")
local metody = {}
for k, v in pairs(dev) do
    if type(v) == "function" then
        table.insert(metody, k)
    end
end
table.sort(metody)
print(table.concat(metody, ", "))

-- 3. Odczyt wymiarow
if dev.getSize then
    local w, h = dev.getSize()
    print(string.format("\nWymiary: %d znakow x %d linii", w, h))
end

-- 4. Proba czyszczenia
print("\nCzyszczenie bufora...")
if dev.clear then
    pcall(dev.clear)
end

-- 5. Proba zapisu roznymi metodami
print("Zapisywanie tekstu testowego...")

-- Metoda A: setCursorPos + write (standard Display Link / Terminal)
if dev.setCursorPos and dev.write then
    pcall(function()
        dev.setCursorPos(1, 1)
        dev.write("TEST CREATE 1")
        dev.setCursorPos(1, 2)
        dev.write("ODJAZD: 12:00")
    end)
end

-- Metoda B: setLine (standard Display Board)
if dev.setLine then
    pcall(function()
        dev.setLine(1, "TEST CREATE 1")
        dev.setLine(2, "ODJAZD: 12:00")
    end)
end

-- 6. Wymuszenie aktualizacji klap mechanicznych
if dev.update then
    local ok, err = pcall(dev.update)
    if ok then
        print("[OK] Wywolano dev.update()")
    else
        print("[!] Blad update(): " .. tostring(err))
    end
else
    print("[i] Brak metody dev.update() - zapis natychmiastowy")
end

print("\n--------------------------------")
print("Jesli tablica nadal nie reaguje:")
print("1. Sprawdz czy Display Board ma obroty (RPM).")
print("2. Kliknij Display Linkiem PPM na tablice,")
print("   a potem zamontuj go z tylu komputera.")
print("--------------------------------")
