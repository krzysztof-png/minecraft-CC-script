-- inspect_back.lua
-- Skrypt inspekcyjny sprawdzajacy wszystkie peryferia podlaczone z tylu (back)

term.clear()
term.setCursorPos(1, 1)

local SIDE = "back"

print("========================================")
print("     INSPEKCJA PERYFERIOW: [" .. SIDE .. "]     ")
print("========================================\n")

-- 1. Sprawdzenie bezposredniego polaczenia
local directType = peripheral.getType(SIDE)

if not directType then
    print("Brak podlaczonego peryferium bezposrednio z tylu.")
    print("Sprawdzam polaczenia w calej sieci...")
else
    print(string.format("Wykryto bezposrednio: [%s] (Typ: %s)", SIDE, directType))
    print("Metody bezposrednie:")
    local methods = peripheral.getMethods(SIDE)
    if methods and #methods > 0 then
        for i, m in ipairs(methods) do
            print(string.format("  [%2d] %s()", i, m))
        end
    else
        print("  (Brak wystawionych metod)")
    end
    print("----------------------------------------")
end

-- 2. Jezeli z tylu jest Wired Modem, przeszukaj cala siec kablowa
if directType == "modem" then
    local modem = peripheral.wrap(SIDE)
    if modem and modem.isColour and modem.getNamesRemote then
        print("\nZ tylu znajduje sie Modem Przewodowy.")
        print("Skanowanie urzadzen w sieci kablowej...\n")
        
        local remoteNames = modem.getNamesRemote()
        
        if #remoteNames == 0 then
            print("Siec jest pusta lub modemy na drugim koncu nie sa aktywne (brak czerwonej ramki).")
        else
            for idx, name in ipairs(remoteNames) do
                local rType = peripheral.getType(name) or "unknown"
                print(string.format("=== [%d] URZADZENIE: %s (%s) ===", idx, name, rType))
                
                local rMethods = peripheral.getMethods(name)
                if rMethods and #rMethods > 0 then
                    for mIdx, method in ipairs(rMethods) do
                        -- Proba bezpiecznego wywolania bezargumentowego
                        local dev = peripheral.wrap(name)
                        local status, res = pcall(function() return dev[method]() end)
                        
                        if status and res ~= nil then
                            print(string.format("   %2d. %-24s -> %s", mIdx, method, tostring(res)))
                        else
                            print(string.format("   %2d. %s()", mIdx, method))
                        end
                    end
                else
                    print("   (Brak metod)")
                end
                print("")
            end
        end
    end
end

-- 3. Podsumowanie wszystkich widocznych peryferiow w CC
print("----------------------------------------")
print("Wszystkie aktualnie widoczne peryferia w systemie:")
local all = peripheral.getNames()
for _, n in ipairs(all) do
    print(string.format(" - %-26s [%s]", n, peripheral.getType(n) or "brak"))
end
