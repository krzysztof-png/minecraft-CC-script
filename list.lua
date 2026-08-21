-- monitor_signals.lua
-- Ciagle sprawdzanie i wyswietlanie listBlockingTrainNames()

-- Znajdz wszystkie peryferia posiadajace metode listBlockingTrainNames
local signals = {}

for _, name in ipairs(peripheral.getNames()) do
    local dev = peripheral.wrap(name)
    if dev and type(dev.listBlockingTrainNames) == "function" then
        table.insert(signals, { name = name, device = dev })
    end
end

if #signals == 0 then
    print("Blad: Nie znaleziono zadnego peryferium z metoda listBlockingTrainNames()!")
    print("Dostepne peryferia w sieci:")
    for _, name in ipairs(peripheral.getNames()) do
        print(" - " .. name .. " (" .. (peripheral.getType(name) or "unknown") .. ")")
    end
    return
end

print("Znaleziono " .. #signals .. " sygnal(y). Rozpoczynam monitorowanie...")
sleep(1)

-- Glowna petla odpytujaca
while true do
    term.clear()
    term.setCursorPos(1, 1)
    
    print("=== PODGLAD BLOKUJACYCH POCIAGOW ===")
    print("Czas: " .. os.date("%T") .. " | [Ctrl+T aby zatrzymac]")
    print(string.rep("-", 45))

    for _, sig in ipairs(signals) do
        print("\nSygnal: " .. sig.name)
        
        local ok, trains = pcall(sig.device.listBlockingTrainNames)
        
        if not ok then
            print("  [BLAD ODCZYTU]: " .. tostring(trains))
        elseif type(trains) == "table" then
            if #trains == 0 then
                print("  Stan: Brak pociagow w sekcji (Tor wolny)")
            else
                print("  Wykryte pociagi (" .. #trains .. "):")
                for i, trainName in ipairs(trains) do
                    print(string.format("   [%d] %s", i, tostring(trainName)))
                end
            end
        else
            print("  Zwrocona wartosc: " .. tostring(trains))
        end
    end

    print("\n" .. string.rep("-", 45))
    sleep(0.1) -- Odswiezanie co 2 ticki gry (100 ms)
end
