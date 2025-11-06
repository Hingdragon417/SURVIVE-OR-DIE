local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local GeneratorService = Knit.CreateService({
    Name = "GeneratorService",
    Client = {
        ProgressUpdated = Knit.CreateSignal(),
        GeneratorCooldown = Knit.CreateSignal(),
        ProgressSync = Knit.CreateSignal(),
    },
})

local MIN_HUMAN_REACTION_TIME = 0.1
local SUSPICIOUS_THRESHOLD = 3
local BUTTON_TIME_LIMIT = 2.5
local playerSuspicionCount = {}
local playerSlowClickCount = {}
local SLOW_CLICK_ALERT_THRESHOLD = 1

local generatorProgress = {}
local playerRoles = {}
local generatorCooldowns = {}
local playerGeneratorLocks = {}

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

function GeneratorService:GetButtonTimeLimit(): number
    return BUTTON_TIME_LIMIT
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
        
        for playerId, genId in pairs(playerGeneratorLocks) do
            if genId == generatorId then
                playerGeneratorLocks[playerId] = nil
            end
        end
    end)
end

function GeneratorService.Client:GetProgress(player: Player, generatorId: string): number
    return self.Server:GetProgress(generatorId)
end

function GeneratorService.Client:GetButtonTimeLimit(player: Player): number
    return self.Server:GetButtonTimeLimit()
end

function GeneratorService.Client:IsOnCooldown(player: Player, generatorId: string): boolean
    return self.Server:IsOnCooldown(generatorId)
end

function GeneratorService.Client:AddProgress(player: Player, generatorId: string, amount: number, reactionTime: number)
    if type(reactionTime) ~= "number" then
        warn("[GeneratorService] Invalid reaction time from", player.Name)
        return
    end
    
    if playerGeneratorLocks[player.UserId] and playerGeneratorLocks[player.UserId] ~= generatorId then
        warn("[GeneratorService] Player", player.Name, "is trying to progress a different generator than they started")
        return nil
    end
    
    if not playerGeneratorLocks[player.UserId] then
        playerGeneratorLocks[player.UserId] = generatorId
    end
    
    if reactionTime < MIN_HUMAN_REACTION_TIME then
        playerSuspicionCount[player.UserId] = (playerSuspicionCount[player.UserId] or 0) + 1
        warn("[GeneratorService] Suspicious reaction time from", player.Name, ":", reactionTime, "seconds")
        
        if playerSuspicionCount[player.UserId] >= SUSPICIOUS_THRESHOLD then
            player:Kick("Suspicious activity detected: Reaction time too fast")
            return
        end
    else
        playerSuspicionCount[player.UserId] = 0
    end
    
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
        playerGeneratorLocks[player.UserId] = nil
    end
    
    return newProgress
end

function GeneratorService.Client:TriggerCooldown(player: Player, generatorId: string, generator: Instance)
    if self.Server:IsOnCooldown(generatorId) then
        warn("[GeneratorService] Generator already on cooldown")
        return
    end
    
    playerGeneratorLocks[player.UserId] = nil
    
    self.Server:StartCooldown(generatorId, generator)
end

function GeneratorService.Client:ReportSlowClick(player: Player, generatorId: string, timeLimit: number)
    playerSlowClickCount[player.UserId] = (playerSlowClickCount[player.UserId] or 0) + 1
    
    warn("[GeneratorService] Player", player.Name, "failed to click within", timeLimit, "seconds")
    
    if playerSlowClickCount[player.UserId] >= SLOW_CLICK_ALERT_THRESHOLD then
        if player.Character and player.Character.PrimaryPart then
            local Players = game:GetService("Players")
            for _, otherPlayer in Players:GetPlayers() do
                if otherPlayer ~= player and otherPlayer.Character and otherPlayer.Character.PrimaryPart then
                    local distance = (otherPlayer.Character.PrimaryPart.Position - player.Character.PrimaryPart.Position).Magnitude
                    if distance <= 50 then
                        createHighlight(
                            player.Character,
                            Color3.fromRGB(255, 255, 0),
                            0.4,
                            3
                        )
                    end
                end
            end
        end
        
        playerSlowClickCount[player.UserId] = 0
    end
end

function GeneratorService:KnitStart()
    local RoundService = Knit.GetService("RoundService")
    local Players = game:GetService("Players")
    
    Players.PlayerRemoving:Connect(function(player)
        playerRoles[player] = nil
        playerSuspicionCount[player.UserId] = nil
        playerSlowClickCount[player.UserId] = nil
        playerGeneratorLocks[player.UserId] = nil
    end)
    
    task.spawn(function()
        while true do
            task.wait(1)
            for generatorId, progress in pairs(generatorProgress) do
                if progress > 0 then
                    self.Client.ProgressSync:FireAll(generatorId, progress)
                end
            end
        end
    end)
end

function GeneratorService:KnitInit()
end

return GeneratorService
