local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local RoundController = Knit.CreateController({
    Name = "RoundController",
})

function RoundController:KnitStart() 
    local roundService = Knit.GetService("RoundService")
    
    roundService.StatusChanged:Connect(function(newStatus)
        local mainGui = Players.LocalPlayer.PlayerGui:WaitForChild("Main")
        local statusContainer = mainGui:WaitForChild("StatusContainer")
        local status = statusContainer:WaitForChild("Status")
        status.Text = newStatus
    end)
end

function RoundController:KnitInit() end

return RoundController