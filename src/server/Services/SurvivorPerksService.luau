local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Assets = ReplicatedStorage.Assets
local Shared = ReplicatedStorage.Shared

local Knit = require(Packages.Knit)
local SurvivorPerks = require(Shared.Data.SurvivorPerks)

local DataService

local SurvivorPerksService = Knit.CreateService({
    Name = "SurvivorPerksService",
    Client = {
        PurchaseSurvivorPerk = "PurchaseSurvivorPerk",
    },
    _purchaseLocks = {},
})

function SurvivorPerksService.Client:PurchaseSurvivorPerk(player: Player, perkName: string)
    local lockKey = player.UserId .. "_" .. perkName
    if SurvivorPerksService._purchaseLocks[lockKey] then
        return false, "Purchase in progress"
    end
    
    SurvivorPerksService._purchaseLocks[lockKey] = true
    
    local abilityData = SurvivorPerks[perkName]
    if not abilityData then
        SurvivorPerksService._purchaseLocks[lockKey] = false
        return false, "Invalid ability"
    end

    local session = DataService.getSession(player)
    if not session or not session.Data then
        SurvivorPerksService._purchaseLocks[lockKey] = false
        return false, "Data not found"
    end
    
    local data = session.Data
    
    local currentAmount = 0
    local availableSlot = nil
    
    for _, slotName in pairs({"Slot1", "Slot2", "Slot3"}) do
        local slot = data.SurvivorPerks[slotName]
        if slot.Name == perkName then
            currentAmount += slot.Quantity
            if not availableSlot then
                availableSlot = slotName
            end
        elseif slot.Name == "" and not availableSlot then
            availableSlot = slotName
        end
    end

    if currentAmount >= abilityData.MaxAmount then
        SurvivorPerksService._purchaseLocks[lockKey] = false
        return false, "Maximum amount reached"
    end

    if data.Cash < abilityData.Price then
        SurvivorPerksService._purchaseLocks[lockKey] = false
        return false, "Not enough cash"
    end
    
    if not availableSlot then
        SurvivorPerksService._purchaseLocks[lockKey] = false
        return false, "No available slots"
    end

    data.Cash -= abilityData.Price
    
    if data.SurvivorPerks[availableSlot].Name == perkName then
        data.SurvivorPerks[availableSlot].Quantity += 1
    else
        data.SurvivorPerks[availableSlot].Name = perkName
        data.SurvivorPerks[availableSlot].Quantity = 1
    end
    
    DataService:Replicate(player, {"Cash", "SurvivorPerks"})
    
    task.delay(0.1, function()
        SurvivorPerksService._purchaseLocks[lockKey] = false
    end)

    return true, "Purchase successful"
end

function SurvivorPerksService:KnitInit() 
    DataService = Knit.GetService("DataService")
end

function SurvivorPerksService:KnitStart()
    while not DataService do
        task.wait()
    end
end

return SurvivorPerksService
