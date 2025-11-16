local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage.Packages
local Shared = ReplicatedStorage.Shared

local Knit = require(Packages.Knit)
local KillerPerks = require(Shared.Data.KillerPerks)
local SurvivorPerks = require(Shared.Data.SurvivorPerks)

local DataController
local PerkShopService
local SurvivorPerksService

local ShopController = Knit.CreateController({
	Name = "ShopController",
	_purchasing = {},
	_connections = {},
})

local isUpdating = false
local currentTab = "Killer"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainGui = playerGui:WaitForChild("Main")
local framesFolder = mainGui:WaitForChild("Frames")
local shopFrame = framesFolder:WaitForChild("Perks")
local contentFrame = shopFrame:WaitForChild("Content")
local tabsFrame = contentFrame:WaitForChild("Tabs")
local killerButton = tabsFrame:WaitForChild("Killer")
local survivorButton = tabsFrame:WaitForChild("Survivor")
local scrollingFrame = contentFrame:WaitForChild("Container")
local timerLabel = shopFrame:WaitForChild("Timer")

local PerksTemplate = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("UIAssets"):WaitForChild("PerksTemplate")

function ShopController:FormatTime(seconds)
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local secs = math.floor(seconds % 60)
	return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

function ShopController:UpdateTimerDisplay()
	local playerData = DataController.getData()
	if playerData and playerData.RestockTimer then
		local timeLeft = playerData.RestockTimer
		if timeLeft > 0 then
			timerLabel.Text = "Next Restock: " .. self:FormatTime(timeLeft)
		else
			timerLabel.Text = "Shop Restocked!"
		end
	else
		timerLabel.Text = "Timer Loading..."
	end
end

function ShopController:GetSurvivorPerkAmount(playerData, perkName)
	if not playerData or not playerData.SurvivorPerks then
		return 0
	end
	
	local total = 0
	for _, slotName in pairs({"Slot1", "Slot2", "Slot3"}) do
		local slot = playerData.SurvivorPerks[slotName]
		if slot and slot.Name == perkName then
			total += slot.Quantity
		end
	end
	
	return total
end

function ShopController:SwitchTab(tabName)
	currentTab = tabName
	
	if tabName == "Killer" then
		killerButton.BackgroundColor3 = Color3.new(0.2, 0.2, 0.8)
		survivorButton.BackgroundColor3 = Color3.new(0.3, 0.3, 0.3)
	else
		killerButton.BackgroundColor3 = Color3.new(0.3, 0.3, 0.3)
		survivorButton.BackgroundColor3 = Color3.new(0.2, 0.2, 0.8)
	end
	
	if tabName == "Killer" then
		self:UpdateShopUI()
	else
		self:UpdateSurvivorPerksUI()
	end
end

