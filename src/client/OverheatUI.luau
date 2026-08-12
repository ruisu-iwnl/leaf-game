local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UILayout = require(script.Parent.UILayout)

local OverheatUI = {}

local TOOL_NAME = "LeafBlower"

local COLOR_COOL = Color3.fromRGB(120, 210, 255)
local COLOR_HOT = Color3.fromRGB(255, 120, 40)
local COLOR_OVERHEATED = Color3.fromRGB(255, 70, 60)

local PULSE_TWEEN_INFO = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local SHOW_TWEEN_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local HIDE_TWEEN_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FADE_TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Heat itself lives entirely as attributes on the tool instance, which persists (and keeps
-- updating server-side) whether it's in the Character or sitting in the Backpack -- so this UI
-- just needs to find that one instance once per life and keep reading it continuously, without
-- ever "unbinding" on unequip. That's deliberate: an earlier version rebound on every equip/unequip
-- and fell back to 0 while unbound, which both looked like (and briefly was) a way to dodge seeing
-- the cooldown -- letting go doesn't erase progress, and this UI shouldn't pretend it does either.
local function buildUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "OverheatUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = UILayout.DisplayOrder.HUD

	-- Bottom-center, just clear of the screen edge -- nothing else lives down here now that
	-- Roblox's default hotbar is disabled in favor of HotbarUI (bottom-right).
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.new(0.5, 0, 1, -UILayout.HudBottomMargin)
	container.Size = UDim2.new(0, 220, 0, 18)
	container.BackgroundTransparency = 1
	container.Visible = false
	container.Parent = screenGui

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = UDim2.new(0.5, 0, 0, 0)
	track.Size = UDim2.new(1, 0, 0, 12)
	track.BackgroundColor3 = Color3.new(0, 0, 0)
	track.BackgroundTransparency = 0.45
	track.BorderSizePixel = 0
	track.Parent = container

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local trackStroke = Instance.new("UIStroke")
	trackStroke.Color = Color3.new(1, 1, 1)
	trackStroke.Transparency = 0.6
	trackStroke.Thickness = 1.25
	trackStroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 0)
	fill.Position = UDim2.new(0, 0, 0, 0)
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = COLOR_COOL
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	screenGui.Parent = playerGui

	return container, track, trackStroke, fill
end

