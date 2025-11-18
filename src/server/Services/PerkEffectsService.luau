local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage.Packages
local Shared = ReplicatedStorage.Shared

local Knit = require(Packages.Knit)
local KillerPerks = require(Shared.Data.KillerPerks)
local SurvivorPerks = require(Shared.Data.SurvivorPerks)

local PerkEffectsService = Knit.CreateService({
    Name = "PerkEffectsService",
    Client = {
        ActivatePerk = Knit.CreateSignal(),
    },
    _activeCooldowns = {},
})

local DataService
local RoundService
local GeneratorService

local function isOnCooldown(player: Player, perkName: string): boolean
    local key = player.UserId .. "_" .. perkName
    if PerkEffectsService._activeCooldowns[key] then
        return true
    end
    return false
end

local function setCooldown(player: Player, perkName: string, duration: number)
    local key = player.UserId .. "_" .. perkName
    PerkEffectsService._activeCooldowns[key] = true
    
    task.delay(duration, function()
        PerkEffectsService._activeCooldowns[key] = nil
    end)
end

function PerkEffectsService:ActivateInvisibility(player: Player)
    self.Client.ActivatePerk:Fire(player, "Invisibility", SurvivorPerks["Invisibility"].Duration)
    
    local character = player.Character
    if not character then return false end
    
    for _, part in character:GetDescendants() do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
            part.Transparency = 1
        elseif part:IsA("Decal") or part:IsA("Texture") then
            part.Transparency = 1
        end
    end
    
    task.delay(SurvivorPerks["Invisibility"].Duration, function()
        if character and character.Parent then
            for _, part in character:GetDescendants() do
                if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                    if part.Name == "Head" then
                        part.Transparency = 0
                    else
                        part.Transparency = 0
                    end
                elseif part:IsA("Decal") or part:IsA("Texture") then
                    part.Transparency = 0
                end
            end
        end
    end)
    
    return true
end

function PerkEffectsService:ActivateHeal(player: Player)
    local character = player.Character
    if not character then return false end
    
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then return false end
    
    humanoid.Health = math.min(humanoid.Health + SurvivorPerks["Heal"].HealAmount, humanoid.MaxHealth)
    
    return true
end

function PerkEffectsService:ActivateSprintBurst(player: Player)
    local character = player.Character
    if not character then return false end
    
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then return false end
    
    local originalSpeed = humanoid.WalkSpeed
    humanoid.WalkSpeed = originalSpeed * SurvivorPerks["Sprint Burst"].SpeedMultiplier
    
    task.delay(SurvivorPerks["Sprint Burst"].Duration, function()
        if humanoid and humanoid.Parent then
            humanoid.WalkSpeed = originalSpeed
        end
    end)
    
    return true
end

function PerkEffectsService:ActivateQuickFix(player: Player)
    local session = DataService and DataService.getSession(player)
    if session then
        session.Data._quickFixActive = true
        session.Data._quickFixEnd = os.time() + SurvivorPerks["Quick Fix"].Duration
    end
    
    task.delay(SurvivorPerks["Quick Fix"].Duration, function()
        if session and session.Data then
            session.Data._quickFixActive = false
        end
    end)
    
    return true
end

function PerkEffectsService:ActivateShowPlayers(player: Player)
    self.Client.ActivatePerk:Fire(player, "Show Players", KillerPerks["Show Players"].Duration)
    
    local highlights = {}
    
    for _, otherPlayer in Players:GetPlayers() do
        if otherPlayer ~= player and otherPlayer.Character then
            local highlight = Instance.new("Highlight")
            highlight.FillColor = Color3.fromRGB(255, 0, 0)
            highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
            highlight.FillTransparency = 0.5
            highlight.OutlineTransparency = 0
            highlight.Parent = otherPlayer.Character
            
            table.insert(highlights, highlight)
        end
    end
    
    task.delay(KillerPerks["Show Players"].Duration, function()
        for _, highlight in highlights do
            if highlight and highlight.Parent then
                highlight:Destroy()
            end
        end
    end)
    
    return true
end

