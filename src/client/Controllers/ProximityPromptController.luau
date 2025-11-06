local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local player = Players.LocalPlayer
local playerGUI = player:WaitForChild("PlayerGui")
local screenGui = playerGUI:WaitForChild("Main")

local ProximityPromptController = Knit.CreateController({
    Name = "ProximityPromptController",
})

local promptConnections = {}
local activePrompts = {}
local createdPrompts = {}

local function stylePrompt(prompt: ProximityPrompt, promptType: string)
    prompt.MaxActivationDistance = 10
    prompt.RequiresLineOfSight = false
    prompt.HoldDuration = 0
    prompt.KeyboardKeyCode = Enum.KeyCode.E
    prompt.RequiresLineOfSight = false
    
    if promptType == "Generator" then
        prompt.ActionText = "Use GenTemplate"
        prompt.ObjectText = "GenTemplate"
    end
end

local function onPromptTriggered(prompt: ProximityPrompt, player: Player, promptType: string, object: Instance)
    if player ~= Players.LocalPlayer then return end
    
    if promptType == "Generator" then
        local success, RoundController = pcall(function()
            return Knit.GetController("RoundController")
        end)
        
        if not success or not RoundController then
            warn("RoundController not found")
            return
        end
        
        if not RoundController.playerRole then
            warn("Player role not assigned yet, please wait for round to start")
            return
        end
        
        if RoundController.playerRole ~= "Survivor" then
            warn("Only Survivors can use generators!")
            return
        end
        
        local generatorFrame = screenGui:FindFirstChild("GeneratorFrame")
        
        if generatorFrame and generatorFrame:IsA("Frame") then
            generatorFrame.Visible = true
            
            local uiScale = generatorFrame:FindFirstChildWhichIsA("UIScale")
            if not uiScale then
                uiScale = Instance.new("UIScale")
                uiScale.Parent = generatorFrame
            end
            
            uiScale.Scale = 0
            
            local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            local tween = TweenService:Create(uiScale, tweenInfo, {Scale = 1})
            tween:Play()
            
            local GeneratorController = Knit.GetController("GeneratorController")
            if GeneratorController then
                GeneratorController:StartGenerator(object)
            end
        else
            warn("GeneratorFrame not found in Main ScreenGui")
        end
    end
end

function ProximityPromptController:CreatePromptForObject(object: Instance)
    if object:FindFirstChildWhichIsA("ProximityPrompt") then
        return
    end
    
    local promptType = nil
    
    if CollectionService:HasTag(object, "Generator") then
        promptType = "Generator"
    end
    
    if not promptType then
        return
    end
    
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "InteractionPrompt"
    prompt.Parent = object
    
    stylePrompt(prompt, promptType)
    
    createdPrompts[object] = prompt
    
    self:SetupPrompt(prompt, promptType, object)
end

function ProximityPromptController:SetupPrompt(prompt: ProximityPrompt, promptType: string, object: Instance)
    if promptConnections[prompt] then
        return
    end
    
    promptConnections[prompt] = {
        Triggered = prompt.Triggered:Connect(function(playerWhoTriggered)
            onPromptTriggered(prompt, playerWhoTriggered, promptType, object)
        end),
        
        PromptShown = prompt.PromptShown:Connect(function()
            activePrompts[prompt] = true
        end),
        
        PromptHidden = prompt.PromptHidden:Connect(function()
            activePrompts[prompt] = nil
        end)
    }
end

function ProximityPromptController:CleanupPrompt(prompt: ProximityPrompt)
    if promptConnections[prompt] then
        for _, connection in pairs(promptConnections[prompt]) do
            if connection then
                connection:Disconnect()
            end
        end
        promptConnections[prompt] = nil
    end
    activePrompts[prompt] = nil
end

function ProximityPromptController:CleanupAllPrompts()
    for prompt, _ in pairs(promptConnections) do
        self:CleanupPrompt(prompt)
    end
    
    for object, prompt in pairs(createdPrompts) do
        if prompt and prompt.Parent then
            prompt:Destroy()
        end
    end
    createdPrompts = {}
end

function ProximityPromptController:KnitStart()
    local interactables = CollectionService:GetTagged("Interactable")
    
    for _, object in ipairs(interactables) do
        self:CreatePromptForObject(object)
    end
    
    CollectionService:GetInstanceAddedSignal("Interactable"):Connect(function(object)
        self:CreatePromptForObject(object)
    end)
    
    CollectionService:GetInstanceRemovedSignal("Interactable"):Connect(function(object)
        local prompt = createdPrompts[object]
        if prompt then
            self:CleanupPrompt(prompt)
            if prompt.Parent then
                prompt:Destroy()
            end
            createdPrompts[object] = nil
        end
    end)
end

function ProximityPromptController:KnitInit()
    self:CleanupAllPrompts()
end

return ProximityPromptController