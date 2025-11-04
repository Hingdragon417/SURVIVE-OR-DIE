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
    -- Server-side debounce
    local lockKey = player.UserId .. "_" .. abilityName
    if AbilitiesService._purchaseLocks[lockKey] then
        print(player.Name, "tried to purchase", abilityName, "but it's locked")
        return false, "Purchase in progress"
    end
    
    AbilitiesService._purchaseLocks[lockKey] = true
    
    -- Validate ability exists
    local abilityData = AbilitiesEnums[abilityName]
    if not abilityData then
        AbilitiesService._purchaseLocks[lockKey] = false
        return false, "Invalid ability"
    end

    -- Get player data
    local session = DataService.getSession(player)
    if not session or not session.Data then
        AbilitiesService._purchaseLocks[lockKey] = false
        return false, "Data not found"
    end
    
    local data = session.Data
    
    -- Find current total quantity of this ability across all slots
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
    
    print(string.format("[AbilitiesService] %s purchasing %s - current: %d, max: %d", 
        player.Name, abilityName, currentAmount, abilityData.MaxAmount))

    -- Check if player has reached max amount
    if currentAmount >= abilityData.MaxAmount then
        AbilitiesService._purchaseLocks[lockKey] = false
        return false, "Maximum amount reached"
    end

    -- Check if player has enough cash
    if data.Cash < abilityData.Price then
        AbilitiesService._purchaseLocks[lockKey] = false
        return false, "Not enough cash"
    end
    
    -- Check if we have an available slot
    if not availableSlot then
        AbilitiesService._purchaseLocks[lockKey] = false
        return false, "No available slots"
    end

    -- Purchase the ability
    data.Cash -= abilityData.Price
    
    -- Add to existing slot or new slot
    if data.Abilities[availableSlot].Name == abilityName then
        data.Abilities[availableSlot].Quantity += 1
        print(string.format("[AbilitiesService] Added to %s, new quantity: %d", availableSlot, data.Abilities[availableSlot].Quantity))
    else
        data.Abilities[availableSlot].Name = abilityName
        data.Abilities[availableSlot].Quantity = 1
        print(string.format("[AbilitiesService] Created new in %s with quantity: 1", availableSlot))
    end
    
    -- Debug: Print all slots after purchase
    print("[AbilitiesService] All slots after purchase:")
    for _, slotName in pairs({"Slot1", "Slot2", "Slot3"}) do
        local slot = data.Abilities[slotName]
        print(string.format("  %s: Name=%s, Quantity=%d", slotName, slot.Name, slot.Quantity))
    end
    
    -- Replicate the changes to the client
    DataService:Replicate(player, {"Cash", "Abilities"})
    
    -- Small delay before unlocking to prevent rapid purchases
    task.delay(0.1, function()
        AbilitiesService._purchaseLocks[lockKey] = false
    end)

    return true, "Purchase successful"
end

function AbilitiesService:KnitInit() 
    DataService = Knit.GetService("DataService")
end

function AbilitiesService:KnitStart()
    -- Wait for DataService to be ready
    while not DataService do
        task.wait()
    end
    print("AbilitiesService started with DataService")
end

return AbilitiesService
