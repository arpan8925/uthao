-- Variables

local QBCore = exports['qb-core']:GetCoreObject()

local meterIsOpen = false
local meterActive = false
local lastLocation = nil
local PlayerJob = {}
local jobRequired = Config.jobRequired
-- Declare a global or player-specific variable to store the vehicle identifier
local playerVehicle = nil

-- used for polyzones
local isInsidePickupZone = false
local isInsideDropZone = false
local Notified = false
local isPlayerInsideZone = false

local bossPed

local meterData = {
    fareAmount = 6,
    currentFare = 0,
    distanceTraveled = 0,
}

local NpcData = {
    Active = false,
    CurrentNpc = nil,
    LastNpc = nil,
    CurrentDeliver = nil,
    LastDeliver = nil,
    Npc = nil,
    NpcBlip = nil,
    DeliveryBlip = nil,
    NpcTaken = false,
    NpcDelivered = false,
    CountDown = 180,
    startingLength = 0,
    distanceLeft = 0,
    CrashCount = 0
}

-- events
--just to prevent some bug if the resource get restarted on production
AddEventHandler('onResourceStart', function(resourceName)
    PlayerJob = QBCore.Functions.GetPlayerData().job
    if Config.UseTarget then
        setupTarget()
        setupCabParkingLocation()
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerJob = QBCore.Functions.GetPlayerData().job
    if Config.UseTarget then
        setupTarget()
        setupCabParkingLocation()
    end
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
    PlayerJob = JobInfo
end)

local dutyKey = false

local function SafeCall(func, ...)
    local success, result = pcall(func, ...)
    if not success then
        print("[ERROR] An error occurred: " .. tostring(result))
    end
    return success, result
end


local function ResetNpcTask()
    NpcData = {
        Active = false,
        CurrentNpc = nil,
        LastNpc = nil,
        CurrentDeliver = nil,
        LastDeliver = nil,
        Npc = nil,
        NpcBlip = nil,
        DeliveryBlip = nil,
        NpcTaken = false,
        NpcDelivered = false,
        startingLength = 0,
        distanceLeft = 0,
        CrashCount = 0
    }
    print("[DEBUG] NPC tasks have been reset.")
end



-- Function to spawn the boss ped
local function SpawnBossPed()
    -- Extract model and coordinates from the configuration
    local model = GetHashKey(Config.bossPed.model)
    local coords = Config.bossPed.coords

    -- Request the model manually
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(0)
    end

    -- Get the ground Z coordinate
    local groundZ
    local foundGround, zPos = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z, 0)
    if foundGround then
        groundZ = zPos
    else
        groundZ = coords.z -- Fall back to the original Z coordinate if ground Z is not found
    end
    
    -- Create the ped using the specified coordinates and adjusted Z coordinate
    local entity = CreatePed(0, model, coords.x, coords.y, groundZ, coords.w, true, false)

    -- Set ped properties: freeze position, make invincible, and block non-temporary events
    FreezeEntityPosition(entity, true)
    SetEntityInvincible(entity, true)
    SetBlockingOfNonTemporaryEvents(entity, true)

    -- Release the model from memory after creating the ped
    SetModelAsNoLongerNeeded(model)

    -- Return the entity so it can be used by ox_target
    return entity
end

-- Function to register and open the boss menu
local function OpenBossMenu()

    QBCore.Functions.TriggerCallback('custom:CheckDutyStatus', function(isOnDuty)

        local onDutyStatus = isOnDuty and "Already On Duty" or "Go On Duty"



        lib.registerContext({

            id = 'boss_menu',

            title = 'Boss Menu',

            options = {

                {

                    title = onDutyStatus,

                    description = isOnDuty and "You are currently on duty" or "Toggle duty status",

                    icon = 'fa-solid fa-pen',

                    onSelect = function()

                        if not isOnDuty then

                            QBCore.Functions.TriggerCallback('custom:CheckDriverLicense', function(hasLicense)

                                if hasLicense then

                                    QBCore.Functions.Notify("Bhai On Duty Hoisos", "success")

                                    TriggerServerEvent('custom:ToggleDuty')

                                    -- Re-register the menu to update the on-duty status in the menu

                                    OpenBossMenu()

                                else

                                    QBCore.Functions.Notify("Don't Have driving license to do this job", "error")

                                end

                            end)

                        else

                            QBCore.Functions.Notify("You are already on duty", "error")

                        end

                    end

                },

                {

                    title = 'Close Menu',

                    description = 'Close the boss menu',

                    icon = 'fa-solid fa-times',

                    onSelect = function()

                        lib.closeContext()

                    end

                }

            }

        })



        -- Show the menu after registering it

        lib.showContext('boss_menu')

    end)

end



-- Register the /taxigooffduty command

