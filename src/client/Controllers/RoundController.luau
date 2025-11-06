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
        warn("[RoundController] Main GUI not found")
        return 
    end
    
    local statusLabel = mainGui:FindFirstChild("Status", true)
    if statusLabel and statusLabel:IsA("TextLabel") then
        statusLabel.Text = status
        print("[RoundController] Updated status label to:", status)
    else
        warn("[RoundController] Status TextLabel not found in Main GUI")
        print("[RoundController] Available children in Main:")
        for _, child in ipairs(mainGui:GetDescendants()) do
            if child:IsA("TextLabel") then
                print("  TextLabel found:", child:GetFullName())
            end
        end
    end
end

function RoundController:KnitStart()
    local RoundService = Knit.GetService("RoundService")
    
    RoundService.RoleAssigned:Connect(function(role)
        self.playerRole = role
        print("[RoundController] Player role assigned:", role)
    end)
    
    RoundService.StatusChanged:Connect(function(status)
        print("[RoundController] Status changed:", status)
        updateStatusDisplay(status)
    end)
end

function RoundController:KnitInit()
end

return RoundController