local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages

local Knit = require(Packages.Knit)

local KnifeService = Knit.CreateService({
    Name = "KnifeService",
    Client = {
        KnifeAttack = "KnifeAttack",
    },
    _attackDebounce = {}
})

function KnifeService.Client:KnifeAttack(player: Player)
    if KnifeService._attackDebounce[player.UserId] then
        return
    end
    
    KnifeService._attackDebounce[player.UserId] = true
    
    local character = player.Character
    if not character then 
        KnifeService._attackDebounce[player.UserId] = nil
        return 
    end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end
    
    local hitbox = Instance.new("Part")
    hitbox.Name = "KnifeHitbox"
    hitbox.Size = Vector3.new(5, 5, 5)
    hitbox.CFrame = rootPart.CFrame * CFrame.new(0, 0, -5.5)
    hitbox.Anchored = false
    hitbox.CanCollide = false
    hitbox.Transparency = 1
    hitbox.Color = Color3.new(1, 0, 0)
    hitbox.Material = Enum.Material.Neon
    hitbox.Massless = true
    hitbox.Parent = workspace
    
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = rootPart
    weld.Part1 = hitbox
    weld.Parent = hitbox
    
    local attachment0 = Instance.new("Attachment")
    attachment0.Parent = rootPart
    attachment0.Position = Vector3.new(0, 0, -5.5)
    
    local attachment1 = Instance.new("Attachment")
    attachment1.Parent = hitbox
    
    local alignPosition = Instance.new("AlignPosition")
    alignPosition.Attachment0 = attachment1
    alignPosition.Attachment1 = attachment0
    alignPosition.MaxForce = math.huge
    alignPosition.Responsiveness = 200
    alignPosition.Parent = hitbox
    
    local alignOrientation = Instance.new("AlignOrientation")
    alignOrientation.Attachment0 = attachment1
    alignOrientation.Attachment1 = attachment0
    alignOrientation.MaxTorque = math.huge
    alignOrientation.Responsiveness = 200
    alignOrientation.Parent = hitbox
    
    local hitPlayers = {}
    
    local touchConnection = hitbox.Touched:Connect(function(hit)
        if hit.Parent and hit.Parent:FindFirstChild("Humanoid") then
            local hitPlayer = game.Players:GetPlayerFromCharacter(hit.Parent)
            
            if hitPlayer and hitPlayer ~= player and not hitPlayers[hitPlayer.UserId] then
                hitPlayers[hitPlayer.UserId] = true
                
                local humanoid = hit.Parent:FindFirstChild("Humanoid")
                if humanoid then
                    humanoid:TakeDamage(25)
                end
            end
        end
    end)
    
    task.delay(1, function()
        touchConnection:Disconnect()
        hitbox:Destroy()
        KnifeService._attackDebounce[player.UserId] = nil
    end)
end

function KnifeService:KnitStart()
end

function KnifeService:KnitInit() 
end

return KnifeService
