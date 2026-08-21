-- train_system_3s.lua
-- System pomiarowy 3 czujnikow:
-- Lewy:   Create_TrainObserver_1 (siec kablowa)
-- Srodek: "back" (bezposrednio z tylu komputera)
-- Prawy:  Create_TrainObserver_0 (siec kablowa)

-- === KONFIGURACJA ODCINKOW I NAZW ===
local D1 = 36.0  -- Odleglosc: Lewy <-> Srodek (w blokach)
local D2 = 31.0  -- Odleglosc: Srodek <-> Prawy (w blokach)

local SENSOR_LEFT_NAME  = "Create_TrainObserver_1"
local SENSOR_RIGHT_NAME = "Create_TrainObserver_0"
local SIDE_MID          = "back"

-- Korekta czasu impulsu Train Observera (zwykle 0.0s do 0.3s w zaleznosci od tickow)
local OBSERVER_LAG = 0.0

local DB_FILE = "transit_logs.json"

-- Baza znanych pociagow: { nazwa, dlugosc_nominalna, tolerancja }
local TRAIN_DATABASE = {
    { name = "Lokomotywa Manewrowa",   length = 8.0,  tolerance = 2.5 },
    { name = "Sklad Towarowy (Krotki)", length = 24.0, tolerance = 3.5 },
    { name = "Sklad Towarowy (Dlugi)",  length = 56.0, tolerance = 5.0 },
    { name = "Ekspres Pasazerski",      length = 42.0, tolerance = 4.0 }
}

-- === INICJALIZACJA PERYFERIOW ===
local sensorLeft  = peripheral.wrap(SENSOR_LEFT_NAME)
local sensorRight = peripheral.wrap(SENSOR_RIGHT_NAME)

if not sensorLeft then
    error("Blad: Brak w sieci peryferium: " .. SENSOR_LEFT_NAME)
end
if not sensorRight then
    error("Blad: Brak w sieci peryferium: " .. SENSOR_RIGHT_NAME)
end

-- Uniwersalny odczyt stanu peryferium (wspiera rozne wersje CC/Create)
local function readObserver(device)
    if not device then return false end
    if device.isPowered then return device.isPowered() end
    if device.getOutput then return device.getOutput() end
    if device.getInput then
        return device.getInput("front") or device.getInput("top") or device.getInput("bottom") or device.getInput("back")
    end
    return false
end

local function getLeft()  return readObserver(sensorLeft) end
local function getMid()   return redstone.getInput(SIDE_MID) end
local function getRight() return readObserver(sensorRight) end

-- === BAZA DANYCH ===
local function loadDatabase()
    if not fs.exists(DB_FILE) then return {} end
    local f = fs.open(DB_FILE, "r")
    local raw = f.readAll()
    f.close()
    return textutils.unserializeJSON(raw) or {}
end

local function saveTransitRecord(record)
    local db = loadDatabase()
    table.insert(db, record)
    local f = fs.open(DB_FILE, "w")
    f.write(textutils.serializeJSON(db))
    f.close()
end

local function identify(len)
    for _, train in ipairs(TRAIN_DATABASE) do
        if math.abs(len - train.length) <= train.tolerance then
            return train.name
        end
    end
    return "Nierozpoznany model"
end

-- === ZMIENNE CZASOWE POMIARU ===
local t_left_front,  t_left_rear  = nil, nil
local t_mid_front,   t_mid_rear   = nil, nil
local t_right_front, t_right_rear = nil, nil

local last_left  = getLeft()
local last_mid   = getMid()
local last_right = getRight()

local function resetTimers()
    t_left_front,  t_left_rear  = nil, nil
    t_mid_front,   t_mid_rear   = nil, nil
    t_right_front, t_right_rear = nil, nil
end

