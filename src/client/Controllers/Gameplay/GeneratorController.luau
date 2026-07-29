local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local player = Players.LocalPlayer
local playerGUI = player:WaitForChild("PlayerGui")
local screenGui = playerGUI:WaitForChild("Main")

local GeneratorController = Knit.CreateController({
    Name = "GeneratorController",
})

local GeneratorService
local RoleShowController
local NotificationController
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
local buttonTimeLimit = 2.5
local roundTransitioning = false -- Add flag to track round transitions
local progressTween = nil
local progressTweenTarget: number? = nil
local completedGenerators = {}
local generatorHighlights = {}

local DEFAULT_GENERATOR_FILL = Color3.fromRGB(255, 255, 0)
local DEFAULT_GENERATOR_OUTLINE = Color3.fromRGB(255, 255, 255)
local FAIL_GENERATOR_FILL = Color3.fromRGB(255, 0, 0)

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
    
    button.AnchorPoint = Vector2.new(0.5, 0.5)
    
    local randomScale = math.random(150, 250) / 100
    local baseSize = button.Size
    button.Size = UDim2.new(
        baseSize.X.Scale * randomScale,
        baseSize.X.Offset,
        baseSize.Y.Scale * randomScale,
        baseSize.Y.Offset
    )
    
    local estimatedWidth = baseSize.X.Offset * randomScale
    local estimatedHeight = baseSize.Y.Offset * randomScale
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
            updateConnection = RunService.Heartbeat:Connect(function()
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
            -- Report slow click to server, which will handle cooldown
            GeneratorService:ReportSlowClick(currentGenerator, timeLimit)
            
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

local function getProgressFrame(warnMissing: boolean?)
    local generatorFrame = screenGui:FindFirstChild("GeneratorFrame")
    if not generatorFrame then return nil end
    
    local content = generatorFrame:FindFirstChild("Content")
    if not content then 
        if warnMissing then warn("Content not found in GeneratorFrame") end
        return nil
    end
    
    local backgroundProgress = content:FindFirstChild("BackgroundProgress")
    if not backgroundProgress then 
        if warnMissing then warn("BackgroundProgress not found in Content") end
        return nil
    end
    
    local progressFrame = backgroundProgress:FindFirstChild("Progress")
    if not progressFrame then 
        if warnMissing then warn("Progress frame not found in BackgroundProgress") end
        return nil
    end

    return progressFrame
end

local function getGeneratorId(generatorObject: Instance): string
    return generatorObject:GetAttribute("GeneratorId") or generatorObject.Parent and generatorObject.Parent.Name or generatorObject:GetFullName()
end

local function getHighlightTarget(generatorObject: Instance): Instance
    if generatorObject:IsA("Model") then
        return generatorObject
    end

    return generatorObject.Parent or generatorObject
end

local function removeGeneratorHighlight(generatorObject: Instance)
    local highlight = generatorHighlights[generatorObject]
    if highlight then
        highlight:Destroy()
        generatorHighlights[generatorObject] = nil
    end
end

local function getOrCreateGeneratorHighlight(generatorObject: Instance): Highlight?
    if not RoleShowController or not RoleShowController:IsKiller() then
        removeGeneratorHighlight(generatorObject)
        return nil
    end

    local generatorId = getGeneratorId(generatorObject)
    if completedGenerators[generatorId] then
        removeGeneratorHighlight(generatorObject)
        return nil
    end

    local highlight = generatorHighlights[generatorObject]
    if highlight and highlight.Parent then
        return highlight
    end

    highlight = Instance.new("Highlight")
    highlight.Name = "KillerGeneratorHighlight"
    highlight.FillColor = DEFAULT_GENERATOR_FILL
    highlight.OutlineColor = DEFAULT_GENERATOR_OUTLINE
    highlight.FillTransparency = 0.7
    highlight.OutlineTransparency = 0
    highlight.Parent = getHighlightTarget(generatorObject)
    generatorHighlights[generatorObject] = highlight

    return highlight
end

local function refreshGeneratorHighlights()
    for generatorObject, _ in pairs(generatorHighlights) do
        if not generatorObject.Parent then
            removeGeneratorHighlight(generatorObject)
        end
    end

    if not RoleShowController or not RoleShowController:IsKiller() then
        for generatorObject, _ in pairs(generatorHighlights) do
            removeGeneratorHighlight(generatorObject)
        end
        return
    end

    for _, generatorObject in ipairs(CollectionService:GetTagged("Generator")) do
        getOrCreateGeneratorHighlight(generatorObject)
    end
end

local function showGeneratorFailure(generatorId: string)
    if not RoleShowController or not RoleShowController:IsKiller() then
        return
    end

    for _, generatorObject in ipairs(CollectionService:GetTagged("Generator")) do
        if getGeneratorId(generatorObject) == generatorId then
            local highlight = getOrCreateGeneratorHighlight(generatorObject)
            if not highlight then
                return
            end

            highlight.FillColor = FAIL_GENERATOR_FILL
            highlight.FillTransparency = 0.35

            task.delay(3, function()
                if not highlight.Parent then
                    return
                end

                highlight.FillColor = DEFAULT_GENERATOR_FILL
                highlight.FillTransparency = 0.7
            end)
            return
        end
    end
end

local function updateProgressBar(progress: number)
    local progressFrame = getProgressFrame(true)
    if not progressFrame then return end
    
    if type(progress) ~= "number" then
        warn("[GeneratorController] Invalid progress type:", type(progress), "Value:", progress)
        return
    end
    
    local targetProgress = math.clamp(progress, 0, 100)
    local targetScale = targetProgress / 100

    if progressTween then
        progressTween:Cancel()
        progressTween = nil
    end
    progressTweenTarget = targetProgress
    
    local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    progressTween = TweenService:Create(progressFrame, tweenInfo, {
        Size = UDim2.new(targetScale, 0, 1, 0)
    })
    local activeTween = progressTween
    activeTween.Completed:Connect(function()
        if progressTween == activeTween then
            progressTween = nil
        end
    end)
    activeTween:Play()
end

local function setProgressBarImmediate(progress: number)
    local progressFrame = getProgressFrame(false)
    if not progressFrame then return end
    
    if type(progress) ~= "number" then 
        return 
    end
    
    if progressTween then
        progressTween:Cancel()
        progressTween = nil
    end

    local targetProgress = math.clamp(progress, 0, 100)
    local targetScale = targetProgress / 100
    progressTweenTarget = targetProgress
    progressFrame.Size = UDim2.new(targetScale, 0, 1, 0)
end

local function syncProgressBar(progress: number)
    if type(progress) ~= "number" then
        return
    end

    if progress <= 0 then
        setProgressBarImmediate(0)
        return
    end

    local targetProgress = math.clamp(progress, 0, 100)
    if progressTween and progressTweenTarget and math.abs(progressTweenTarget - targetProgress) < 0.01 then
        return
    end

    updateProgressBar(targetProgress)
end

local function reportMissClickAndClose()
    -- Report miss click to server, server will handle cooldown
    if currentGenerator then
        GeneratorService:ReportMissClick(currentGenerator)
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
    local generatorId = getGeneratorId(generatorObject)
    
    -- Check with server if generator can be accessed
    GeneratorService:CanAccessGenerator(generatorId):andThen(function(canAccess, reason)
        if not canAccess then
            if NotificationController then
                NotificationController:ShowWarning(reason or "You cannot repair this generator right now.")
            else
                warn("[GeneratorController] Cannot access generator", generatorId)
            end
            local generatorFrame = screenGui:FindFirstChild("GeneratorFrame")
            if generatorFrame then
                generatorFrame.Visible = false
            end
            return
        end
        
        self:_StartGeneratorInternal(generatorObject, generatorId)
    end):catch(function(err)
        warn("[GeneratorController] Failed to check generator access:", err)
        if NotificationController then
            NotificationController:ShowWarning("Could not check that generator right now.")
        end
    end)
end

function GeneratorController:_StartGeneratorInternal(generatorObject: Instance, generatorId: string)
    
    if currentGenerator and currentGenerator ~= generatorId then
        self:CloseGenerator()
    end
    
    GeneratorService:GetProgress(generatorId):andThen(function(progress)
        if type(progress) == "number" and currentGenerator == generatorId then
            setProgressBarImmediate(progress)
        end
    end):catch(function(err)
        warn("[GeneratorController] Failed to get progress:", err)
    end)
    
    GeneratorService:GetButtonTimeLimit():andThen(function(limit)
        if type(limit) == "number" then
            buttonTimeLimit = limit
        end
    end):catch(function(err)
        warn("[GeneratorController] Failed to get time limit:", err)
    end)
    
    currentGenerator = generatorId
    currentGeneratorObject = generatorObject
    
    local proximityPrompt = generatorObject:FindFirstChildWhichIsA("ProximityPrompt")
    if proximityPrompt then
        proximityPrompt.Enabled = false
    end
    
    local generatorFrame = screenGui:FindFirstChild("GeneratorFrame")
    if not generatorFrame then 
        warn("[GeneratorController] GeneratorFrame not found")
        return 
    end
    
    local content = generatorFrame:FindFirstChild("Content")
    if not content then return end
    
    local clickBox = content:FindFirstChild("Clickbox")
    if not clickBox then return end
    
    clearButtons()
    disconnectListeners()
    
    -- Show frame with animation after validation
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
    
    RunService.RenderStepped:Wait()
    
    -- Always reset progress bar to 0 first to clear any stale progress
    setProgressBarImmediate(0)
    
    -- Then sync with actual server progress
    GeneratorService:GetProgress(generatorId):andThen(function(serverProgress)
        if type(serverProgress) == "number" and generatorId == currentGenerator then
            setProgressBarImmediate(serverProgress)
        end
    end):catch(function(err)
        warn("[GeneratorController] Failed to get initial progress:", err)
    end)
    
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
            end
        end
    end)
    
    frameClickConnection = generatorFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            local mousePos = UserInputService:GetMouseLocation()
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
                        reportMissClickAndClose()
                        break
                    end
                end
            end
        end
    end)
    
    clickAwayConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local mousePos = UserInputService:GetMouseLocation()
            local guiObjects = playerGUI:GetGuiObjectsAtPosition(mousePos.X, mousePos.Y)
            
            local clickedInside = false
            for _, obj in guiObjects do
                if obj:IsDescendantOf(generatorFrame) then
                    clickedInside = true
                    break
                end
            end
            
            if not clickedInside then
                reportMissClickAndClose()
            end
        end
    end)
    
    movementConnection = RunService.Heartbeat:Connect(function()
        if player.Character and player.Character.PrimaryPart and initialPosition then
            local currentPos = player.Character.PrimaryPart.Position
            local distance = (currentPos - initialPosition).Magnitude
            
            if distance > 3 then
                reportMissClickAndClose()
            end
        end
    end)
