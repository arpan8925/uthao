QBCore = exports['qb-core']:GetCoreObject()


local function SpawnBossPed(index)
    local model = GetHashKey(Config.BossPed[index].model)
    local coords = Config.BossPed[index].coords
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(0)
    end
    local groundZ
    local foundGround, zPos = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z, 0)
    if foundGround then
        groundZ = zPos
    else
        groundZ = coords.z 
    end
    local entity = CreatePed(0, model, coords.x, coords.y, groundZ, coords.w, true, false)

    FreezeEntityPosition(entity, true)
    SetEntityInvincible(entity, true)
    SetBlockingOfNonTemporaryEvents(entity, true)

    SetModelAsNoLongerNeeded(model)

    return entity
end

local function ondutymenu()
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
        lib.showContext('boss_menu')
    end)
end

-- Function to register and open the boss menu
local function startjobmenu()
    lib.registerContext({
        id = 'boss_menu',
        title = 'Boss Menu',
        options = {
            {
                title = "Start Job",
                description = "Start Doing Uthao Job",
                icon = 'fa-solid fa-car',
                onSelect = function()
                    print("Blip Marked")
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
    lib.showContext('boss_menu')
end


local bossped function SpawnAndSetupBossPeds()
    -- Spawn the first Ped (Taxi Boss)
    local bossPedEntity1 = SpawnBossPed(1)
    exports.ox_target:addLocalEntity(bossPedEntity1, {
        name = "boss_target_1",
        label = 'On Duty Boss',
        icon = 'fa-solid fa-pen',
        onSelect = function ()
            ondutymenu()
        end 
    })

    -- Spawn the second Ped (Another Boss, you can customize the function as needed)
    local bossPedEntity2 = SpawnBossPed(2)  -- You can use a different function if you want a different Ped
    exports.ox_target:addLocalEntity(bossPedEntity2, {
        name = "boss_target_2",
        label = 'Start Job',
        icon = 'fa-solid fa-pen',
        onSelect = function ()
            startjobmenu()  -- You can use a different menu function if required
        end 
    })

end

-- Return the SpawnAndSetupBossPeds function to be callable externally
return {
    SpawnAndSetupBossPeds = SpawnAndSetupBossPeds
}