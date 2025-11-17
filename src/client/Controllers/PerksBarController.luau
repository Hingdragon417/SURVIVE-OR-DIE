local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage.Packages
local Shared = ReplicatedStorage.Shared

local Knit = require(Packages.Knit)
local KillerPerks = require(Shared.Data.KillerPerks)
local SurvivorPerks = require(Shared.Data.SurvivorPerks)

local DataController
local DataService
local RoleShowController
local PerkEffectsService
local RoundService

local UtilBarController = Knit.CreateController({
	Name = "UtilBarController",
	_perksEnabled = false,
	_cooldowns = {},
	_cooldownConnections = {},
	_connections = {},
})

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainGui = playerGui:WaitForChild("Main")
local framesFolder = mainGui:WaitForChild("Frames")
local bottomContainer = mainGui:WaitForChild("BottomContainer")

local PerksTemplate = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("UIAssets"):WaitForChild("AbilitiesTemplate")

local keyBindings = {
	[Enum.KeyCode.R] = "Slot1",
	[Enum.KeyCode.Q] = "Slot2",
	[Enum.KeyCode.E] = "Slot3"
}

function UtilBarController:UseAbility(slotName)
	if not self._perksEnabled then return end
	
	if self._cooldowns[slotName] and tick() < self._cooldowns[slotName] then
		return
	end
	
	local playerData = DataController.getData()
	if not playerData then return end

	local isKiller = RoleShowController:IsKiller()
	if isKiller then
		return self:UseKillerPerks(slotName)
	else
		return self:UseSurvivorPerks(slotName)
	end
end

function UtilBarController:UseKillerPerks(slotName)
	local playerData = DataController.getData()
	if not playerData or not playerData.Perks then return end

	local PerksSlot = playerData.Perks[slotName]
	if not PerksSlot or PerksSlot.Name == "" or PerksSlot.Quantity <= 0 then return end

	local PerksData = KillerPerks[PerksSlot.Name]
	if not PerksData then return end

	DataService:UseKillerPerk(slotName):andThen(function(success, message)
		if success then
			self._cooldowns[slotName] = tick() + PerksData.Cooldown
			self:StartCooldownVisual(slotName, PerksData.Cooldown)
			
			PerkEffectsService:UsePerk(PerksSlot.Name, true):andThen(function(effectSuccess)
				if not effectSuccess then
					warn("Failed to activate killer perk effect:", PerksSlot.Name)
				end
			end):catch(function(err)
				warn("Error activating killer perk:", err)
			end)
		else
			warn("Failed to use killer perk:", message)
		end
	end):catch(function(err)
		warn("Error using killer perk:", err)
	end)
end

function UtilBarController:UseSurvivorPerks(slotName)
	local playerData = DataController.getData()
	if not playerData or not playerData.SurvivorPerks then return end

	local PerkSlot = playerData.SurvivorPerks[slotName]
	if not PerkSlot or PerkSlot.Name == "" then return end

	local PerkData = SurvivorPerks[PerkSlot.Name]
	if not PerkData then return end

	DataService:UseSurvivorPerk(slotName):andThen(function(success, message)
		if success then
			self._cooldowns[slotName] = tick() + PerkData.Cooldown
			self:StartCooldownVisual(slotName, PerkData.Cooldown)
			
			PerkEffectsService:UsePerk(PerkSlot.Name, false):andThen(function(effectSuccess)
				if not effectSuccess then
					warn("Failed to activate survivor perk effect:", PerkSlot.Name)
				end
			end):catch(function(err)
				warn("Error activating survivor perk:", err)
			end)
		else
			warn("Failed to use survivor perk:", message)
		end
	end):catch(function(err)
		warn("Error using survivor perk:", err)
	end)
end

function UtilBarController:StartCooldownVisual(slotName, cooldownTime)
	if self._cooldownConnections[slotName] then
		self._cooldownConnections[slotName]:Disconnect()
	end
	
	local endTime = tick() + cooldownTime
	self._cooldowns[slotName] = endTime
	
	local function updateCooldownText()
		local perkSlot = bottomContainer:FindFirstChild("PerksSlot" .. slotName)
		if not perkSlot then return false end
		
		local keybindLabel = perkSlot:FindFirstChild("Keybind")
		if not keybindLabel or not keybindLabel:IsA("TextLabel") then return false end
		
		local remaining = endTime - tick()
		if remaining <= 0 then
			self._cooldowns[slotName] = nil
			for keyCode, bindSlot in pairs(keyBindings) do
				if bindSlot == slotName then
					keybindLabel.Text = keyCode.Name
					keybindLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
					break
				end
			end
			return false
		else
			keybindLabel.Text = tostring(math.ceil(remaining))
			keybindLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
			return true
		end
	end
	
	local connection
	connection = game:GetService("RunService").Heartbeat:Connect(function()
		if not updateCooldownText() then
			connection:Disconnect()
			self._cooldownConnections[slotName] = nil
		end
	end)
	
	self._cooldownConnections[slotName] = connection
	updateCooldownText()