end

function GeneratorController:ResetForNewRound()
    -- Set flag to prevent issues during transition
    roundTransitioning = true
    table.clear(completedGenerators)
    setProgressBarImmediate(0)
    refreshGeneratorHighlights()
    
    -- Close any active generator interface
    self:CloseGenerator()
    
    -- Clear the flag after a short delay to allow round to properly start
    task.delay(2, function()
        roundTransitioning = false
    end)
end

function GeneratorController:CloseGenerator()
    local generatorFrame = screenGui:FindFirstChild("GeneratorFrame")
    if generatorFrame then
        generatorFrame.Visible = false
    end
    
    if currentGeneratorObject then
        local proximityPrompt = currentGeneratorObject:FindFirstChildWhichIsA("ProximityPrompt")
        if proximityPrompt then
            proximityPrompt.Enabled = true
        end
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
        if generatorId == "all" then
            self:ResetForNewRound()
            return
        end

        if onCooldown then
            showGeneratorFailure(generatorId)
        end
        
        -- If this generator is on cooldown and it's the current one, close it
        if onCooldown and generatorId == currentGenerator then
            GeneratorController:CloseGenerator()
        end
    end)
    
    GeneratorService.GeneratorCompleted:Connect(function(generatorId: string)
        completedGenerators[generatorId] = true
        refreshGeneratorHighlights()

        if roundTransitioning then
            return
        end
        
        -- Close the generator UI if it's the current one
        if generatorId == currentGenerator then
            GeneratorController:CloseGenerator()
        end
    end)
    
    GeneratorService.ProgressSync:Connect(function(generatorId: string, progress: number)
        if generatorId == "all" and type(progress) == "number" then
            setProgressBarImmediate(progress)
            return
        end

        if generatorId == currentGenerator and type(progress) == "number" then
            syncProgressBar(progress)
        end
    end)
    
    -- Connect to round status changes to reset generators
    local RoundService = Knit.GetService("RoundService")
    RoundService.StatusChanged:Connect(function(status)
        if status == "Intermission" then
            self:ResetForNewRound()
        end
    end)

    CollectionService:GetInstanceAddedSignal("Generator"):Connect(function(generatorObject)
        if RoleShowController and RoleShowController:IsKiller() then
            getOrCreateGeneratorHighlight(generatorObject)
        end
    end)

    CollectionService:GetInstanceRemovedSignal("Generator"):Connect(function(generatorObject)
        removeGeneratorHighlight(generatorObject)
    end)

    RoleShowController:OnRoleChanged(function()
        refreshGeneratorHighlights()
    end)
    
    local generatorFrame = screenGui:FindFirstChild("GeneratorFrame")
    if generatorFrame then
        local closeButton = generatorFrame:FindFirstChild("X")
        if closeButton and closeButton:IsA("GuiButton") then
            closeButton.Activated:Connect(function()
                reportMissClickAndClose()
            end)
        end
    end
end

function GeneratorController:KnitInit()
    GeneratorService = Knit.GetService("GeneratorService")
    RoleShowController = Knit.GetController("RoleShowController")
    NotificationController = Knit.GetController("NotificationController")
end

return GeneratorController
