local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local player = Players.LocalPlayer
local playerGUI = player:WaitForChild("PlayerGui")
local screenGui = playerGUI:WaitForChild("Main")

local GeneratorController = Knit.CreateController({
    Name = "GeneratorController",
})

local GeneratorService
local currentGenerator = nil
local currentGeneratorObject = nil
local activeButtons = {}
local clickStartTime = nil
local clickAwayConnection = nil
local movementConnection = nil
local frameClickConnection = nil
local progressUpdatedConnection = nil
local generatorCooldownConnection = nil
local initialPosition = nil
local generatorCooldowns = {}
local buttonTimeLimit = 2.5

local function clearButtons()
    for _, button in ipairs(activeButtons) do
        if button and button.Parent then
            button:Destroy()
        end
    end
    activeButtons = {}
end

local function getRandomPosition(clickBox: Frame, buttonAbsoluteSize: Vector2, edgePadding: number): UDim2
    local clickBoxWidth = clickBox.AbsoluteSize.X
    local clickBoxHeight = clickBox.AbsoluteSize.Y
    
    local minX = edgePadding + buttonAbsoluteSize.X / 2
    local maxX = clickBoxWidth - edgePadding - buttonAbsoluteSize.X / 2
    local minY = edgePadding + buttonAbsoluteSize.Y / 2
    local maxY = clickBoxHeight - edgePadding - buttonAbsoluteSize.Y / 2
    
    if maxX <= minX then maxX = minX + 1 end
    if maxY <= minY then maxY = minY + 1 end
    
    local randomX = math.random(minX, maxX)
    local randomY = math.random(minY, maxY)
    
    return UDim2.new(0, randomX, 0, randomY)
end

local function spawnButton(clickBox: Frame)
    local template = ReplicatedStorage:FindFirstChild("Assets")
    if template then
        template = template:FindFirstChild("UIAssets")
    end
    if template then
        template = template:FindFirstChild("GenTemplate")
    end
    
    if not template then
        warn("GenTemplate not found in ReplicatedStorage/Assets/UIAssets")
        return
    end
    
    local button = template:Clone()
    
    local uiScale = button:FindFirstChildWhichIsA("UIScale")
    if not uiScale then
        uiScale = Instance.new("UIScale")
        uiScale.Parent = button
    end
    
    local randomScale = math.random(35, 65) / 100
    uiScale.Scale = randomScale
    
    button.AnchorPoint = Vector2.new(0.5, 0.5)
    
    local tempSize = button.Size
    local estimatedWidth = tempSize.X.Offset * randomScale
    local estimatedHeight = tempSize.Y.Offset * randomScale
    local buttonAbsoluteSize = Vector2.new(estimatedWidth, estimatedHeight)
    local edgePadding = 20
    
    button.Position = getRandomPosition(clickBox, buttonAbsoluteSize, edgePadding)
    
    button.Parent = clickBox
    
    local buttonClickStartTime = tick()
    local buttonClicked = false
    
    local timeLimit = buttonTimeLimit
    
    local generatorFrame = screenGui:FindFirstChild("GeneratorFrame")
    if generatorFrame then
        local timerLabel = generatorFrame:FindFirstChild("Timer")
        if timerLabel and timerLabel:IsA("TextLabel") then
            timerLabel.Text = string.format("Click on the circles but don't miss! (%.1fs)", timeLimit)
            
            local startTime = tick()
            local updateConnection
            updateConnection = game:GetService("RunService").Heartbeat:Connect(function()
                if buttonClicked or not button.Parent then
                    updateConnection:Disconnect()
                    return
                end
                
                local elapsed = tick() - startTime
                local remaining = math.max(0, timeLimit - elapsed)
                timerLabel.Text = string.format("Click on the circles but don't miss! (%.1fs)", remaining)
            end)
        end
    end
    
    task.delay(timeLimit, function()
        if not buttonClicked and button.Parent then
            GeneratorService:ReportSlowClick(currentGenerator, timeLimit)
            
            if currentGenerator and currentGeneratorObject then
                if not generatorCooldowns[currentGenerator] then
                    local generatorModel = currentGeneratorObject.Parent
                    GeneratorService:TriggerCooldown(currentGenerator, generatorModel)
                end
            end
            
            local buttonIndex = table.find(activeButtons, button)
            if buttonIndex then
                table.remove(activeButtons, buttonIndex)
            end
            
            button.Parent = nil
            task.defer(function()
                button:Destroy()
            end)
            
            GeneratorController:CloseGenerator()
        end
    end)
    
    button.Activated:Connect(function()
        if buttonClicked then return end
        buttonClicked = true
        
        local reactionTime = tick() - buttonClickStartTime
        
        if currentGenerator then
            task.spawn(function()
                GeneratorService:AddProgress(currentGenerator, 8, reactionTime)
            end)
        end
        
        local buttonIndex = table.find(activeButtons, button)
        if buttonIndex then
            table.remove(activeButtons, buttonIndex)
        end
        
        button.Parent = nil
        task.defer(function()
            button:Destroy()
        end)
        
        if clickBox.Parent and clickBox.Parent.Visible then
            spawnButton(clickBox)
        end
    end)
    
    table.insert(activeButtons, button)
