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
local NotificationController

local ShopController = Knit.CreateController({
	Name = "ShopController",
	_purchasing = {},
	_connections = {},
})

local SLOT_ORDER = {"Slot1", "Slot2", "Slot3"}
local currentTab = "Killer"
local currentManaFilter: number? = 1
local currentSelectedPerkName: string? = nil

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainGui = playerGui:WaitForChild("Main")
local framesFolder = mainGui:WaitForChild("Frames")
local shopFrame = framesFolder:WaitForChild("Perks")
local contentFrame = shopFrame:WaitForChild("Content")
local tabsFrame = contentFrame:FindFirstChild("Tabs") or shopFrame:WaitForChild("Tabs")
local killerButton = tabsFrame:WaitForChild("Killer")
local survivorButton = tabsFrame:WaitForChild("Survivor")
local scrollingFrame = contentFrame:FindFirstChild("ScrollingFrame") or contentFrame:FindFirstChild("Container") or contentFrame:WaitForChild("ScrollingFrame")
local selectedTemplate = contentFrame:WaitForChild("SelectedTemplate")
local timerLabel = shopFrame:FindFirstChild("Timer")
local equippedCountLabel = shopFrame:WaitForChild("EquippedAmount")
local manaControls = shopFrame:WaitForChild("ButtonContainer")

local uiAssets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("UIAssets")
local PerkTemplate = uiAssets:WaitForChild("PerkTemplate")

local function findGui(instance, name)
	return instance and instance:FindFirstChild(name, true)
end

local function setText(instance, text)
	if instance and (instance:IsA("TextLabel") or instance:IsA("TextButton")) then
		instance.Text = text
	end
end

local function findPerkImage(instance)
	local directImage = instance and instance:FindFirstChild("ImageLabel", true)
	if directImage and directImage:IsA("ImageLabel") then
		return directImage
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("ImageLabel") then
			return descendant
		end
	end

	return nil
end

local function findSelectButton(instance)
	local selectButton = findGui(instance, "Select")
	if selectButton and selectButton:IsA("GuiButton") then
		return selectButton
	end

	return nil
end

local function findInteractButton(instance)
	local interactButton = findGui(instance, "Interact") or findGui(instance, "Ineract")
	if interactButton and interactButton:IsA("GuiButton") then
		return interactButton
	end

	return nil
end

