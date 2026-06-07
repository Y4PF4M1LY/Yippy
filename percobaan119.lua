-- Auto Fishing Script | Delta Executor Compatible
-- J = Toggle Start/Stop | K = Hide/Show UI

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local config = {
    enabled      = false,
    instantCatch = true,
    autoRecast   = true,
    castHoldTime = 0.5,
    savedPosition = nil,
    clickDelay   = 0.009,
}

local isCasting        = false
local isMinigameActive = false
local clickRunning     = false
local animConnection   = nil
local lastCastTime     = 0
local currentFPS       = 0
local currentPing      = 0
local frameCount       = 0
local lastFPSUpdate    = tick()

-- ─────────────────────────────────────────────────────────────
--  Delta-safe input (mouse1click / mouse1press / mouse1release)
-- ─────────────────────────────────────────────────────────────
local function simClick()
    if mouse1click then
        pcall(mouse1click)
    elseif mouse1press and mouse1release then
        pcall(mouse1press)
        task.wait()
        pcall(mouse1release)
    end
end

local function simPress()
    if mouse1press then pcall(mouse1press) end
end

local function simRelease()
    if mouse1release then pcall(mouse1release) end
end

-- ─────────────────────────────────────────────────────────────
--  Core logic
-- ─────────────────────────────────────────────────────────────
local function teleportToSpot()
    if not config.savedPosition then return end
    local char = player.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        char.HumanoidRootPart.CFrame = config.savedPosition
        task.wait(0.1)
    end
end

local function disableAnims()
    local char = player.Character or player.CharacterAdded:Wait()
    local hum  = char:WaitForChild("Humanoid")
    local anim = hum:FindFirstChildOfClass("Animator")
    if anim then
        for _, t in ipairs(anim:GetPlayingAnimationTracks()) do t:Stop(0) end
    end
    if animConnection then animConnection:Disconnect() end
    animConnection = hum.AnimationPlayed:Connect(function(track)
        if config.enabled then track:Stop(0) end
    end)
end

local function pressFishingButton(holdTime)
    simPress()
    task.wait(math.max(0.05, holdTime))
    simRelease()
end

local function castRod()
    if isCasting then return end
    isCasting = true
    if config.savedPosition then teleportToSpot() end
    pressFishingButton(config.castHoldTime)
    lastCastTime = tick()
    task.wait(0.1 + math.random(10, 30) / 1000)
    isCasting = false
end

local function isMiniGameActive()
    local char = player.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") then
                local status = item:FindFirstChild("Status")
                if status and status:GetAttribute("MiniGame") == true then return true end
            end
        end
    end
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            local status = item:FindFirstChild("Status")
            if status and status:GetAttribute("MiniGame") == true then return true end
        end
    end
    local fishGui = playerGui:FindFirstChild("FishingRodGUI")
    if fishGui then
        local bg = fishGui:FindFirstChild("Background")
        if bg and bg.Visible then return true end
    end
    for _, gui in ipairs(playerGui:GetChildren()) do
        if gui:IsA("ScreenGui") and gui.Enabled and gui.Name ~= "AutoFishingGUI" then
            for _, desc in ipairs(gui:GetDescendants()) do
                if (desc:IsA("TextLabel") or desc:IsA("TextButton")) and desc.Visible then
                    local t = string.lower(desc.Text or "")
                    if string.find(t, "tap") or string.find(t, "catch") then return true end
                end
            end
        end
    end
    return false
end

local function doInstantCatch()
    local startTime = tick()
    task.spawn(function()
        while isMinigameActive and (tick() - startTime) < 0.05 do
            for i = 1, 10 do simClick() end
            task.wait()
        end
    end)
    task.wait(0.02)
end

local function doSmoothCatch()
    simClick()
    task.wait(config.clickDelay * 2)
end

local function startAutoClick()
    clickRunning = true
    task.spawn(function()
        while clickRunning and config.enabled do
            if not isCasting then
                isMinigameActive = isMiniGameActive()
                if isMinigameActive then
                    if config.instantCatch then doInstantCatch() else doSmoothCatch() end
                else
                    task.wait(0.05)
                end
            else
                task.wait(0.05)
            end
        end
        clickRunning = false
    end)
end

local function stopAutoClick()
    clickRunning = false
end

local function monitorRecast()
    task.spawn(function()
        while config.enabled do
            task.wait(0.3)
            if config.autoRecast and not isMinigameActive and not isCasting then
                if tick() - lastCastTime >= 0.7 then castRod() end
            end
        end
    end)
