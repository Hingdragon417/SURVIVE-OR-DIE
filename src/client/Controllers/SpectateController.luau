local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local player = Players.LocalPlayer
local playerGUI = player:WaitForChild("PlayerGui")

local SpectateController = Knit.CreateController({
    Name = "SpectateController",
})

local RoundService
local playersInRound = {}
local currentSpectateIndex = 1
local isSpectating = false
local spectateClickConnection = nil

function SpectateController:StartSpectating()
    if isSpectating then return end
    
    self:UpdatePlayersInRound()
    task.wait(0.1)
    
    if #playersInRound == 0 then
        warn("[SpectateController] No other players to spectate")
        return
    end
    
    isSpectating = true
    self:SpectateNext()
    
    if spectateClickConnection then
        spectateClickConnection:Disconnect()
    end
    
    spectateClickConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local mousePos = UserInputService:GetMouseLocation()
            local guiObjects = playerGUI:GetGuiObjectsAtPosition(mousePos.X, mousePos.Y)
            
            local clickedWatchButton = false
            for _, obj in guiObjects do
                if obj.Name == "Watch" and (obj:IsA("GuiButton") or obj:IsA("ImageButton")) then
                    clickedWatchButton = true
                    break
                end
            end
            
            if not clickedWatchButton then
                self:SpectateNext()
            end
        end
    end)
end

function SpectateController:IsSpectating(): boolean
    return isSpectating
end

function SpectateController:UpdatePlayersInRound()
    RoundService:GetPlayersInRound():andThen(function(players)
        playersInRound = {}
        for _, p in ipairs(players or {}) do
            if p ~= player then
                table.insert(playersInRound, p)
            end
        end
    end):catch(function(err)
        warn("[SpectateController] Failed to get players in round:", err)
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
        warn("[SpectateController] No other players to spectate")
        self:StopSpectating()
        return
    end
    
    local camera = workspace.CurrentCamera
    if not camera then return end
    
    local character = targetPlayer.Character
    if character and character:FindFirstChild("Humanoid") then
        camera.CameraSubject = character.Humanoid
    end
end

function SpectateController:StopSpectating()
    if not isSpectating then return end
    
    isSpectating = false
    
    if spectateClickConnection then
        spectateClickConnection:Disconnect()
        spectateClickConnection = nil
    end
    
    local camera = workspace.CurrentCamera
    if not camera then return end
    
    if player.Character and player.Character:FindFirstChild("Humanoid") then
        camera.CameraSubject = player.Character.Humanoid
    end
    
    currentSpectateIndex = 1
end

function SpectateController:KnitStart()
    self:UpdatePlayersInRound()
end

function SpectateController:KnitInit()
    RoundService = Knit.GetService("RoundService")
    
    isSpectating = false
    if spectateClickConnection then
        spectateClickConnection:Disconnect()
        spectateClickConnection = nil
    end
end

return SpectateController