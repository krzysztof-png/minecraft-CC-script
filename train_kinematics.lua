-- train_system.lua (Wersja zoptymalizowana i skalibrowana)

-- === KALIBRACJA ODLEGŁOŚCI I CZUJNIKÓW ===
local D1 = 15.0        -- Dystans Sensor A -> Sensor B (w blokach)
local D2 = 15.0        -- Dystans Sensor B -> Sensor C (w blokach)

local SIDE_A = "left"
local SIDE_B = "front"
local SIDE_C = "right"

-- CZAS PODTRZYMANIA IMPULSU:
-- Train Observer trzyma sygnał w Create zazwyczaj przez min. 0.5s (10 ticków) po minięciu.
-- Jeśli długość składu wychodzi zawyżona, zwiększ tę wartość (w sekundach, np. 0.2 - 0.5).
local OBSERVER_LAG = 0.0 

local DB_FILE = "transit_logs.json"

local TRAIN_DATABASE = {
    { name = "Lokomotywa Manewrowa", length = 8.0,  tolerance = 2.5 },
    { name = "Sklad Towarowy (Krotki)", length = 24.0, tolerance = 4.0 },
    { name = "Sklad Towarowy (Dlugi)",  length = 56.0, tolerance = 5.0 },
    { name = "Ekspres Pasazerski",      length = 42.0, tolerance = 4.0 }
}

-- === BAZA DANYCH ===
local function loadDatabase()
    if not fs.exists(DB_FILE) then return {} end
    local file = fs.open(DB_FILE, "r")
    local content = file.readAll()
    file.close()
    return textutils.unserializeJSON(content) or {}
end

local function saveTransitRecord(record)
    local db = loadDatabase()
    table.insert(db, record)
    local file = fs.open(DB_FILE, "w")
    file.write(textutils.serializeJSON(db))
    file.close()
end

-- === ZMIENNE STANU ===
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
    t_A_front, t_A_rear, t_B_front, t_C_front = nil, nil, nil, nil
end

local function computeResults(dir)
    local dt1, dt2, dist1, dist2

    if dir == "A_TO_C" then
        dt1 = t_B_front - t_A_front
        dt2 = t_C_front - t_B_front
        dist1, dist2 = D1, D2
    else
        dt1 = t_B_front - t_C_front
        dt2 = t_A_front - t_B_front
        dist1, dist2 = D2, D1
    end

    -- Odrzucenie anomalii (np. podwójne wyzwolenie w tym samym ticku)
    if dt1 < 0.05 or dt2 < 0.05 then 
        resetMeasurement()
        return 
    end

    local v1 = dist1 / dt1 -- prędkość na 1. odcinku (bloki/s)
    local v2 = dist2 / dt2 -- prędkość na 2. odcinku (bloki/s)
    
    -- Wyliczenie średniego przyspieszenia
    local time_between_sections = (dt1 + dt2) / 2.0
    local accel = (v2 - v1) / time_between_sections

    -- Czas fizycznej obecności pociągu nad czujnikiem A
    local dt_occupancy = 0
    if dir == "A_TO_C" and t_A_rear then
        dt_occupancy = (t_A_rear - t_A_front) - OBSERVER_LAG
    end

    if dt_occupancy < 0 then dt_occupancy = 0 end

    -- Obliczenie długości z korekcją przyspieszenia
    local length = (v1 * dt_occupancy) + (0.5 * accel * (dt_occupancy ^ 2))
    
    -- Fallback: jeśli wynik wyszedł ujemny lub absurdalny przez błąd zbocza
    if length <= 0 then
        length = v1 * dt_occupancy
    end

    local identifiedTrain = identify(length)

    local record = {
        id = os.epoch("utc"),
        timestamp = os.date("!%Y-%m-%d %H:%M:%S"),
        direction = (dir == "A_TO_C" and "A -> C" or "C -> A"),
        v_initial_kmh = math.floor(v1 * 3.6 * 10) / 10,
        v_final_kmh = math.floor(v2 * 3.6 * 10) / 10,
        accel_mps2 = math.floor(accel * 100) / 100,
        length_blocks = math.floor(length * 10) / 10,
        train_model = identifiedTrain
    }

    saveTransitRecord(record)

    print("========================================")
    print("ZAPISANO PRZEJAZD: " .. record.timestamp)
    print(string.format("Kierunek: %s | Sklad: %s", record.direction, record.train_model))
    print(string.format("V1: %.1f km/h -> V2: %.1f km/h (a: %+.2f m/s2)", record.v_initial_kmh, record.v_final_kmh, record.accel_mps2))
    print(string.format("Czas nad A: %.2f s | Dlugosc: %.1f m", dt_occupancy, record.length_blocks))
    print("========================================\n")

    resetMeasurement()
end

term.clear()
term.setCursorPos(1, 1)
print("=== SKALIBROWANY SYSTEM DETEKCJI PRZEJAZDOW ===")
print("Dystanse: D1=" .. D1 .. "m, D2=" .. D2 .. "m")
print("Oczekiwanie na sklady...\n")

while true do
    os.pullEvent("redstone")
    
    local in_A = redstone.getInput(SIDE_A)
    local in_B = redstone.getInput(SIDE_B)
    local in_C = redstone.getInput(SIDE_C)
    local now = os.epoch("utc") / 1000.0

    -- Detekcja zboczy na A
    if in_A and not last_A then
        t_A_front = now
    elseif not in_A and last_A and t_A_front then
        t_A_rear = now
    end

    -- Detekcja zbocza na B
    if in_B and not last_B then
        t_B_front = now
    end

    -- Detekcja zbocza na C
    if in_C and not last_C then
        t_C_front = now
    end

    -- Wyliczenie po zebraniu kompletu punktów
    if t_A_front and t_B_front and t_C_front and t_A_rear then
        computeResults("A_TO_C")
    end

    -- Reset w przypadku utknięcia/anulowania przejazdu
    if t_A_front and (now - t_A_front > 20.0) and not t_C_front then
        resetMeasurement()
    end

    last_A, last_B, last_C = in_A, in_B, in_C
end
