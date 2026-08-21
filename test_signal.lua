-- test_bridge.lua
-- Skrypt diagnostyczny dla CC:C Bridge

local target = peripheral.find("train_signal") 
    or peripheral.find("train_station") 
    or peripheral.find("target")

if not target then
    print("Nie znaleziono peryferium Create/Bridge!")
    print("Dostepne peryferia w sieci:")
    for _, name in ipairs(peripheral.getNames()) do
        print(" - " .. name .. " (" .. peripheral.getType(name) .. ")")
    end
    return
end

local periName = peripheral.getName(target)
local periType = peripheral.getType(target)

print("Polaczono z: " .. periName .. " [" .. periType .. "]")
print("----------------------------------------")
print("Dostepne metody:")
for _, method in ipairs(peripheral.getMethods(periName)) do
    print(" > " .. method)
end
print("----------------------------------------")

-- Funkcja pomocnicza do odczytu danych w zaleznosci od dostepnych metod CC:C Bridge
local function checkTrain()
    print("\n[Odczyt danych " .. os.date("%T") .. "]")
    
    -- 1. Jezeli obiekt ma metode getTrainName (stacja / target)
    if target.getTrainName then
        local name = target.getTrainName()
        print("getTrainName(): " .. tostring(name))
    end

    -- 2. Jezeli obiekt ma getTrain (obiekt tabeli z danymi pociagu)
    if target.getTrain then
        local trainData = target.getTrain()
        if type(trainData) == "table" then
            print("getTrain(): Dane pociagu:")
            for k, v in pairs(trainData) do
                print("   " .. tostring(k) .. " = " .. tostring(v))
            end
        else
            print("getTrain(): " .. tostring(trainData))
        end
    end

    -- 3. Jezeli obiekt to train_signal (listBlockingTrainNames / getBlockingTrains)
    if target.listBlockingTrainNames then
        local trains = target.listBlockingTrainNames()
        print("listBlockingTrainNames(): Liczba pociagow: " .. #trains)
        for i, tname in ipairs(trains) do
            print("   " .. i .. ". " .. tname)
        end
    end

    if target.getBlockingTrains then
        local trains = target.getBlockingTrains()
        print("getBlockingTrains(): Liczba wpisow: " .. (type(trains) == "table" and #trains or 0))
    end
end

-- Poczatkowy odczyt
checkTrain()

print("\nNasluchiwanie eventow (Ctrl+T aby przerwac)...")
while true do
    local eventData = { os.pullEvent() }
    local eventName = eventData[1]
    
    -- Ignorujemy klikniecia myszka i odswiezanie ekranu
    if eventName ~= "timer" and eventName ~= "mouse_click" and eventName ~= "mouse_up" then
        print("\nOdebrano event: " .. eventName)
        for i = 2, #eventData do
            print("  arg[" .. (i-1) .. "]: " .. tostring(eventData[i]))
        end
        checkTrain()
    end
end
