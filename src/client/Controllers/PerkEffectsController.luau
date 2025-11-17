local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local player = Players.LocalPlayer

local PerkEffectsController = Knit.CreateController({
    Name = "PerkEffectsController",
})

local PerkEffectsService
local activePerkConnection

local function applyBlackout(duration: number)
    local colorCorrection = Instance.new("ColorCorrectionEffect")
    colorCorrection.Brightness = -0.8
    colorCorrection.Contrast = 0.5
    colorCorrection.Saturation = -1
    colorCorrection.Parent = Lighting
    
    local blur = Instance.new("BlurEffect")
    blur.Size = 15
    blur.Parent = Lighting
    
    task.delay(duration, function()
        if colorCorrection and colorCorrection.Parent then
            colorCorrection:Destroy()
        end
        if blur and blur.Parent then
            blur:Destroy()
        end
    end)
end

local function freezeGeneratorsUI(duration: number)
    print("[PerkEffects] Generators frozen for", duration, "seconds")
end

local function applyInvisibility(duration: number)
    local character = player.Character
    if not character then
        return
    end
    
    for _, part in pairs(character:GetChildren()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
            part.Transparency = 1
        elseif part:IsA("Accessory") then
            local handle = part:FindFirstChild("Handle")
            if handle then
                handle.Transparency = 1
            end
        end
    end
    
    task.delay(duration, function()
        if not character or not character.Parent then
            return
        end
        
        for _, part in pairs(character:GetChildren()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                part.Transparency = 0
            elseif part:IsA("Accessory") then
                local handle = part:FindFirstChild("Handle")
                if handle then
                    handle.Transparency = 0
                end
            end
        end
    end)
end

local function showPlayers(duration: number)
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
    
    task.delay(duration, function()
        for _, highlight in highlights do
            if highlight and highlight.Parent then
                highlight:Destroy()
            end
        end
    end)
end

function PerkEffectsController:KnitStart()
    activePerkConnection = PerkEffectsService.ActivatePerk:Connect(function(perkName: string, duration: number)
        if perkName == "Blackout" then
            applyBlackout(duration)
        elseif perkName == "FreezeGenerators" then
            freezeGeneratorsUI(duration)
        elseif perkName == "Invisibility" then
            applyInvisibility(duration)
        elseif perkName == "Show Players" then
            showPlayers(duration)
        end
    end)
end

function PerkEffectsController:KnitInit()
    if activePerkConnection then
        activePerkConnection:Disconnect()
        activePerkConnection = nil
    end
    PerkEffectsService = Knit.GetService("PerkEffectsService")
end

return PerkEffectsController
