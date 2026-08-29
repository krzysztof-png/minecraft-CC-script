-- list.lua / monitor_signals.lua
-- Continuous monitor for listBlockingTrainNames()

local signals = {}

for _, name in ipairs(peripheral.getNames()) do
    local dev = peripheral.wrap(name)
    if dev and type(dev.listBlockingTrainNames) == "function" then
        table.insert(signals, { name = name, device = dev })
    end
end

if #signals == 0 then
    print("Error: No peripheral found with listBlockingTrainNames() method!")
    print("Available network peripherals:")
    for _, name in ipairs(peripheral.getNames()) do
        print(" - " .. name .. " (" .. (peripheral.getType(name) or "unknown") .. ")")
    end
    return
end

print("Found " .. #signals .. " signal(s). Starting monitor...")
sleep(1)

while true do
    term.clear()
    term.setCursorPos(1, 1)
    
    print("=== BLOCKING TRAINS MONITOR ===")
    print("Time: " .. os.date("%T") .. " | [Ctrl+T to stop]")
    print(string.rep("-", 45))

    for _, sig in ipairs(signals) do
        print("\nSignal: " .. sig.name)
        
        local ok, trains = pcall(sig.device.listBlockingTrainNames)
        
        if not ok then
            print("  [READ ERROR]: " .. tostring(trains))
        elseif type(trains) == "table" then
            if #trains == 0 then
                print("  Status: No trains in section (Track clear)")
            else
                print("  Detected trains (" .. #trains .. "):")
                for i, trainName in ipairs(trains) do
                    print(string.format("   [%d] %s", i, tostring(trainName)))
                end
            end
        else
            print("  Return value: " .. tostring(trains))
        end
    end

    print("\n" .. string.rep("-", 45))
    sleep(0.1)
end
