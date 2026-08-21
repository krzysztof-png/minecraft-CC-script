-- train_detector_v2.lua
-- Zaawansowany detektor pociągów z Target Block

local target = peripheral.wrap("back") or peripheral.find("create_target")

if not target then
    error("Nie znaleziono peryferium 'create_target'!")
end

print("=====================================")
print("  DETEKTOR POCIAGOW - v2.0")
print("  Advanced Computer + Target Block")
print("=====================================")

-- Konfiguracja
local CONFIG = {
    checkInterval = 0.3,  -- Jak często sprawdzać (sekundy)
    maxHistory = 20,      -- Ile pociągów pamiętać
    debug = false         -- Wyświetlać debug info
}

local state = {
    previousTrainData = nil,
    detectedTrains = {},
    lastCheck = os.clock(),
    trainCount = 0
}

-- Funkcja do odczytania bufora
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

-- Funkcja do parsowania danych pociągu
local function parseTrainData(lines)
    if not lines or #lines == 0 then return nil end
    
    local data = {
        raw = lines,
        detected = false,
        name = "Nieznany",
        speed = 0,
        carriages = 0,
        status = "N/A"
    }
    
    -- Złącz wszystko w jeden string do analizy
    local fullText = table.concat(lines, " "):lower()
    
    -- Detekcja czy pociąg jest obecny
    if fullText:find("train") or fullText:find("pociag") or #lines > 0 then
        data.detected = true
    end
    
    -- Parsuj każdą linię
    for _, line in ipairs(lines) do
        local lower = line:lower()
        
        -- Nazwa pociągu
        if lower:find("name") or lower:find("nazwa") then
            data.name = line:gsub("^.-:%s*", ""):match("^%s*(.-)%s*$") or "Bez nazwy"
        end
        
        -- Prędkość
        if lower:find("speed") or lower:find("pęd") then
            local speed = line:match("([0-9.]+)")
            data.speed = speed and tonumber(speed) or 0
        end
        
        -- Wagony
        if lower:find("carriage") or lower:find("wagon") or lower:find("segment") then
            local num = line:match("(%d+)")
            data.carriages = num and tonumber(num) or 0
        end
        
        -- Status
        if lower:find("status") or lower:find("stan") then
            data.status = line:gsub("^.-:%s*", ""):match("^%s*(.-)%s*$") or "Nieznany"
        end
    end
    
    return data
end

-- Porównaj dane pociągów
local function hasTrainChanged(old, new)
    if (not old or not old.detected) and (new and new.detected) then
        return true, "new" -- Nowy pociąg
    elseif (old and old.detected) and (not new or not new.detected) then
        return true, "left" -- Pociąg wyjechał
    elseif old and new and old.detected and new.detected then
        if old.name ~= new.name then
            return true, "changed" -- Inny pociąg
        end
    end
    return false, nil
end

-- Wyświetl informacje o pociągu
local function displayTrain(trainData, eventType)
    if trainData.detected then
        local status = eventType == "new" and "✓ PRZYBYCIE" or eventType == "changed" and "➜ ZMIANA" or "UPDATE"
        
        print("\n" .. string.rep("─", 50))
        print(string.format("[%s] %s POCIAGU", os.date("%H:%M:%S"), status))
        print(string.rep("─", 50))
        print(string.format("  Nazwa:  %s", trainData.name))
        print(string.format("  Prędkość: %.2f m/s", trainData.speed))
        print(string.format("  Wagony:  %d", trainData.carriages))
        print(string.format("  Status:  %s", trainData.status))
        print(string.rep("─", 50))
        
        state.trainCount = state.trainCount + 1
    else
        if eventType == "left" then
            print(string.format("\n[%s] ✗ ODJAZD - Pociąg '%s' opuścił obszar", 
                os.date("%H:%M:%S"), state.previousTrainData.name))
        end
    end
end

-- Dodaj do historii
local function addToHistory(trainData)
    if trainData.detected then
        table.insert(state.detectedTrains, 1, {
            time = os.date("%H:%M:%S"),
            name = trainData.name,
            speed = trainData.speed,
            carriages = trainData.carriages
        })
        
        -- Ogranicz historię
        if #state.detectedTrains > CONFIG.maxHistory then
            table.remove(state.detectedTrains)
        end
    end
end

-- Wyświetl historię
local function showHistory()
    print("\n╔════════════════════════════════════════╗")
    print("║      HISTORIA WYKRYTYCH POCIAGOW      ║")
    print("║  Razem: " .. state.trainCount .. " pociągów")
    print("╚════════════════════════════════════════╝")
    
    if #state.detectedTrains == 0 then
        print("(brak)")
        return
    end
    
    for i, train in ipairs(state.detectedTrains) do
        print(string.format("%2d. [%s] %s (%d wagonów, %.1f m/s)", 
            i, train.time, train.name, train.carriages, train.speed))
    end
end

-- Inicjalizacja
print("\nInitjalizacja...")
local initialLines = readTargetBuffer()
state.previousTrainData = parseTrainData(initialLines)

print(string.format("✓ Połączono. %s pociąg na Target Block.", 
    state.previousTrainData and state.previousTrainData.detected and "Znaleziono" or "Brak"))

print("\n" .. string.rep("═", 50))
print("NASLUCHIWANIE ZMIAN (Wpisz 'quit' aby wyjść, 'history' aby zobaczyć historię)")
print(string.rep("═", 50) .. "\n")

-- Timer dla pętli
os.startTimer(CONFIG.checkInterval)

-- Główna pętla
while true do
    local event, param = os.pullEvent()
    
    if event == "timer" then
        -- Sprawdź zmiany
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
            print("\nZamykam detektor...")
            break
        end
    end
end

print("✓ Detektor pociągów zamknięty.")