RegisterCommand('taxigooffduty', function()

    QBCore.Functions.TriggerCallback('custom:CheckDutyStatus', function(isOnDuty)

        if isOnDuty then

            QBCore.Functions.Notify("Bhai Off Duty Hoisos", "success")



            -- Check and remove NPC blip if it exists

            if NpcData.NpcBlip ~= nil and DoesBlipExist(NpcData.NpcBlip) then

                print("[DEBUG] Removing NPC blip ID: " .. tostring(NpcData.NpcBlip))

                SafeCall(RemoveBlip, NpcData.NpcBlip)

                NpcData.NpcBlip = nil -- Dereference the blip

            else

                print("[DEBUG] No valid NPC blip to remove or blip does not exist.")

            end



            -- Check and remove NPC if it exists

            if NpcData.Npc ~= nil then

                SafeCall(function()

                    local RemovePed = function(p)

                        SetTimeout(60000, function()

                            DeletePed(p)

                        end)

                    end

                    RemovePed(NpcData.Npc)

                end)

                print("[DEBUG] NPC removed.")

            else

                print("[DEBUG] No NPC to remove.")

            end

            SafeCall(ResetNpcTask)

            QBCore.Functions.Notify("You are now off duty. Onduty Function Call", "success")

            TriggerServerEvent('custom:ToggleDuty')
            TriggerServerEvent('custom:VanishRentedVehicle')
            local playerPed = PlayerPedId()
            ClearPedProp(playerPed, 0)    

            playerVehicle = nil



        else

            QBCore.Functions.Notify("You are already off duty", "error")

            print("[DEBUG] Player is already off duty.")

        end

    end)

end, false) -- false means the command doesn't need to be run as an admin

-- Spawn the boss ped when the script is loaded and set up ox_target interaction

CreateThread(function()

    local bossPedEntity = SpawnBossPed()



    -- Set up ox_target interaction with multiple options

    exports.ox_target:addLocalEntity(bossPedEntity, {

        name = "boss_target",

        label = 'Taxi Boss',

        icon = 'fa-solid fa-pen',

        onSelect = function ()

            OpenBossMenu()

        end 

    })

end)

local function resetMeter()
    meterData = {
        fareAmount = 6,
        currentFare = 0,
        distanceTraveled = 0,
        startingLength = 0,
        distanceLeft = 0
    }
end

local function whitelistedVehicle()
    local veh = GetEntityModel(GetVehiclePedIsIn(PlayerPedId()))
    local retval = false

    for i = 1, #Config.AllowedVehicles, 1 do
        if veh == GetHashKey(Config.AllowedVehicles[i].model) then
            retval = true
        end
    end

    if veh == GetHashKey('dynasty') then
        retval = true
    end

    return retval
end

local function IsDriver()
    return GetPedInVehicleSeat(GetVehiclePedIsIn(PlayerPedId(), false), -1) == PlayerPedId()
end

