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

function RoundController:KnitStart()
    local RoundService = Knit.GetService("RoundService")
    
    RoundService.RoleAssigned:Connect(function(role)
        self.playerRole = role
    end)
    
    RoundService.StatusChanged:Connect(function(status)
        updateStatusDisplay(status)
    end)
end

function RoundController:KnitInit()
end

return RoundController