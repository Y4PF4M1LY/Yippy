-- ============================================================
--  NO-ANIMATION FISHING SCRIPT + SAVE SPOT
--  Works with most Roblox fishing games (e.g. Fishing Simulator,
--  Fisch, Dave's Microgame, etc.)
--  Executor: Synapse X / KRNL / Fluxus / Solara
-- ============================================================

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer  = Players.LocalPlayer
local Character    = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
local Humanoid     = Character:WaitForChild("Humanoid")

-- ============================================================
--  CONFIGURATION  (edit these to match your game)
-- ============================================================
local CFG = {
    -- Auto-Fish settings
    AutoFish        = true,       -- toggle auto fishing on/off
    NoAnimation     = true,       -- skip cast/reel animations
    AutoCast        = true,       -- auto-cast after catch/miss
    CastDelay       = 0.05,       -- seconds between casts (lower = faster)
    AutoReel        = true,       -- auto-reel when fish bites
    ReelDelay       = 0.05,       -- seconds after bite before reeling

    -- Save Spot settings
    SavedPosition   = nil,        -- set by SaveSpot()
    ReturnOnDie     = true,       -- teleport back to spot on respawn

    -- Remote / Function names (change to match YOUR game)
    -- Use game.Workspace or Remote Spy to find these!
    CastRemote      = "Cast",     -- RemoteEvent name for casting
    ReelRemote      = "Reel",     -- RemoteEvent name for reeling
    BiteEvent       = "FishBite", -- RemoteEvent the server fires when fish bites

    -- Animation IDs to disable (add the game's fishing anim IDs here)
    AnimsToKill     = {
        "rbxassetid://000000000",  -- replace with actual animation IDs
    },
}

-- ============================================================
--  UTILITIES
-- ============================================================

local function Notify(title, text, duration)
    duration = duration or 3
    -- Try to use the built-in notification, fall back silently
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title    = "[FishScript] " .. title,
            Text     = text,
            Duration = duration,
        })
    end)
    print("[FishScript] " .. title .. " | " .. text)
end

local function SafeFireRemote(remoteName, ...)
    local remote = LocalPlayer:FindFirstChild(remoteName, true)
               or game.Workspace:FindFirstChild(remoteName, true)
               or game.ReplicatedStorage:FindFirstChild(remoteName, true)
    if remote and remote:IsA("RemoteEvent") then
        remote:FireServer(...)
        return true
    end
    -- Also try RemoteFunction
    local func = game.ReplicatedStorage:FindFirstChild(remoteName, true)
    if func and func:IsA("RemoteFunction") then
        pcall(func.InvokeServer, func, ...)
        return true
    end
    return false
end

-- ============================================================
--  NO-ANIMATION: Kill fishing animations on the character
-- ============================================================

local function KillAnimations()
    if not CFG.NoAnimation then return end
    local AnimController = Character:FindFirstChildOfClass("Animator")
                        or Character:FindFirstChildOfClass("AnimationController")
    if not AnimController then return end

    for _, track in ipairs(AnimController:GetPlayingAnimationTracks()) do
        for _, id in ipairs(CFG.AnimsToKill) do
            if track.Animation.AnimationId == id then
                track:Stop(0)  -- Stop with 0 fade time = instant
            end
        end
        -- Optionally stop ALL tracks (aggressive mode):
        -- track:Stop(0)
    end
end

-- Hook into animation loaded event to instantly kill fishing anims
local Animator = Character:WaitForChild("Humanoid"):WaitForChild("Animator")
Animator.AnimationPlayed:Connect(function(track)
    if not CFG.NoAnimation then return end
    for _, id in ipairs(CFG.AnimsToKill) do
        if track.Animation.AnimationId == id then
            track:Stop(0)
            track:AdjustSpeed(0)
        end
    end
end)

-- ============================================================
--  SAVE SPOT SYSTEM
-- ============================================================

local SavedCFrame = nil

local function SaveSpot()
    SavedCFrame = HumanoidRootPart.CFrame
    CFG.SavedPosition = HumanoidRootPart.Position
    Notify("Spot Saved", string.format(
        "X: %.1f  Y: %.1f  Z: %.1f",
        CFG.SavedPosition.X,
        CFG.SavedPosition.Y,
        CFG.SavedPosition.Z
    ))
