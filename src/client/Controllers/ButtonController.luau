local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local HoverSound = SoundService.Sounds:WaitForChild("Hover")
local ClickSound = SoundService.Sounds:WaitForChild("Click")

local Packages = ReplicatedStorage.Packages
local Shared = ReplicatedStorage.Shared

local Knit = require(Packages.Knit)

local player = Players.LocalPlayer
local playerGUI = player:WaitForChild("PlayerGui")
local screenGui = playerGUI:WaitForChild("Main")
local buttons = screenGui:WaitForChild("Buttons")
local frames : Folder = screenGui:WaitForChild("Frames")

local startScale = 1
local hoverScale = 1.1
local clickedScale = 0.95
local hoverTweenTime = 0.15
local clickTweenTime = 0.1

local ButtonController = Knit.CreateController({
    Name = "ButtonController",
})

local buttonTweens = {}
local buttonHoverStates = {} 
local frameTweens = {}
local isTransitioning = false

function ButtonController:CleanupFrameTweens()
    for frame, tween in pairs(frameTweens) do
        if tween then
            tween:Cancel()
        end
    end
    for frame, _ in pairs(frameTweens) do
        frameTweens[frame] = nil
    end
end

function ButtonController:TweenElement(element : GuiObject, targetScale : number, duration : number?, easingStyle : Enum.EasingStyle?, easingDirection : Enum.EasingDirection?, doWait : boolean?)
    duration = duration or hoverTweenTime
    easingStyle = easingStyle or Enum.EasingStyle.Quad
    easingDirection = easingDirection or Enum.EasingDirection.Out

    if buttonTweens[element] then
        buttonTweens[element]:Cancel()
    end
    
    local uiScale = element:FindFirstChildWhichIsA("UIScale") or Instance.new("UIScale", element)
    local tweenInfo = TweenInfo.new(duration, easingStyle, easingDirection)
    local tween = TweenService:Create(uiScale, tweenInfo, {Scale = targetScale})

    buttonTweens[element] = tween

    tween.Completed:Connect(function()
        if buttonTweens[element] == tween then
            buttonTweens[element] = nil
        end
    end)
    
    tween:Play()
    HoverSound:Play()

    if doWait then
        print("Waiting for tween to complete on element:", element.Name, " with visibility:", element.Visible)
        tween.Completed:Wait()
        print("Tween completed on element:", element.Name)
    end
    return tween
end

local previousFrame : Frame
local currentFrame : Frame

local isDebounce = false
local DEBOUNCE_TIME = 0.1

