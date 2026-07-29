local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local player = Players.LocalPlayer
local playerGUI = player:WaitForChild("PlayerGui")
local mainGui = playerGUI:WaitForChild("Main")
local framesFolder = mainGui:WaitForChild("Frames")
local watchFrame = framesFolder:WaitForChild("Watch")
local watchContent = watchFrame:WaitForChild("Content")
local leftButton = watchContent:WaitForChild("Left")
local rightButton = watchContent:WaitForChild("Right")
local exitButton = watchFrame:WaitForChild("Exit")
local usernameLabel = watchContent:WaitForChild("Username")

local SpectateController = Knit.CreateController({
    Name = "SpectateController",
})

local RoundService
local NotificationController
local playersInRound = {}
local currentSpectateIndex = 1
local isSpectating = false
local uiConnections = {}

local function setUsername(targetPlayer: Player?)
    if usernameLabel and usernameLabel:IsA("TextLabel") then
        usernameLabel.Text = targetPlayer and targetPlayer.Name or ""
    end
end

function SpectateController:StartSpectating()
    if isSpectating then return end
    
    self:UpdatePlayersInRound():andThen(function()
        if #playersInRound == 0 then
            if NotificationController then
                NotificationController:ShowWarning("No players are available to spectate.")
            else
                warn("[SpectateController] No other players to spectate")
            end
            return
        end

        isSpectating = true
        watchFrame.Visible = true
        self:SpectateNext()
    end)
end

function SpectateController:IsSpectating(): boolean
    return isSpectating
end

function SpectateController:UpdatePlayersInRound()
    return RoundService:GetPlayersInRound():andThen(function(players)
        playersInRound = {}
        for _, p in ipairs(players or {}) do
            if p ~= player then
                table.insert(playersInRound, p)
            end
        end
    end):catch(function(err)
        warn("[SpectateController] Failed to get players in round:", err)
        if NotificationController then
            NotificationController:ShowWarning("Could not load players to spectate.")
        end
    end)
end

function SpectateController:SpectateNext()
    if #playersInRound == 0 then
        return
    end
    
    currentSpectateIndex = currentSpectateIndex + 1
    if currentSpectateIndex > #playersInRound then
        currentSpectateIndex = 1
    end
    
    self:SpectatePlayer(playersInRound[currentSpectateIndex])
end

function SpectateController:SpectatePrevious()
    if #playersInRound == 0 then
        return
    end
    
    currentSpectateIndex = currentSpectateIndex - 1
    if currentSpectateIndex < 1 then
        currentSpectateIndex = #playersInRound
    end
    
    self:SpectatePlayer(playersInRound[currentSpectateIndex])
end

function SpectateController:SpectatePlayer(targetPlayer: Player)
    if not targetPlayer or targetPlayer == player then
        return
    end
    
    if #playersInRound == 0 then
        if NotificationController then
            NotificationController:ShowWarning("No players are available to spectate.")
        else
            warn("[SpectateController] No other players to spectate")
        end
        self:StopSpectating()
        return
    end
    
    local camera = workspace.CurrentCamera
    if not camera then return end
    
    local character = targetPlayer.Character
    if character and character:FindFirstChild("Humanoid") then
        camera.CameraSubject = character.Humanoid
    end

    setUsername(targetPlayer)
end

function SpectateController:StopSpectating()
    if not isSpectating then return end
    
    isSpectating = false
    watchFrame.Visible = false
    setUsername(nil)
    
    local camera = workspace.CurrentCamera
    if not camera then return end
    
    if player.Character and player.Character:FindFirstChild("Humanoid") then
        camera.CameraSubject = player.Character.Humanoid
    end
    
    currentSpectateIndex = 1
end

function SpectateController:KnitStart()
    watchFrame.Visible = false

    table.insert(uiConnections, leftButton.MouseButton1Click:Connect(function()
        self:SpectatePrevious()
    end))

    table.insert(uiConnections, rightButton.MouseButton1Click:Connect(function()
        self:SpectateNext()
    end))

    table.insert(uiConnections, exitButton.MouseButton1Click:Connect(function()
        self:StopSpectating()
    end))

    self:UpdatePlayersInRound()
end

function SpectateController:KnitInit()
    RoundService = Knit.GetService("RoundService")
    NotificationController = Knit.GetController("NotificationController")
    
    isSpectating = false
    for _, connection in ipairs(uiConnections) do
        if connection then
            connection:Disconnect()
        end
    end
    uiConnections = {}
end

return SpectateController