end

local function TeleportToSavedSpot()
    if not SavedCFrame then
        Notify("No Spot", "Save a spot first with SaveSpot()!")
        return
    end
    -- Yield until character exists
    Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
    -- Teleport slightly above to avoid floor clipping
    HumanoidRootPart.CFrame = SavedCFrame * CFrame.new(0, 0.5, 0)
    Notify("Teleported", "Returned to saved spot!")
end

-- Auto-return on death if enabled
LocalPlayer.CharacterAdded:Connect(function(newChar)
    Character        = newChar
    HumanoidRootPart = newChar:WaitForChild("HumanoidRootPart")
    Humanoid         = newChar:WaitForChild("Humanoid")

    -- Re-hook animation killer
    local newAnimator = Humanoid:WaitForChild("Animator")
    newAnimator.AnimationPlayed:Connect(function(track)
        if not CFG.NoAnimation then return end
        for _, id in ipairs(CFG.AnimsToKill) do
            if track.Animation.AnimationId == id then
                track:Stop(0)
                track:AdjustSpeed(0)
            end
        end
    end)

    if CFG.ReturnOnDie and SavedCFrame then
        task.wait(1.5) -- wait for character to fully load
        TeleportToSavedSpot()
        Notify("Respawn", "Teleported back to fishing spot.")
    end
end)

-- ============================================================
--  AUTO-FISH LOOP
-- ============================================================

local IsFishing  = false
local FishBit    = false

-- Listen for the server's "fish bite" event
local function HookBiteEvent()
    local biteRemote = game.ReplicatedStorage:FindFirstChild(CFG.BiteEvent, true)
    if biteRemote and biteRemote:IsA("RemoteEvent") then
        biteRemote.OnClientEvent:Connect(function()
            FishBit = true
        end)
        Notify("Hook OK", "Bite event found and hooked!")
    else
        -- Fallback: detect bite via GUI changes (common in fishing games)
        -- Watch for a "Reel!" / "Click!" button becoming visible
        task.spawn(function()
            while true do
                task.wait(0.05)
                -- Generic search for reel buttons across common fishing games
                local gui = LocalPlayer.PlayerGui
                for _, obj in ipairs(gui:GetDescendants()) do
                    if obj:IsA("TextButton") or obj:IsA("ImageButton") then
                        local name = obj.Name:lower()
                        if (name:find("reel") or name:find("click") or name:find("catch"))
                            and obj.Visible then
                            FishBit = true
                        end
                    end
                end
            end
        end)
        Notify("Fallback", "Using GUI detection for bites.")
    end
end

local function DoCast()
    -- Try remote first
    local ok = SafeFireRemote(CFG.CastRemote)
    if not ok then
        -- Fallback: simulate mouse click (works for click-to-cast games)
        -- You can also fire a specific BindableEvent if needed
        Notify("Cast Fail", "Could not find Cast remote — check CFG.CastRemote")
    end
    KillAnimations()
end

local function DoReel()
    local ok = SafeFireRemote(CFG.ReelRemote)
    if not ok then
        Notify("Reel Fail", "Could not find Reel remote — check CFG.ReelRemote")
    end
    KillAnimations()
    FishBit = false
end

local AutoFishConnection

local function StartAutoFish()
    if IsFishing then return end
    IsFishing = true
    FishBit   = false
    HookBiteEvent()

    Notify("Auto Fish", "Started! Press [F] to toggle.")

    task.spawn(function()
        while IsFishing do
            -- Cast
            if CFG.AutoCast then
                DoCast()
                task.wait(CFG.CastDelay)
            end

            -- Wait for bite
            local timeout = 30  -- seconds before recasting if no bite
            local elapsed = 0
            while not FishBit and elapsed < timeout and IsFishing do
                task.wait(0.05)
                elapsed += 0.05
            end

            -- Reel
            if FishBit and CFG.AutoReel then
                task.wait(CFG.ReelDelay)
                DoReel()
                task.wait(0.3)
            end
        end
    end)
end

