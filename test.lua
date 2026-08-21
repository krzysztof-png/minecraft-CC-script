-- probe_observer.lua
-- Skrypt inspekcyjny do zbadania peryferium Create_TrainObserver

local name = "Create_TrainObserver_0"
local dev = peripheral.wrap(name)

term.clear()
term.setCursorPos(1, 1)

if not dev then
    print("BLAD: Nie wykryto peryferium " .. name)
    print("Dostepne peryferia w sieci:")
    for _, p in ipairs(peripheral.getNames()) do
        print(" - " .. p)
    end
    return
end

print("=== INSPEKCJA: " .. name .. " ===")
print("Typ: " .. peripheral.getType(name))
print("\n--- WSZYSTKIE METODY ---")
local methods = peripheral.getMethods(name)
if #methods == 0 then
    print("[BRAK METOD]")
else
    for i, m in ipairs(methods) do
        local ok, res = pcall(dev[m])
        if ok then
            print(string.format(" %2d. %s() -> %s", i, m, tostring(res)))
        else
            print(string.format(" %2d. %s() [Wymaga argumentow / blad]", i, m))
        end
    end
end

print("\n-------------------------------------------")
print("NASLUCHIWANIE EVENTOW (Przejedz pociagiem!)")
print("Wcisnij Ctrl+T aby przerwac...")
print("-------------------------------------------")

while true do
    local ev = { os.pullEvent() }
    local evName = ev[1]

    -- Filtrujemy tylko zdarzenia klawiatury
    if evName ~= "key" and evName ~= "key_up" and evName ~= "char" then
        print(string.format("[%s] Event: %s", os.date("%T"), evName))
        for i = 2, #ev end do
            print(string.format("   param[%d] = %s", i - 1, tostring(ev[i])))
        end
    end
end