local function DrawText3D(x, y, z, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    BeginTextCommandDisplayText('STRING')
    SetTextCentre(true)
    AddTextComponentSubstringPlayerName(text)
    SetDrawOrigin(x, y, z, 0)
    EndTextCommandDisplayText(0.0, 0.0)
    local factor = (string.len(text)) / 370
    DrawRect(0.0, 0.0 + 0.0125, 0.017 + factor, 0.03, 0, 0, 0, 75)
    ClearDrawOrigin()
end

local function GetDeliveryLocation()
    NpcData.CurrentDeliver = math.random(1, #Config.NPCLocations.DeliverLocations)
    if NpcData.LastDeliver ~= nil then
        while NpcData.LastDeliver ~= NpcData.CurrentDeliver do
            NpcData.CurrentDeliver = math.random(1, #Config.NPCLocations.DeliverLocations)
        end
    end

    if NpcData.DeliveryBlip ~= nil then
        RemoveBlip(NpcData.DeliveryBlip)
    end
    NpcData.DeliveryBlip = AddBlipForCoord(Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].x, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].y, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].z)
    SetBlipColour(NpcData.DeliveryBlip, 3)
    SetBlipRoute(NpcData.DeliveryBlip, true)
    SetBlipRouteColour(NpcData.DeliveryBlip, 3)
    NpcData.LastDeliver = NpcData.CurrentDeliver
    if not Config.UseTarget then -- added checks to disable distance checking if polyzone option is used
        CreateThread(function()
            while true and NpcData.Active do
                local ped = PlayerPedId()
                local pos = GetEntityCoords(ped)
                local dist = #(pos - vector3(Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].x, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].y, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].z))
                if dist < 25 then
                    DrawMarker(2, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].x, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].y, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, 255, 0, 0, 255, 0, 0, 0, 1, 0, 0, 0)
                    if dist < 5 then
                        DrawText3D(Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].x, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].y, Config.NPCLocations.DeliverLocations[NpcData.CurrentDeliver].z, Lang:t('info.drop_off_npc'))
                        if IsControlJustPressed(0, 38) then
                            local veh = GetVehiclePedIsIn(ped, 0)
                            TaskLeaveVehicle(NpcData.Npc, veh, 0)
                            SetEntityAsMissionEntity(NpcData.Npc, false, true)
                            SetEntityAsNoLongerNeeded(NpcData.Npc)
                            local targetCoords = Config.NPCLocations.TakeLocations[NpcData.LastNpc]
                            TaskGoStraightToCoord(NpcData.Npc, targetCoords.x, targetCoords.y, targetCoords.z, 1.0, -1, 0.0, 0.0)
                            
                            
                            -- Animation code

                            local animDict = "mp_common"

                            local animName = "givetake1_a"

                            RequestAnimDict(animDict)

                            while not HasAnimDictLoaded(animDict) do

                                Wait(100)

                            end

                            SetPedPropIndex(NpcData.Npc, 0, -1, 0, true)

                            TaskPlayAnim(NpcData.Npc, animDict, animName, 8.0, -8.0, 5000, 49, 0, false, false, false)

                            Wait(1000) -- Wait for the animation to complete
                                                        
                            SendNUIMessage({
                                action = 'toggleMeter'
                            })
                            TriggerServerEvent('qb-taxi:server:NpcPay', meterData.currentFare, NpcData.CrashCount == 0)
                            PlayPedAmbientSpeechNative(NpcData.Npc, NpcData.CrashCount == 0 and Config.Advanced.Speech.Happy or Config.Advanced.Speech.Grateful, 'SPEECH_PARAMS_ALLOW_REPEAT')
                            meterActive = false
                            SendNUIMessage({
                                action = 'resetMeter'
                            })
                            QBCore.Functions.Notify(Lang:t('info.person_was_dropped_off'), 'success')
                            if NpcData.DeliveryBlip ~= nil then
                                RemoveBlip(NpcData.DeliveryBlip)
                            end
                            local RemovePed = function(p)
                                SetTimeout(60000, function()
                                    DeletePed(p)
                                end)
                            end
                            RemovePed(NpcData.Npc)
                            ResetNpcTask()
                            break
                        end
                    end
                end
                Wait(1)
            end
        end)
    end
end

local function EnumerateEntitiesWithinDistance(entities, isPlayerEntities, coords, maxDistance)
    local nearbyEntities = {}
    if coords then
        coords = vector3(coords.x, coords.y, coords.z)
    else
        local playerPed = PlayerPedId()
        coords = GetEntityCoords(playerPed)
    end
    for k, entity in pairs(entities) do
        local distance = #(coords - GetEntityCoords(entity))
        if distance <= maxDistance then
            nearbyEntities[#nearbyEntities + 1] = isPlayerEntities and k or entity
        end
    end
    return nearbyEntities
end

local function GetVehiclesInArea(coords, maxDistance) -- Vehicle inspection in designated area
    return EnumerateEntitiesWithinDistance(GetGamePool('CVehicle'), false, coords, maxDistance)
end

local function IsSpawnPointClear(coords, maxDistance) -- Check the spawn point to see if it's empty or not:
    return #GetVehiclesInArea(coords, maxDistance) == 0
end

local function getVehicleSpawnPoint()
    local near = nil
    local distance = 10000
    for k, v in pairs(Config.CabSpawns) do
        if IsSpawnPointClear(vector3(v.x, v.y, v.z), 2.5) then
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local cur_distance = #(pos - vector3(v.x, v.y, v.z))
            if cur_distance < distance then
                distance = cur_distance
                near = k
            end
        end
    end
    return near
end

local function calculateFareAmount()
    if meterIsOpen and meterActive and not NpcData.NpcTaken then -- For RP purposes
        local startPos = lastLocation
        local newPos = GetEntityCoords(PlayerPedId())
        if startPos ~= newPos then
            local newDistance = #(startPos - newPos)
            lastLocation = newPos
            meterData['distanceTraveled'] += (newDistance / 1609)
            local fareAmount = ((meterData['distanceTraveled']) * Config.Meter['defaultPrice']) + Config.Meter['startingPrice']
            meterData['currentFare'] = math.floor(fareAmount)
            SendNUIMessage({
                action = 'updateMeter',
                meterData = meterData
            })
        end
    end

    if meterIsOpen and meterActive and NpcData.NpcTaken then
        if DoesBlipHaveGpsRoute(NpcData.DeliveryBlip) then
            local startPos = lastLocation
            local newPos = GetEntityCoords(PlayerPedId())
            if startPos ~= newPos then
                lastLocation = newPos
                if NpcData.startingLength == 0 then NpcData.startingLength = GetGpsBlipRouteLength() end -- initial length
                NpcData.distanceLeft = GetGpsBlipRouteLength()                                           -- refresh length as driving
                if GetGpsBlipRouteLength() > NpcData.distanceLeft then return end                        -- check route length against previous route length
                local distanceTraveled = NpcData.startingLength - NpcData.distanceLeft                   -- calculate route progress
                if distanceTraveled < 0 then return end
                meterData['distanceTraveled'] = (distanceTraveled / 1609)
                local fareAmount = ((meterData['distanceTraveled']) * Config.Meter['defaultPrice']) + Config.Meter['startingPrice']
                meterData['currentFare'] = math.floor(fareAmount)
                SendNUIMessage({
                    action = 'updateMeter',
                    meterData = meterData
                })
            end
        end
    end
end

local function listenForVehicleDamage()
    CreateThread(function()
        local lastVehicleHealth = nil
        while true do
            if not Config.Advanced.Bonus.Enabled or not NpcData.Active then return end

            if NpcData.NpcTaken then
                local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)

                if vehicle and vehicle ~= 0 then
                    local currentHealth = GetEntityHealth(vehicle)
                    if currentHealth < Config.Advanced.MinCabHealth then
                        TriggerEvent('qb-taxi:client:CancelTaxiNpc')
                        return QBCore.Functions.Notify(Lang:t('error.broken_taxi'), 'error')
                    end

                    if lastVehicleHealth and currentHealth < lastVehicleHealth then
                        if Config.Advanced.Speech.Enabled then
                            if lastVehicleHealth - currentHealth < 10 then -- small crash = angry / big crash = scared
                                PlayPedAmbientSpeechNative(NpcData.Npc, Config.Advanced.Speech.Angry, 'SPEECH_PARAMS_ALLOW_REPEAT')
                            else
                                PlayPedAmbientSpeechNative(NpcData.Npc, Config.Advanced.Speech.Scared, 'SPEECH_PARAMS_ALLOW_REPEAT')
                            end
                        end

                        NpcData.CrashCount += 1
                        if NpcData.CrashCount >= Config.Advanced.MaxCrashesAllowed then
                            TriggerEvent('qb-taxi:client:CancelTaxiNpc')
                            return QBCore.Functions.Notify(Lang:t('error.ride_canceled'), 'error')
                        end

                        local count = Config.Advanced.MaxCrashesAllowed - NpcData.CrashCount
                        QBCore.Functions.Notify(string.format(Lang:t('error.crash_warning'), count, count == 1 and Lang:t('error.time') or Lang:t('error.times')), 'error')
                    end
                    lastVehicleHealth = currentHealth
                else
                    lastVehicleHealth = nil
                end
            end
            Wait(200)
        end
    end)
