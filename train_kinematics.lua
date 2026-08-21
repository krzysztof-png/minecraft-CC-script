-- train_kinematics_3s.lua
-- Precyzyjny pomiar predkosci, przyspieszenia i dlugosci (3 sensory)

-- === KONFIGURACJA ODCINKOW I BOKOW ===
local D1 = 15.0        -- Dystans A -> B (w blokach)
local D2 = 15.0        -- Dystans B -> C (w blokach)

local SIDE_A = "left"  -- Pierwszy sensor
local SIDE_B = "front" -- Srodkowy sensor
local SIDE_C = "right" -- Trzeci sensor

-- Baza znanych pociagow: { nazwa, oczekiwana_dlugosc, tolerancja }
local TRAIN_DATABASE = {
    { name = "Lokomotywa Manewrowa", length = 8.0,  tolerance = 2.0 },
    { name = "Sklad Towarowy (Krotki)", length = 24.0, tolerance = 3.5 },
    { name = "Sklad Towarowy (Dlugi)",  length = 56.0, tolerance = 4.0 },
    { name = "Ekspres Pasazerski",      length = 42.0, tolerance = 3.0 }
}

-- === ZMIENNE CZASOWE (TIMINGI) ===
local t_A_front, t_A_rear
local t_B_front
local t_C_front

local last_A = redstone.getInput(SIDE_A)
local last_B = redstone.getInput(SIDE_B)
local last_C = redstone.getInput(SIDE_C)

local function identify(len)
    for _, train in ipairs(TRAIN_DATABASE) do
        if math.abs(len - train.length) <= train.tolerance then
            return train.name
        end
    end
    return "Nierozpoznany model"
end

local function resetMeasurement()
    t_A_front = nil
    t_A_rear = nil
    t_B_front = nil
    t_C_front = nil
end

local function computeResults(dir)
    local dt1, dt2, v1, v2, dist1, dist2

    if dir == "A_TO_C" then
        dt1 = t_B_front - t_A_front
        dt2 = t_C_front - t_B_front
        dist1, dist2 = D1, D2
    else
        -- Kierunek odwrotny C -> B -> A
        dt1 = t_B_front - t_C_front
        dt2 = t_A_front - t_B_front
        dist1, dist2 = D2, D1
    end

    if dt1 <= 0.02 or dt2 <= 0.02 then return end

    v1 = dist1 / dt1 -- b/s na 1. odcinku
    v2 = dist2 / dt2 -- b/s na 2. odcinku

    -- Przyspieszenie a = dv / dt (b/s^2)
    local accel = (v2 - v1) / dt2
    local v_avg = (v1 + v2) / 2.0

    -- Obliczenie dlugosci
    local dt_occupancy = 0
    if dir == "A_TO_C" and t_A_rear then
        dt_occupancy = t_A_rear - t_A_front
    elseif dir == "C_TO_A" and t_A_rear then
        dt_occupancy = t_A_rear - t_C_front
    end

    -- Wzor kinematyczny: L = v1 * dt + 0.5 * a * (dt^2)
    local length = (v1 * dt_occupancy) + (0.5 * accel * (dt_occupancy ^ 2))
    if length < 0 then length = v_avg * dt_occupancy end

    print("========================================")
    print("Kierunek:       " .. (dir == "A_TO_C" and "A -> B -> C" or "C -> B -> A"))
    print(string.format("Predkosc pocz.: %.2f b/s (%.1f km/h)", v1, v1 * 3.6))
    print(string.format("Predkosc konc.: %.2f b/s (%.1f km/h)", v2, v2 * 3.6))
    print(string.format("Przyspieszenie: %+.2f b/s^2", accel))
    print(string.format("Wyliczona dl.:  %.1f blokow", length))
    print("Rozpoznano:     " .. identify(length))
    print("========================================\n")

    resetMeasurement()
end

print("System 3 sensorow uruchomiony.")
print(string.format("Konfiguracja: D1=%.1fm, D2=%.1fm | Wejscia: %s, %s, %s", D1, D2, SIDE_A, SIDE_B, SIDE_C))
print("Oczekiwanie na sklad...\n")

while true do
    os.pullEvent("redstone")
    
    local in_A = redstone.getInput(SIDE_A)
    local in_B = redstone.getInput(SIDE_B)
    local in_C = redstone.getInput(SIDE_C)
    local now = os.epoch("utc") / 1000.0

    -- 1. Detekcja czoła i tyłu na A
    if in_A and not last_A then
        t_A_front = now
        print(string.format("[%s] Czolo na Sensorze A", os.date("%T")))
    elseif not in_A and last_A and t_A_front then
        t_A_rear = now
    end

    -- 2. Detekcja czoła na B
    if in_B and not last_B then
        t_B_front = now
        print(string.format("[%s] Czolo na Sensorze B", os.date("%T")))
    end

    -- 3. Detekcja czoła na C
    if in_C and not last_C then
        t_C_front = now
        print(string.format("[%s] Czolo na Sensorze C", os.date("%T")))
    end

    -- Sprawdzenie czy mamy komplet danych dla kierunku A -> B -> C
    if t_A_front and t_B_front and t_C_front and t_A_rear then
        computeResults("A_TO_C")
    end

    -- Timeout resetujacy w razie wycofania pociagu lub zablokowania
    if t_A_front and (now - t_A_front > 30.0) and not t_C_front then
        print("[OSTRZEZENIE] Przekroczono czas oczekiwania na Sensor C. Reset.")
        resetMeasurement()
    end

    last_A = in_A
    last_B = in_B
    last_C = in_C
end
