local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
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

local SLOT_ORDER = {"Slot1", "Slot2", "Slot3"}

local function ensureOwnedTable(data)
	data.OwnedSurvivorPerks = data.OwnedSurvivorPerks or {}
	for _, slotName in ipairs(SLOT_ORDER) do
		local slot = data.SurvivorPerks and data.SurvivorPerks[slotName]
		if slot and slot.Name ~= "" then
			data.OwnedSurvivorPerks[slot.Name] = true
		end
	end
	return data.OwnedSurvivorPerks
end

local function getEquippedMana(data)
	local total = 0
	for _, slotName in ipairs(SLOT_ORDER) do
		local slot = data.SurvivorPerks and data.SurvivorPerks[slotName]
		local perkData = slot and SurvivorPerks[slot.Name]
		if perkData then
			total += perkData.ManaCost or 1
		end
	end
	return total
end

local function findEquippedSlot(data, perkName)
	for _, slotName in ipairs(SLOT_ORDER) do
		local slot = data.SurvivorPerks and data.SurvivorPerks[slotName]
		if slot and slot.Name == perkName then
			return slotName
		end
	end
	return nil
end

local function findEmptySlot(data)
	for _, slotName in ipairs(SLOT_ORDER) do
		local slot = data.SurvivorPerks and data.SurvivorPerks[slotName]
		if slot and slot.Name == "" then
			return slotName
		end
	end
	return nil
end

function SurvivorPerksService:GetEquippedSurvivorPerkMana(playerData)
	if not playerData or not playerData.SurvivorPerks then
		return 0
	end

	return getEquippedMana(playerData)
end

function SurvivorPerksService.Client:PurchaseSurvivorPerk(player: Player, perkName: string)
	local lockKey = player.UserId .. "_" .. perkName
	if SurvivorPerksService._purchaseLocks[lockKey] then
		return false, "Purchase in progress"
	end

	SurvivorPerksService._purchaseLocks[lockKey] = true

	local perkData = SurvivorPerks[perkName]
	if not perkData then
		SurvivorPerksService._purchaseLocks[lockKey] = false
		return false, "Invalid perk"
	end

	local session = DataService.getSession(player)
	if not session or not session.Data then
		SurvivorPerksService._purchaseLocks[lockKey] = false
		return false, "Data not found"
	end

	local data = session.Data
	local ownedPerks = ensureOwnedTable(data)
	local equippedSlot = findEquippedSlot(data, perkName)

	if equippedSlot then
		data.SurvivorPerks[equippedSlot].Name = ""
		data.SurvivorPerks[equippedSlot].Quantity = 0
		DataService:Replicate(player, {"SurvivorPerks"})
		SurvivorPerksService._purchaseLocks[lockKey] = false
		return true, "Unequipped"
	end

	if not ownedPerks[perkName] then
		if data.Coins < perkData.Price then
			SurvivorPerksService._purchaseLocks[lockKey] = false
			return false, "Not enough coins"
		end

		data.Coins -= perkData.Price
		ownedPerks[perkName] = true
		DataService:Replicate(player, {"Coins", "OwnedSurvivorPerks"})
		SurvivorPerksService._purchaseLocks[lockKey] = false
		return true, "Purchased"
	end

	local availableSlot = findEmptySlot(data)
	if not availableSlot then
		DataService:Replicate(player, {"Coins", "OwnedSurvivorPerks"})
		SurvivorPerksService._purchaseLocks[lockKey] = false
		return false, "No available slots"
	end

	local maxMana = data.MaxSurvivorPerkMana or 3
	local nextMana = getEquippedMana(data) + (perkData.ManaCost or 1)
	if nextMana > maxMana then
		DataService:Replicate(player, {"Coins", "OwnedSurvivorPerks"})
		SurvivorPerksService._purchaseLocks[lockKey] = false
		return false, "Not enough perk mana"
	end

	data.SurvivorPerks[availableSlot].Name = perkName
	data.SurvivorPerks[availableSlot].Quantity = 1

	DataService:Replicate(player, {"Coins", "SurvivorPerks", "OwnedSurvivorPerks"})
	SurvivorPerksService._purchaseLocks[lockKey] = false
	return true, "Equipped"
end

function SurvivorPerksService:KnitInit()
	DataService = Knit.GetService("DataService")
end

return SurvivorPerksService
