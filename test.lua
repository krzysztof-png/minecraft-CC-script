-- inspect_back.lua / test.lua
-- Inspection script checking all connected peripherals on the back side / network

term.clear()
term.setCursorPos(1, 1)

local SIDE = "back"

print("========================================")
print("     PERIPHERAL INSPECTION: [" .. SIDE .. "]     ")
print("========================================\n")

local directType = peripheral.getType(SIDE)

if not directType then
    print("No peripheral directly connected to the back.")
    print("Scanning network connections...")
else
    print(string.format("Detected directly: [%s] (Type: %s)", SIDE, directType))
    print("Direct methods:")
    local methods = peripheral.getMethods(SIDE)
    if methods and #methods > 0 then
        for i, m in ipairs(methods) do
            print(string.format("  [%2d] %s()", i, m))
        end
    else
        print("  (No exposed methods)")
    end
    print("----------------------------------------")
end

if directType == "modem" then
    local modem = peripheral.wrap(SIDE)
    if modem and modem.isColour and modem.getNamesRemote then
        print("\nWired Modem found on the back.")
        print("Scanning devices on the wired network...\n")
        
        local remoteNames = modem.getNamesRemote()
        
        if #remoteNames == 0 then
            print("Network is empty or remote modems are inactive (no red border).")
        else
            for idx, name in ipairs(remoteNames) do
                local rType = peripheral.getType(name) or "unknown"
                print(string.format("=== [%d] DEVICE: %s (%s) ===", idx, name, rType))
                
                local rMethods = peripheral.getMethods(name)
                if rMethods and #rMethods > 0 then
                    for mIdx, method in ipairs(rMethods) do
                        local dev = peripheral.wrap(name)
                        local status, res = pcall(function() return dev[method]() end)
                        
                        if status and res ~= nil then
                            print(string.format("   %2d. %-24s -> %s", mIdx, method, tostring(res)))
                        else
                            print(string.format("   %2d. %s()", mIdx, method))
                        end
                    end
                else
                    print("   (No methods)")
                end
                print("")
            end
        end
    end
end

print("----------------------------------------")
print("All currently visible peripherals in system:")
local all = peripheral.getNames()
for _, n in ipairs(all) do
    print(string.format(" - %-26s [%s]", n, peripheral.getType(n) or "none"))
end