end

function UtilBarController:UpdateUI()
	local playerData = DataController.getData()
	if not playerData then return end

	local isKiller = RoleShowController:IsKiller() or false
	
	for _, child in pairs(bottomContainer:GetChildren()) do
		if child:IsA("GuiObject") and child.Name:find("PerksSlot") then
			child:Destroy()
		end
	end

	local slotOrder = {"Slot1", "Slot2", "Slot3"}
	for _, slotName in ipairs(slotOrder) do
		local slot = isKiller and playerData.Perks and playerData.Perks[slotName] 
			or playerData.SurvivorPerks and playerData.SurvivorPerks[slotName]
		
		if not slot then continue end

		if not PerksTemplate then
			warn("[PerksBarController] PerksTemplate not found!")
			return
		end

		local newTemplate = PerksTemplate:Clone()
		if not newTemplate then
			warn("[PerksBarController] Failed to clone PerksTemplate")
			continue
		end
		
		newTemplate.Name = "PerksSlot" .. slotName

		local keybindLabel = newTemplate:FindFirstChild("Keybind")
		if keybindLabel and keybindLabel:IsA("TextLabel") then
			if self._cooldowns[slotName] then
				local remaining = self._cooldowns[slotName] - tick()
				if remaining > 0 then
					keybindLabel.Text = tostring(math.ceil(remaining))
					keybindLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
				else
					self._cooldowns[slotName] = nil
					for keyCode, bindSlot in pairs(keyBindings) do
						if bindSlot == slotName then
							keybindLabel.Text = keyCode.Name
							keybindLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
							break
						end
					end
				end
			else
				for keyCode, bindSlot in pairs(keyBindings) do
					if bindSlot == slotName then
						keybindLabel.Text = keyCode.Name
						keybindLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
						break
					end
				end
			end
		end

		if slot.Name ~= "" and slot.Quantity and slot.Quantity > 0 then
			local itemData = isKiller and KillerPerks[slot.Name] or SurvivorPerks[slot.Name]
			if itemData then
				local imageLabel = newTemplate:FindFirstChild("ImageLabel")
				if imageLabel and imageLabel:IsA("ImageLabel") then
					imageLabel.Image = "rbxassetid://" .. itemData.Image
				end
				
				local nameLabel = newTemplate:FindFirstChild("Name")
				if nameLabel and nameLabel:IsA("TextLabel") then
					nameLabel.Text = slot.Name
				end

			local quantityLabel = newTemplate:FindFirstChild("Quantity")
			if quantityLabel then
				quantityLabel.Text = "x" .. slot.Quantity
				quantityLabel.Visible = true
			end
			
			newTemplate.Visible = self._perksEnabled
			newTemplate.Parent = bottomContainer				if newTemplate:IsA("TextButton") or newTemplate:IsA("ImageButton") then
					newTemplate.Activated:Connect(function()
						self:UseAbility(slotName)
					end)
				end
			else
				warn("[PerksBarController] Item data not found for:", slot.Name)
				newTemplate:Destroy()
			end
		else
			newTemplate:Destroy()
		end
	end
end

function UtilBarController:KnitStart()
	table.insert(self._connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		local slotName = keyBindings[input.KeyCode]
		if slotName then
			self:UseAbility(slotName)
		end
	end))

	table.insert(self._connections, DataController.onReplicated("Perks"):Connect(function()
		self:UpdateUI()
	end))

	table.insert(self._connections, DataController.onReplicated("SurvivorPerks"):Connect(function()
		self:UpdateUI()
	end))

	table.insert(self._connections, DataController.onReplicated("Shop"):Connect(function()
		task.wait()
		self:UpdateUI()
	end))

	table.insert(self._connections, DataController.onReplicated("Coins"):Connect(function()
		task.wait()
		self:UpdateUI()
	end))

	table.insert(self._connections, RoleShowController:OnRoleChanged(function()
		self:UpdateUI()
	end))

	task.wait(1)
	self:UpdateUI()
end

function UtilBarController:KnitInit()
	DataController = Knit.GetController("DataController")
	DataService = Knit.GetService("DataService")
	RoleShowController = Knit.GetController("RoleShowController")
	PerkEffectsService = Knit.GetService("PerkEffectsService")
	RoundService = Knit.GetService("RoundService")
	
	table.insert(self._connections, RoundService.PerksEnabled:Connect(function(enabled)
		self._perksEnabled = enabled
		self:UpdateUI()
	end))
end

function UtilBarController:Cleanup()
	for _, connection in pairs(self._connections) do
		if connection and connection.Disconnect then
			connection:Disconnect()
		end
	end
	self._connections = {}
	
	for _, connection in pairs(self._cooldownConnections) do
		if connection and connection.Disconnect then
			connection:Disconnect()
		end
	end
	self._cooldownConnections = {}
end

return UtilBarController