end

-- qb-menu

function TaxiGarage()
    local vehicleMenu = {
        {
            header = Lang:t('menu.taxi_menu_header'),
            isMenuHeader = true
        }
    }
    for _, v in pairs(Config.AllowedVehicles) do
        vehicleMenu[#vehicleMenu + 1] = {
            header = v.label,
            params = {
                event = 'qb-taxi:client:TakeVehicle',
                args = {
                    model = v.model
                }
            }
        }
    end
    -- qb-bossmenu:client:openMenu
    if PlayerJob.name == jobRequired and PlayerJob.isboss and Config.UseTarget then
        vehicleMenu[#vehicleMenu + 1] = {
            header = Lang:t('menu.boss_menu'),
            txt = '',
            params = {
                event = 'qb-bossmenu:client:forceMenu'
            }
        }
    end

    vehicleMenu[#vehicleMenu + 1] = {
        header = Lang:t('menu.close_menu'),
        txt = '',
        params = {
            event = 'qb-menu:client:closeMenu'
        }
    }
    exports['qb-menu']:openMenu(vehicleMenu)
end


RegisterNetEvent('qb-taxi:client:TakeVehicle', function(data)
    local SpawnPoint = getVehicleSpawnPoint()
    if SpawnPoint then
        local coords = vector3(Config.CabSpawns[SpawnPoint].x, Config.CabSpawns[SpawnPoint].y, Config.CabSpawns[SpawnPoint].z)
        local CanSpawn = IsSpawnPointClear(coords, 2.0)
        if CanSpawn then
            QBCore.Functions.TriggerCallback('QBCore:Server:SpawnVehicle', function(netId)
                local veh = NetToVeh(netId)
                playerVehicle = netId  -- Store the vehicle network ID
                SetVehicleNumberPlateText(veh, 'TAXI' .. tostring(math.random(1000, 9999)))
                exports['LegacyFuel']:SetFuel(veh, 100.0)
                closeMenuFull()
                SetEntityHeading(veh, Config.CabSpawns[SpawnPoint].w)
                TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
                TriggerEvent('vehiclekeys:client:SetOwner', QBCore.Functions.GetPlate(veh))
                SetVehicleEngineOn(veh, true, true)

                Citizen.Wait(100)

                -- Wear a helmet or hat after 2 seconds if it's a bike
                if IsThisModelABike(GetEntityModel(veh)) then
                    Citizen.Wait(2000)  -- Wait for 2 seconds
                    local playerPed = PlayerPedId()
                    local hatDrawable = 18  -- Helmet or Hat ID
                    local hatTexture = 0  -- Helmet or Hat Texture ID

                    -- Apply helmet or hat using SetPedPropIndex
                    SetPedPropIndex(playerPed, 0, hatDrawable, hatTexture, true)
                    print("Helmet Applied")
                end



                Citizen.Wait(100)
                TriggerEvent('qb-taxi:client:DoTaxiNpc')
            end, data.model, coords, true)
        else
            QBCore.Functions.Notify(Lang:t('info.no_spawn_point'), 'error')
        end
    else
        QBCore.Functions.Notify(Lang:t('info.no_spawn_point'), 'error')
        return
    end
end)