end

local function updateProgressBar(progress: number)
    local generatorFrame = screenGui:FindFirstChild("GeneratorFrame")
    if not generatorFrame then return end
    
    local content = generatorFrame:FindFirstChild("Content")
    if not content then 
        warn("Content not found in GeneratorFrame")
        return 
    end
    
    local backgroundProgress = content:FindFirstChild("BackgroundProgress")
    if not backgroundProgress then 
        warn("BackgroundProgress not found in Content")
        return 
    end
    
    local progressFrame = backgroundProgress:FindFirstChild("Progress")
    if not progressFrame then 
        warn("Progress frame not found in BackgroundProgress")
        return 
    end
    
    if type(progress) ~= "number" then
        warn("[GeneratorController] Invalid progress type:", type(progress), "Value:", progress)
        return
    end
    
    local targetScale = math.clamp(progress / 100, 0, 1)
    
    local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween = TweenService:Create(progressFrame, tweenInfo, {
        Size = UDim2.new(targetScale, 0, 1, 0)
    })
    tween:Play()
end

local function setProgressBarImmediate(progress: number)
    local generatorFrame = screenGui:FindFirstChild("GeneratorFrame")
    if not generatorFrame then return end
    
    local content = generatorFrame:FindFirstChild("Content")
    if not content then return end
    
    local backgroundProgress = content:FindFirstChild("BackgroundProgress")
    if not backgroundProgress then return end
    
    local progressFrame = backgroundProgress:FindFirstChild("Progress")
    if not progressFrame then return end
    
    if type(progress) ~= "number" then return end
    
    local targetScale = math.clamp(progress / 100, 0, 1)
    progressFrame.Size = UDim2.new(targetScale, 0, 1, 0)
end

local function triggerCooldownAndClose()
    if currentGenerator and currentGeneratorObject then
        if not generatorCooldowns[currentGenerator] then
            local generatorModel = currentGeneratorObject.Parent
            GeneratorService:TriggerCooldown(currentGenerator, generatorModel)
        end
    end
    
    GeneratorController:CloseGenerator()
end

local function disconnectListeners()
    if clickAwayConnection then
        clickAwayConnection:Disconnect()
        clickAwayConnection = nil
    end
    if movementConnection then
        movementConnection:Disconnect()
        movementConnection = nil
    end
    if frameClickConnection then
        frameClickConnection:Disconnect()
        frameClickConnection = nil
    end
    if progressUpdatedConnection then
        progressUpdatedConnection:Disconnect()
        progressUpdatedConnection = nil
    end
    if generatorCooldownConnection then
        generatorCooldownConnection:Disconnect()
        generatorCooldownConnection = nil
    end
end

