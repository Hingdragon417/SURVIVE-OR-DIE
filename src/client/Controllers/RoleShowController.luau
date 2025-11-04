local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)

local Signal = require(ReplicatedStorage.Packages.Signal)

local RoleShowController = Knit.CreateController({
    Name = "RoleShowController",
    _assignedRole = nil,
    _isKiller = false,
    _roleChanged = nil
})

function RoleShowController:KnitInit()
    self._roundService = Knit.GetService("RoundService")
    self._roleChanged = Signal.new()
end

function RoleShowController:IsKiller()
    return self._isKiller
end

function RoleShowController:OnRoleChanged(callback)
    return self._roleChanged:Connect(callback)
end

function RoleShowController:AnimateRoleText(finalRole)
    local main = Players.LocalPlayer.PlayerGui:WaitForChild("Main")
    local roleShow = main:WaitForChild("RoleShow")
    local roleText = roleShow:WaitForChild("Role")
    
    roleShow.Visible = true
    
    -- Fixed animation timing for both roles
    local flashDuration = 0.15
    for i = 1, 8 do
        roleText.Text = "Killer"
        roleText.TextColor3 = Color3.fromRGB(255, 0, 0)
        task.wait(flashDuration)
        
        roleText.Text = "Survivor"
        roleText.TextColor3 = Color3.fromRGB(0, 255, 0)
        task.wait(flashDuration)
    end
    
    -- Final role reveal with consistent timing
    roleText.Text = finalRole
    roleText.TextColor3 = if finalRole == "Killer" 
        then Color3.fromRGB(255, 0, 0) 
        else Color3.fromRGB(0, 255, 0)
    
    task.wait(2)
    roleShow.Visible = false
end

function RoleShowController:KnitStart()
    self._roundService.RoleAssigned:Connect(function(role)
        self._isKiller = role == "Killer"
        if role then
            task.spawn(function()
                self:AnimateRoleText(role)
            end)
            self._roleChanged:Fire(role)
        end
    end)
end

return RoleShowController