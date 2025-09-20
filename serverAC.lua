local configFile = LoadResourceFile(GetCurrentResourceName(), "config/config.json")
local cfgFile = json.decode(configFile)

local ACconfigFile = LoadResourceFile(GetCurrentResourceName(), "config/ac_config.json")
local ACcfgFile = json.decode(ACconfigFile)

local localsFile = LoadResourceFile(GetCurrentResourceName(), "locals/"..cfgFile['locals']..".json")
local lang = json.decode(localsFile)

if cfgFile['EnableAcFunctions'] then
    RegisterNetEvent('Prefech:DropPlayer')
    AddEventHandler('Prefech:DropPlayer', function(reason)
        if not IsPlayerAceAllowed(source, cfgFile['AntiCheatBypass']) then
            DropPlayer(source, 'Automated kick: '..reason)
        end
    end)

    RegisterNetEvent('Prefech:getACConfig')
    AddEventHandler('Prefech:getACConfig', function()
        TriggerClientEvent('Prefech:SendACConfig', source, ACcfgFile)
    end)

    RegisterNetEvent('Prefech:ClientDetection')
    AddEventHandler('Prefech:ClientDetection', function(reason, detectionType, details)
        local src = source
        if not IsPlayerAceAllowed(src, cfgFile['AntiCheatBypass']) then
            exports['screenshot-basic']:requestClientScreenshot(src, {
                fileName = 'anticheat/'..detectionType..'_'..os.time()..'.jpg',
                quality = 0.95
            }, function(err, data)
                local screenshotUrl = data and data.url or nil
                local logMsg = string.format('🚨 Vehicle Throw Detection | Player: %s (%s) | Details: %s', GetPlayerName(src), GetPlayerIdentifier(src, 0), details)
                CreateLog({
                    channel = 'anticheat',
                    player_id = src,
                    EmbedMessage = logMsg,
                    responseUrl = screenshotUrl
                })
                if ACcfgFile[detectionType] and ACcfgFile[detectionType].kick then
                    DropPlayer(src, 'Automated kick: ' .. reason)
                end
            end)
        end
    end)

    RegisterNetEvent('Prefech:DebugLog')
    AddEventHandler('Prefech:DebugLog', function(message)
        local src = source
        CreateLog({
            channel = 'anticheat',
            player_id = src,
            EmbedMessage = '🔍 Debug Log | '..message
        })
    end)

    local validResourceList
    local function collectValidResourceList()
        validResourceList = {}
        for i = 0, GetNumResources() - 1 do
            validResourceList[GetResourceByFindIndex(i)] = true
        end
    end

    AddEventHandler("onResourceListRefresh", collectValidResourceList)
    RegisterNetEvent("Prefech:resourceCheck")
    AddEventHandler("Prefech:resourceCheck", function(rcList)
        local source = source
        collectValidResourceList()
        Wait(500)
        for _, resource in ipairs(rcList) do
            if not validResourceList[resource] then
                TriggerEvent('ACCheatAlert', {target = source, reason = 'URD', kick = true})
            end
        end
    end)
end