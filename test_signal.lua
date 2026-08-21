-- test_signal.lua
-- Skrypt do testowania peryferii Train Signal

-- Znajdź sygnał w otoczeniu (zakładamy, że jest połączony przewodowo lub przylega bezpośrednio)
local signal = peripheral.find("train_signal")

if not signal then
    error("Nie znaleziono peryferii 'train_signal'. Sprawdź połączenie!")
end

print("Test sygnału pociągu uruchomiony.")
print("Obserwuję: " .. peripheral.getName(signal))
print("---------------------------------------")

-- Funkcja pomocnicza do wyświetlania stanu
local function printTrainStatus()
    local trains = signal.listBlockingTrainNames()
    if #trains > 0 then
        print("Obecny pociąg: " .. trains[1])
    else
        print("Sygnał wolny (brak pociągu).")
    end
end

-- Początkowy odczyt
printTrainStatus()

-- Pętla nasłuchująca zdarzeń
while true do
    -- Czekaj na zdarzenie zmiany stanu sygnału
    -- Create Mod wysyła 'train_signal_state_change'
    local event, side = os.pullEvent("train_signal_state_change")
    
    print("\n[ZMIANA STANU DETEKTORA]")
    printTrainStatus()
end
