local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Packages = ReplicatedStorage.Packages

local Knit = require(Packages.Knit)
local PerkEnums = require(ReplicatedStorage.Shared.Data.PerkEnums)

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

	for perkName, perkData in pairs(PerkEnums) do
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
		local remainingSlots = maxItems - #shopItems
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
		for i = 1, math.min(remainingSlots, #unselectedPerks) do
			table.insert(shopItems, unselectedPerks[i])
		end
	end

	return shopItems
end

function ShopService.Client:PurchasePerk(player, perkName)
	local session = DataService.getSession(player)
	if not session or not session.Data then
		return false, "No player data found"
	end

	local perkData = PerkEnums[perkName]
	if not perkData then
		return false, "Perk not found"
	end

	local currentStock = session.Data.Shop[perkName]
	if not currentStock or currentStock <= 0 then
		return false, "Out of stock or not available"
	end

	if session.Data.Cash < perkData.Price then
		return false, "Not enough cash"
	end

	local availableSlot = nil
	for _, slot in pairs({"Slot1", "Slot2", "Slot3"}) do
		if session.Data.Perks[slot].Name == perkName then
			availableSlot = slot
			break
		end
	end

	if not availableSlot then
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

	session.Data.Cash -= perkData.Price
	session.Data.Shop[perkName] = currentStock - 1

	if session.Data.Perks[availableSlot].Name == perkName then
		session.Data.Perks[availableSlot].Quantity += 1
	else
		session.Data.Perks[availableSlot].Name = perkName
		session.Data.Perks[availableSlot].Quantity = 1
	end

	DataService:Replicate(player, {"Cash", "Perks", "Shop"})
	return true, "Purchase successful"
end

function ShopService:UpdatePlayerShops(shopItems)
	print("[ShopService] UpdatePlayerShops called with", #shopItems, "items")
	for _, player in pairs(Players:GetPlayers()) do
		print(string.format("[ShopService] Processing player: %s", player.Name))
		local session = DataService.getSession(player)
		if session and session.Data then
			print(string.format("[ShopService] %s has session data", player.Name))
			local needsReset = false
			if session.Data.Shop then
				local count = 0
				for _ in pairs(session.Data.Shop) do count += 1 end
				print(string.format("[ShopService] %s current shop has %d items", player.Name, count))
				if #session.Data.Shop > 0 or next(session.Data.Shop) == nil then
					needsReset = true
				end
			else
				needsReset = true
			end
			if needsReset then
				print(string.format("[ShopService] Resetting shop for %s", player.Name))
				session.Data.Shop = {}
				session.Data.RestockTimer = 15 * 60
				for _, item in pairs(shopItems) do
					session.Data.Shop[item.name] = item.data.Stock
					print(string.format("[ShopService] Added %s to %s's shop (Stock: %d)", item.name, player.Name, item.data.Stock))
				end
				DataService:Replicate(player, {"Shop", "RestockTimer"})
			else
				print(string.format("[ShopService] %s already has shop, skipping", player.Name))
			end
		else
			print(string.format("[ShopService] %s has no session, retrying...", player.Name))
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
	game:GetService("RunService").Heartbeat:Connect(function()
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
	print("[ShopService] Starting shop generation...")
	local shopItems = self:GenerateShopItems()
	print(string.format("[ShopService] Generated %d shop items", #shopItems))
	for i, item in pairs(shopItems) do
		print(string.format("[ShopService] Item %d: %s (Stock: %d)", i, item.name, item.data.Stock))
	end
	
	-- Listen for when players' data is loaded and give them shop items
	DataService._onPlayerDataLoaded:Connect(function(player)
		print(string.format("[ShopService] Player %s data loaded, initializing shop", player.Name))
		task.wait(0.1) -- Small delay to ensure everything is ready
		local session = DataService.getSession(player)
		if session and session.Data then
			if not session.Data.Shop or next(session.Data.Shop) == nil then
				print(string.format("[ShopService] Setting up initial shop for %s", player.Name))
				session.Data.Shop = {}
				session.Data.RestockTimer = 15 * 60
				for _, item in pairs(shopItems) do
					session.Data.Shop[item.name] = item.data.Stock
					print(string.format("[ShopService] Added %s to %s's shop (Stock: %d)", item.name, player.Name, item.data.Stock))
				end
				DataService:Replicate(player, {"Shop", "RestockTimer"})
			end
		end
	end)
	
	task.wait(3)
	print("[ShopService] Updating player shops...")
	self:UpdatePlayerShops(shopItems)
	self:StartRestockTimer()
	print("[ShopService] Shop service started")
end

function ShopService:KnitInit()
	DataService = Knit.GetService("DataService")
end

return ShopService