function GeneratorController:StartGenerator(generatorObject: Instance)
    local generatorId = generatorObject:GetFullName()
    
    if generatorCooldowns[generatorId] == true then
        warn("[GeneratorController] Generator", generatorId, "is on cooldown, cannot access")
        local generatorFrame = screenGui:FindFirstChild("GeneratorFrame")
        if generatorFrame then
            generatorFrame.Visible = false
        end
        return
    end
    
    if currentGenerator and currentGenerator ~= generatorId then
        self:CloseGenerator()
    end
    
    local success1, initialProgress = pcall(function()
        return GeneratorService:GetProgress(generatorId)
    end)
    
    local success2, timeLimit = pcall(function()
        return GeneratorService:GetButtonTimeLimit()
    end)
    
    if not success1 then
        warn("[GeneratorController] Failed to get progress:", initialProgress)
        initialProgress = 0
    end
    
    if not success2 then
        warn("[GeneratorController] Failed to get time limit:", timeLimit)
        timeLimit = 2.5
    end
    
    currentGenerator = generatorId
    currentGeneratorObject = generatorObject
    
    local generatorFrame = screenGui:FindFirstChild("GeneratorFrame")
    if not generatorFrame then return end
    
    local content = generatorFrame:FindFirstChild("Content")
    if not content then return end
    
    local clickBox = content:FindFirstChild("Clickbox")
    if not clickBox then return end
    
    clearButtons()
    disconnectListeners()
    
    generatorFrame.Visible = true
    
    task.wait()
    
    if type(initialProgress) == "number" then
        setProgressBarImmediate(initialProgress)
    elseif type(initialProgress) == "table" and initialProgress.progress then
        setProgressBarImmediate(initialProgress.progress)
    end
    
    if type(timeLimit) == "number" then
        buttonTimeLimit = timeLimit
    elseif type(timeLimit) == "table" and type(timeLimit.timeLimit) == "number" then
        buttonTimeLimit = timeLimit.timeLimit
    else
        buttonTimeLimit = 2.5
    end
    
    spawnButton(clickBox)
    
    if player.Character and player.Character.PrimaryPart then
        initialPosition = player.Character.PrimaryPart.Position
    end
    
    progressUpdatedConnection = GeneratorService.ProgressUpdated:Connect(function(generatorId: string, progress: number)
        if generatorId == currentGenerator then
            local progressValue = progress
            if type(progress) == "table" and progress.progress then
                progressValue = progress.progress
            end
            
            if type(progressValue) == "number" then
                updateProgressBar(progressValue)
                
                if progressValue >= 100 then
                    self:CloseGenerator()
                end
            end
        end
    end)
    
    frameClickConnection = generatorFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            local mousePos = game:GetService("UserInputService"):GetMouseLocation()
            local guiObjects = playerGUI:GetGuiObjectsAtPosition(mousePos.X, mousePos.Y)
            
            local clickedButton = false
            for _, obj in guiObjects do
                if obj.Name == "GenTemplate" then
                    clickedButton = true
                    break
                end
            end
            
            if not clickedButton then
                for _, obj in guiObjects do
                    if obj == clickBox then
                        triggerCooldownAndClose()
                        break
                    end
                end
            end
        end
    end)
    
    clickAwayConnection = game:GetService("UserInputService").InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local mousePos = game:GetService("UserInputService"):GetMouseLocation()
            local guiObjects = playerGUI:GetGuiObjectsAtPosition(mousePos.X, mousePos.Y)
            
            local clickedInside = false
            for _, obj in guiObjects do
                if obj:IsDescendantOf(generatorFrame) then
                    clickedInside = true
                    break
                end
            end
            
            if not clickedInside then
                triggerCooldownAndClose()
            end
        end
    end)
    
    movementConnection = game:GetService("RunService").Heartbeat:Connect(function()
        if player.Character and player.Character.PrimaryPart and initialPosition then
            local currentPos = player.Character.PrimaryPart.Position
            local distance = (currentPos - initialPosition).Magnitude
            
            if distance > 3 then
                triggerCooldownAndClose()
            end
        end
    end)
end

function GeneratorController:CloseGenerator()
    local generatorFrame = screenGui:FindFirstChild("GeneratorFrame")
    if generatorFrame then
        generatorFrame.Visible = false
    end
    
    clearButtons()
    disconnectListeners()
    currentGenerator = nil
    currentGeneratorObject = nil
    initialPosition = nil
    buttonTimeLimit = 2.5
end

function GeneratorController:SetProgressBarAfterUIReady(progress)
    if type(progress) == "number" then
        setProgressBarImmediate(progress)
    end
end

function GeneratorController:KnitStart()
    GeneratorService.GeneratorCooldown:Connect(function(generatorId: string, onCooldown: boolean)
        if onCooldown then
            generatorCooldowns[generatorId] = true
        else
            generatorCooldowns[generatorId] = nil
        end
        
        if onCooldown and generatorId == currentGenerator then
            GeneratorController:CloseGenerator()
        end
    end)
    
    GeneratorService.ProgressSync:Connect(function(generatorId: string, progress: number)
        if generatorId == currentGenerator then
            local progressValue = progress
            if type(progress) == "table" and progress.progress then
                progressValue = progress.progress
            end
            
            if type(progressValue) == "number" then
                setProgressBarImmediate(progressValue)
            end
        end
    end)
    
    local generatorFrame = screenGui:FindFirstChild("GeneratorFrame")
    if generatorFrame then
        local closeButton = generatorFrame:FindFirstChild("X")
        if closeButton and closeButton:IsA("GuiButton") then
            closeButton.Activated:Connect(function()
                triggerCooldownAndClose()
            end)
        end
    end
end

function GeneratorController:KnitInit()
    GeneratorService = Knit.GetService("GeneratorService")
end

return GeneratorController