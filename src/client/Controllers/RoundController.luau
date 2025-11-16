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
    
    local topContainer = mainGui:FindFirstChild("TopContainer")
    if not topContainer then
        return
    end
    
    local timer = topContainer:FindFirstChild("Timer")
    if not timer then
        return
    end
    
    local title = timer:FindFirstChild("Title")
    local subtitle = timer:FindFirstChild("Subtitle")
    
    -- Parse the status string (e.g., "Round (4:32)" or "Intermission (10)")
    local statusType, time = status:match("^(.-)%s*%((.-)%)$")
    
    if statusType and time then
        if title and title:IsA("TextLabel") then
            title.Text = statusType
        end
        
        if subtitle and subtitle:IsA("TextLabel") then
            subtitle.Text = time
        end
    else
        -- Fallback if format doesn't match
        if title and title:IsA("TextLabel") then
            title.Text = status
        end
        
        if subtitle and subtitle:IsA("TextLabel") then
            subtitle.Text = ""
        end
    end
end

local function updateGeneratorDisplay(completedCount)
    local mainGui = playerGUI:FindFirstChild("Main")
    if not mainGui then 
        return 
    end
    
    local topContainer = mainGui:FindFirstChild("TopContainer")
    if not topContainer then
        return
    end
    
    local timer = topContainer:FindFirstChild("Timer")
    if not timer then
        return
    end
    
    local generators = timer:FindFirstChild("Generators")
    if generators and generators:IsA("TextLabel") then
        generators.Text = string.format("%d/5 Generators", completedCount)
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
