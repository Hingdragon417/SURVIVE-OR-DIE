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

function SurvivorPerksService:GetEquippedSurvivorPerksCount(playerData)
    if not playerData or not playerData.SurvivorPerks then
        return 0
    end
    
    local count = 0
    for _, slotName in pairs({"Slot1", "Slot2", "Slot3"}) do
        local slot = playerData.SurvivorPerks[slotName]
        if slot and slot.Name ~= "" then
            count = count + 1
        end
    end
    
    return count
end

function SurvivorPerksService:GetUniqueSurvivorPerks(playerData)
    if not playerData or not playerData.SurvivorPerks then
        return {}
    end
    
    local uniquePerks = {}
    for _, slotName in pairs({"Slot1", "Slot2", "Slot3"}) do
        local slot = playerData.SurvivorPerks[slotName]
        if slot and slot.Name ~= "" then
            uniquePerks[slot.Name] = true
        end
    end
    
    return uniquePerks
end

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

    if data.Coins < abilityData.Price then
        SurvivorPerksService._purchaseLocks[lockKey] = false
        return false, "Not enough coins"
    end
    
    if not availableSlot then
        -- Check if player has reached the limit of 3 slots
        local equippedCount = self.Server:GetEquippedSurvivorPerksCount(data)
        if equippedCount >= 3 then
            SurvivorPerksService._purchaseLocks[lockKey] = false
            return false, "Maximum abilities reached (3/3)"
        else
            SurvivorPerksService._purchaseLocks[lockKey] = false
            return false, "No available slots"
        end
    end

    data.Coins -= abilityData.Price
    
    if data.SurvivorPerks[availableSlot].Name == perkName then
        data.SurvivorPerks[availableSlot].Quantity += 1
    else
        data.SurvivorPerks[availableSlot].Name = perkName
        data.SurvivorPerks[availableSlot].Quantity = 1
    end
    
    DataService:Replicate(player, {"Coins", "SurvivorPerks"})
    
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