function OverheatUI.Start()
	local player = Players.LocalPlayer
	local container, track, trackStroke, fill = buildUI()

	local restingPosition = container.Position
	local hiddenPosition = restingPosition + UDim2.new(0, 0, 0, 16)
	container.Position = hiddenPosition

	local currentTool = nil
	local pulseTween = nil
	local visibilityTween = nil
	local isVisible = false
	local wasOverheated = false
	local basePosition = restingPosition

	-- Quick decaying jitter on the whole bar, fired once right when overheat triggers -- separate
	-- from the steady pulse (which keeps going the whole time it's locked out). Shakes around
	-- whatever the current slide-in/out position is, not a fixed point.
	local function shake()
		task.spawn(function()
			local duration = 0.35
			local magnitude = 6
			local elapsed = 0
			while elapsed < duration do
				local dt = task.wait()
				elapsed += dt
				local decay = 1 - math.min(elapsed / duration, 1)
				local offsetX = (math.random() - 0.5) * 2 * magnitude * decay
				local offsetY = (math.random() - 0.5) * 2 * magnitude * decay
				basePosition = isVisible and restingPosition or hiddenPosition
				container.Position = basePosition + UDim2.new(0, offsetX, 0, offsetY)
			end
			container.Position = basePosition
		end)
	end

	local function setPulsing(active)
		if active then
			if pulseTween then
				return
			end
			pulseTween = TweenService:Create(fill, PULSE_TWEEN_INFO, { BackgroundTransparency = 0.55 })
			pulseTween:Play()
		elseif pulseTween then
			pulseTween:Cancel()
			pulseTween = nil
			fill.BackgroundTransparency = 0
		end
	end

	-- Modern slide-and-settle entrance/exit -- Position + a couple of plain Transparency tweens,
	-- deliberately not a CanvasGroup/GroupTransparency: that relies on an offscreen compositing
	-- buffer that isn't reliably supported on every platform/graphics setting, and silently doing
	-- nothing (staying fully visible) was exactly the bug that took three rounds to track down here.
	local function applyVisible(show)
		if isVisible == show then
			return
		end
		isVisible = show

		if visibilityTween then
			visibilityTween:Cancel()
		end

		if show then
			container.Visible = true
			visibilityTween = TweenService:Create(container, SHOW_TWEEN_INFO, { Position = restingPosition })
			visibilityTween:Play()
			TweenService:Create(track, FADE_TWEEN_INFO, { BackgroundTransparency = 0.45 }):Play()
			TweenService:Create(trackStroke, FADE_TWEEN_INFO, { Transparency = 0.6 }):Play()
		else
			visibilityTween = TweenService:Create(container, HIDE_TWEEN_INFO, { Position = hiddenPosition })
			visibilityTween:Play()
			TweenService:Create(track, HIDE_TWEEN_INFO, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(trackStroke, HIDE_TWEEN_INFO, { Transparency = 1 }):Play()

			local thisTween = visibilityTween
			thisTween.Completed:Connect(function(playbackState)
				if playbackState == Enum.PlaybackState.Completed and not isVisible and visibilityTween == thisTween then
					container.Visible = false
				end
			end)
		end
	end

	-- Polled every frame rather than driven off GetAttributeChangedSignal -- one source of truth
	-- for fill/visibility, so there's no discrete event to miss.
	--
	-- Visibility has two independent gates:
	--   - equipped: currently in the Character, not just sitting in the Backpack. Unequipping
	--     (even mid-blow, without clicking to stop first) hides the bar immediately -- there's no
	--     reason to keep a HUD element on screen for a tool you're not even holding.
	--   - equipped AND (blowing, locked out from overheating, OR still holding leftover heat) --
	--     so letting go with partial heat still shows it draining to 0 while equipped, instead of
	--     vanishing early.
	-- This does NOT reopen the earlier reset exploit: currentTool is never swapped out just because
	-- it's unequipped (see the note above buildUI), so heatFraction always reads the true,
	-- continuously-tracked server value the instant it's shown again, whether that's because you
	-- re-equipped or because it started blowing/overheating again.
	RunService.Heartbeat:Connect(function()
		local equipped = currentTool ~= nil and currentTool.Parent == player.Character
		local heatFraction = math.clamp(currentTool and currentTool:GetAttribute("HeatFraction") or 0, 0, 1)
		local overheated = (currentTool and currentTool:GetAttribute("Overheated")) or false
		local blowing = (currentTool and currentTool:GetAttribute("Blowing")) or false

		fill.Size = UDim2.new(heatFraction, 0, 1, 0)
		fill.BackgroundColor3 = overheated and COLOR_OVERHEATED or COLOR_COOL:Lerp(COLOR_HOT, heatFraction)

		if overheated and not wasOverheated then
			shake()
		end
		wasOverheated = overheated
		setPulsing(overheated)

		applyVisible(equipped and (blowing or overheated or heatFraction > 0.001))
	end)

	local function findTool(character)
		if character then
			local inCharacter = character:FindFirstChild(TOOL_NAME)
			if inCharacter and inCharacter:IsA("Tool") then
				return inCharacter
			end
		end
		local backpack = player:FindFirstChild("Backpack")
		local inBackpack = backpack and backpack:FindFirstChild(TOOL_NAME)
		if inBackpack and inBackpack:IsA("Tool") then
			return inBackpack
		end
		return nil
	end

	-- StarterPack clones a fresh tool into the Backpack automatically on spawn, but that can lag a
	-- frame or two behind CharacterAdded -- retry briefly instead of giving up on the first miss.
	local function onCharacterAdded(character)
		currentTool = nil
		wasOverheated = false
		task.spawn(function()
			local tool = findTool(character)
			local attempts = 0
			while not tool and attempts < 50 and character == player.Character do
				task.wait(0.1)
				tool = findTool(character)
				attempts += 1
			end
			if character == player.Character then
				currentTool = tool
			end
		end)
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

return OverheatUI
