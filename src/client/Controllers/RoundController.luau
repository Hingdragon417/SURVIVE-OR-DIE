local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local player = Players.LocalPlayer
local playerGUI = player:WaitForChild("PlayerGui")

local RoundController = Knit.CreateController({
    Name = "RoundController",
})

RoundController.playerRole = nil

local RoundService

local function updateStatusDisplay(status)
    local mainGui = playerGUI:FindFirstChild("Main")
    if not mainGui then 
        return 
    end
    
    local statusLabel = mainGui:FindFirstChild("Status", true)
    if statusLabel and statusLabel:IsA("TextLabel") then
        statusLabel.Text = status
    end
end

local function updateGeneratorDisplay(completedCount)
    local mainGui = playerGUI:FindFirstChild("Main")
    if not mainGui then 
        return 
    end
    
    local statusContainer = mainGui:FindFirstChild("StatusContainer")
    if not statusContainer then
        return
    end
    
    local gensLabel = statusContainer:FindFirstChild("Gens")
    if gensLabel and gensLabel:IsA("TextLabel") then
        gensLabel.Text = string.format("%d/5 Generators", completedCount)
    end
end

function RoundController:KnitStart()
    
    RoundService.RoleAssigned:Connect(function(role)
        self.playerRole = role
    end)
    
    RoundService.StatusChanged:Connect(function(status)
        updateStatusDisplay(status)
    end)
    
    RoundService.GeneratorsCompleted:Connect(function(completedCount)
        updateGeneratorDisplay(completedCount)
    end)
end

function RoundController:KnitInit()
    RoundService = Knit.GetService("RoundService")
end

return RoundController