local function findDescriptionText(instance)
	local descriptionLabel = findGui(instance, "Description")
	if descriptionLabel and (descriptionLabel:IsA("TextLabel") or descriptionLabel:IsA("TextButton")) then
		return descriptionLabel
	end

	local interactButton = findInteractButton(instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant.Name == "Text" and (descendant:IsA("TextLabel") or descendant:IsA("TextButton")) then
			if not interactButton or not descendant:IsDescendantOf(interactButton) then
				return descendant
			end
		end
	end

	return nil
end

local function getSlotTable(playerData)
	if currentTab == "Killer" then
		return playerData and playerData.Perks
	end

	return playerData and playerData.SurvivorPerks
end

local function getOwnedTable(playerData)
	if currentTab == "Killer" then
		return playerData and playerData.OwnedKillerPerks or {}
	end

	return playerData and playerData.OwnedSurvivorPerks or {}
end

local function getMaxMana(playerData)
	if currentTab == "Killer" then
		return playerData and playerData.MaxKillerPerkMana or 3
	end

	return playerData and playerData.MaxSurvivorPerkMana or 3
end

local function getPerksForCurrentTab()
	return if currentTab == "Killer" then KillerPerks else SurvivorPerks
end

local function getEquippedSlot(playerData, perkName)
	local slots = getSlotTable(playerData)
	if not slots then
		return nil
	end

	for _, slotName in ipairs(SLOT_ORDER) do
		local slot = slots[slotName]
		if slot and slot.Name == perkName then
			return slotName
		end
	end

	return nil
end

function ShopController:GetEquippedPerkMana(playerData)
	local slots = getSlotTable(playerData)
	local perks = getPerksForCurrentTab()
	if not slots then
		return 0
	end

	local total = 0
	for _, slotName in ipairs(SLOT_ORDER) do
		local slot = slots[slotName]
		local perkData = slot and perks[slot.Name]
		if perkData then
			total += perkData.ManaCost or 1
		end
	end

	return total
end

function ShopController:UpdateEquippedCountDisplay()
	if not equippedCountLabel then return end

	local playerData = DataController.getData() or {}

	local usedMana = self:GetEquippedPerkMana(playerData)
	local maxMana = getMaxMana(playerData)
	equippedCountLabel.Text = string.format("Mana (%d/%d)", usedMana, maxMana)
end

function ShopController:ClearItems()
	for _, child in pairs(scrollingFrame:GetChildren()) do
		if child:IsA("GuiObject") and child.Name ~= "UIListLayout" then
			child:Destroy()
		end
	end
end

function ShopController:GetSortedPerks()
	local perkEntries = {}
	for perkName, perkData in pairs(getPerksForCurrentTab()) do
		local manaCost = perkData.ManaCost or 1
		if not currentManaFilter or manaCost == currentManaFilter then
			table.insert(perkEntries, {
				Name = perkName,
				Data = perkData,
			})
		end
	end

	table.sort(perkEntries, function(left, right)
		local leftMana = left.Data.ManaCost or 1
		local rightMana = right.Data.ManaCost or 1
		if leftMana == rightMana then
			return left.Name < right.Name
		end
		return leftMana < rightMana
	end)

	return perkEntries
end

function ShopController:UpdateSelectedTemplate(perkName)
	currentSelectedPerkName = perkName
	selectedTemplate.Visible = true

	local perkData = getPerksForCurrentTab()[perkName]
	if not perkData then
		return
	end

	local playerData = DataController.getData() or {}
	local owned = getOwnedTable(playerData)[perkName] == true
	local equipped = getEquippedSlot(playerData, perkName) ~= nil

	local iconLabel = findPerkImage(selectedTemplate)
	if iconLabel then
		iconLabel.Image = "rbxassetid://" .. tostring(perkData.Image)
	end

	local nameText = findGui(selectedTemplate, "Name")
	setText(nameText, perkData.Name or perkName)

	local descriptionText = findDescriptionText(selectedTemplate)
	setText(descriptionText, perkData.Description or "")

	local manaText = findGui(selectedTemplate, "Mana")
	setText(manaText, "Mana - " .. tostring(perkData.ManaCost or 1))

	local interactButton = findInteractButton(selectedTemplate)
	if interactButton then
		local buttonText = findGui(interactButton, "Text")
		if not owned then
			setText(buttonText, "$" .. tostring(perkData.Price))
			if not buttonText then
				setText(interactButton, "$" .. tostring(perkData.Price))
			end
		elseif equipped then
			setText(buttonText, "Unequip")
			if not buttonText then
				setText(interactButton, "Unequip")
			end
		else
			setText(buttonText, "Equip")
			if not buttonText then
				setText(interactButton, "Equip")
			end
		end
	end
end

function ShopController:UpdatePerksUI()
	local playerData = DataController.getData() or {}

	self:ClearItems()

	for index, perkEntry in ipairs(self:GetSortedPerks()) do
		local perkName = perkEntry.Name
		local perkData = perkEntry.Data
		local newItem = PerkTemplate:Clone()
		newItem.Name = currentTab .. "PerkItem" .. index
		newItem.Visible = true
		newItem.Parent = scrollingFrame

		local holder = newItem:FindFirstChild("Holder") or newItem
		local nameLabel = findGui(holder, "Name")
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = perkData.Name or perkName
		end

		local manaLabel = findGui(holder, "Mana") or findGui(holder, "Stock")
		if manaLabel and manaLabel:IsA("TextLabel") then
			manaLabel.Text = "Mana: " .. tostring(perkData.ManaCost or 1)
		end

		local descriptionLabel = findGui(holder, "Description")
		if descriptionLabel and descriptionLabel:IsA("TextLabel") then
			descriptionLabel.Text = perkData.Description or ""
		end

		local iconLabel = findPerkImage(newItem)
		if iconLabel then
			iconLabel.Image = "rbxassetid://" .. tostring(perkData.Image)
		end

		local selectButton = findSelectButton(newItem)
		if selectButton then
			selectButton.MouseButton1Click:Connect(function()
				self:UpdateSelectedTemplate(perkName)
			end)
		end
	end

	if currentSelectedPerkName and getPerksForCurrentTab()[currentSelectedPerkName] then
		self:UpdateSelectedTemplate(currentSelectedPerkName)
	end

	self:UpdateEquippedCountDisplay()
	if timerLabel and timerLabel:IsA("TextLabel") then
		timerLabel.Text = ""
	end
end

function ShopController:PurchaseOrTogglePerk(perkName)
	if self._purchasing[perkName] then
		return
	end

	self._purchasing[perkName] = true

	local promise = if currentTab == "Killer" then PerkShopService:PurchasePerk(perkName) else SurvivorPerksService:PurchaseSurvivorPerk(perkName)

	promise:andThen(function(success, message)
		if not success and message then
			if NotificationController then
				NotificationController:ShowWarning(message)
			else
				warn("[PerksShopController]", message)
			end
		end
		self._purchasing[perkName] = false
		if currentSelectedPerkName then
			self:UpdateSelectedTemplate(currentSelectedPerkName)
		end
	end):catch(function(err)
		warn("[PerksShopController] Failed to purchase/equip perk:", err)
		if NotificationController then
			NotificationController:ShowWarning("Could not update that perk right now.")
		end
		self._purchasing[perkName] = false
		self:UpdatePerksUI()
	end)
end

function ShopController:SwitchTab(tabName)
	currentTab = tabName
	currentSelectedPerkName = nil
	selectedTemplate.Visible = false

	if tabName == "Killer" then
		killerButton.BackgroundColor3 = Color3.fromRGB(51, 51, 204)
		survivorButton.BackgroundColor3 = Color3.fromRGB(77, 77, 77)
	else
		killerButton.BackgroundColor3 = Color3.fromRGB(77, 77, 77)
		survivorButton.BackgroundColor3 = Color3.fromRGB(51, 51, 204)
	end

	self:UpdatePerksUI()
end

function ShopController:SetManaFilter(manaCost: number?)
	currentManaFilter = manaCost

	if manaControls then
		for _, button in ipairs(manaControls:GetDescendants()) do
			if button:IsA("GuiButton") then
				local buttonManaCost = ({
					onemana = 1,
					twomana = 2,
					threemana = 3,
				})[string.lower(button.Name)]

				if buttonManaCost == currentManaFilter then
					button.BackgroundTransparency = 0
					button.BackgroundColor3 = Color3.fromRGB(51, 51, 204)
				else
					button.BackgroundTransparency = 0.35
					button.BackgroundColor3 = Color3.fromRGB(77, 77, 77)
				end
			end
		end
	end

	self:UpdatePerksUI()
end

function ShopController:SetupManaButtons()
	if not manaControls then
		return
	end

	local manaButtonMap = {
		onemana = 1,
		twomana = 2,
		threemana = 3,
	}

	for _, button in ipairs(manaControls:GetDescendants()) do
		if button:IsA("GuiButton") then
			local manaCost = manaButtonMap[string.lower(button.Name)]
			if manaCost then
				table.insert(self._connections, button.MouseButton1Click:Connect(function()
					self:SetManaFilter(manaCost)
				end))
			end
		end
	end
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
	selectedTemplate.Visible = false

	table.insert(self._connections, killerButton.MouseButton1Click:Connect(function()
		self:SwitchTab("Killer")
	end))

	table.insert(self._connections, survivorButton.MouseButton1Click:Connect(function()
		self:SwitchTab("Survivor")
	end))

	self:SetupManaButtons()

	local interactButton = findInteractButton(selectedTemplate)
	if interactButton then
		table.insert(self._connections, interactButton.MouseButton1Click:Connect(function()
			if currentSelectedPerkName then
				self:PurchaseOrTogglePerk(currentSelectedPerkName)
			end
		end))
	end

	table.insert(self._connections, DataController.onReplicated({"Perks", "SurvivorPerks", "OwnedKillerPerks", "OwnedSurvivorPerks", "MaxKillerPerkMana", "MaxSurvivorPerkMana"}):Connect(function()
		self:UpdatePerksUI()
	end))

	self:SetManaFilter(1)
	self:SwitchTab("Killer")
end

function ShopController:KnitInit()
	self:Cleanup()
	DataController = Knit.GetController("DataController")
	NotificationController = Knit.GetController("NotificationController")
	PerkShopService = Knit.GetService("ShopService")
	SurvivorPerksService = Knit.GetService("SurvivorPerksService")
end

return ShopController