function closeMenuFull()
    exports['qb-menu']:closeMenu()
end

-- Events
RegisterNetEvent('qb-taxi:client:DoTaxiNpc', function()
    if not PlayerJob.onduty then return end
    if whitelistedVehicle() then
        if not NpcData.Active then
            NpcData.CurrentNpc = math.random(1, #Config.NPCLocations.TakeLocations)
            if NpcData.LastNpc ~= nil then
                while NpcData.LastNpc ~= NpcData.CurrentNpc do
                    NpcData.CurrentNpc = math.random(1, #Config.NPCLocations.TakeLocations)
                end
            end

            local Gender = math.random(1, #Config.NpcSkins)
            local PedSkin = math.random(1, #Config.NpcSkins[Gender])
            local model = GetHashKey(Config.NpcSkins[Gender][PedSkin])
            RequestModel(model)
            while not HasModelLoaded(model) do Wait(0) end
            NpcData.Npc = CreatePed(3, model, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].x, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].y, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].z - 0.98, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].w, true, true)
            PlaceObjectOnGroundProperly(NpcData.Npc)
            FreezeEntityPosition(NpcData.Npc, true)
            if NpcData.NpcBlip ~= nil then
                RemoveBlip(NpcData.NpcBlip)
            end
            QBCore.Functions.Notify(Lang:t('info.npc_on_gps'), 'success')

            -- added checks to disable distance checking if polyzone option is used
            if Config.UseTarget then createNpcPickUpLocation() end

            NpcData.NpcBlip = AddBlipForCoord(Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].x, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].y, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].z)
            SetBlipColour(NpcData.NpcBlip, 3)
            SetBlipRoute(NpcData.NpcBlip, true)
            SetBlipRouteColour(NpcData.NpcBlip, 3)
            NpcData.LastNpc = NpcData.CurrentNpc
            NpcData.Active = true
            -- added checks to disable distance checking if polyzone option is used
            if not Config.UseTarget then
                CreateThread(function()
                    while not NpcData.NpcTaken and NpcData.Active do
                        local ped = PlayerPedId()
                        local pos = GetEntityCoords(ped)
                        local dist = #(pos - vector3(Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].x, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].y, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].z))

                        if dist < 25 then
                            DrawMarker(0, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].x, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].y, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].z + 1.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, 255, 0, 0, 255, 1, 0, 0, 1, 0, 0, 0)

                            if dist < 5 then
                                DrawText3D(Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].x, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].y, Config.NPCLocations.TakeLocations[NpcData.CurrentNpc].z, Lang:t('info.call_npc'))
                                if IsControlJustPressed(0, 38) then
                                    local veh = GetVehiclePedIsIn(ped, 0)
                                    local maxSeats, freeSeat = GetVehicleMaxNumberOfPassengers(veh)
                                
                                    for i = maxSeats - 1, 0, -1 do
                                        if IsVehicleSeatFree(veh, i) then
                                            freeSeat = i
                                            break
                                        end
                                    end
                                
                                    meterIsOpen = true
                                    meterActive = true
                                    lastLocation = GetEntityCoords(PlayerPedId())
                                    SendNUIMessage({
                                        action = 'openMeter',
                                        toggle = true,
                                        meterData = Config.Meter
                                    })
                                    SendNUIMessage({
                                        action = 'toggleMeter'
                                    })
                                    ClearPedTasksImmediately(NpcData.Npc)
                                    FreezeEntityPosition(NpcData.Npc, false)
                                
                                    -- Attempt to make NPC enter the vehicle
                                    local attempts = 0
                                    local maxAttempts = 5
                                    local npcInVehicle = false
                                
                                    while not npcInVehicle and attempts < maxAttempts do
                                        TaskEnterVehicle(NpcData.Npc, veh, -1, freeSeat, 1.0, 0)
                                        Citizen.Wait(2000)  -- Wait 2 seconds to see if NPC enters the vehicle
                                
                                        -- Check if NPC is in the vehicle
                                        if IsPedInVehicle(NpcData.Npc, veh, true) then
                                            npcInVehicle = true
                                            print("NPC successfully entered the vehicle")
                                        else
                                            attempts = attempts + 1
                                            print("NPC failed to enter the vehicle, attempt " .. attempts)
                                        end
                                    end
                                
                                    -- Handle case where NPC fails to enter after all attempts
                                    if not npcInVehicle then
                                        QBCore.Functions.Notify("NPC failed to enter the vehicle", "error")
                                        -- Optionally: Handle this scenario, e.g., by removing the NPC or resetting the script
                                    else
                                        listenForVehicleDamage()
                                        resetMeter()
                                        QBCore.Functions.Notify(Lang:t('info.go_to_location'))
                                        if NpcData.NpcBlip ~= nil then
                                            RemoveBlip(NpcData.NpcBlip)
                                        end
                                        GetDeliveryLocation()
                                        NpcData.NpcTaken = true
                                    end
                                end                                
                            end
                        end
                        Wait(1)
                    end
                end)
            end
        else
            QBCore.Functions.Notify(Lang:t('error.already_mission'))
        end
    else
        QBCore.Functions.Notify(Lang:t('error.not_in_taxi'))
    end
