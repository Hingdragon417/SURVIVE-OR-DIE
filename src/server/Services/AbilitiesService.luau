local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Assets = ReplicatedStorage.Assets
local Shared = ReplicatedStorage.Shared

local Knit = require(Packages.Knit)
local AbilitiesEnums = require(Shared.Data.AbilitiesEnums)

local DataService

local AbilitiesService = Knit.CreateService({
    Name = "AbilitiesService",
    Client = {
        PurchaseAbility = "PurchaseAbility",
    },
    _purchaseLocks = {},
})

function AbilitiesService.Client:PurchaseAbility(player: Player, abilityName: string)
    local lockKey = player.UserId .. "_" .. abilityName
    if AbilitiesService._purchaseLocks[lockKey] then
        return false, "Purchase in progress"
    end
    
    AbilitiesService._purchaseLocks[lockKey] = true
    
    local abilityData = AbilitiesEnums[abilityName]
    if not abilityData then
        AbilitiesService._purchaseLocks[lockKey] = false
        return false, "Invalid ability"
    end

    local session = DataService.getSession(player)
    if not session or not session.Data then
        AbilitiesService._purchaseLocks[lockKey] = false
        return false, "Data not found"
    end
    
    local data = session.Data
    
    local currentAmount = 0
    local availableSlot = nil
    
    for _, slotName in pairs({"Slot1", "Slot2", "Slot3"}) do
        local slot = data.Abilities[slotName]
        if slot.Name == abilityName then
            currentAmount += slot.Quantity
            if not availableSlot then
                availableSlot = slotName
            end
        elseif slot.Name == "" and not availableSlot then
            availableSlot = slotName
        end
    end

    if currentAmount >= abilityData.MaxAmount then
        AbilitiesService._purchaseLocks[lockKey] = false
        return false, "Maximum amount reached"
    end

    if data.Cash < abilityData.Price then
        AbilitiesService._purchaseLocks[lockKey] = false
        return false, "Not enough cash"
    end
    
    if not availableSlot then
        AbilitiesService._purchaseLocks[lockKey] = false
        return false, "No available slots"
    end

    data.Cash -= abilityData.Price
    
    if data.Abilities[availableSlot].Name == abilityName then
        data.Abilities[availableSlot].Quantity += 1
    else
        data.Abilities[availableSlot].Name = abilityName
        data.Abilities[availableSlot].Quantity = 1
    end
    
    DataService:Replicate(player, {"Cash", "Abilities"})
    
    task.delay(0.1, function()
        AbilitiesService._purchaseLocks[lockKey] = false
    end)

    return true, "Purchase successful"
end

function AbilitiesService:KnitInit() 
    DataService = Knit.GetService("DataService")
end

function AbilitiesService:KnitStart()
    while not DataService do
        task.wait()
    end
end

return AbilitiesService