end

-- ─────────────────────────────────────────────────────────────
--  FPS + Ping
-- ─────────────────────────────────────────────────────────────
RunService.Heartbeat:Connect(function()
    frameCount += 1
    local t = tick()
    if t - lastFPSUpdate >= 1 then
        currentFPS    = frameCount
        frameCount    = 0
        lastFPSUpdate = t
    end
end)

task.spawn(function()
    while true do
        task.wait(0.5)
        local ok, v = pcall(function() return math.floor(player:GetNetworkPing() * 1000) end)
        if ok and v then currentPing = v end
    end
end)

-- ─────────────────────────────────────────────────────────────
--  UI
-- ─────────────────────────────────────────────────────────────
local toggleBtn_ref  = nil  -- referenced by keybind
local contentRef     = nil  -- referenced by K keybind
local frameRef       = nil
local uiHidden       = false
local W, H           = 260, 320

local function buildUI()
    local old = playerGui:FindFirstChild("AutoFishingGUI")
    if old then old:Destroy() end

    local sg = Instance.new("ScreenGui")
    sg.Name           = "AutoFishingGUI"
    sg.ResetOnSpawn   = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local frame = Instance.new("Frame")
    frame.Size             = UDim2.new(0, W, 0, H)
    frame.Position         = UDim2.new(0.5, -W/2, 0.5, -H/2)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
    frame.BorderSizePixel  = 0
    frame.ClipsDescendants = true
    frame.Parent           = sg
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)
    frameRef = frame

    local shadow = Instance.new("Frame")
    shadow.Size                   = UDim2.new(1, 14, 1, 14)
    shadow.Position               = UDim2.new(0, -7, 0, -7)
    shadow.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
    shadow.BackgroundTransparency = 0.55
    shadow.BorderSizePixel        = 0
    shadow.ZIndex                 = 0
    shadow.Parent                 = frame
    Instance.new("UICorner", shadow).CornerRadius = UDim.new(0, 18)

    local titleBar = Instance.new("Frame")
    titleBar.Size             = UDim2.new(1, 0, 0, 36)
    titleBar.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
    titleBar.BorderSizePixel  = 0
    titleBar.Active           = true
    titleBar.ZIndex           = 2
    titleBar.Parent           = frame
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)

    local titlePatch = Instance.new("Frame")
    titlePatch.Size             = UDim2.new(1, 0, 0, 12)
    titlePatch.Position         = UDim2.new(0, 0, 1, -12)
    titlePatch.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
    titlePatch.BorderSizePixel  = 0
    titlePatch.ZIndex           = 2
    titlePatch.Parent           = titleBar

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size                   = UDim2.new(1, -80, 1, 0)
    titleLbl.Position               = UDim2.new(0, 12, 0, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text                   = "🎣 Ultimate Fishing"
    titleLbl.Font                   = Enum.Font.GothamBold
    titleLbl.TextSize               = 13
    titleLbl.TextColor3             = Color3.fromRGB(255, 255, 255)
    titleLbl.TextXAlignment         = Enum.TextXAlignment.Left
    titleLbl.ZIndex                 = 3
    titleLbl.Parent                 = titleBar

    -- Keybind hint in title bar
    local keybindHint = Instance.new("TextLabel")
    keybindHint.Size                   = UDim2.new(0, 60, 1, 0)
    keybindHint.Position               = UDim2.new(1, -92, 0, 0)
    keybindHint.BackgroundTransparency = 1
    keybindHint.Text                   = "[J] [K]"
    keybindHint.Font                   = Enum.Font.Gotham
    keybindHint.TextSize               = 10
    keybindHint.TextColor3             = Color3.fromRGB(200, 230, 255)
    keybindHint.ZIndex                 = 3
    keybindHint.Parent                 = titleBar

    local minBtn = Instance.new("TextButton")
    minBtn.Size               = UDim2.new(0, 26, 0, 26)
    minBtn.Position           = UDim2.new(1, -32, 0.5, -13)
    minBtn.BackgroundTransparency = 1
    minBtn.Text               = "—"
    minBtn.Font               = Enum.Font.GothamBold
    minBtn.TextSize           = 16
    minBtn.TextColor3         = Color3.fromRGB(255, 255, 255)
    minBtn.ZIndex             = 4
    minBtn.Parent             = titleBar

    local content = Instance.new("Frame")
    content.Size              = UDim2.new(1, 0, 1, -36)
    content.Position          = UDim2.new(0, 0, 0, 36)
    content.BackgroundTransparency = 1
    content.Parent            = frame
    contentRef = content

    local function makeBtn(text, color, sx, sy, px, py)
        local b = Instance.new("TextButton")
        b.Size             = UDim2.new(sx, 0, 0, sy)
        b.Position         = UDim2.new(px, 0, 0, py)
        b.BackgroundColor3 = color
        b.Text             = text
        b.Font             = Enum.Font.GothamBold
        b.TextSize         = 11
        b.TextColor3       = Color3.fromRGB(255, 255, 255)
        b.AutoButtonColor  = false
        b.Parent           = content
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
        return b
    end

    local toggleBtn  = makeBtn("⏹ DISABLED  [J]",      Color3.fromRGB(210,45,45),  0.9, 38, 0.05, 10)
    toggleBtn.TextSize = 12
    toggleBtn_ref = toggleBtn

    local instantBtn = makeBtn("⚡ INSTANT CATCH: ON",  Color3.fromRGB(200,120,0),  0.9, 30, 0.05, 55)
    local saveBtn    = makeBtn("📌 SAVE SPOT",          Color3.fromRGB(60,60,75),  0.43, 30, 0.05, 91)
    local gotoBtn    = makeBtn("📍 GOTO SPOT",          Color3.fromRGB(60,60,75),  0.43, 30, 0.52, 91)
    gotoBtn.TextColor3 = Color3.fromRGB(150,150,165)

    local statusLbl = Instance.new("TextLabel")
    statusLbl.Size           = UDim2.new(0.9, 0, 0, 22)
    statusLbl.Position       = UDim2.new(0.05, 0, 0, 127)
    statusLbl.BackgroundTransparency = 1
    statusLbl.Text           = "Spot Status: Position Unset"
    statusLbl.Font           = Enum.Font.Gotham
    statusLbl.TextSize       = 11
    statusLbl.TextColor3     = Color3.fromRGB(180,180,200)
    statusLbl.TextXAlignment = Enum.TextXAlignment.Left
    statusLbl.Parent         = content

    local statsBox = Instance.new("Frame")
    statsBox.Size             = UDim2.new(0.9, 0, 0, 90)
    statsBox.Position         = UDim2.new(0.05, 0, 0, 153)
    statsBox.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
    statsBox.BackgroundTransparency = 0.2
    statsBox.BorderSizePixel  = 0
    statsBox.Parent           = content
    Instance.new("UICorner", statsBox).CornerRadius = UDim.new(0, 9)

    local function statLabel(text, yOff, color)
        local l = Instance.new("TextLabel")
        l.Size           = UDim2.new(1, -16, 0, 20)
        l.Position       = UDim2.new(0, 8, 0, yOff)
        l.BackgroundTransparency = 1
        l.Text           = text
        l.Font           = Enum.Font.GothamBold
        l.TextSize       = 11
        l.TextColor3     = color or Color3.fromRGB(0, 230, 140)
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Parent         = statsBox
        return l
    end

    local fpsLbl  = statLabel("FPS: --",     6)
    local pingLbl = statLabel("Ping: -- ms", 30)
    local modeLbl = statLabel("Mode: Idle",  54, Color3.fromRGB(150,150,170))

    local badgeLbl = Instance.new("TextLabel")
    badgeLbl.Size           = UDim2.new(0.9, 0, 0, 16)
    badgeLbl.Position       = UDim2.new(0.05, 0, 0, 254)
    badgeLbl.BackgroundTransparency = 1
    badgeLbl.Text           = "⚙ Delta Compatible  |  [J] Toggle  [K] Hide"
    badgeLbl.Font           = Enum.Font.Gotham
    badgeLbl.TextSize       = 10
    badgeLbl.TextColor3     = Color3.fromRGB(0, 190, 255)
    badgeLbl.TextXAlignment = Enum.TextXAlignment.Center
    badgeLbl.Parent         = content

    -- enable/disable logic extracted so keybind can reuse it
    local function setEnabled(state)
        config.enabled = state
        if config.enabled then
            toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 200, 80)
            toggleBtn.Text = "▶ ENABLED  [J]"
            statusLbl.Text = config.savedPosition
                and "Spot Status: Position Locked ✔"
                or  "⚠ No Position Saved"
            statusLbl.TextColor3 = config.savedPosition
                and Color3.fromRGB(0, 230, 140)
                or  Color3.fromRGB(255, 160, 40)
            disableAnims()
            startAutoClick()
            monitorRecast()
            task.wait(0.3)
            castRod()
        else
            toggleBtn.BackgroundColor3 = Color3.fromRGB(210,45,45)
            toggleBtn.Text = "⏹ DISABLED  [J]"
            stopAutoClick()
            if animConnection then animConnection:Disconnect() end
        end
    end

    -- ── Collapse / Expand ─────────────────────────────────────────
    local collapsed = false
    local function setCollapsed(state)
        collapsed = state
        content.Visible = not collapsed
        if collapsed then
            frame.Size     = UDim2.new(0, W, 0, 36)
            frame.Position = UDim2.new(0.5, -W/2, 0.5, -18)
        else
            frame.Size     = UDim2.new(0, W, 0, H)
            frame.Position = UDim2.new(0.5, -W/2, 0.5, -H/2)
        end
        minBtn.Text = collapsed and "+" or "—"
    end
    minBtn.MouseButton1Click:Connect(function() setCollapsed(not collapsed) end)

    instantBtn.MouseButton1Click:Connect(function()
        config.instantCatch = not config.instantCatch
        if config.instantCatch then
            instantBtn.BackgroundColor3 = Color3.fromRGB(200,120,0)
            instantBtn.Text = "⚡ INSTANT CATCH: ON"
        else
            instantBtn.BackgroundColor3 = Color3.fromRGB(50,50,65)
            instantBtn.Text = "⚡ INSTANT CATCH: OFF"
        end
    end)

    saveBtn.MouseButton1Click:Connect(function()
        local char = player.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            config.savedPosition = char.HumanoidRootPart.CFrame
            saveBtn.BackgroundColor3 = Color3.fromRGB(0, 160, 90)
            gotoBtn.TextColor3 = Color3.fromRGB(255,255,255)
            statusLbl.Text       = "Spot Status: Position Locked ✔"
            statusLbl.TextColor3 = Color3.fromRGB(0, 230, 140)
            task.wait(0.4)
            saveBtn.BackgroundColor3 = Color3.fromRGB(60,60,75)
        end
    end)

    gotoBtn.MouseButton1Click:Connect(function()
        if config.savedPosition then teleportToSpot() end
    end)

    toggleBtn.MouseButton1Click:Connect(function()
        setEnabled(not config.enabled)
    end)

    -- ── Stats loop ────────────────────────────────────────────────
    task.spawn(function()
        while statsBox and statsBox.Parent do
            task.wait(0.5)
            fpsLbl.Text  = "FPS: " .. currentFPS
            pingLbl.Text = "Ping: " .. currentPing .. " ms"
            if not config.enabled then
                modeLbl.Text       = "Mode: Idle"
                modeLbl.TextColor3 = Color3.fromRGB(130,130,150)
            elseif isMinigameActive then
                modeLbl.Text       = config.instantCatch and "Mode: ⚡ Instant Catching!" or "Mode: 🎯 Catching..."
                modeLbl.TextColor3 = Color3.fromRGB(0, 230, 140)
            else
                modeLbl.Text       = "Mode: 🎣 Waiting for bite..."
                modeLbl.TextColor3 = Color3.fromRGB(255, 200, 60)
            end
        end
    end)

    -- ── Drag ──────────────────────────────────────────────────────
    local dragging, mPos, fPos
    titleBar.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            mPos = inp.Position
            fPos = frame.Position
        end
    end)
    titleBar.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
            local d = inp.Position - mPos
            frame.Position = UDim2.new(
                fPos.X.Scale, fPos.X.Offset + d.X,
                fPos.Y.Scale, fPos.Y.Offset + d.Y
            )
        end
    end)

    -- ── Keybinds: J = toggle on/off | K = hide/show UI ───────────
    UserInputService.InputBegan:Connect(function(inp, gameProcessed)
        if gameProcessed then return end
        if inp.KeyCode == Enum.KeyCode.J then
            setEnabled(not config.enabled)
        elseif inp.KeyCode == Enum.KeyCode.K then
            uiHidden = not uiHidden
            frame.Visible = not uiHidden
        end
    end)

    -- ── Respawn ───────────────────────────────────────────────────
    player.CharacterAdded:Connect(function()
        if config.enabled then task.wait(0.8); disableAnims() end
    end)

    sg.Parent = playerGui
end

task.wait(1)
buildUI()