end)

RegisterNetEvent('qb-taxi:client:CancelTaxiNpc', function()
    if NpcData.Active then
        NpcData.Active = false
        NpcData.NpcTaken = false
        NpcData.CurrentNpc = nil
        NpcData.LastNpc = nil
        NpcData.CurrentDeliver = nil
        NpcData.LastDeliver = nil
        NpcData.CrashCount = 0

        if DoesEntityExist(NpcData.Npc) then
            SetEntityAsMissionEntity(NpcData.Npc, false, true)
            DeleteEntity(NpcData.Npc)
        end

        if NpcData.NpcBlip ~= nil then
            RemoveBlip(NpcData.NpcBlip)
        end
        if NpcData.DeliveryBlip ~= nil then
            RemoveBlip(NpcData.DeliveryBlip)
        end

        if meterActive then
            SendNUIMessage({
                action = 'resetMeter'
            })
            SendNUIMessage({
                action = 'toggleMeter'
            })
            meterActive = false
        end
    end
end)

RegisterNetEvent('qb-taxi:client:toggleMeter', function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        if whitelistedVehicle() then
            if not meterIsOpen and IsDriver() then
                SendNUIMessage({
                    action = 'openMeter',
                    toggle = true,
                    meterData = Config.Meter
                })
                meterIsOpen = true
            else
                SendNUIMessage({
                    action = 'openMeter',
                    toggle = false
                })
                meterIsOpen = false
            end
        else
            QBCore.Functions.Notify(Lang:t('error.missing_meter'), 'error')
        end
    else
        QBCore.Functions.Notify(Lang:t('error.no_vehicle'), 'error')
    end
end)

RegisterNetEvent('qb-taxi:client:enableMeter', function()
    if meterIsOpen then
        SendNUIMessage({
            action = 'toggleMeter'
        })
    else
        QBCore.Functions.Notify(Lang:t('error.not_active_meter'), 'error')
    end
end)

-- NUI Callbacks

RegisterNUICallback('enableMeter', function(data, cb)
    meterActive = data.enabled
    if not meterActive then resetMeter() end
    lastLocation = GetEntityCoords(PlayerPedId())
    cb('ok')
end)

