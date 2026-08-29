-- test_signal.lua / train_detector_v2.lua
-- Advanced Train Detector with Target Block

local target = peripheral.wrap("back") or peripheral.find("create_target")

if not target then
    error("Peripheral 'create_target' not found!")
end

print("=====================================")
print("     TRAIN DETECTOR - v2.0")
print("  Advanced Computer + Target Block")
print("=====================================")

local CONFIG = {
    checkInterval = 0.3,  -- Check interval in seconds
    maxHistory = 20,      -- Max stored trains
    debug = false         -- Debug logging
}

local state = {
    previousTrainData = nil,
    detectedTrains = {},
    lastCheck = os.clock(),
    trainCount = 0
}

local function readTargetBuffer()
    local lines = {}
    
    if target.dump then
        lines = target.dump()
    else
        local line = 1
        while true do
            local content = target.getLine and target.getLine(line) or 
                          target.getText and target.getText(line)
            if not content or content == "" then break end
            table.insert(lines, content)
            line = line + 1
        end
    end
    
    return lines
end

local function parseTrainData(lines)
    if not lines or #lines == 0 then return nil end
    
    local data = {
        raw = lines,
        detected = false,
        name = "Unknown",
        speed = 0,
        carriages = 0,
        status = "N/A"
    }
    
    local fullText = table.concat(lines, " "):lower()
    
    if fullText:find("train") or fullText:find("pociag") or #lines > 0 then
        data.detected = true
    end
    
    for _, line in ipairs(lines) do
        local lower = line:lower()
        
        if lower:find("name") or lower:find("nazwa") then
            data.name = line:gsub("^.-:%s*", ""):match("^%s*(.-)%s*$") or "Unnamed"
        end
        
        if lower:find("speed") or lower:find("pęd") then
            local speed = line:match("([0-9.]+)")
            data.speed = speed and tonumber(speed) or 0
        end
        
        if lower:find("carriage") or lower:find("wagon") or lower:find("segment") then
            local num = line:match("(%d+)")
            data.carriages = num and tonumber(num) or 0
        end
        
        if lower:find("status") or lower:find("stan") then
            data.status = line:gsub("^.-:%s*", ""):match("^%s*(.-)%s*$") or "Unknown"
        end
    end
    
    return data
end

local function hasTrainChanged(old, new)
    if (not old or not old.detected) and (new and new.detected) then
        return true, "new"
    elseif (old and old.detected) and (not new or not new.detected) then
        return true, "left"
    elseif old and new and old.detected and new.detected then
        if old.name ~= new.name then
            return true, "changed"
        end
    end
    return false, nil
end

local function displayTrain(trainData, eventType)
    if trainData.detected then
        local status = eventType == "new" and "✓ ARRIVAL" or eventType == "changed" and "➜ CHANGE" or "UPDATE"
        
        print("\n" .. string.rep("─", 50))
        print(string.format("[%s] %s TRAIN", os.date("%H:%M:%S"), status))
        print(string.rep("─", 50))
        print(string.format("  Name:      %s", trainData.name))
        print(string.format("  Speed:     %.2f m/s", trainData.speed))
        print(string.format("  Carriages: %d", trainData.carriages))
        print(string.format("  Status:    %s", trainData.status))
        print(string.rep("─", 50))
        
        state.trainCount = state.trainCount + 1
    else
        if eventType == "left" then
            print(string.format("\n[%s] ✗ DEPARTURE - Train '%s' left the area", 
                os.date("%H:%M:%S"), state.previousTrainData.name))
        end
    end
end

local function addToHistory(trainData)
    if trainData.detected then
        table.insert(state.detectedTrains, 1, {
            time = os.date("%H:%M:%S"),
            name = trainData.name,
            speed = trainData.speed,
            carriages = trainData.carriages
        })
        
        if #state.detectedTrains > CONFIG.maxHistory then
            table.remove(state.detectedTrains)
        end
    end
end

local function showHistory()
    print("\n╔════════════════════════════════════════╗")
    print("║        DETECTED TRAIN HISTORY          ║")
    print("║  Total: " .. state.trainCount .. " trains")
    print("╚════════════════════════════════════════╝")
    
    if #state.detectedTrains == 0 then
        print("(none)")
        return
    end
    
    for i, train in ipairs(state.detectedTrains) do
        print(string.format("%2d. [%s] %s (%d carriages, %.1f m/s)", 
            i, train.time, train.name, train.carriages, train.speed))
    end
end

print("\nInitializing...")
local initialLines = readTargetBuffer()
state.previousTrainData = parseTrainData(initialLines)

print(string.format("✓ Connected. Train on Target Block: %s.", 
    state.previousTrainData and state.previousTrainData.detected and "Found" or "None"))

print("\n" .. string.rep("═", 50))
print("LISTENING FOR CHANGES (Press 'q' to quit, 'h' for history)")
print(string.rep("═", 50) .. "\n")

os.startTimer(CONFIG.checkInterval)

while true do
    local event, param = os.pullEvent()
    
    if event == "timer" then
        local currentLines = readTargetBuffer()
        local currentTrainData = parseTrainData(currentLines)
        
        local changed, changeType = hasTrainChanged(state.previousTrainData, currentTrainData)
        
        if changed then
            displayTrain(currentTrainData, changeType)
            if currentTrainData.detected then
                addToHistory(currentTrainData)
            end
        end
        
        state.previousTrainData = currentTrainData
        os.startTimer(CONFIG.checkInterval)
        
    elseif event == "char" then
        if param == "h" then
            showHistory()
            os.startTimer(CONFIG.checkInterval)
        elseif param == "q" then
            print("\nClosing detector...")
            break
        end
    end
end

print("✓ Train detector closed.")
