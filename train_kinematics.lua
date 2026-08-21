-- train_system.lua
-- Glowny system pomiarowy z lokalna baza przejazdow (JSON)

-- === KONFIGURACJA ODCINKOW I BOKOW ===
local D1 = 15.0        -- Dystans A -> B (w blokach)
local D2 = 15.0        -- Dystans B -> C (w blokach)

local SIDE_A = "left"  -- Pierwszy sensor
local SIDE_B = "front" -- Srodkowy sensor
local SIDE_C = "right" -- Trzeci sensor

local DB_FILE = "transit_logs.json"

-- Baza znanych pociagow
local TRAIN_DATABASE = {
    { name = "Lokomotywa Manewrowa", length = 8.0,  tolerance = 2.0 },
    { name = "Sklad Towarowy (Krotki)", length = 24.0, tolerance = 3.5 },
    { name = "Sklad Towarowy (Dlugi)",  length = 56.0, tolerance = 4.0 },
    { name = "Ekspres Pasazerski",      length = 42.0, tolerance = 3.0 }
}

-- === MODUŁ BAZY DANYCH (JSON) ===
local function loadDatabase()
    if not fs.exists(DB_FILE) then
        return {}
    end
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
    local dt1, dt2, v1, v2, dist1, dist2

    if dir == "A_TO_C" then
        dt1 = t_B_front - t_A_front
        dt2 = t_C_front - t_B_front
        dist1, dist2 = D1, D2
    else
        dt1 = t_B_front - t_C_front
        dt2 = t_A_front - t_B_front
        dist1, dist2 = D2, D1
    end

    if dt1 <= 0.02 or dt2 <= 0.02 then return end

    v1 = dist1 / dt1
    v2 = dist2 / dt2
    local accel = (v2 - v1) / dt2
    local v_avg = (v1 + v2) / 2.0

    local dt_occupancy = 0
    if dir == "A_TO_C" and t_A_rear then
        dt_occupancy = t_A_rear - t_A_front
    elseif dir == "C_TO_A" and t_A_rear then
        dt_occupancy = t_A_rear - t_C_front
    end

    local length = (v1 * dt_occupancy) + (0.5 * accel * (dt_occupancy ^ 2))
    if length < 0 then length = v_avg * dt_occupancy end

    local identifiedTrain = identify(length)

    -- Utworzenie wpisu do bazy
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
    print(string.format("V: %.1f -> %.1f km/h | Dlugosc: %.1f m", record.v_initial_kmh, record.v_final_kmh, record.length_blocks))
    print("========================================\n")

    resetMeasurement()
end

term.clear()
term.setCursorPos(1, 1)
print("=== SERWER DETEKCJI PRZEJAZDOW KOLEJOWYCH ===")
print(string.format("Baza danych: %s", DB_FILE))
print("Oczekiwanie na sklady...\n")

while true do
    os.pullEvent("redstone")
    
    local in_A = redstone.getInput(SIDE_A)
    local in_B = redstone.getInput(SIDE_B)
    local in_C = redstone.getInput(SIDE_C)
    local now = os.epoch("utc") / 1000.0

    -- Detekcja A
    if in_A and not last_A then
        t_A_front = now
    elseif not in_A and last_A and t_A_front then
        t_A_rear = now
    end

    -- Detekcja B
    if in_B and not last_B then
        t_B_front = now
    end

    -- Detekcja C
    if in_C and not last_C then
        t_C_front = now
    end

    -- Wyliczenie dla kierunku A -> B -> C
    if t_A_front and t_B_front and t_C_front and t_A_rear then
        computeResults("A_TO_C")
    end

    -- Timeout resetujacy (30s)
    if t_A_front and (now - t_A_front > 30.0) and not t_C_front then
        resetMeasurement()
    end

    last_A, last_B, last_C = in_A, in_B, in_C
end
