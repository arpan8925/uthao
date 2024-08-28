local QBCore = exports['qb-core']:GetCoreObject()

function NearTaxi(src)
    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    for _, v in pairs(Config.NPCLocations.DeliverLocations) do
        local dist = #(coords - vector3(v.x, v.y, v.z))
        if dist < 20 then
            return true
        end
    end
end

QBCore.Functions.CreateCallback('custom:CheckDutyStatus', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    local isOnDuty = Player.PlayerData.job.onduty

    cb(isOnDuty)
end)

RegisterServerEvent('custom:ToggleDuty', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    Player.Functions.SetJobDuty(not Player.PlayerData.job.onduty)

    -- Do not send a notification here
end)

QBCore.Functions.CreateCallback('custom:CheckDriverLicense', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    local hasLicense = Player.Functions.GetItemByName('driver_license')

    if hasLicense then
        cb(true)
    else
        cb(false)
    end
end)

RegisterNetEvent('qb-taxi:server:NpcPay', function(payment, hasReceivedBonus)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if Player.PlayerData.job.name == Config.jobRequired then
        if NearTaxi(src) then
            local randomAmount = math.random(1, 5)
            local r1, r2 = math.random(1, 5), math.random(1, 5)
            if randomAmount == r1 or randomAmount == r2 then 
                payment = payment + math.random(10, 20) 
            end

            if Config.Advanced.Bonus.Enabled then
                local tipAmount = math.floor(payment * Config.Advanced.Bonus.Percentage / 100)

                payment = payment + tipAmount
                if hasReceivedBonus then
                    TriggerClientEvent('QBCore:Notify', src, string.format(Lang:t('info.tip_received'), tipAmount), 'primary', 5000)
                else
                    TriggerClientEvent('QBCore:Notify', src, Lang:t('info.tip_not_received'), 'primary', 5000)
                end
            end

            if Config.Management then
                exports['qb-banking']:AddMoney('taxi', payment, 'Customer payment')
            else
                Player.Functions.AddMoney('cash', payment, 'Taxi payout')
            end

            local chance = math.random(1, 100)
            if chance < 26 then
                exports['qb-inventory']:AddItem(src, 'cryptostick', 1, false, false, 'qb-taxi:server:NpcPay')
                TriggerClientEvent('qb-inventory:client:ItemBox', src, QBCore.Shared.Items['cryptostick'], 'add')
            end

            Citizen.Wait(100)  -- Brief pause before starting the next NPC task
            TriggerClientEvent('qb-taxi:client:DoTaxiNpc', src)  -- Start the next task for the player

        else
            DropPlayer(src, 'Attempting To Exploit')
        end
    else
        DropPlayer(src, 'Attempting To Exploit')
    end
end)


-- Server-side event to charge the player $1000 for renting a vehicle
RegisterNetEvent('custom:ChargeForRental')
AddEventHandler('custom:ChargeForRental', function(data)
    local src = source
    local xPlayer = QBCore.Functions.GetPlayer(src)
    local amountToCharge = 1000
    local bankBalance = xPlayer.PlayerData.money['bank']
    local cashBalance = xPlayer.PlayerData.money['cash']

    if bankBalance >= amountToCharge then
        -- Charge from bank account
        xPlayer.Functions.RemoveMoney('bank', amountToCharge, "Vehicle rental")
        TriggerClientEvent('custom:ChargeForRentalResult', src, true, data)
    elseif cashBalance >= amountToCharge then
        -- Charge from cash if bank doesn't have enough
        xPlayer.Functions.RemoveMoney('cash', amountToCharge, "Vehicle rental")
        TriggerClientEvent('custom:ChargeForRentalResult', src, true, data)
    else
        -- Insufficient funds
        TriggerClientEvent('custom:ChargeForRentalResult', src, false)
    end
end)


-- Server-side event to credit $750 to the player's bank account
RegisterNetEvent('custom:CreditForVehicleReturn')
AddEventHandler('custom:CreditForVehicleReturn', function()
    local src = source
    local xPlayer = QBCore.Functions.GetPlayer(src)
    local creditAmount = 750

    xPlayer.Functions.AddMoney('bank', creditAmount, "Vehicle returned")
    TriggerClientEvent('QBCore:Notify', src, 'You have been credited $750 for returning the vehicle.', 'success')
end)




QBCore = exports['qb-core']:GetCoreObject()

QBCore.Functions.CreateCallback('whitelistedVehicle:getOwnedVehicles', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if Player then
        local citizenId = Player.PlayerData.citizenid
        exports.oxmysql:fetch("SELECT vehicle, plate FROM player_vehicles WHERE citizenid = ?", {citizenId}, function(result)
            local ownedVehicles = {}
            for _, v in pairs(result) do
                table.insert(ownedVehicles, {model = v.vehicle, plate = v.plate})
            end
            cb(ownedVehicles)
        end)
    else
        cb({})
    end
end)