local function StopAutoFish()
    IsFishing = false
    Notify("Auto Fish", "Stopped.")
end

local function ToggleAutoFish()
    if IsFishing then StopAutoFish() else StartAutoFish() end
end

-- ============================================================
--  KEYBINDS
--  F  = Toggle auto fishing
--  G  = Save current position
--  H  = Teleport to saved position
-- ============================================================

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.F then
        ToggleAutoFish()

    elseif input.KeyCode == Enum.KeyCode.G then
        SaveSpot()

    elseif input.KeyCode == Enum.KeyCode.H then
        TeleportToSavedSpot()
    end
end)

-- ============================================================
--  SIMPLE ON-SCREEN GUI
-- ============================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name         = "FishScriptGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent       = LocalPlayer.PlayerGui

local Frame = Instance.new("Frame")
Frame.Size              = UDim2.new(0, 230, 0, 120)
Frame.Position          = UDim2.new(0, 10, 0.5, -60)
Frame.BackgroundColor3  = Color3.fromRGB(15, 15, 25)
Frame.BackgroundTransparency = 0.15
Frame.BorderSizePixel   = 0
Frame.Parent            = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 8)
Corner.Parent = Frame

local Title = Instance.new("TextLabel")
Title.Size              = UDim2.new(1, 0, 0, 28)
Title.BackgroundColor3  = Color3.fromRGB(30, 120, 220)
Title.BackgroundTransparency = 0
Title.TextColor3        = Color3.fromRGB(255, 255, 255)
Title.Font              = Enum.Font.GothamBold
Title.TextSize          = 13
Title.Text              = "🎣  FISHING SCRIPT"
Title.Parent            = Frame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 8)
TitleCorner.Parent = Title

local function MakeLabel(text, yOffset)
    local lbl = Instance.new("TextLabel")
    lbl.Size             = UDim2.new(1, -10, 0, 20)
    lbl.Position         = UDim2.new(0, 5, 0, 30 + yOffset)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3       = Color3.fromRGB(200, 210, 255)
    lbl.Font             = Enum.Font.Gotham
    lbl.TextSize         = 11
    lbl.TextXAlignment   = Enum.TextXAlignment.Left
    lbl.Text             = text
    lbl.Parent           = Frame
    return lbl
end

MakeLabel("[ F ]  Toggle Auto Fish", 4)
MakeLabel("[ G ]  Save Spot", 24)
MakeLabel("[ H ]  Go to Saved Spot", 44)

local StatusLabel = MakeLabel("Status: IDLE", 68)
StatusLabel.TextColor3 = Color3.fromRGB(100, 200, 100)

-- Update status label
RunService.Heartbeat:Connect(function()
    if IsFishing then
        StatusLabel.Text       = "Status: FISHING 🟢"
        StatusLabel.TextColor3 = Color3.fromRGB(100, 220, 100)
    elseif SavedCFrame then
        StatusLabel.Text       = "Status: SPOT SAVED 📍"
        StatusLabel.TextColor3 = Color3.fromRGB(100, 180, 255)
    else
        StatusLabel.Text       = "Status: IDLE"
        StatusLabel.TextColor3 = Color3.fromRGB(160, 160, 160)
    end
end)

-- ============================================================
--  GLOBAL FUNCTIONS (callable from executor console)
-- ============================================================
_G.SaveSpot          = SaveSpot
_G.TeleportToSpot    = TeleportToSavedSpot
_G.StartAutoFish     = StartAutoFish
_G.StopAutoFish      = StopAutoFish
_G.ToggleAutoFish    = ToggleAutoFish

-- ============================================================
Notify("Loaded", "Ready! F=Fish  G=Save  H=Return")
print([[
╔══════════════════════════════════╗
║   FISHING SCRIPT — LOADED        ║
║  F  → Toggle auto fish           ║
║  G  → Save current spot          ║
║  H  → Teleport to saved spot     ║
║                                  ║
║  Console commands:               ║
║  _G.SaveSpot()                   ║
║  _G.TeleportToSpot()             ║
║  _G.StartAutoFish()              ║
║  _G.StopAutoFish()               ║
╚══════════════════════════════════╝
]])