function ShopController:UpdateShopUI()
	if isUpdating then 
		return 
	end
	isUpdating = true

	local playerData = DataController.getData()
	
	if playerData and playerData.Shop then
		for _, child in pairs(scrollingFrame:GetChildren()) do
			if child:IsA("GuiObject") and child.Name ~= "UIListLayout" then
				child:Destroy()
			end
		end

		local itemIndex = 1
		for perkName, stockAmount in pairs(playerData.Shop) do
			local perkData = KillerPerks[perkName]
			if not perkData then 
				continue 
			end

			local newItem
			local success, err = pcall(function()
				newItem = PerksTemplate:Clone()
				newItem.Name = "ShopItem" .. itemIndex
				newItem.Visible = true
				newItem.Parent = scrollingFrame
			end)
			if not success then 
				continue 
			end
			if not newItem then 
				continue 
			end

			local holder = newItem:FindFirstChild("Holder")
			if not holder then
				continue
			end

			local nameLabel = holder:FindFirstChild("Name")
			if nameLabel then
				nameLabel.Text = perkData.Name
			end

			local stockLabel = holder:FindFirstChild("Stock")
			if stockLabel then
				stockLabel.Text = "Stock: " .. stockAmount
			end

			local purchaseButton = holder:FindFirstChild("Buy")
			if purchaseButton then
				local buttonText = purchaseButton:FindFirstChild("Text")
				
				if stockAmount > 0 then
					if buttonText then buttonText.Text = "$" .. perkData.Price end
					purchaseButton.BackgroundColor3 = Color3.new(0, 0.7, 0)
				else
					if buttonText then buttonText.Text = "Out of Stock" end
					purchaseButton.BackgroundColor3 = Color3.new(0.5, 0.5, 0.5)
				end

				purchaseButton.MouseButton1Click:Connect(function()
					if stockAmount > 0 then
						if buttonText then buttonText.Text = "..." end
						purchaseButton.BackgroundColor3 = Color3.new(0.7, 0.7, 0)
						purchaseButton.Active = false

						PerkShopService:PurchasePerk(perkName):andThen(function(success, message)
							if success then
								stockAmount -= 1
								if stockLabel then
									stockLabel.Text = "Stock: " .. stockAmount
								end
								if stockAmount > 0 then
									if buttonText then buttonText.Text = "$" .. perkData.Price end
									purchaseButton.BackgroundColor3 = Color3.new(0, 0.7, 0)
								else
									if buttonText then buttonText.Text = "Out of Stock" end
									purchaseButton.BackgroundColor3 = Color3.new(0.5, 0.5, 0.5)
								end
							else
								if buttonText then buttonText.Text = "$" .. perkData.Price end
								purchaseButton.BackgroundColor3 = Color3.new(0, 0.7, 0)
							end
							purchaseButton.Active = true
						end):catch(function()
							if buttonText then buttonText.Text = "$" .. perkData.Price end
							purchaseButton.BackgroundColor3 = Color3.new(0, 0.7, 0)
							purchaseButton.Active = true
						end)
					end
				end)
			end

			local iconLabel = holder:FindFirstChild("Icon")
			if iconLabel then
				iconLabel.Image = "rbxassetid://" .. perkData.Image
			end

			itemIndex += 1
		end
	end

	self:UpdateTimerDisplay()
	isUpdating = false
end

function ShopController:UpdateSurvivorPerksUI()
	if isUpdating then 
		return 
	end
	isUpdating = true

	local playerData = DataController.getData()
	
	for _, child in pairs(scrollingFrame:GetChildren()) do
		if child:IsA("GuiObject") and child.Name ~= "UIListLayout" then
			child:Destroy()
		end
	end

	if playerData and playerData.SurvivorPerks then
		local itemIndex = 1
		for perkName, perkData in pairs(SurvivorPerks) do
			local newItem
			local success, err = pcall(function()
				newItem = PerksTemplate:Clone()
				newItem.Name = "SurvivorPerkItem" .. itemIndex
				newItem.Visible = true
				newItem.Parent = scrollingFrame
			end)
			if not success then 
				continue 
			end
			if not newItem then 
				continue 
			end

			local holder = newItem:FindFirstChild("Holder")
			if not holder then
				continue
			end

			local nameLabel = holder:FindFirstChild("Name")
			if nameLabel then
				nameLabel.Text = perkData.Name
			end

			local ownedAmount = self:GetSurvivorPerkAmount(playerData, perkName)
			local stockLabel = holder:FindFirstChild("Stock")
			if stockLabel then
				stockLabel.Text = string.format("%d/%d", ownedAmount, perkData.MaxAmount)
			end

			local purchaseButton = holder:FindFirstChild("Buy")
			if purchaseButton then
				local buttonText = purchaseButton:FindFirstChild("Text")
				
				if ownedAmount >= perkData.MaxAmount then
					if buttonText then buttonText.Text = "MAX" end
					purchaseButton.BackgroundColor3 = Color3.new(0.5, 0.5, 0.5)
					purchaseButton.Active = false
				else
					if buttonText then buttonText.Text = "$" .. perkData.Price end
					purchaseButton.BackgroundColor3 = Color3.new(0, 0.7, 0)
					purchaseButton.Active = true

					purchaseButton.MouseButton1Click:Connect(function()
						self:PurchaseSurvivorPerk(perkName, newItem, buttonText, stockLabel, perkData)
					end)
				end
			end

			local iconLabel = holder:FindFirstChild("Icon")
			if iconLabel then
				iconLabel.Image = "rbxassetid://" .. perkData.Image
			end

			itemIndex += 1
		end
	end

	isUpdating = false
