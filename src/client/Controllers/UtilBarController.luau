local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage.Packages
local Shared = ReplicatedStorage.Shared

local Knit = require(Packages.Knit)
local PerksEnums = require(Shared.Data.PerkEnums)
local AbilitiesEnums = require(Shared.Data.AbilitiesEnums)

local DataController
local DataService
local RoleShowController

local UtilBarController = Knit.CreateController({
	Name = "UtilBarController",
})

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainGui = playerGui:WaitForChild("Main")
local framesFolder = mainGui:WaitForChild("Frames")
local utilityFrame = mainGui:WaitForChild("Utility")
local centerFrame = utilityFrame:WaitForChild("Center")

local PerksTemplate = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("UIAssets"):WaitForChild("PerkBarTemplate")

local keyBindings = {
	[Enum.KeyCode.R] = "Slot1",
	[Enum.KeyCode.Q] = "Slot2",
	[Enum.KeyCode.E] = "Slot3"
}

function UtilBarController:UseAbility(slotName)
	local playerData = DataController.getData()
	if not playerData then return end

	local isKiller = RoleShowController:IsKiller()
	if not isKiller then
		return self:UseKillerPerks(slotName)
	else
		return self:UseSurvivorAbility(slotName)
	end
end

function UtilBarController:UseKillerPerks(slotName)
	local playerData = DataController.getData()
	if not playerData or not playerData.Perks then return end

	local PerksSlot = playerData.Perks[slotName]
	if not PerksSlot or PerksSlot.Name == "" or PerksSlot.Quantity <= 0 then return end

	local PerksData = PerksEnums[PerksSlot.Name]
	if not PerksData then return end

	local success, message = DataService:UsePerks(slotName):await()
	if success then
		self:PerformEffect(PerksSlot.Name, "Perks")
	end
end

function UtilBarController:UseSurvivorAbility(slotName)
	local playerData = DataController.getData()
	if not playerData or not playerData.Abilities then return end

	local AbilitySlot = playerData.Abilities[slotName]
	if not AbilitySlot or AbilitySlot.Name == "" then return end

	local success, message = DataService:UseAbility(slotName):await()
	if success then
		self:PerformEffect(AbilitySlot.Name, "Abilities")
	end
end

function UtilBarController:UpdateUI()
	local playerData = DataController.getData()
	if not playerData then return end

	local isKiller = RoleShowController:IsKiller() or false
	
	-- Clear existing slots
	for _, child in pairs(centerFrame:GetChildren()) do
		if child:IsA("GuiObject") and child.Name:find("PerksSlot") then
			child:Destroy()
		end
	end

	local slotOrder = {"Slot1", "Slot2", "Slot3"}
	for _, slotName in ipairs(slotOrder) do
		-- For killers, show abilities. For survivors, show perks
		local slot = not isKiller and playerData.Perks and playerData.Perks[slotName] 
			or playerData.Abilities and playerData.Abilities[slotName]
		
		if not slot then continue end

		local newTemplate = PerksTemplate:Clone()
		newTemplate.Name = "PerksSlot" .. slotName
		newTemplate.Visible = true

		local keybindLabel = newTemplate:FindFirstChild("Keybind")
		if keybindLabel then
			for keyCode, bindSlot in pairs(keyBindings) do
				if bindSlot == slotName then
					keybindLabel.Text = keyCode.Name
					break
				end
			end
		end

		if slot.Name ~= "" and slot.Quantity and slot.Quantity > 0 then
			local itemData = not isKiller and PerksEnums[slot.Name] or AbilitiesEnums[slot.Name]
			if itemData then
				local imageLabel = newTemplate:FindFirstChild("ImageLabel")
				if imageLabel then
					imageLabel.Image = "rbxassetid://" .. itemData.Image
				end

				local quantityLabel = newTemplate:FindFirstChild("Quantity")
				if quantityLabel then
					quantityLabel.Text = "x" .. slot.Quantity
					quantityLabel.Visible = true
				end
				
				newTemplate.Parent = centerFrame
			end
		else
			-- Don't show empty slots
			newTemplate:Destroy()
		end
	end
end

function UtilBarController:PerformEffect(name, category)
	local modulePath = script.Parent.Parent.Modules[category][name]
	local success, module = pcall(function()
		return require(modulePath)
	end)

	if success and module and module.Execute then
		if name == "Invisibility" then
			task.spawn(function()
				module.Execute()
			end)
		else
			module.Execute()
		end
	end
end

function UtilBarController:KnitStart()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		local slotName = keyBindings[input.KeyCode]
		if slotName then
			self:UseAbility(slotName)
		end
	end)

	DataController.onReplicated("Perks"):Connect(function()
		self:UpdateUI()
	end)

	DataController.onReplicated("Abilities"):Connect(function()
		self:UpdateUI()
	end)

	DataController.onReplicated("Shop"):Connect(function()
		task.wait()
		self:UpdateUI()
	end)

	DataController.onReplicated("Cash"):Connect(function()
		task.wait()
		self:UpdateUI()
	end)

	RoleShowController:OnRoleChanged(function()
		self:UpdateUI()
	end)

	task.wait(1)
	self:UpdateUI()
end

function UtilBarController:KnitInit()
	DataController = Knit.GetController("DataController")
	DataService = Knit.GetService("DataService")
	RoleShowController = Knit.GetController("RoleShowController")
end

return UtilBarController