-- Threads
CreateThread(function()
    local TaxiBlip = AddBlipForCoord(Config.Location)
    SetBlipSprite(TaxiBlip, 198)
    SetBlipDisplay(TaxiBlip, 4)
    SetBlipScale(TaxiBlip, 0.6)
    SetBlipAsShortRange(TaxiBlip, true)
    SetBlipColour(TaxiBlip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(Lang:t('info.blip_name'))
    EndTextCommandSetBlipName(TaxiBlip)
end)

CreateThread(function()
    while true do
        Wait(2000)
        calculateFareAmount()
    end
end)

CreateThread(function()
    while true do
        if not IsPedInAnyVehicle(PlayerPedId(), false) then
            if meterIsOpen then
                SendNUIMessage({
                    action = 'openMeter',
                    toggle = false
                })
                meterIsOpen = false
            end
        end
        Wait(200)
    end
end)

RegisterNetEvent('qb-taxijob:client:requestcab', function()
    TaxiGarage()
end)

-- added checks to disable distance checking if polyzone option is used
CreateThread(function()
    while true do
        if not Config.UseTarget then
            local inRange = false
            if LocalPlayer.state.isLoggedIn then
                local Player = QBCore.Functions.GetPlayerData()
                if Player.job.name == jobRequired then
                    local ped = PlayerPedId()
                    local pos = GetEntityCoords(ped)
                    local vehDist = #(pos - vector3(Config.parkLocation.x, Config.parkLocation.y, Config.parkLocation.z))
                    if vehDist < 30 then
                        inRange = true
                        DrawMarker(2, Config.parkLocation.x, Config.parkLocation.y, Config.parkLocation.z, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.3, 0.5, 0.2, 200, 0, 0, 222, false, false, false, true, false, false, false)
                        if vehDist < 1.5 then
                            if whitelistedVehicle() then
                                DrawText3D(Config.parkLocation.x, Config.parkLocation.y, Config.parkLocation.z + 0.3, Lang:t('info.vehicle_parking'))
                                if IsControlJustReleased(0, 38) then
                                    if IsPedInAnyVehicle(PlayerPedId(), false) then
                                        local vehicle = GetVehiclePedIsIn(PlayerPedId())
                                        DeleteVehicle(vehicle)
                                        playerVehicle = nil -- Reset the vehicle identifier after deletion
                                    end
                                end
                            else
                                DrawText3D(Config.parkLocation.x, Config.parkLocation.y, Config.parkLocation.z + 0.3, Lang:t('info.job_vehicles'))
                                if IsControlJustReleased(0, 38) then
                                    if PlayerJob.onduty then
                                        TaxiGarage()
                                    else
                                        QBCore.Functions.Notify('You need to be on duty', 'error')
                                    end
                                end
                            end
                        end
                    end
                end
            end
            if not inRange then
                Wait(3000)
            end
        end
        Wait(3)
    end
end)

-- POLY & TARGET Conversion code

-- setup qb-target
function setupTarget()
    CreateThread(function()
        exports['qb-target']:SpawnPed({
            model = 'a_m_m_indian_01',
            coords = vector4(901.34, -170.06, 74.08, 228.81),
            minusOne = true,
            freeze = true,
            invincible = true,
            blockevents = true,
            animDict = 'abigail_mcs_1_concat-0',
            anim = 'csb_abigail_dual-0',
            flag = 1,
            scenario = 'WORLD_HUMAN_AA_COFFEE',
            target = {
                options = {
                    {
                        type = 'client',
                        event = 'qb-taxijob:client:requestcab',
                        icon = 'fas fa-sign-in-alt',
                        label = '🚕 Request Taxi Cab',
                        job = jobRequired,
                    }
                },
                distance = 2.5,
            },
            spawnNow = true,
            currentpednumber = 0,
        })
    end)
end

local zone
local deliveryZone

function createNpcPickUpLocation()
    zone = BoxZone:Create(Config.PZLocations.TakeLocations[NpcData.CurrentNpc].coord, Config.PZLocations.TakeLocations[NpcData.CurrentNpc].height, Config.PZLocations.TakeLocations[NpcData.CurrentNpc].width, {
        heading = Config.PZLocations.TakeLocations[NpcData.CurrentNpc].heading,
        debugPoly = false,
        minZ = Config.PZLocations.TakeLocations[NpcData.CurrentNpc].minZ,
        maxZ = Config.PZLocations.TakeLocations[NpcData.CurrentNpc].maxZ,
    })

    zone:onPlayerInOut(function(isPlayerInside)
        if isPlayerInside then
            if whitelistedVehicle() and not isInsidePickupZone and not NpcData.NpcTaken then
                isInsidePickupZone = true
                exports['qb-core']:DrawText(Lang:t('info.call_npc'), Config.DefaultTextLocation)
                callNpcPoly()
            end
        else
            isInsidePickupZone = false
        end
    end)
end

function createNpcDelieveryLocation()
    deliveryZone = BoxZone:Create(Config.PZLocations.DropLocations[NpcData.CurrentDeliver].coord, Config.PZLocations.DropLocations[NpcData.CurrentDeliver].height, Config.PZLocations.DropLocations[NpcData.CurrentDeliver].width, {
        heading = Config.PZLocations.DropLocations[NpcData.CurrentDeliver].heading,
        debugPoly = false,
        minZ = Config.PZLocations.DropLocations[NpcData.CurrentDeliver].minZ,
        maxZ = Config.PZLocations.DropLocations[NpcData.CurrentDeliver].maxZ,
    })

    deliveryZone:onPlayerInOut(function(isPlayerInside)
        if isPlayerInside then
            if whitelistedVehicle() and not isInsideDropZone and NpcData.NpcTaken then
                isInsideDropZone = true
                exports['qb-core']:DrawText(Lang:t('info.drop_off_npc'), Config.DefaultTextLocation)
                dropNpcPoly()
            end
        else
            isInsideDropZone = false
        end
    end)
end

function callNpcPoly()
    CreateThread(function()
        while not NpcData.NpcTaken do
            local ped = PlayerPedId()
            if isInsidePickupZone then
                if IsControlJustPressed(0, 38) then
                    exports['qb-core']:KeyPressed()
                    local veh = GetVehiclePedIsIn(ped, false)
                    local maxSeats, freeSeat = GetVehicleMaxNumberOfPassengers(veh)

                    for i = maxSeats - 1, 0, -1 do
                        if IsVehicleSeatFree(veh, i) then
                            freeSeat = i
                            break
                        end
                    end

                    meterIsOpen = true
                    meterActive = true
                    lastLocation = GetEntityCoords(PlayerPedId())
                    SendNUIMessage({
                        action = 'openMeter',
                        toggle = true,
                        meterData = Config.Meter
                    })
                    SendNUIMessage({
                        action = 'toggleMeter'
                    })
                    ClearPedTasksImmediately(NpcData.Npc)
                    FreezeEntityPosition(NpcData.Npc, false)
                    TaskEnterVehicle(NpcData.Npc, veh, -1, freeSeat, 1.0, 0)
                    listenForVehicleDamage()
                    resetMeter()
                    QBCore.Functions.Notify(Lang:t('info.go_to_location'))
                    if NpcData.NpcBlip ~= nil then
                        RemoveBlip(NpcData.NpcBlip)
                    end
                    GetDeliveryLocation()
                    NpcData.NpcTaken = true
                    createNpcDelieveryLocation()
                    zone:destroy()
                end
            end
            Wait(1)
        end
    end)
end

function dropNpcPoly()
    CreateThread(function()
        while NpcData.NpcTaken do
            local ped = PlayerPedId()
            if isInsideDropZone then
                if IsControlJustPressed(0, 38) then
                    exports['qb-core']:KeyPressed()
                    local veh = GetVehiclePedIsIn(ped, 0)
                    TaskLeaveVehicle(NpcData.Npc, veh, 0)
                    SetEntityAsMissionEntity(NpcData.Npc, false, true)
                    SetEntityAsNoLongerNeeded(NpcData.Npc)
                    local targetCoords = Config.NPCLocations.TakeLocations[NpcData.LastNpc]
                    TaskGoStraightToCoord(NpcData.Npc, targetCoords.x, targetCoords.y, targetCoords.z, 1.0, -1, 0.0, 0.0)
                    SendNUIMessage({
                        action = 'toggleMeter'
                    })
                    TriggerServerEvent('qb-taxi:server:NpcPay', meterData.currentFare, NpcData.CrashCount == 0)
                    PlayPedAmbientSpeechNative(NpcData.Npc, NpcData.CrashCount == 0 and Config.Advanced.Speech.Happy or Config.Advanced.Speech.Grateful, 'SPEECH_PARAMS_ALLOW_REPEAT')
                    meterActive = false
                    SendNUIMessage({
                        action = 'resetMeter'
                    })
                    QBCore.Functions.Notify(Lang:t('info.person_was_dropped_off'), 'success')
                    if NpcData.DeliveryBlip ~= nil then
                        RemoveBlip(NpcData.DeliveryBlip)
                    end
                    local RemovePed = function(p)
                        SetTimeout(60000, function()
                            DeletePed(p)
                        end)
                    end
                    RemovePed(NpcData.Npc)
                    ResetNpcTask()
                    deliveryZone:destroy()
                    break
                end
            end
            Wait(1)
        end
    end)
end

function setupCabParkingLocation()
    local taxiParking = BoxZone:Create(vector3(908.62, -173.82, 74.51), 11.0, 38.2, {
        name = 'qb-taxi',
        heading = 55,
        --debugPoly=true
    })

    taxiParking:onPlayerInOut(function(isPlayerInside)
        if isPlayerInside and not Notified and Config.UseTarget then
            if whitelistedVehicle() then
                exports['qb-core']:DrawText(Lang:t('info.vehicle_parking'), Config.DefaultTextLocation)
                Notified = true
                isPlayerInsideZone = true
            end
        else
            exports['qb-core']:HideText()
            Notified = false
            isPlayerInsideZone = false
        end
    end)
end

-- thread to handle vehicle parking
CreateThread(function()
    while true do
        if isPlayerInsideZone then
            if IsControlJustReleased(0, 38) then
                exports['qb-core']:KeyPressed()
                if IsPedInAnyVehicle(PlayerPedId(), false) then
                    local ped = PlayerPedId()
                    local vehicle = GetVehiclePedIsIn(ped, false)
                    if meterIsOpen then
                        TriggerEvent('qb-taxi:client:toggleMeter')
                        meterActive = false
                    end
                    TaskLeaveVehicle(PlayerPedId(), vehicle, 0)
                    Wait(2000) -- 2 second delay just to ensure the player is out of the vehicle
                    DeleteVehicle(vehicle)
                    QBCore.Functions.Notify(Lang:t('info.taxi_returned'), 'success')
                end
            end
        end
        Wait(1)
    end
end)