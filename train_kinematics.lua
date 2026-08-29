-- train_kinematics.lua
-- 3-Sensor Speed & Length Kinematics System:
-- Left:   Create_TrainObserver_1 (Wired network)
-- Middle: "back" (Direct redstone behind computer)
-- Right:  Create_TrainObserver_0 (Wired network)

-- === TRACK SEGMENT DISTANCES ===
local D1 = 36.0  -- Distance: Left <-> Middle (in blocks)
local D2 = 31.0  -- Distance: Middle <-> Right (in blocks)

local SENSOR_LEFT_NAME  = "Create_TrainObserver_1"
local SENSOR_RIGHT_NAME = "Create_TrainObserver_0"
local SIDE_MID          = "back"

-- Train Observer pulse lag correction (0.0s to 0.3s depending on ticks)
local OBSERVER_LAG = 0.0

local DB_FILE = "transit_logs.json"

-- Known Trains Database: { name, nominal_length, tolerance }
local TRAIN_DATABASE = {
    { name = "Shunting Locomotive",    length = 8.0,  tolerance = 2.5 },
    { name = "Freight Train (Short)", length = 24.0, tolerance = 3.5 },
    { name = "Freight Train (Long)",  length = 56.0, tolerance = 5.0 },
    { name = "Passenger Express",     length = 42.0, tolerance = 4.0 }
}

-- === PERIPHERAL INITIALIZATION ===
local sensorLeft  = peripheral.wrap(SENSOR_LEFT_NAME)
local sensorRight = peripheral.wrap(SENSOR_RIGHT_NAME)

if not sensorLeft then
    error("Error: Missing network peripheral: " .. SENSOR_LEFT_NAME)
end
if not sensorRight then
    error("Error: Missing network peripheral: " .. SENSOR_RIGHT_NAME)
end

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

-- === DATABASE ===
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
    return "Unrecognized Model"
end

-- === TIMING VARIABLES ===
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

    v1 = dist1 / dt1
    v2 = dist2 / dt2
    
    local dt_mid_span = (dt1 + dt2) / 2.0
    local accel = (v2 - v1) / dt_mid_span
    local v_avg = (v1 + v2) / 2.0

    if dt_occupancy < 0 then dt_occupancy = 0 end

    local length = (v1 * dt_occupancy) + (0.5 * accel * (dt_occupancy ^ 2))
    if length <= 0 then length = v_avg * dt_occupancy end

    local model = identify(length)
    local record = {
        id = os.epoch("utc"),
        timestamp = os.date("!%Y-%m-%d %H:%M:%S"),
        direction = (direction == "LEWY_DO_PRAWY" and "Left -> Right" or "Right -> Left"),
        v_entry_kmh = math.floor(v1 * 3.6 * 10) / 10,
        v_exit_kmh  = math.floor(v2 * 3.6 * 10) / 10,
        accel_mps2  = math.floor(accel * 100) / 100,
        length_m    = math.floor(length * 10) / 10,
        train_model = model
    }

    saveTransitRecord(record)

    print("========================================")
    print("SAVED PASSAGE: " .. record.timestamp)
    print(string.format("Direction: %s | Model: %s", record.direction, record.train_model))
    print(string.format("V1: %.1f km/h -> V2: %.1f km/h (a: %+.2f m/s2)", record.v_entry_kmh, record.v_exit_kmh, record.accel_mps2))
    print(string.format("Calculated Length: %.1f m", record.length_m))
    print("========================================\n")

    resetTimers()
end

term.clear()
term.setCursorPos(1, 1)
print("=== TRAIN MEASUREMENT SERVER (3 SENSORS) ===")
print("Left:   " .. SENSOR_LEFT_NAME)
print("Middle: side '" .. SIDE_MID .. "'")
print("Right:  " .. SENSOR_RIGHT_NAME)
print(string.format("Distances: D1=%.1fm, D2=%.1fm", D1, D2))
print("Waiting for trains...\n")

while true do
    os.pullEvent()

    local cur_left  = getLeft()
    local cur_mid   = getMid()
    local cur_right = getRight()
    local now       = os.epoch("utc") / 1000.0

    if cur_left and not last_left then
        t_left_front = now
        print(string.format("[%s] Front at Left Sensor", os.date("%T")))
    elseif not cur_left and last_left and t_left_front then
        t_left_rear = now
    end

    if cur_mid and not last_mid then
        t_mid_front = now
        print(string.format("[%s] Front at Middle Sensor", os.date("%T")))
    elseif not cur_mid and last_mid and t_mid_front then
        t_mid_rear = now
    end

    if cur_right and not last_right then
        t_right_front = now
        print(string.format("[%s] Front at Right Sensor", os.date("%T")))
    elseif not cur_right and last_right and t_right_front then
        t_right_rear = now
    end

    if t_left_front and t_mid_front and t_right_front and t_left_rear then
        if t_left_front < t_mid_front and t_mid_front < t_right_front then
            computeResults("LEWY_DO_PRAWY")
        end
    end

    if t_right_front and t_mid_front and t_left_front and t_right_rear then
        if t_right_front < t_mid_front and t_mid_front < t_left_front then
            computeResults("PRAWY_DO_LEWY")
        end
    end

    local start_time = t_left_front or t_right_front
    if start_time and (now - start_time > 25.0) and not (t_left_front and t_right_front) then
        print("[RESET] Passage timeout exceeded.")
        resetTimers()
    end

    last_left  = cur_left
    last_mid   = cur_mid
    last_right = cur_right
end
