local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local GeneratorService = Knit.CreateService({
    Name = "GeneratorService",
    Client = {
        ProgressUpdated = Knit.CreateSignal(),
        GeneratorCooldown = Knit.CreateSignal(),
    },
})

local generatorProgress = {}
local playerRoles = {}
local generatorCooldowns = {}

local function createHighlight(parent: Instance, fillColor: Color3, fillTransparency: number, duration: number)
    local highlight = Instance.new("Highlight")
    highlight.FillColor = fillColor
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = fillTransparency
    highlight.OutlineTransparency = 0
    highlight.Parent = parent
    
    if duration then
        task.delay(duration, function()
            if highlight and highlight.Parent then
                highlight:Destroy()
            end
        end)
    end
    
    return highlight
end

function GeneratorService:SetPlayerRole(player: Player, role: string)
    playerRoles[player] = role
end

function GeneratorService:GetProgress(generatorId: string): number
    return generatorProgress[generatorId] or 0
end

function GeneratorService:IsOnCooldown(generatorId: string): boolean
    return generatorCooldowns[generatorId] ~= nil
end

function GeneratorService:StartCooldown(generatorId: string, generator: Instance)
    if generatorCooldowns[generatorId] then return end
    
    generatorCooldowns[generatorId] = true
    self.Client.GeneratorCooldown:FireAll(generatorId, true)
    
    local primaryPart = nil
    if generator:IsA("Model") then
        primaryPart = generator.PrimaryPart or generator:FindFirstChildWhichIsA("BasePart")
    elseif generator:IsA("BasePart") then
        primaryPart = generator
    end
    
    if primaryPart then
        local Players = game:GetService("Players")
        for _, player in Players:GetPlayers() do
            if player.Character and player.Character.PrimaryPart then
                local distance = (player.Character.PrimaryPart.Position - primaryPart.Position).Magnitude
                if distance <= 15 then
                    createHighlight(
                        player.Character,
                        Color3.fromRGB(255, 0, 0),
                        0.5,
                        5
                    )
                end
            end
        end
        
        local highlightTarget = generator:IsA("Model") and generator or primaryPart
        createHighlight(
            highlightTarget,
            Color3.fromRGB(255, 165, 0),
            0.3,
            5
        )
    end
    
    task.delay(5, function()
        generatorCooldowns[generatorId] = nil
        self.Client.GeneratorCooldown:FireAll(generatorId, false)
    end)
end

function GeneratorService.Client:GetProgress(player: Player, generatorId: string): number
    return self.Server:GetProgress(generatorId)
end

function GeneratorService.Client:IsOnCooldown(player: Player, generatorId: string): boolean
    return self.Server:IsOnCooldown(generatorId)
end

function GeneratorService.Client:AddProgress(player: Player, generatorId: string, amount: number)
    if self.Server:IsOnCooldown(generatorId) then
        warn("[GeneratorService] Generator is on cooldown, rejecting interaction")
        return nil
    end
    
    if playerRoles[player] ~= "Survivor" then
        warn("[GeneratorService] Player", player.Name, "is not a Survivor (role:", playerRoles[player], "), rejecting progress")
        return nil
    end
    
    local currentProgress = self.Server:GetProgress(generatorId)
    local newProgress = math.min(currentProgress + amount, 100)
    
    generatorProgress[generatorId] = newProgress
    
    self.ProgressUpdated:FireAll(generatorId, newProgress)
    
    if newProgress >= 100 then
        print("[GeneratorService] Generator", generatorId, "completed!")
    end
    
    return newProgress
end

function GeneratorService.Client:TriggerCooldown(player: Player, generatorId: string, generator: Instance)
    if self.Server:IsOnCooldown(generatorId) then
        warn("[GeneratorService] Generator already on cooldown")
        return
    end
    
    self.Server:StartCooldown(generatorId, generator)
end

function GeneratorService:KnitStart()
    local RoundService = Knit.GetService("RoundService")
    local Players = game:GetService("Players")
    
    Players.PlayerRemoving:Connect(function(player)
        playerRoles[player] = nil
    end)
    
    print("GeneratorService started")
end

function GeneratorService:KnitInit()
end

return GeneratorService
