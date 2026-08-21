-- target_reader.lua
-- Skrypt do odczytu danych pociagu z CC:C Bridge Target Block

-- Pobranie peryferium z 'back' lub automatyczne znalezienie create_target
local target = peripheral.wrap("back") or peripheral.find("create_target")

if not target then
    error("Nie znaleziono peryferium 'create_target' (Target Block) na boku 'back'!")
end

print("Polaczono z Target Blockiem.")
print("---------------------------------------")

-- Funkcja do bezpiecznego odczytu calej zawartosci Target Blocka
local function readTargetBuffer()
    print("\n--- ODCZYT BUFORA (" .. os.date("%T") .. ") ---")
    
    -- 1. Nowsze wersje CC:C Bridge wspieraja target.dump() zwracajace tablice linii
    if target.dump then
        local lines = target.dump()
        if #lines == 0 then
            print("[Pusty bufor]")
        else
            for i, line in ipairs(lines) do
                print(string.format("[%02d] %s", i, line))
            end
        end
        return
    end

    -- 2. Fallback: odczyt linijka po linijce (getText / getLine)
    local line = 1
    local foundAny = false
    while true do
        local content = nil
        if target.getLine then
            content = target.getLine(line)
        elseif target.getText then
            content = target.getText(line)
        end

        if not content or content == "" then
            break
        end

        print(string.format("[%02d] %s", line, content))
        foundAny = true
        line = line + 1
    end

    if not foundAny then
        print("[Pusty bufor]")
    end
end

-- Poczatkowy stan bufora
readTargetBuffer()

print("\nNasluchiwanie zmian z Display Linka (Ctrl+T aby zatrzymac)...")

-- Glowna petla nasluchujaca eventow
while true do
    local eventData = { os.pullEvent() }
    local eventName = eventData[1]

    -- CC:C Bridge wyrzuca event przy kazdej aktualizacji z Display Linka
    if eventName:find("target") or eventName == "redstone" or eventName == "display_link" then
        print("\n[EVENT: " .. eventName .. "]")
        readTargetBuffer()
    end
end
