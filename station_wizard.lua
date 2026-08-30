--------------------------------------------------------------------------------
--          KREATOR MULTI-STACJI W SIECI (station_wizard.lua)                  --
--------------------------------------------------------------------------------
local CONFIG_FILE = "station_layout.json"
local PROTOKOL    = "kolej_net"
local SERWER_HOST = "centrala_glowna"
local MOJE_ID     = os.getComputerID()

local function setC(fg, bg)
    term.setTextColor(fg or colors.white)
    term.setBackgroundColor(bg or colors.black)
end

local function pobierzSygnalyWiedNet()
    local nazwySet = {}
    for _, name in ipairs(peripheral.getNames()) do
        nazwySet[name] = true
        local dev = peripheral.wrap(name)
        if dev and dev.getNamesRemote then
            local ok, remotes = pcall(dev.getNamesRemote)
            if ok and remotes and type(remotes) == "table" then
                for _, rName in ipairs(remotes) do
                    nazwySet[rName] = true
                end
            end
        end
    end

    local lista = {}
    for n, _ in pairs(nazwySet) do
        local dev = peripheral.wrap(n)
        if dev then
            local isWireless = false
            if dev.isWireless then pcall(function() isWireless = dev.isWireless() end) end
            if not isWireless and n ~= "terminal" then
                table.insert(lista, n)
            end
        end
    end
    table.sort(lista)
    return lista
end

