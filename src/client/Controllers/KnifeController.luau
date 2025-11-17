local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage.Packages

local Knit = require(Packages.Knit)

local KnifeController = Knit.CreateController({
    Name = "KnifeController",
    _animation1 = nil,
    _animation2 = nil,
    _idleAnimation = nil,
    _animationTrack1 = nil,
    _animationTrack2 = nil,
    _idleAnimationTrack = nil,
    _isAnimating = false,
    _useFirstAnimation = true,
    _trail = nil,
})

local player = Players.LocalPlayer
local KnifeService

function KnifeController:IsKnifeEquipped()
    local character = player.Character
    if not character then return false end
    
    local knife = character:FindFirstChild("Knife")
    return knife ~= nil and knife:IsA("Tool")
end

function KnifeController:LoadAnimation()
    local character = player.Character
    if not character then return end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    
    if not self._animation1 then
        self._animation1 = Instance.new("Animation")
        self._animation1.AnimationId = "rbxassetid://131699929199125"
    end
    
    if not self._animation2 then
        self._animation2 = Instance.new("Animation")
        self._animation2.AnimationId = "rbxassetid://127808105361505"
    end
    
    if not self._idleAnimation then
        self._idleAnimation = Instance.new("Animation")
        self._idleAnimation.AnimationId = "rbxassetid://133821879724965"
    end
    
    self._animationTrack1 = humanoid:LoadAnimation(self._animation1)
    self._animationTrack2 = humanoid:LoadAnimation(self._animation2)
    self._idleAnimationTrack = humanoid:LoadAnimation(self._idleAnimation)
    self._idleAnimationTrack.Priority = Enum.AnimationPriority.Idle
    self._animationTrack1.Priority = Enum.AnimationPriority.Action
    self._animationTrack2.Priority = Enum.AnimationPriority.Action
    
    if self._idleAnimationTrack then
        self._idleAnimationTrack.Looped = true
    end
end

function KnifeController:PlayKnifeAnimation()
    if self._isAnimating then
        return
    end
    
    if not self._animationTrack1 or not self._animationTrack2 then
        self:LoadAnimation()
    end
    
    self._isAnimating = true
    
    if self._trail then
        self._trail.Enabled = true
    end
    
    local trackToPlay = self._useFirstAnimation and self._animationTrack1 or self._animationTrack2
    
    if trackToPlay then
        trackToPlay:Play()
        
        trackToPlay.Stopped:Wait()
        
        if self._trail then
            self._trail.Enabled = false
        end
        
        self._useFirstAnimation = not self._useFirstAnimation
        self._isAnimating = false
    else
        self._isAnimating = false
    end
end

function KnifeController:KnitStart() 
    player.CharacterAdded:Connect(function(character)
        character:WaitForChild("Humanoid")
        self:LoadAnimation()
        self:SetupKnifeTool(character)
    end)
    
    if player.Character then
        self:LoadAnimation()
        self:SetupKnifeTool(player.Character)
    end
    
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            if self:IsKnifeEquipped() then
                
                KnifeService:KnifeAttack()
                
                self:PlayKnifeAnimation()
            end
        end
    end)
end

function KnifeController:SetupKnifeTool(character)
    local knife = character:WaitForChild("Knife", 10)
    if not knife or not knife:IsA("Tool") then return end
    
    local handle = knife:FindFirstChild("Handle")
    if handle then
        if not handle:FindFirstChild("Trail") then
            local attachment0 = Instance.new("Attachment")
            attachment0.Name = "Attachment0"
            attachment0.Parent = handle
            
            local attachment1 = Instance.new("Attachment")
            attachment1.Name = "Attachment1"
            attachment1.Position = Vector3.new(0, 2, 0)
            attachment1.Parent = handle
            
            local trail = Instance.new("Trail")
            trail.Name = "Trail"
            trail.Attachment0 = attachment0
            trail.Attachment1 = attachment1
            trail.Color = ColorSequence.new(Color3.new(1, 1, 1))
            trail.Transparency = NumberSequence.new(0.5)
            trail.Lifetime = 0.3
            trail.Enabled = false
            trail.Parent = handle
            
            self._trail = trail
        else
            self._trail = handle:FindFirstChild("Trail")
        end
    end
    
    knife.Equipped:Connect(function()
        if self._idleAnimationTrack then
            self._idleAnimationTrack:Play()
        end
    end)
    
    knife.Unequipped:Connect(function()
        if self._idleAnimationTrack then
            self._idleAnimationTrack:Stop()
        end
    end)
end

function KnifeController:KnitInit()
    KnifeService = Knit.GetService("KnifeService")
end

return KnifeController