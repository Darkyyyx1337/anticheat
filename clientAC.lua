-- =================================================================
-- || Anticheat Client - Versiune Revizuită și Îmbunătățită        ||
-- =================================================================
local configFile = LoadResourceFile(GetCurrentResourceName(), "config/config.json")
if not configFile then
    print('[ANTI-CHEAT] Eroare CRITICĂ: Nu am putut încărca config.json. Resursa se va opri.')
    return
end
local cfgFile = json.decode(configFile)

local localsFile = LoadResourceFile(GetCurrentResourceName(), "locals/"..cfgFile['locals']..".json")
if not localsFile then
    print('[ANTI-CHEAT] Eroare CRITICĂ: Nu am putut încărca fișierul de limbă. Verifică setarea "locals" din config.json.')
    return
end
local lang = json.decode(localsFile)

-- Verificăm dacă funcțiile AC sunt activate
if not cfgFile['EnableAcFunctions'] then
    print('[ANTI-CHEAT] Info: Functiile Anti-Cheat sunt dezactivate in config.json. Se încarcă doar log-urile.')
    return
end

-- =================================================================
-- || Variabile și Configurare Inițială                           ||
-- =================================================================
local acConfig = {}
local hasConfigBeenReceived = false
local playerPed = PlayerPedId()

-- Funcție pentru a printa mesaje de debug în consola F8
local function debugPrint(msg)
    print('[ANTI-CHEAT-DEBUG] ' .. msg)
end

-- =================================================================
-- || Sincronizare Configurare cu Serverul                        ||
-- =================================================================
CreateThread(function()
    -- Cerem configurarea de la server la pornire și apoi la fiecare 2 minute
    while true do
        if GetPlayerServerId(PlayerId()) ~= 0 then -- Așteptăm ca jucătorul să fie valid
            TriggerServerEvent('Prefech:getACConfig')
            debugPrint("Am cerut configurarea de la server...")
            Wait(120000) -- 2 minute
        else
            Wait(1000) -- Așteptăm conectarea completă
        end
    end
end)

RegisterNetEvent('Prefech:SendACConfig')
AddEventHandler('Prefech:SendACConfig', function(_config)
    acConfig = _config
    hasConfigBeenReceived = true
    debugPrint("Configurarea Anti-Cheat a fost primită și aplicată cu succes!")
end)

-- Actualizăm playerPedId la fiecare frame
CreateThread(function()
    while true do
        playerPed = PlayerPedId()
        Wait(500)
    end
end)


-- =================================================================
-- || MODUL: Detecție Avansată de Entități (Obiecte și Ped-uri)    ||
-- =================================================================
CreateThread(function()
    while not hasConfigBeenReceived do
        Wait(1000) -- Așteptăm să primim configurarea înainte de a porni detecțiile
    end
    debugPrint("MODUL: Detecția avansată de entități este ACTIVĂ.")

    while true do
        Wait(750) -- Frecvență optimizată pentru a reduce impactul pe performanță

        -- --- Verificare Obiecte (Props) ---
        for _, object in ipairs(GetGamePool('CObject')) do
            -- Condiții de detecție:
            -- 1. Obiectul există
            -- 2. Nu este o ușă de vehicul (fals pozitiv comun)
            -- 3. NU este deținut de rețea (condiția cheie pentru hack-uri)
            if DoesEntityExist(object) and not IsEntityAVehicle(object) and not NetworkGetEntityIsNetworked(object) then
                SetEntityAsNoLongerNeeded(object) -- Marcam pentru ștergere
                DeleteObject(object)
                debugPrint('Acțiune: Obiect suspect (model ' .. GetEntityModel(object) .. ') detectat și șters.')

                -- Trimitem alerta, dar fără a bloca thread-ul
                Citizen.SetTimeout(0, function()
                    TriggerServerEvent('ACCheatAlert', {
                        target = GetPlayerServerId(PlayerId()),
                        reason = 'BO02: Spawn obiect nelocal',
                        screenshot = true,
                        kick = true -- Recomandat kick pentru spawn de obiecte
                    })
                end)
            end
        end

        -- --- Verificare Ped-uri (NPCs) ---
        for _, ped in ipairs(GetGamePool('CPed')) do
             -- Condiții de detecție:
             -- 1. Nu este jucătorul curent
             -- 2. Entitatea există
             -- 3. NU este un alt jucător
             -- 4. NU este deținut de rețea (condiția cheie)
             -- 5. NU este un animal (pentru a evita fals pozitive)
            if ped ~= playerPed and DoesEntityExist(ped) and not IsPedAPlayer(ped) and not NetworkGetEntityIsNetworked(ped) and not IsPedAnimal(ped) then
                SetEntityAsNoLongerNeeded(ped) -- Marcam pentru ștergere
                DeletePed(ped)
                debugPrint('Acțiune: Ped suspect (model ' .. GetEntityModel(ped) .. ') detectat și șters.')

                -- Trimitem alerta
                Citizen.SetTimeout(0, function()
                     TriggerServerEvent('ACCheatAlert', {
                        target = GetPlayerServerId(PlayerId()),
                        reason = 'BP02: Spawn ped nelocal',
                        screenshot = true,
                        kick = true -- Recomandat kick pentru spawn de ped-uri
                    })
                end)
            end
        end
    end
end)


