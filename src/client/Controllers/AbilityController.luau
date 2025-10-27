local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage.Packages
local Shared = ReplicatedStorage.Shared

local Knit = require(Packages.Knit)
local AbilityEnums = require(Shared.Data.AbilityEnums)

local DataController
local DataService

local AbilityController = Knit.CreateController({
    Name = "AbilityController",
})

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainGui = playerGui:WaitForChild("Main")
local framesFolder = mainGui:WaitForChild("Frames")
local utilityFrame = mainGui:WaitForChild("Utility")
local centerFrame = utilityFrame:WaitForChild("Center")

local abilityTemplate = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("UIAssets"):WaitForChild("AbilityTemplate")

local keyBindings = {
    [Enum.KeyCode.R] = "Slot1",
    [Enum.KeyCode.Q] = "Slot2", 
    [Enum.KeyCode.E] = "Slot3"
}

function AbilityController:UseAbility(slotName)
    local playerData = DataController.getData()
    
    if not playerData or not playerData.Abilities then
        warn("No player data available")
        return
    end
    
    local abilitySlot = playerData.Abilities[slotName]
    
    if not abilitySlot or abilitySlot.Name == "" or abilitySlot.Quantity <= 0 then
        warn("No ability available in slot:", slotName)
        return
    end
    
    local abilityData = AbilityEnums[abilitySlot.Name]
    
    if not abilityData then
        warn("No ability data found for:", abilitySlot.Name)
        return
    end
    
    local success, message = DataService:UseAbility(slotName):await()
    if success then
        self:PerformAbilityEffect(abilitySlot.Name, abilityData)
    else
        warn("Failed to use ability:", message)
    end
end

function AbilityController:UpdateAbilityUI()
    local playerData = DataController.getData()
    if not playerData or not playerData.Abilities then
        return
    end
    
    -- Attempt to update UI - fail silently if UI not available
    pcall(function()
        -- Cleanup existing UI elements
        for _, child in pairs(centerFrame:GetChildren()) do
            if child:IsA("GuiObject") and child.Name:find("AbilitySlot") then
                child:Destroy()
            end
        end
        
        -- Create new UI elements
        for slotName, abilitySlot in pairs(playerData.Abilities) do
            if abilitySlot.Name ~= "" and abilitySlot.Quantity > 0 then
                local abilityData = AbilityEnums[abilitySlot.Name]
                if abilityData then
                    local newTemplate = abilityTemplate:Clone()
                    newTemplate.Name = "AbilitySlot" .. slotName
                    newTemplate.Visible = true
                    newTemplate.Parent = centerFrame
                    
                    local imageLabel = newTemplate:FindFirstChild("ImageLabel")
                    if imageLabel then
                        imageLabel.Image = "rbxassetid://" .. abilityData.Image
                    end
                    
                    local keybindLabel = newTemplate:FindFirstChild("Keybind")
                    if keybindLabel then
                        for keyCode, slot in pairs(keyBindings) do
                            if slot == slotName then
                                keybindLabel.Text = keyCode.Name
                                break
                            end
                        end
                    end
                    
                    local quantityLabel = newTemplate:FindFirstChild("Quantity")
                    if quantityLabel then
                        quantityLabel.Text = "x" .. abilitySlot.Quantity
                    end
                end
            end
        end
    end)
end

function AbilityController:PerformAbilityEffect(abilityName, abilityData)
    local modulePath = script.Parent.Parent.Modules.Abilities[abilityName]
    
    local success, abilityModule = pcall(function()
        return require(modulePath)
    end)
    
    if success and abilityModule and abilityModule.Execute then
        if abilityName == "Invisibility" then
            task.spawn(function()
                abilityModule.Execute()
            end)
        else
            abilityModule.Execute()
        end
    end
end

function AbilityController:KnitStart()
    -- Key bindings - completely independent of UI
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end
        
        local slotName = keyBindings[input.KeyCode]
        if slotName then
            self:UseAbility(slotName)
        end
    end)
    
    -- UI updates only when data changes
    DataController.onReplicated("Abilities"):Connect(function()
        self:UpdateAbilityUI()
    end)
    
    task.wait(1)
    -- Initial UI update
    self:UpdateAbilityUI()
end

function AbilityController:KnitInit()
    DataController = Knit.GetController("DataController")
    DataService = Knit.GetService("DataService")
end

return AbilityController