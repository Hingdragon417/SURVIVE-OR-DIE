local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Packages = ReplicatedStorage.Packages

local Knit = require(Packages.Knit)
local KillerPerks = require(ReplicatedStorage.Shared.Data.KillerPerks)

local DataService

local ShopService = Knit.CreateService({
	Name = "ShopService",
	Client = {
		PurchasePerk = "PurchasePerk"
	}
})

function ShopService:GenerateShopItems()
	local shopItems = {}
	local maxItems = 3
	local availablePerks = {}

	for perkName, perkData in pairs(KillerPerks) do
		table.insert(availablePerks, { name = perkName, data = perkData })
	end

	local maxAttempts, attempts = 100, 0
	while #shopItems < maxItems and attempts < maxAttempts do
		attempts += 1
		for _, perk in pairs(availablePerks) do
			if #shopItems >= maxItems then break end
			local alreadySelected = false
			for _, selectedItem in pairs(shopItems) do
				if selectedItem.name == perk.name then
					alreadySelected = true
					break
				end
			end
			if not alreadySelected then
				if math.random(1, 100) <= perk.data.Chance then
					table.insert(shopItems, perk)
				end
			end
		end
	end

	if #shopItems < maxItems then
		local unselectedPerks = {}
		for _, perk in pairs(availablePerks) do
			local alreadySelected = false
			for _, selectedItem in pairs(shopItems) do
				if selectedItem.name == perk.name then
					alreadySelected = true
					break
				end
			end
			if not alreadySelected then
				table.insert(unselectedPerks, perk)
			end
		end
		
		for i = #unselectedPerks, 2, -1 do
			local j = math.random(i)
			unselectedPerks[i], unselectedPerks[j] = unselectedPerks[j], unselectedPerks[i]
		end
		
		local remainingSlots = maxItems - #shopItems
		for i = 1, math.min(remainingSlots, #unselectedPerks) do
			table.insert(shopItems, unselectedPerks[i])
		end
	end

	return shopItems
end

function ShopService:GetEquippedKillerPerksCount(playerData)
	if not playerData or not playerData.Perks then
		return 0
	end
	
	local count = 0
	for _, slotName in pairs({"Slot1", "Slot2", "Slot3"}) do
		local slot = playerData.Perks[slotName]
		if slot and slot.Name ~= "" then
			count = count + 1
		end
	end
	
	return count
end

function ShopService:GetUniqueKillerPerks(playerData)
	if not playerData or not playerData.Perks then
		return {}
	end
	
	local uniquePerks = {}
	for _, slotName in pairs({"Slot1", "Slot2", "Slot3"}) do
		local slot = playerData.Perks[slotName]
		if slot and slot.Name ~= "" then
			uniquePerks[slot.Name] = true
		end
	end
	
	return uniquePerks
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

	local currentStock = session.Data.Shop[perkName]
	if not currentStock or currentStock <= 0 then
		return false, "Out of stock or not available"
	end

	if session.Data.Coins < perkData.Price then
		return false, "Not enough coins"
	end

	local availableSlot = nil
	-- First check if player already has this perk and can add more
	for _, slot in pairs({"Slot1", "Slot2", "Slot3"}) do
		if session.Data.Perks[slot].Name == perkName then
			availableSlot = slot
			break
		end
	end

	-- If not found, look for empty slot
	if not availableSlot then
		-- Check if player has reached the limit of 3 slots
		local equippedCount = self.Server:GetEquippedKillerPerksCount(session.Data)
		if equippedCount >= 3 then
			return false, "Maximum abilities reached (3/3)"
		end
		
		if session.Data.Perks.Slot1.Name == "" then
			availableSlot = "Slot1"
		elseif session.Data.Perks.Slot2.Name == "" then
			availableSlot = "Slot2"
		elseif session.Data.Perks.Slot3.Name == "" then
			availableSlot = "Slot3"
		end
	end

	if not availableSlot then
		return false, "No available perk slots"
	end

	session.Data.Coins -= perkData.Price
	session.Data.Shop[perkName] = currentStock - 1

	if session.Data.Perks[availableSlot].Name == perkName then
		session.Data.Perks[availableSlot].Quantity += 1
	else
		session.Data.Perks[availableSlot].Name = perkName
		session.Data.Perks[availableSlot].Quantity = 1
	end

	DataService:Replicate(player, {"Coins", "Perks", "Shop"})
	return true, "Purchase successful"
end

function ShopService:UpdatePlayerShops(shopItems)
	for _, player in pairs(Players:GetPlayers()) do
		local session = DataService.getSession(player)
		if session and session.Data then
			-- Always regenerate shop if it's empty or corrupted
			if not session.Data.Shop or next(session.Data.Shop) == nil then
				session.Data.Shop = {}
				session.Data.RestockTimer = 15 * 60
				for _, item in pairs(shopItems) do
					session.Data.Shop[item.name] = item.data.Stock
				end
				DataService:Replicate(player, {"Shop", "RestockTimer"})
			end
		else
			-- Retry after a delay if session data is not available yet
			task.spawn(function()
				task.wait(2)
				local retrySession = DataService.getSession(player)
				if retrySession and retrySession.Data then
					if not retrySession.Data.Shop or next(retrySession.Data.Shop) == nil then
						retrySession.Data.Shop = {}
						retrySession.Data.RestockTimer = 15 * 60
						for _, item in pairs(shopItems) do
							retrySession.Data.Shop[item.name] = item.data.Stock
						end
						DataService:Replicate(player, {"Shop", "RestockTimer"})
					end
				end
			end)
		end
	end
end

function ShopService:StartRestockTimer()
	RunService.Heartbeat:Connect(function()
		for _, player in pairs(Players:GetPlayers()) do
			local session = DataService.getSession(player)
			if session and session.Data and session.Data.RestockTimer then
				if session.Data.RestockTimer > 0 then
					session.Data.RestockTimer -= (1 / 60)
					if session.Data.RestockTimer <= 0 then
						self:RegeneratePlayerShop(player)
					end
					DataService:Replicate(player, "RestockTimer")
				end
			end
		end
	end)
end

function ShopService:RegeneratePlayerShop(player)
	local session = DataService.getSession(player)
	if not session or not session.Data then return end

	local shopItems = self:GenerateShopItems()
	session.Data.Shop = {}
	session.Data.RestockTimer = 15 * 60
	for _, item in pairs(shopItems) do
		session.Data.Shop[item.name] = item.data.Stock
	end
	DataService:Replicate(player, {"Shop", "RestockTimer"})
end

function ShopService:KnitStart()
	local shopItems = self:GenerateShopItems()
	
	DataService._onPlayerDataLoaded:Connect(function(player)
		task.wait(0.1)
		local session = DataService.getSession(player)
		if session and session.Data then
			if not session.Data.Shop or next(session.Data.Shop) == nil then
				session.Data.Shop = {}
				session.Data.RestockTimer = 15 * 60
				for _, item in pairs(shopItems) do
					session.Data.Shop[item.name] = item.data.Stock
				end
				DataService:Replicate(player, {"Shop", "RestockTimer"})
			end
		end
	end)
	
	task.wait(3)
	self:UpdatePlayerShops(shopItems)
	self:StartRestockTimer()
end

function ShopService:KnitInit()
	DataService = Knit.GetService("DataService")
end

return ShopService