local function hideFrame(frame)
    -- Cancel any existing frame tween first
    if frameTweens[frame] then
        frameTweens[frame]:Cancel()
        frameTweens[frame] = nil
    end
    
    local uiScale = frame:FindFirstChildWhichIsA("UIScale") or Instance.new("UIScale", frame)
    
    -- If frame is already hidden but scale is not 0, we should still animate it
    if not frame.Visible and uiScale.Scale <= 0 then
        return nil
    end
    
    -- Make sure frame is visible for the animation
    frame.Visible = true
    
    -- Ensure the scale is set to 1 before tweening to 0
    if uiScale.Scale <= 0 then
        uiScale.Scale = 1
    end
    
    print("Starting hide animation for frame:", frame.Name, "Current scale:", uiScale.Scale)
    
    local tweenInfo = TweenInfo.new(hoverTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    local tween = TweenService:Create(uiScale, tweenInfo, {Scale = 0})
    
    frameTweens[frame] = tween
    
    tween.Completed:Connect(function()
        print("Hide animation completed for frame:", frame.Name)
        frame.Visible = false
        if frameTweens[frame] == tween then
            frameTweens[frame] = nil
        end
    end)
    
    tween:Play()
    return tween
end

local function showFrame(frame)
    if isDebounce then
        print("Debounced - hiding frame if visible")
        if frame.Visible then 
            hideFrame(frame)
        end 
        return false
    end
    
    isDebounce = true
    task.delay(DEBOUNCE_TIME, function()
        isDebounce = false
    end)
    
    -- Cancel any existing frame tween
    if frameTweens[frame] then
        frameTweens[frame]:Cancel()
        frameTweens[frame] = nil
    end
    
    local uiScale = frame:FindFirstChildWhichIsA("UIScale") or Instance.new("UIScale", frame)
    uiScale.Scale = 0
    frame.Visible = true
    
    local tweenInfo = TweenInfo.new(hoverTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween = TweenService:Create(uiScale, tweenInfo, {Scale = 1})
    
    frameTweens[frame] = tween
    
    tween.Completed:Connect(function()
        if frameTweens[frame] == tween then
            frameTweens[frame] = nil
        end
    end)
    
    tween:Play()
    return true
end


function ButtonController.onFrameInvisible()
    local SelectedFrame = currentFrame
    print("onFrameInvisible called - currentFrame:", SelectedFrame and SelectedFrame.Name or "nil")
    
    if SelectedFrame then
        print("Setting transition flag and calling hideFrame")
        isTransitioning = true
        local hideTween = hideFrame(SelectedFrame)
        
        if hideTween then
            print("Hide tween created successfully")
            hideTween.Completed:Connect(function()
                print("Hide tween completed, resetting transition flag")
                isTransitioning = false
            end)
        else
            print("Hide tween was nil, resetting transition flag immediately")
            isTransitioning = false
        end
        
        previousFrame = currentFrame
        currentFrame = nil
        print("transition frame invisible")
    else
        print("No current frame to hide")
    end
end

function ButtonController.onFrameVisible(SelectedFrame : Frame)
    -- If same frame is already current, do nothing
    if currentFrame == SelectedFrame then
        return
    end
    
    -- If already transitioning, queue this request
    if isTransitioning then
        return
    end

    -- Store the frame we want to show
    local targetFrame = SelectedFrame
    isTransitioning = true
    
    -- If there's a current frame, hide it first and wait for completion
    if currentFrame then
        local frameToHide = currentFrame
        previousFrame = currentFrame
        currentFrame = nil
        
        local hideTween = hideFrame(frameToHide)
        
        if hideTween then
            -- Wait for hide animation to complete before showing new frame
            hideTween.Completed:Connect(function()
                -- Only proceed if this is still the target frame (prevent race conditions)
                if targetFrame == SelectedFrame then
                    currentFrame = targetFrame
                    local success = showFrame(currentFrame)
                    if success then
                        print("Success showing frame:", currentFrame.Name)
                    else
                        print("Failed to show frame due to rate limiting")
                        currentFrame = nil
                    end
                end
                isTransitioning = false
            end)
        else
            -- No hide animation needed, show immediately
            currentFrame = targetFrame
            local success = showFrame(currentFrame)
            if success then
                print("Success showing frame:", currentFrame.Name)
            else
                print("Failed to show frame due to rate limiting")
                currentFrame = nil
            end
            isTransitioning = false
        end
    else
        -- No current frame, show immediately
        currentFrame = targetFrame
        local success = showFrame(currentFrame)
        if success then
            print("Success showing frame:", currentFrame.Name)
        else
            print("Failed to show frame due to rate limiting")
            currentFrame = nil
        end
        isTransitioning = false
    end
    
    -- Hide any other visible frames that aren't the current or target
    for _, frame in pairs(frames:GetChildren()) do
        if frame:IsA("Frame") and frame ~= targetFrame and frame ~= currentFrame and frame.Visible then
            hideFrame(frame)
        end
    end
end

function ButtonController:ClickedButtonTween(button : GuiButton | ImageButton)
    if buttonTweens[button] then
        buttonTweens[button]:Cancel()
    end
    
    local uiScale = button:FindFirstChildWhichIsA("UIScale") or Instance.new("UIScale", button)
    
    local clickDownTween = TweenService:Create(
        uiScale, 
        TweenInfo.new(clickTweenTime * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), 
        {Scale = clickedScale}
    )
    
    buttonTweens[button] = clickDownTween
    clickDownTween:Play()
    
    clickDownTween.Completed:Connect(function()

        local targetScale = buttonHoverStates[button] and hoverScale or startScale
        
        local clickUpTween = TweenService:Create(
            uiScale, 
            TweenInfo.new(clickTweenTime * 1.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), 
            {Scale = targetScale}
        )
        
        buttonTweens[button] = clickUpTween
        clickUpTween:Play()

        clickUpTween.Completed:Connect(function()
            if buttonTweens[button] == clickUpTween then
                buttonTweens[button] = nil
            end
        end)
    end)

    local SelectedFrame = frames:WaitForChild(button.Name)

    local isCurrentlyActive = (currentFrame == SelectedFrame)
    
    print("Button clicked: "..button.Name, "Currently active:", isCurrentlyActive)

    if not isCurrentlyActive then
        self.onFrameVisible(SelectedFrame)
    else
        self.onFrameInvisible()
    end
end

-- @param uiScreen : Instance The screen instance containing the buttons
function ButtonController:SetupButtons(uiScreen: Instance) : any
    for _, descendant in ipairs(uiScreen:GetDescendants()) do
        if descendant:IsA("GuiButton") then
            descendant.Active = true
            local uiScale = descendant:FindFirstChildWhichIsA("UIScale") or Instance.new("UIScale", descendant)
            uiScale.Scale = 1

            local scaleHover = 1.2
            local scalePressed = 1 / 1.2
            local originalScale = 1

            descendant.MouseEnter:Connect(function()
                buttonHoverStates[descendant] = true
                if not buttonTweens[descendant] then
                    self:TweenElement(descendant, scaleHover, hoverTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                end
            end)

            descendant.MouseLeave:Connect(function()
                buttonHoverStates[descendant] = false
                if buttonTweens[descendant] then
                    buttonTweens[descendant]:Cancel()
                    buttonTweens[descendant] = nil
                end
                self:TweenElement(descendant, originalScale, hoverTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            end)

            descendant.MouseButton1Up:Connect(function()
                local targetScale = buttonHoverStates[descendant] and scaleHover or originalScale
                self:TweenElement(descendant, targetScale, hoverTweenTime)
            end)

            descendant.MouseButton1Down:Connect(function()
                self:TweenElement(descendant, scalePressed, hoverTweenTime)
            end)

            descendant.Activated:Connect(function()
            ClickSound:Play()
            end)
        end
    end
end

function ButtonController:KnitStart() 
    for _, button in buttons:GetChildren() do
        if button:IsA("GuiButton") or button:IsA("ImageButton") then
            button.MouseEnter:Connect(function()
                buttonHoverStates[button] = true

                if not buttonTweens[button] then
                    self:TweenElement(button, hoverScale, hoverTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                end
            end)

            button.MouseLeave:Connect(function()
                buttonHoverStates[button] = false

                if buttonTweens[button] then
                    buttonTweens[button]:Cancel()
                    buttonTweens[button] = nil
                end
                
                self:TweenElement(button, startScale, hoverTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            end)

            button.MouseButton1Click:Connect(function()
                self:ClickedButtonTween(button)
            end)
        end
    end
end

function ButtonController:KnitInit()
    -- Clean up any existing frame tweens to ensure fresh start
    self:CleanupFrameTweens()
    isTransitioning = false
    currentFrame = nil
    previousFrame = nil
    print("ButtonController initialized")
end

return ButtonController