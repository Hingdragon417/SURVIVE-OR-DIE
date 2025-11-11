local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage.Packages

local Knit = require(Packages.Knit)

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
local BASE_SIZE = 1920

local function formatCash(amount: number): string
	if not amount or type(amount) ~= "number" then
		return "0"
	end
	
	if amount >= 1000000000 then
		return string.format("%.1fB", amount / 1000000000)
	elseif amount >= 1000000 then
		return string.format("%.1fM", amount / 1000000)
	elseif amount >= 1000 then
		return string.format("%.1fK", amount / 1000)
	else
		return tostring(math.floor(amount))
	end
end

local function updateCashDisplay(cash: number)
	if not cash or type(cash) ~= "number" then
		return
	end
	
	local mainGui = playerGui:FindFirstChild("Main")
	if not mainGui then return end
	
	local leftContainer = mainGui:FindFirstChild("LeftContainer")
	if not leftContainer then return end
	
	local coins = leftContainer:FindFirstChild("Coins")
	if not coins then return end
	
	local amount = coins:FindFirstChild("Amount")
	if not amount then return end
	
	local textLabel = amount:FindFirstChild("Text")
	if not textLabel or not textLabel:IsA("TextLabel") then return end
	
	textLabel.Text = formatCash(cash)
end

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
            updateAllUIStrokeThickness()
            
            local DataController = Knit.GetController("DataController")
            
            task.spawn(function()
                local playerData = DataController.waitForData()
                
                while not playerData.Cash do
                    task.wait(0.1)
                    playerData = DataController.getData()
                end
                
                DataController.onReplicated("Cash"):Connect(function()
                    local data = DataController.getData()
                    if data and data.Cash then
                        updateCashDisplay(data.Cash)
                    end
                end)
                
                updateCashDisplay(playerData.Cash)
            end)
        end)
        :catch(warn)
end