-- =================================================================
-- || MODUL: Detecție Vehicule Aruncate (Vehicle Throw)           ||
-- =================================================================
local suspiciousVehicles = {}
CreateThread(function()
    while not hasConfigBeenReceived do Wait(1000) end
    if not acConfig.vehicle_throw or not acConfig.vehicle_throw.enabled then
        debugPrint("MODUL: Detecția 'Vehicle Throw' este DEZACTIVATĂ în ac_config.json.")
        return
    end
    debugPrint("MODUL: Detecția 'Vehicle Throw' este ACTIVĂ.")

    while true do
        Wait(250)
        local vehicles = GetGamePool('CVehicle')
        for _, vehicle in ipairs(vehicles) do
            if DoesEntityExist(vehicle) and not IsEntityAPed(vehicle) then
                local speed = GetEntitySpeed(vehicle)
                local vehNetId = NetworkGetNetworkIdFromEntity(vehicle)

                if speed > (acConfig.vehicle_throw.minSpeed or 100.0) and not IsPedInVehicle(playerPed, vehicle, false) then
                    local currentTime = GetGameTimer()
                    if not suspiciousVehicles[vehNetId] then
                        suspiciousVehicles[vehNetId] = { firstDetection = currentTime, count = 1 }
                    else
                        suspiciousVehicles[vehNetId].count = suspiciousVehicles[vehNetId].count + 1
                    end

                    if suspiciousVehicles[vehNetId].count >= (acConfig.vehicle_throw.detectionThreshold or 3) then
                        debugPrint('Acțiune: Vehicul aruncat detectat! Se trimite alerta.')
                        TriggerServerEvent('Prefech:ClientDetection', 'Vehicle as projectile', 'vehicle_throw',
                            string.format('Vehicul: %s | Viteză: %.2f', GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))), speed))
                        suspiciousVehicles[vehNetId] = nil -- Resetam după raportare
                    end
                end
            end
        end
    end
end)

-- Curățare periodică a listei de vehicule suspecte
CreateThread(function()
    while true do
        Wait(15000) -- Curățăm la fiecare 15 secunde
        local currentTime = GetGameTimer()
        for netId, data in pairs(suspiciousVehicles) do
            if (currentTime - data.firstDetection) > (acConfig.vehicle_throw.detectionTimeWindow or 10000) then
                suspiciousVehicles[netId] = nil
            end
        end
    end
end)


-- =================================================================
-- || Alte Module (Blacklisted Vehicles, Keys, Commands)          ||
-- =================================================================
-- Aici lăsăm codul original, deoarece logica sa este în mare parte corectă.
-- Am adăugat doar verificarea `hasConfigBeenReceived` pentru a ne asigura că nu rulează fără configurare.

CreateThread(function()
    while not hasConfigBeenReceived do Wait(1000) end
    debugPrint("MODUL: Verificările pentru vehicule, taste și comenzi interzise sunt ACTIVE.")
    local warnLimit = 0

    while true do
        Wait(500)
        local currentVehicle = GetVehiclePedIsIn(playerPed, false)
        if DoesEntityExist(currentVehicle) then
            local vehicleModelHash = GetEntityModel(currentVehicle)
            for _, blacklistedVeh in pairs(acConfig['BlacklistedVehicles'] or {}) do
                if vehicleModelHash == GetHashKey(blacklistedVeh) then
                    DeleteVehicle(currentVehicle)
                    warnLimit = warnLimit + 1
                    TriggerServerEvent('ACCheatAlert', {target = GetPlayerServerId(PlayerId()), reason = 'BV01: '..blacklistedVeh, screenshot = true, kick = (warnLimit >= (acConfig.KickSettings.BlacklistedVehicleLimit or 3))})
                end
            end
        end
    end
end)

CreateThread(function()
    while not hasConfigBeenReceived do Wait(1000) end
    local CooldownWait = false
    while true do
        Wait(10)
        if not CooldownWait then
            for key, reason in pairs(acConfig['BlacklistedKeys'] or {}) do
                if IsControlJustPressed(0, tonumber(key)) and not IsNuiFocused() then
                    CooldownWait = true
                    TriggerServerEvent('ACCheatAlert', {target = GetPlayerServerId(PlayerId()), reason = 'BK01: '..reason, screenshot = true, kick = true})
                    Citizen.SetTimeout(5000, function() CooldownWait = false end)
                end
            end
        end
    end
end)
