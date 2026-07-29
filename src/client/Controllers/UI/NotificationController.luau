local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local NotificationController = Knit.CreateController({
	Name = "NotificationController",
	_connections = {},
	_template = nil,
	_container = nil,
	_activeCount = 0,
})

local GeneratorService
local PerkEffectsService
local RoleShowController

local TYPE_COLORS = {
	Info = Color3.fromRGB(255, 255, 255),
	Success = Color3.fromRGB(96, 255, 120),
	Warning = Color3.fromRGB(255, 204, 69),
	Danger = Color3.fromRGB(255, 83, 83),
}

local TYPE_DURATIONS = {
	Info = 3,
	Success = 4,
	Warning = 4,
	Danger = 5,
}

function NotificationController:_resolveUi(): boolean
	if self._container and self._container.Parent and self._template and self._template.Parent then
		return true
	end

	local mainGui = playerGui:FindFirstChild("Main")
	if not mainGui then
		return false
	end

	local container = mainGui:FindFirstChild("Notification", true)
	if not container then
		return false
	end

	local template = container:FindFirstChild("TextLabel")
	if not template or not template:IsA("TextLabel") then
		return false
	end

	self._container = container
	self._template = template
	if container:IsA("GuiObject") then
		container.Visible = false
	end
	template.Visible = false

	return true
end

function NotificationController:Show(message: string, notificationType: string?, duration: number?)
	if type(message) ~= "string" or message == "" then
		return
	end

	if not self:_resolveUi() then
		warn("[NotificationController] Main.Notification.TextLabel not found")
		return
	end

	local resolvedType = notificationType or "Info"
	local displayDuration = duration or TYPE_DURATIONS[resolvedType] or TYPE_DURATIONS.Info
	local textLabel = self._template:Clone()

	self._activeCount += 1
	if self._container:IsA("GuiObject") then
		self._container.Visible = true
	end

	textLabel.Name = "NotificationMessage"
	textLabel.Text = message
	textLabel.TextColor3 = TYPE_COLORS[resolvedType] or TYPE_COLORS.Info
	textLabel.TextTransparency = 1
	textLabel.Visible = true
	textLabel.Parent = self._container

	local fadeIn = TweenService:Create(textLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	})
	fadeIn:Play()

	task.delay(displayDuration, function()
		if not textLabel.Parent then
			return
		end

		local fadeOut = TweenService:Create(textLabel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
		})
		fadeOut.Completed:Connect(function()
			if textLabel.Parent then
				textLabel:Destroy()
			end

			self._activeCount = math.max(0, self._activeCount - 1)
			if self._activeCount == 0 and self._container and self._container:IsA("GuiObject") then
				self._container.Visible = false
			end
		end)
		fadeOut:Play()
	end)
end

function NotificationController:ShowInfo(message: string, duration: number?)
	self:Show(message, "Info", duration)
end

function NotificationController:ShowSuccess(message: string, duration: number?)
	self:Show(message, "Success", duration)
end

function NotificationController:ShowWarning(message: string, duration: number?)
	self:Show(message, "Warning", duration)
end

function NotificationController:ShowDanger(message: string, duration: number?)
	self:Show(message, "Danger", duration)
end

function NotificationController:_connectGeneratorNotifications()
	table.insert(self._connections, GeneratorService.GeneratorCooldown:Connect(function(generatorId: string, onCooldown: boolean)
		if generatorId == "all" or not onCooldown then
			return
		end

		if RoleShowController and RoleShowController:IsKiller() then
			self:ShowWarning("A survivor failed a generator.")
		else
			self:ShowWarning("Generator failed. It is cooling down.")
		end
	end))
end

function NotificationController:_connectPerkNotifications()
	table.insert(self._connections, PerkEffectsService.ActivatePerk:Connect(function(perkName: string, duration: number)
		if perkName == "Blackout" then
			self:ShowDanger("Blackout activated.", duration)
		elseif perkName == "FreezeGenerators" then
			self:ShowWarning("Generators are frozen.", duration)
		end
	end))
end

function NotificationController:KnitStart()
	self:_resolveUi()
	self:_connectGeneratorNotifications()
	self:_connectPerkNotifications()
end

function NotificationController:KnitInit()
	GeneratorService = Knit.GetService("GeneratorService")
	PerkEffectsService = Knit.GetService("PerkEffectsService")
	RoleShowController = Knit.GetController("RoleShowController")
end

return NotificationController
