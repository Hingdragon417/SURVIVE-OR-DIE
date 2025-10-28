local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage.Packages

local Knit = require(Packages.Knit)

local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera
local BASE_SIZE = 1920

local function updateAllUIStrokeThickness()
	local scale = camera.ViewportSize.X / BASE_SIZE
	
	for _, instance in ipairs(localPlayer.PlayerGui:GetDescendants()) do
		if instance:IsA("UIStroke") then
			local initial = instance:GetAttribute("InitialThickness")
			if not initial then
				initial = instance.Thickness
				instance:SetAttribute("InitialThickness", initial)
			end
			instance.Thickness = initial * scale
		end
	end
end

-- Connect to viewport size changes
camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateAllUIStrokeThickness)

do
    Knit.AddControllersDeep(script.Parent.Controllers)

    Knit.Start()
        :andThen(function()
            print("Client has started!")
            -- Call immediately after client starts
            updateAllUIStrokeThickness()
        end)
        :catch(warn)
end