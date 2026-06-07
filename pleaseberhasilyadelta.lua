-- Auto Fishing Script v3 | Delta + Solara + Mobile
-- Fixes: cast & reel now fire RemoteEvents directly (bypasses mouse sim issues)
-- PC: J = Toggle | K = Hide UI
-- Mobile: on-screen buttons

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ─────────────────────────────────────────────────────────────
--  Device detection
-- ─────────────────────────────────────────────────────────────
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- ─────────────────────────────────────────────────────────────
--  Executor detection
-- ─────────────────────────────────────────────────────────────
local execName = "PC"
if identifyexecutor then
    execName = tostring(identifyexecutor())
elseif getexecutorname then
    execName = tostring(getexecutorname())
end
local isDelta = string.lower(execName):find("delta") ~= nil
if isMobile then execName = "Mobile" end

-- ─────────────────────────────────────────────────────────────
--  Config
-- ─────────────────────────────────────────────────────────────
local config = {
    enabled       = false,
    instantCatch  = true,
    autoRecast    = true,
    castHoldTime  = 0.5,
    savedPosition = nil,
    clickDelay    = 0.009,
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
local uiHidden         = false
local W, H             = 270, 340

-- ─────────────────────────────────────────────────────────────
--  Remote finder — searches ReplicatedStorage for fishing remotes
--  Common names used by fishing games
-- ─────────────────────────────────────────────────────────────
local function findRemote(...)
    local names = {...}
    -- Search ReplicatedStorage recursively
    local function search(parent)
        for _, child in ipairs(parent:GetChildren()) do
            local lower = child.Name:lower()
            for _, name in ipairs(names) do
                if lower:find(name:lower()) then
                    return child
                end
            end
            local found = search(child)
            if found then return found end
        end
    end
    return search(ReplicatedStorage)
end

-- ─────────────────────────────────────────────────────────────
--  Tool activator — works on all executors including Delta
--  Directly activates/deactivates the equipped tool via
--  the Humanoid's tool methods, bypassing mouse simulation
-- ─────────────────────────────────────────────────────────────
local function getEquippedTool()
    local char = player.Character
    if not char then return nil end
    return char:FindFirstChildOfClass("Tool")
end

local function activateTool()
    local tool = getEquippedTool()
    if not tool then return false end

    -- Method 1: FireServer on the tool's activate remote (most reliable on Delta)
    local activateRemote = tool:FindFirstChild("Activate")
        or tool:FindFirstChild("ActivateEvent")
        or tool:FindFirstChild("UseEvent")
    if activateRemote and activateRemote:IsA("RemoteEvent") then
        activateRemote:FireServer()
        return true
    end

    -- Method 2: Call tool:Activate() directly
    local ok = pcall(function() tool:Activate() end)
    if ok then return true end

    -- Method 3: Delta mouse globals (direct call, no pcall)
    if mouse1press then
        mouse1press()
        return true
    end

    return false
end

local function deactivateTool()
    local tool = getEquippedTool()
    if not tool then return end

    local deactivateRemote = tool:FindFirstChild("Deactivate")
        or tool:FindFirstChild("DeactivateEvent")
    if deactivateRemote and deactivateRemote:IsA("RemoteEvent") then
        deactivateRemote:FireServer()
        return
    end

    pcall(function() tool:Deactivate() end)

    if mouse1release then
        mouse1release()
    end
end

-- ─────────────────────────────────────────────────────────────
--  Minigame button clicker
--  Fires the catch button's remote or clicks it directly
-- ─────────────────────────────────────────────────────────────
local function simClick()
    if isMobile then
        -- Fire any visible catch/tap button
        for _, gui in ipairs(playerGui:GetChildren()) do
            if gui:IsA("ScreenGui") and gui.Enabled and gui.Name ~= "AutoFishingGUI" then
                for _, desc in ipairs(gui:GetDescendants()) do
                    if (desc:IsA("TextButton") or desc:IsA("ImageButton")) and desc.Visible then
                        local t = string.lower(desc.Text or "")
                        local n = string.lower(desc.Name or "")
                        if t:find("tap") or t:find("catch") or n:find("catch") or n:find("tap") or n:find("reel") then
                            pcall(function() desc:activate() end)
                            return
                        end
                    end
                end
            end
        end
        -- Fallback to tool activation
        activateTool()
        task.wait(0.02)
        deactivateTool()
    else
        -- PC/Delta: try tool activation first (most reliable), then mouse globals
        local tool = getEquippedTool()
        if tool then
            -- Check for a catch/reel remote on the tool
            local catchRemote = tool:FindFirstChild("Catch")
                or tool:FindFirstChild("CatchEvent")
                or tool:FindFirstChild("ReelEvent")
                or tool:FindFirstChild("Reel")
            if catchRemote and catchRemote:IsA("RemoteEvent") then
                catchRemote:FireServer()
                return
            end
            -- Try tool:Activate() directly
            local ok = pcall(function() tool:Activate() end)
            if ok then
                task.wait(0.013)
                pcall(function() tool:Deactivate() end)
                return
            end
        end

        -- Last resort: Delta mouse globals (no pcall)
        if mouse1click then
            mouse1click()
        elseif mouse1press and mouse1release then
            mouse1press()
            task.wait(0.013)
            mouse1release()
        end
    end
end

-- ─────────────────────────────────────────────────────────────
--  Cast — hold-activate the rod
-- ─────────────────────────────────────────────────────────────
local function pressFishingButton(holdTime)
    local tool = getEquippedTool()
    if tool then
        -- Try RemoteEvent on tool first
        local castRemote = tool:FindFirstChild("Cast")
            or tool:FindFirstChild("CastEvent")
            or tool:FindFirstChild("Activate")
            or tool:FindFirstChild("ActivateEvent")
        if castRemote and castRemote:IsA("RemoteEvent") then
            castRemote:FireServer()
            task.wait(math.max(0.05, holdTime))
            return
        end
    end

    -- Tool:Activate/Deactivate with hold
    activateTool()
    task.wait(math.max(0.05, holdTime))
    deactivateTool()
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
                    if t:find("tap") or t:find("catch") then return true end
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

-- FPS
RunService.Heartbeat:Connect(function()
    frameCount += 1
    local t = tick()
    if t - lastFPSUpdate >= 1 then
        currentFPS    = frameCount
        frameCount    = 0
        lastFPSUpdate = t
    end
end)

-- Ping
task.spawn(function()
    while true do
        task.wait(0.5)
        local ok, v = pcall(function()
            return math.floor(player:GetNetworkPing() * 1000)
        end)
        if ok and v then currentPing = v end
    end
end)

-- ─────────────────────────────────────────────────────────────
--  UI
-- ─────────────────────────────────────────────────────────────
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
    titleBar.Size             = UDim2.new(1, 0, 0, 40)
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
    titleLbl.Size                   = UDim2.new(1, -50, 1, 0)
    titleLbl.Position               = UDim2.new(0, 12, 0, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text                   = "🎣 Auto Fishing  |  " .. execName
    titleLbl.Font                   = Enum.Font.GothamBold
    titleLbl.TextSize               = 12
    titleLbl.TextColor3             = Color3.fromRGB(255, 255, 255)
    titleLbl.TextXAlignment         = Enum.TextXAlignment.Left
    titleLbl.ZIndex                 = 3
    titleLbl.Parent                 = titleBar

    local minBtn = Instance.new("TextButton")
    minBtn.Size               = UDim2.new(0, 30, 0, 30)
    minBtn.Position           = UDim2.new(1, -36, 0.5, -15)
    minBtn.BackgroundTransparency = 1
    minBtn.Text               = "—"
    minBtn.Font               = Enum.Font.GothamBold
    minBtn.TextSize           = 18
    minBtn.TextColor3         = Color3.fromRGB(255, 255, 255)
    minBtn.ZIndex             = 4
    minBtn.Parent             = titleBar

    local content = Instance.new("Frame")
    content.Size              = UDim2.new(1, 0, 1, -40)
    content.Position          = UDim2.new(0, 0, 0, 40)
    content.BackgroundTransparency = 1
    content.Parent            = frame

    local btnH = isMobile and 44 or 34
    local function makeBtn(text, color, sx, sy, px, py)
        local b = Instance.new("TextButton")
        b.Size             = UDim2.new(sx, 0, 0, sy)
        b.Position         = UDim2.new(px, 0, 0, py)
        b.BackgroundColor3 = color
        b.Text             = text
        b.Font             = Enum.Font.GothamBold
        b.TextSize         = isMobile and 13 or 11
        b.TextColor3       = Color3.fromRGB(255, 255, 255)
        b.AutoButtonColor  = false
        b.Parent           = content
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
        return b
    end

    local y0 = 10
    local toggleBtn = makeBtn("⏹ DISABLED" .. (isMobile and "" or "  [J]"),
        Color3.fromRGB(210,45,45), 0.9, btnH+4, 0.05, y0)
    toggleBtn.TextSize = isMobile and 14 or 12

    local y1 = y0 + btnH + 10
    local instantBtn = makeBtn("⚡ INSTANT CATCH: ON", Color3.fromRGB(200,120,0), 0.9, btnH, 0.05, y1)

    local y2 = y1 + btnH + 6
    local saveBtn = makeBtn("📌 SAVE SPOT", Color3.fromRGB(60,60,75), 0.43, btnH, 0.05, y2)
    local gotoBtn = makeBtn("📍 GOTO SPOT", Color3.fromRGB(60,60,75), 0.43, btnH, 0.52, y2)
    gotoBtn.TextColor3 = Color3.fromRGB(150,150,165)

    local y3 = y2 + btnH + 6
    local statusLbl = Instance.new("TextLabel")
    statusLbl.Size           = UDim2.new(0.9, 0, 0, 22)
    statusLbl.Position       = UDim2.new(0.05, 0, 0, y3)
    statusLbl.BackgroundTransparency = 1
    statusLbl.Text           = "Spot Status: Position Unset"
    statusLbl.Font           = Enum.Font.Gotham
    statusLbl.TextSize       = 11
    statusLbl.TextColor3     = Color3.fromRGB(180,180,200)
    statusLbl.TextXAlignment = Enum.TextXAlignment.Left
    statusLbl.Parent         = content

    local y4 = y3 + 26
    local statsBox = Instance.new("Frame")
    statsBox.Size             = UDim2.new(0.9, 0, 0, 90)
    statsBox.Position         = UDim2.new(0.05, 0, 0, y4)
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

    local y5 = y4 + 96

    if isMobile then
        local hideBtn = makeBtn("👁 HIDE UI", Color3.fromRGB(40,40,55), 0.9, btnH, 0.05, y5)

        local showBtn = Instance.new("TextButton")
        showBtn.Size             = UDim2.new(0, 70, 0, 30)
        showBtn.Position         = UDim2.new(0, 8, 1, -38)
        showBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
        showBtn.Text             = "🎣 Show"
        showBtn.Font             = Enum.Font.GothamBold
        showBtn.TextSize         = 12
        showBtn.TextColor3       = Color3.fromRGB(255,255,255)
        showBtn.Visible          = false
        showBtn.ZIndex           = 10
        showBtn.Parent           = sg
        Instance.new("UICorner", showBtn).CornerRadius = UDim.new(0, 8)

        hideBtn.MouseButton1Click:Connect(function()
            uiHidden        = not uiHidden
            frame.Visible   = not uiHidden
            showBtn.Visible = uiHidden
        end)
        showBtn.MouseButton1Click:Connect(function()
            uiHidden        = false
            frame.Visible   = true
            showBtn.Visible = false
        end)

        H = y5 + btnH + 14
        frame.Size     = UDim2.new(0, W, 0, H)
        frame.Position = UDim2.new(0.5, -W/2, 0.5, -H/2)
    else
        local badgeLbl = Instance.new("TextLabel")
        badgeLbl.Size           = UDim2.new(0.9, 0, 0, 16)
        badgeLbl.Position       = UDim2.new(0.05, 0, 0, y5)
        badgeLbl.BackgroundTransparency = 1
        badgeLbl.Text           = "⚙ Delta/Solara  |  [J] Toggle  [K] Hide"
        badgeLbl.Font           = Enum.Font.Gotham
        badgeLbl.TextSize       = 10
        badgeLbl.TextColor3     = Color3.fromRGB(0, 190, 255)
        badgeLbl.TextXAlignment = Enum.TextXAlignment.Center
        badgeLbl.Parent         = content
    end

    -- ── setEnabled ────────────────────────────────────────────────
    local function setEnabled(state)
        config.enabled = state
        if config.enabled then
            toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 200, 80)
            toggleBtn.Text = "▶ ENABLED" .. (isMobile and "" or "  [J]")
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
            toggleBtn.Text = "⏹ DISABLED" .. (isMobile and "" or "  [J]")
            stopAutoClick()
            if animConnection then animConnection:Disconnect() end
        end
    end

    -- ── Collapse ──────────────────────────────────────────────────
    local collapsed = false
    minBtn.MouseButton1Click:Connect(function()
        collapsed = not collapsed
        content.Visible = not collapsed
        if collapsed then
            frame.Size     = UDim2.new(0, W, 0, 40)
            frame.Position = UDim2.new(0.5, -W/2, 0.5, -20)
        else
            frame.Size     = UDim2.new(0, W, 0, H)
            frame.Position = UDim2.new(0.5, -W/2, 0.5, -H/2)
        end
        minBtn.Text = collapsed and "+" or "—"
    end)

    instantBtn.MouseButton1Click:Connect(function()
        config.instantCatch = not config.instantCatch
        instantBtn.BackgroundColor3 = config.instantCatch
            and Color3.fromRGB(200,120,0) or Color3.fromRGB(50,50,65)
        instantBtn.Text = config.instantCatch
            and "⚡ INSTANT CATCH: ON" or "⚡ INSTANT CATCH: OFF"
    end)

    saveBtn.MouseButton1Click:Connect(function()
        local char = player.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            config.savedPosition = char.HumanoidRootPart.CFrame
            saveBtn.BackgroundColor3 = Color3.fromRGB(0,160,90)
            gotoBtn.TextColor3       = Color3.fromRGB(255,255,255)
            statusLbl.Text           = "Spot Status: Position Locked ✔"
            statusLbl.TextColor3     = Color3.fromRGB(0,230,140)
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

    -- Stats loop
    task.spawn(function()
        while statsBox and statsBox.Parent do
            task.wait(0.5)
            fpsLbl.Text  = "FPS: "  .. currentFPS
            pingLbl.Text = "Ping: " .. currentPing .. " ms"
            if not config.enabled then
                modeLbl.Text       = "Mode: Idle"
                modeLbl.TextColor3 = Color3.fromRGB(130,130,150)
            elseif isMinigameActive then
                modeLbl.Text       = config.instantCatch and "Mode: ⚡ Instant Catching!" or "Mode: 🎯 Catching..."
                modeLbl.TextColor3 = Color3.fromRGB(0,230,140)
            else
                modeLbl.Text       = "Mode: 🎣 Waiting for bite..."
                modeLbl.TextColor3 = Color3.fromRGB(255,200,60)
            end
        end
    end)

    -- Drag (mouse + touch)
    local dragging, mPos, fPos
    titleBar.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            mPos = inp.Position
            fPos = frame.Position
        end
    end)
    titleBar.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragging and (
            inp.UserInputType == Enum.UserInputType.MouseMovement or
            inp.UserInputType == Enum.UserInputType.Touch
        ) then
            local d = inp.Position - mPos
            frame.Position = UDim2.new(
                fPos.X.Scale, fPos.X.Offset + d.X,
                fPos.Y.Scale, fPos.Y.Offset + d.Y
            )
        end
    end)

    -- PC keybinds
    if not isMobile then
        UserInputService.InputBegan:Connect(function(inp, gameProcessed)
            if gameProcessed then return end
            if inp.KeyCode == Enum.KeyCode.J then
                setEnabled(not config.enabled)
            elseif inp.KeyCode == Enum.KeyCode.K then
                uiHidden      = not uiHidden
                frame.Visible = not uiHidden
            end
        end)
    end

    player.CharacterAdded:Connect(function()
        if config.enabled then task.wait(0.8); disableAnims() end
    end)

    sg.Parent = playerGui
end

task.wait(1)
buildUI()