local function computeResults(direction)
    local dt1, dt2, dist1, dist2, v1, v2
    local dt_occupancy = 0

    if direction == "LEWY_DO_PRAWY" then
        dt1 = t_mid_front - t_left_front
        dt2 = t_right_front - t_mid_front
        dist1, dist2 = D1, D2
        if t_left_rear then
            dt_occupancy = (t_left_rear - t_left_front) - OBSERVER_LAG
        end
    else -- PRAWY_DO_LEWY
        dt1 = t_mid_front - t_right_front
        dt2 = t_left_front - t_mid_front
        dist1, dist2 = D2, D1
        if t_right_rear then
            dt_occupancy = (t_right_rear - t_right_front) - OBSERVER_LAG
        end
    end

    if dt1 <= 0.03 or dt2 <= 0.03 then
        resetTimers()
        return
    end

    v1 = dist1 / dt1 -- b/s (1. odcinek)
    v2 = dist2 / dt2 -- b/s (2. odcinek)
    
    local dt_mid_span = (dt1 + dt2) / 2.0
    local accel = (v2 - v1) / dt_mid_span
    local v_avg = (v1 + v2) / 2.0

    if dt_occupancy < 0 then dt_occupancy = 0 end

    -- Wzor kinematyczny: s = v0*t + 0.5*a*t^2
    local length = (v1 * dt_occupancy) + (0.5 * accel * (dt_occupancy ^ 2))
    if length <= 0 then length = v_avg * dt_occupancy end

    local model = identify(length)
    local record = {
        id = os.epoch("utc"),
        timestamp = os.date("!%Y-%m-%d %H:%M:%S"),
        direction = (direction == "LEWY_DO_PRAWY" and "Lewy -> Prawy" or "Prawy -> Lewy"),
        v_entry_kmh = math.floor(v1 * 3.6 * 10) / 10,
        v_exit_kmh  = math.floor(v2 * 3.6 * 10) / 10,
        accel_mps2  = math.floor(accel * 100) / 100,
        length_m    = math.floor(length * 10) / 10,
        train_model = model
    }

    saveTransitRecord(record)

    print("========================================")
    print("ZAPISANO PRZEJAZD: " .. record.timestamp)
    print(string.format("Kierunek: %s | Model: %s", record.direction, record.train_model))
    print(string.format("V1: %.1f km/h -> V2: %.1f km/h (a: %+.2f m/s2)", record.v_entry_kmh, record.v_exit_kmh, record.accel_mps2))
    print(string.format("Wyliczona dlugosc: %.1f m", record.length_m))
    print("========================================\n")

    resetTimers()
end

term.clear()
term.setCursorPos(1, 1)
print("=== SERWER POMIAROWY PRZEJAZDOW (3 SENSORY) ===")
print("Lewy:   " .. SENSOR_LEFT_NAME)
print("Srodek: bok '" .. SIDE_MID .. "'")
print("Prawy:  " .. SENSOR_RIGHT_NAME)
print(string.format("Baza pomiarowa: D1=%.1fm, D2=%.1fm", D1, D2))
print("Oczekiwanie na sklady...\n")

while true do
    os.pullEvent() -- Reaguje na redstone, zmiane stanu peryferiow lub zdarzenia modemu

    local cur_left  = getLeft()
    local cur_mid   = getMid()
    local cur_right = getRight()
    local now       = os.epoch("utc") / 1000.0

    -- 1. Zmiany na Lewym Sensorze (Create_TrainObserver_1)
    if cur_left and not last_left then
        t_left_front = now
        print(string.format("[%s] Czolo na Sensorze Lewym", os.date("%T")))
    elseif not cur_left and last_left and t_left_front then
        t_left_rear = now
    end

    -- 2. Zmiany na Srodkowym Sensorze (back)
    if cur_mid and not last_mid then
        t_mid_front = now
        print(string.format("[%s] Czolo na Sensorze Srodkowym", os.date("%T")))
    elseif not cur_mid and last_mid and t_mid_front then
        t_mid_rear = now
    end

    -- 3. Zmiany na Prawym Sensorze (Create_TrainObserver_0)
    if cur_right and not last_right then
        t_right_front = now
        print(string.format("[%s] Czolo na Sensorze Prawym", os.date("%T")))
    elseif not cur_right and last_right and t_right_front then
        t_right_rear = now
    end

    -- 4. Detekcja kierunku i wykonanie obliczen
    -- Kierunek: Lewy -> Srodek -> Prawy
    if t_left_front and t_mid_front and t_right_front and t_left_rear then
        if t_left_front < t_mid_front and t_mid_front < t_right_front then
            computeResults("LEWY_DO_PRAWY")
        end
    end

    -- Kierunek: Prawy -> Srodek -> Lewy
    if t_right_front and t_mid_front and t_left_front and t_right_rear then
        if t_right_front < t_mid_front and t_mid_front < t_left_front then
            computeResults("PRAWY_DO_LEWY")
        end
    end

    -- Timeout resetujacy (gdy pociag stanal w polowie lub zawrocil)
    local start_time = t_left_front or t_right_front
    if start_time and (now - start_time > 25.0) and not (t_left_front and t_right_front) then
        print("[RESET] Przekroczono limit czasu oczekiwania na pelen przejazd.")
        resetTimers()
    end

    last_left  = cur_left
    last_mid   = cur_mid
    last_right = cur_right
end
