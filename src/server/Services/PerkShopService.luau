local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages

local Knit = require(Packages.Knit)
local KillerPerks = require(ReplicatedStorage.Shared.Data.KillerPerks)

local DataService

local ShopService = Knit.CreateService({
	Name = "ShopService",
	Client = {
		PurchasePerk = "PurchasePerk",
	},
})

local SLOT_ORDER = {"Slot1", "Slot2", "Slot3"}

local function ensureOwnedTable(data)
	data.OwnedKillerPerks = data.OwnedKillerPerks or {}
	for _, slotName in ipairs(SLOT_ORDER) do
		local slot = data.Perks and data.Perks[slotName]
		if slot and slot.Name ~= "" then
			data.OwnedKillerPerks[slot.Name] = true
		end
	end
	return data.OwnedKillerPerks
end

local function getEquippedMana(data)
	local total = 0
	for _, slotName in ipairs(SLOT_ORDER) do
		local slot = data.Perks and data.Perks[slotName]
		local perkData = slot and KillerPerks[slot.Name]
		if perkData then
			total += perkData.ManaCost or 1
		end
	end
	return total
end

local function findEquippedSlot(data, perkName)
	for _, slotName in ipairs(SLOT_ORDER) do
		local slot = data.Perks and data.Perks[slotName]
		if slot and slot.Name == perkName then
			return slotName
		end
	end
	return nil
end

local function findEmptySlot(data)
	for _, slotName in ipairs(SLOT_ORDER) do
		local slot = data.Perks and data.Perks[slotName]
		if slot and slot.Name == "" then
			return slotName
		end
	end
	return nil
end

function ShopService:GetEquippedKillerPerkMana(playerData)
	if not playerData or not playerData.Perks then
		return 0
	end

	return getEquippedMana(playerData)
end

function ShopService.Client:PurchasePerk(player, perkName)
	local session = DataService.getSession(player)
	if not session or not session.Data then
		return false, "No player data found"
	end

	local perkData = KillerPerks[perkName]
	if not perkData then
		return false, "Perk not found"
	end

	local data = session.Data
	local ownedPerks = ensureOwnedTable(data)
	local equippedSlot = findEquippedSlot(data, perkName)

	if equippedSlot then
		data.Perks[equippedSlot].Name = ""
		data.Perks[equippedSlot].Quantity = 0
		DataService:Replicate(player, {"Perks"})
		return true, "Unequipped"
	end

	if not ownedPerks[perkName] then
		if data.Coins < perkData.Price then
			return false, "Not enough coins"
		end

		data.Coins -= perkData.Price
		ownedPerks[perkName] = true
		DataService:Replicate(player, {"Coins", "OwnedKillerPerks"})
		return true, "Purchased"
	end

	local availableSlot = findEmptySlot(data)
	if not availableSlot then
		DataService:Replicate(player, {"Coins", "OwnedKillerPerks"})
		return false, "No available perk slots"
	end

	local maxMana = data.MaxKillerPerkMana or 3
	local nextMana = getEquippedMana(data) + (perkData.ManaCost or 1)
	if nextMana > maxMana then
		DataService:Replicate(player, {"Coins", "OwnedKillerPerks"})
		return false, "Not enough perk mana"
	end

	data.Perks[availableSlot].Name = perkName
	data.Perks[availableSlot].Quantity = 1

	DataService:Replicate(player, {"Coins", "Perks", "OwnedKillerPerks"})
	return true, "Equipped"
end

function ShopService:KnitInit()
	DataService = Knit.GetService("DataService")
end

return ShopService