local function uruchomKreatorStacji(istniejacyID)
    term.clear()
    term.setCursorPos(1, 1)
    setC(colors.yellow, colors.blue)
    print("========================================")
    print("   KREATOR MULTI-STACJI DLA SIECI SRK   ")
    print("========================================")
    setC(colors.white, colors.black)

    -- KROK 1: NAZWA I OZNACZENIE STACJI
    print("\n[KROK 1] IDENTYFIKACJA STACJI W SIECI")
    write("Pełna Nazwa Stacji (np. Gdynia Główna): ")
    setC(colors.yellow, colors.black)
    local nazwaStacji = read()
    if nazwaStacji == "" then nazwaStacji = "Stacja_" .. MOJE_ID end
    setC(colors.white, colors.black)

    write("Kod / Unikalne ID Stacji (np. GD, SP, WWA): ")
    setC(colors.yellow, colors.black)
    local kodStacji = read()
    if kodStacji == "" then kodStacji = "ST_" .. MOJE_ID end
    setC(colors.white, colors.black)

    local stacjaID = istniejacyID or kodStacji

    -- KROK 2: LICZBA PERONÓW
    print("\n[KROK 2] PERONY STACJI " .. kodStacji)
    write("Ilosc Peronow na tej stacji [np. 2]: ")
    setC(colors.yellow, colors.black)
    local iloscPeronow = tonumber(read()) or 1
    setC(colors.white, colors.black)

    local peronyMap = {}
    for p = 1, iloscPeronow do
        print(string.format(" Peron #%d -> Wpisz numery torow (np. 1,2):", p))
        write("  Tory przy Peronie " .. p .. ": ")
        setC(colors.yellow, colors.black)
        local toryInput = read()
        setC(colors.white, colors.black)
        
        local toryLista = {}
        for tNum in toryInput:gmatch("%d+") do
            table.insert(toryLista, tNum)
        end
        if #toryLista == 0 then toryLista = { tostring(p) } end
        peronyMap[tostring(p)] = toryLista
    end

    -- KROK 3: TORY I TORY PRZEJAZDOWE
    print("\n[KROK 3] TORY I TORY PRZEJAZDOWE")
    write("Calkowita ilosc torow na tej stacji [np. 4]: ")
    setC(colors.yellow, colors.black)
    local iloscTorow = tonumber(read()) or 2
    setC(colors.white, colors.black)

    local wykryteSygnaly = pobierzSygnalyWiedNet()
    local toryStructure = {}

    print(string.format("\nWykryto %d sygnalow/peryferii na kablu.", #wykryteSygnaly))

    for t = 1, iloscTorow do
        local tStr = tostring(t)
        print(string.format("\n--- KONFIGURACJA TORU NR %s (STACJA %s) ---", tStr, kodStacji))
        
        print(string.format("Typ toru %s:", tStr))
        print(" [1] Tor Peronowy (Zatrzynanie pociagow osobowych)")
        print(" [2] Tor Przejazdowy (Bez zatrzymania / Expres / Towarowy)")
        write(" Wybór [1-2, domyslnie 1]: ")
        
        local typTor = "PERONOWY"
        local chTyp = read()
        if chTyp == "2" then typTor = "PRZEJAZDOWY" end

        local przypisanySygnal = wykryteSygnaly[t] or ("Create_Signal_" .. (t - 1))
        if #wykryteSygnaly > 0 then
            print(" Wybierz sygnal Create podpiety do Toru " .. tStr .. ":")
            for idx, sName in ipairs(wykryteSygnaly) do
                print(string.format("   [%d] %s", idx, sName))
            end
            write(string.format(" Wybór [1-%d, domyślnie %d]: ", #wykryteSygnaly, t))
            local sIdx = tonumber(read()) or t
            przypisanySygnal = wykryteSygnaly[sIdx] or przypisanySygnal
        end

        local nPeronu = "1"
        for pNr, tList in pairs(peronyMap) do
            for _, tN in ipairs(tList) do
                if tN == tStr then nPeronu = pNr end
            end
        end

        toryStructure[tStr] = {
            numer = tStr,
            typ = typTor,
            peron = nPeronu,
            sygnal = przypisanySygnal
        }

        setC(colors.lime, colors.black)
        print(string.format(" [OK] Tor %s (%s) -> Peron %s | Sygnal: %s", tStr, typTor, nPeronu, przypisanySygnal))
        setC(colors.white, colors.black)
    end

    local stacjaData = {
        id = stacjaID,
        nazwa = nazwaStacji,
        kod = kodStacji,
        iloscPeronow = iloscPeronow,
        iloscTorow = iloscTorow,
        perony = peronyMap,
        tory = toryStructure
    }

    local f = fs.open(CONFIG_FILE, "w")
    f.write(textutils.serializeJSON(stacjaData))
    f.close()

    -- Wysyłanie do Serwera Centralnego
    local modem = peripheral.find("modem")
    if modem then
        pcall(function() rednet.open(peripheral.getName(modem)) end)
        local serverId = rednet.lookup(PROTOKOL, SERWER_HOST)
        if serverId then
            rednet.send(serverId, { typ = "ZAPISZ_STACJE", idStacji = stacjaID, stacja = stacjaData }, PROTOKOL)
        end
        rednet.broadcast({ typ = "ZAPISZ_STACJE", idStacji = stacjaID, stacja = stacjaData }, PROTOKOL)
    end

    setC(colors.yellow, colors.blue)
    print("\n========================================")
    print("   ZAPISANO STACJĘ " .. stacjaID .. " NA SERWERZE! ")
    print("========================================")
    setC(colors.white, colors.black)
    sleep(1.5)
    return stacjaData
end

-- Menu Główne Zarządzania Multi-Stacjami
term.clear()
term.setCursorPos(1, 1)
setC(colors.yellow, colors.blue)
print("========================================")
print("  SIECIOWY ZARZĄDCA MULTI-STACJI (SRK)  ")
print("========================================")
setC(colors.white, colors.black)

print("\nWybierz akcje w sieci kolejowej:")
print(" [1] Dodaj / Skonfiguruj nowa stacje")
print(" [2] Pobierz stacje z Serwera Centralnego")
print(" [3] Wywietl zarejestrowane stacje w bazie")
write("Wybór [1-3, domyslnie 1]: ")

local choice = read()
if choice == "2" or choice == "3" then
    local modem = peripheral.find("modem")
    if modem then pcall(function() rednet.open(peripheral.getName(modem)) end) end
    local serverId = rednet.lookup(PROTOKOL, SERWER_HOST)
    if serverId then
        print("Pobieranie stacji z serwera #" .. serverId .. "...")
        rednet.send(serverId, { typ = "POBIERZ_STACJE" }, PROTOKOL)
        sleep(1.0)
    end
    if fs.exists(CONFIG_FILE) then
        local f = fs.open(CONFIG_FILE, "r")
        local data = textutils.unserializeJSON(f.readAll())
        f.close()
        print("\nAktualna Stacja: " .. (data.nazwa or "Unknown") .. " (ID: " .. (data.id or "ST") .. ")")
    end
else
    uruchomKreatorStacji()
end

return {
    kreator = uruchomKreatorStacji,
    wczytaj = function()
        if fs.exists(CONFIG_FILE) then
            local f = fs.open(CONFIG_FILE, "r")
            local t = f.readAll()
            f.close()
            return textutils.unserializeJSON(t)
        end
        return nil
    end
}
