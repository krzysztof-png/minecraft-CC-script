-- train_kinematics.lua
-- Pomiar prędkości i długości pociągu przy użyciu 2 Obserwatorów Create

-- === KONFIGURACJA ===
local DISTANCE = 20.0      -- Dystans między czujnikami A i B w blokach (metrach)
local SIDE_A   = "left"    -- Bok komputera dla Obserwatora A (początkowy)
local SIDE_B   = "right"   -- Bok komputera dla Obserwatora B (końcowy)

-- Baza znanych pociągów: { nazwa, oczekiwana_długość, tolerancja }
local TRAIN_DATABASE = {
    { name = "Lokomotywa Manewrowa", length = 8.0,  tolerance = 2.0 },
    { name = "Skład Towarowy (Krótki)", length = 24.0, tolerance = 3.5 },
    { name = "Skład Towarowy (Długi)",  length = 56.0, tolerance = 4.0 },
    { name = "Ekspres Pasażerski",       length = 42.0, tolerance = 3.0 }
}

-- === ZMIENNE STANU ===
local t_A_front = nil  -- Czas uderzenia czoła w A
local t_A_rear  = nil  -- Czas opuszczenia A przez tył
local t_B_front = nil  -- Czas uderzenia czoła w B

local last_state_A = redstone.getInput(SIDE_A)
local last_state_B = redstone.getInput(SIDE_B)

local function identifyTrain(measured_length)
    for _, train in ipairs(TRAIN_DATABASE) do
        if math.abs(measured_length - train.length) <= train.tolerance then
            return train.name
        end
    end
    return "Nieznany skład (Nierozpoznany model)"
end

print("System pomiarowy uruchomiony.")
print(string.format("Baza pomiarowa: %.1f blokow | Sensor A: %s | Sensor B: %s", DISTANCE, SIDE_A, SIDE_B))
print("Oczekiwanie na pociag...\n")

while true do
    os.pullEvent("redstone")
    
    local state_A = redstone.getInput(SIDE_A)
    local state_B = redstone.getInput(SIDE_B)
    local now = os.epoch("utc") / 1000.0 -- Czas z precyzją milisekundową (w sekundach)

    -- 1. ZBOCZE NARASTAJĄCE NA A (Czoło pociągu wjeżdża na Obserwator A)
    if state_A and not last_state_A then
        t_A_front = now
        t_A_rear = nil
        t_B_front = nil
        print(string.format("[%s] Wykryto czolo skladu na Sensorze A...", os.date("%T")))
    end

    -- 2. ZBOCZE OPADAJĄCE NA A (Tył pociągu opuszcza Obserwator A)
    if not state_A and last_state_A and t_A_front then
        t_A_rear = now
    end

    -- 3. ZBOCZE NARASTAJĄCE NA B (Czoło pociągu dociera do Obserwatora B)
    if state_B and not last_state_B and t_A_front then
        t_B_front = now
        
        -- Czas przejazdu czoła z A do B
        local dt_travel = t_B_front - t_A_front

        if dt_travel > 0.05 then
            -- Obliczenie prędkości (v = d / t)
            local speed = DISTANCE / dt_travel -- w blokach na sekundę (m/s)
            local speed_kmh = speed * 3.6

            -- Jeśli tył składu minął już czujnik A, możemy policzyć długość od razu
            if t_A_rear then
                local dt_occupancy = t_A_rear - t_A_front
                local length = speed * dt_occupancy
                local train_name = identifyTrain(length)

                print("========================================")
                print(string.format("Predkosc:     %.2f b/s (%.1f km/h)", speed, speed_kmh))
                print(string.format("Czas tranzytu: %.2f s", dt_occupancy))
                print(string.format("Dlugosc:      %.1f blokow", length))
                print("Identyfikacja: " .. train_name)
                print("========================================\n")

                -- Reset do kolejnego pomiaru
                t_A_front, t_A_rear, t_B_front = nil, nil, nil
            else
                -- Skład jest bardzo długi (dłuższy niż dystans DISTANCE)
                print(string.format("Predkosc pomierzona: %.1f km/h. Oczekiwanie na koniec skladu na Sensorze A...", speed_kmh))
            end
        end
    end

    -- Obsługa przypadku dla pociągów dłuższych niż odległość między sensorami (t_A_rear następuje po t_B_front)
    if not state_A and last_state_A and t_A_front and t_B_front then
        t_A_rear = now
        local speed = DISTANCE / (t_B_front - t_A_front)
        local dt_occupancy = t_A_rear - t_A_front
        local length = speed * dt_occupancy
        local train_name = identifyTrain(length)

        print("========================================")
        print(string.format("Predkosc:     %.2f b/s (%.1f km/h)", speed, speed * 3.6))
        print(string.format("Dlugosc:      %.1f blokow", length))
        print("Identyfikacja: " .. train_name)
        print("========================================\n")

        t_A_front, t_A_rear, t_B_front = nil, nil, nil
    end

    last_state_A = state_A
    last_state_B = state_B
end