function PerkEffectsService:ActivateBloodlust(player: Player)
    local character = player.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return false end
    
    local killerPosition = character.HumanoidRootPart.Position
    local closestPlayer = nil
    local closestDistance = math.huge
    
    for _, otherPlayer in Players:GetPlayers() do
        if otherPlayer ~= player and table.find(RoundService.PlayersInRound, otherPlayer) then
            local otherCharacter = otherPlayer.Character
            if otherCharacter and otherCharacter:FindFirstChild("HumanoidRootPart") then
                local distance = (otherCharacter.HumanoidRootPart.Position - killerPosition).Magnitude
                if distance < closestDistance then
                    closestDistance = distance
                    closestPlayer = otherPlayer
                end
            end
        end
    end
    
    if not closestPlayer then return false end
    
    local targetCharacter = closestPlayer.Character
    if not targetCharacter then return false end
    
    local highlight = Instance.new("Highlight")
    highlight.FillColor = Color3.fromRGB(255, 0, 0)
    highlight.OutlineColor = Color3.fromRGB(150, 0, 0)
    highlight.FillTransparency = 0.5
    highlight.OutlineTransparency = 0
    highlight.Parent = targetCharacter
    
    if not self._bloodlustTargets then
        self._bloodlustTargets = {}
    end
    self._bloodlustTargets[player.UserId] = closestPlayer.UserId
    
    task.delay(KillerPerks["Bloodlust"].Duration, function()
        if highlight and highlight.Parent then
            highlight:Destroy()
        end
        if self._bloodlustTargets then
            self._bloodlustTargets[player.UserId] = nil
        end
    end)
    
    return true
end

function PerkEffectsService:ActivateFreezeGenerators(player: Player)
    self.Client.ActivatePerk:FireAll("FreezeGenerators", KillerPerks["Freeze Generators"].Duration)
    
    if GeneratorService then
        GeneratorService:FreezeGenerators(KillerPerks["Freeze Generators"].Duration)
    end
    
    return true
end

function PerkEffectsService:ActivateBlackout(player: Player)
    for _, otherPlayer in Players:GetPlayers() do
        if otherPlayer ~= player then
            self.Client.ActivatePerk:Fire(otherPlayer, "Blackout", KillerPerks["Blackout"].Duration)
        end
    end
    
    return true
end

function PerkEffectsService:ActivateHuntersMark(player: Player)
    local character = player.Character
    if not character or not character.PrimaryPart then return false end
    
    local nearestPlayer = nil
    local nearestDistance = math.huge
    
    for _, otherPlayer in Players:GetPlayers() do
        if otherPlayer ~= player and otherPlayer.Character and otherPlayer.Character.PrimaryPart then
            local distance = (character.PrimaryPart.Position - otherPlayer.Character.PrimaryPart.Position).Magnitude
            if distance < nearestDistance then
                nearestDistance = distance
                nearestPlayer = otherPlayer
            end
        end
    end
    
    if nearestPlayer and nearestPlayer.Character then
        local highlight = Instance.new("Highlight")
        highlight.FillColor = Color3.fromRGB(255, 165, 0)
        highlight.OutlineColor = Color3.fromRGB(255, 255, 0)
        highlight.FillTransparency = 0.3
        highlight.OutlineTransparency = 0
        highlight.Parent = nearestPlayer.Character
        
        task.delay(KillerPerks["Hunter's Mark"].Duration, function()
            if highlight and highlight.Parent then
                highlight:Destroy()
            end
        end)
    end
    
    return true
end

function PerkEffectsService.Client:UsePerk(player: Player, perkName: string, isKiller: boolean)
    if isOnCooldown(player, perkName) then
        return false, "Ability on cooldown"
    end
    
    local perkData = isKiller and KillerPerks[perkName] or SurvivorPerks[perkName]
    if not perkData then
        return false, "Invalid perk"
    end
    
    local success = false
    
    if perkName == "Invisibility" then
        success = PerkEffectsService:ActivateInvisibility(player)
    elseif perkName == "Heal" then
        success = PerkEffectsService:ActivateHeal(player)
    elseif perkName == "Sprint Burst" then
        success = PerkEffectsService:ActivateSprintBurst(player)
    elseif perkName == "Quick Fix" then
        success = PerkEffectsService:ActivateQuickFix(player)
    elseif perkName == "Show Players" then
        success = PerkEffectsService:ActivateShowPlayers(player)
    elseif perkName == "Bloodlust" then
        success = PerkEffectsService:ActivateBloodlust(player)
    elseif perkName == "Freeze Generators" then
        success = PerkEffectsService:ActivateFreezeGenerators(player)
    elseif perkName == "Blackout" then
        success = PerkEffectsService:ActivateBlackout(player)
    elseif perkName == "Hunter's Mark" then
        success = PerkEffectsService:ActivateHuntersMark(player)
    end
    
    if success then
        setCooldown(player, perkName, perkData.Cooldown)
    end
    
    return success
end

function PerkEffectsService:IsBloodlustTarget(attackerUserId: number, targetUserId: number): boolean
    if not self._bloodlustTargets then return false end
    return self._bloodlustTargets[attackerUserId] == targetUserId
end

function PerkEffectsService:KnitStart()
end

function PerkEffectsService:KnitInit()
    DataService = Knit.GetService("DataService")
    RoundService = Knit.GetService("RoundService")
    GeneratorService = Knit.GetService("GeneratorService")
end

return PerkEffectsService