end

function ShopController:PurchaseSurvivorPerk(perkName, itemFrame, buttonText, stockLabel, perkData)
	if self._purchasing[perkName] then
		return
	end
	
	self._purchasing[perkName] = true
	
	if buttonText then buttonText.Text = "..." end
	local holder = itemFrame:FindFirstChild("Holder")
	local purchaseButton = holder and holder:FindFirstChild("Buy")
	if purchaseButton then
		purchaseButton.BackgroundColor3 = Color3.new(0.7, 0.7, 0)
		purchaseButton.Active = false
	end
	
	SurvivorPerksService:PurchaseSurvivorPerk(perkName):andThen(function(success, message)
		if not success then
			if buttonText then buttonText.Text = "$" .. perkData.Price end
			if purchaseButton then
				purchaseButton.BackgroundColor3 = Color3.new(0, 0.7, 0)
				purchaseButton.Active = true
			end
			self._purchasing[perkName] = false
			return
		end
		
		task.wait(0.2)
		local newData = DataController.getData()
		if newData then
			local ownedAmount = self:GetSurvivorPerkAmount(newData, perkName)
			if stockLabel then
				stockLabel.Text = string.format("%d/%d", ownedAmount, perkData.MaxAmount)
			end
			
			if ownedAmount >= perkData.MaxAmount then
				if buttonText then buttonText.Text = "MAX" end
				if purchaseButton then
					purchaseButton.BackgroundColor3 = Color3.new(0.5, 0.5, 0.5)
					purchaseButton.Active = false
				end
			else
				if buttonText then buttonText.Text = "$" .. perkData.Price end
				if purchaseButton then
					purchaseButton.BackgroundColor3 = Color3.new(0, 0.7, 0)
					purchaseButton.Active = true
				end
			end
		end
		
		self._purchasing[perkName] = false
	end):catch(function(err)
		if buttonText then buttonText.Text = "$" .. perkData.Price end
		if purchaseButton then
			purchaseButton.BackgroundColor3 = Color3.new(0, 0.7, 0)
			purchaseButton.Active = true
		end
		self._purchasing[perkName] = false
	end)
end

function ShopController:Cleanup()
	for _, connection in pairs(self._connections) do
		if connection then
			connection:Disconnect()
		end
	end
	self._connections = {}
end

function ShopController:KnitStart()
	table.insert(self._connections, killerButton.MouseButton1Click:Connect(function()
		self:SwitchTab("Killer")
	end))
	
	table.insert(self._connections, survivorButton.MouseButton1Click:Connect(function()
		self:SwitchTab("Survivor")
	end))
	
	table.insert(self._connections, DataController.onReplicated("Shop"):Connect(function()
		if currentTab == "Killer" then
			self:UpdateShopUI()
		end
	end))

	table.insert(self._connections, DataController.onReplicated("Cash"):Connect(function()
		if currentTab == "Killer" then
			self:UpdateShopUI()
		end
	end))

	table.insert(self._connections, DataController.onReplicated("RestockTimer"):Connect(function()
		self:UpdateTimerDisplay()
	end))
	
	table.insert(self._connections, DataController.onReplicated("SurvivorPerks"):Connect(function()
		if currentTab == "Survivor" then
			self:UpdateSurvivorPerksUI()
		end
	end))

	task.wait(1.5)
	self:SwitchTab("Killer")
end

function ShopController:KnitInit()
	self:Cleanup()
	DataController = Knit.GetController("DataController")
	PerkShopService = Knit.GetService("ShopService")
	SurvivorPerksService = Knit.GetService("SurvivorPerksService")
end

return ShopController
