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
    -- Check debounce
    if KnifeService._attackDebounce[player.UserId] then
        print(string.format("[KnifeService] %s attack blocked by debounce", player.Name))
        return
    end
    
    print(string.format("[KnifeService] %s attacked with knife", player.Name))
    
    -- Set debounce
    KnifeService._attackDebounce[player.UserId] = true
    
    local character = player.Character
    if not character then 
        KnifeService._attackDebounce[player.UserId] = nil
        return 
    end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end
    
    -- Create hitbox
    local hitbox = Instance.new("Part")
    hitbox.Name = "KnifeHitbox"
    hitbox.Size = Vector3.new(5, 5, 5)
    hitbox.CFrame = rootPart.CFrame * CFrame.new(0, 0, -5.5) -- 5.5 studs in front
    hitbox.Anchored = false
    hitbox.CanCollide = false
    hitbox.Transparency = 1
    hitbox.Color = Color3.new(1, 0, 0) -- Red color
    hitbox.Material = Enum.Material.Neon
    hitbox.Massless = true
    hitbox.Parent = workspace
    
    -- Weld hitbox to player so it moves with them
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = rootPart
    weld.Part1 = hitbox
    weld.Parent = hitbox
    
    -- Create attachment for proper offset
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
    
    print(string.format("[KnifeService] Created hitbox at %s", tostring(hitbox.Position)))
    
    -- Track which players have been hit to prevent multiple damage
    local hitPlayers = {}
    
    -- Damage players that touch the hitbox
    local touchConnection = hitbox.Touched:Connect(function(hit)
        if hit.Parent and hit.Parent:FindFirstChild("Humanoid") then
            local hitPlayer = game.Players:GetPlayerFromCharacter(hit.Parent)
            
            -- Don't damage the attacker or players already hit
            if hitPlayer and hitPlayer ~= player and not hitPlayers[hitPlayer.UserId] then
                hitPlayers[hitPlayer.UserId] = true
                
                local humanoid = hit.Parent:FindFirstChild("Humanoid")
                if humanoid then
                    humanoid:TakeDamage(25)
                    print(string.format("[KnifeService] %s damaged %s for 25", player.Name, hitPlayer.Name))
                end
            end
        end
    end)
    
    -- Remove hitbox and debounce after animation time
    task.delay(1, function()
        touchConnection:Disconnect()
        hitbox:Destroy()
        KnifeService._attackDebounce[player.UserId] = nil
        print("[KnifeService] Hitbox removed and debounce cleared")
    end)
end

function KnifeService:KnitStart()
    print("[KnifeService] started")
end

function KnifeService:KnitInit() 
    
end

return KnifeService
