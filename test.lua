-- debug_observers.lua
local s_left = peripheral.wrap("Create_TrainObserver_1")
local s_right = peripheral.wrap("Create_TrainObserver_0")

print("--- METODY DLA OBSERVER_1 (Lewy) ---")
if s_left then
    for _, m in ipairs(peripheral.getMethods("Create_TrainObserver_1")) do
        print(" > " .. m)
    end
else
    print("BLAD: Nie znaleziono Create_TrainObserver_1")
end

print("\n--- METODY DLA OBSERVER_0 (Prawy) ---")
if s_right then
    for _, m in ipairs(peripheral.getMethods("Create_TrainObserver_0")) do
        print(" > " .. m)
    end
else
    print("BLAD: Nie znaleziono Create_TrainObserver_0")
end

print("\nNacisnij dowolny klawisz, aby rozpoczac monitorowanie na zywo...")
os.pullEvent("key")

while true do
    term.clear()
    term.setCursorPos(1, 1)
    
    -- Odczyt wszystkich możliwych wariantów
    local left_val = "brak danych"
    if s_left then
        if s_left.isPowered then left_val = tostring(s_left.isPowered())
        elseif s_left.getState then left_val = tostring(s_left.getState())
        elseif s_left.getSignal then left_val = tostring(s_left.getSignal())
        end
    end

    local mid_val = tostring(redstone.getInput("back"))

    local right_val = "brak danych"
    if s_right then
        if s_right.isPowered then right_val = tostring(s_right.isPowered())
        elseif s_right.getState then right_val = tostring(s_right.getState())
        elseif s_right.getSignal then right_val = tostring(s_right.getSignal())
        end
    end

    print("=== PODGLAD STANOW NA ZYWO ===")
    print("Lewy  (Observer_1): " .. left_val)
    print("Srodek (back)     : " .. mid_val)
    print("Prawy (Observer_0): " .. right_val)
    print("\nPrzejedz pociagiem, aby sprawdzic czy stany zmieniaja sie na true.")
    
    sleep(0.05) -- 1 tick
end
