local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Same slide-in/pulse/shake progress-bar system as OverheatUI.luau, reused as-is (see that file's
-- comments for the reasoning behind each piece), just reading the Rake's flat RakeCooldownFraction/
-- RakeOnCooldown attributes instead of the Blower's heat buildup -- a straight timer counting down
-- to 0 rather than something that can build up faster or slower depending on use.
local RakeCooldownUI = {}

local TOOL_NAME = "LeafRake"

local BAR_COLOR = Color3.fromRGB(210, 150, 70)
local BAR_COLOR_LOCKED = Color3.fromRGB(255, 90, 70)

local PULSE_TWEEN_INFO = TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local SHOW_TWEEN_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local HIDE_TWEEN_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FADE_TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function buildUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "RakeCooldownUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	-- Same position OverheatUI's bar uses -- only one of the two tools is ever equipped (and
	-- therefore visible) at once, so they never actually overlap on screen.
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.new(0.5, 0, 1, -100)
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
	fill.BackgroundColor3 = BAR_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	screenGui.Parent = playerGui

	return container, track, trackStroke, fill
end

function RakeCooldownUI.Start()
	local player = Players.LocalPlayer
	local container, track, trackStroke, fill = buildUI()

	local restingPosition = container.Position
	local hiddenPosition = restingPosition + UDim2.new(0, 0, 0, 16)
	container.Position = hiddenPosition

	local currentTool = nil
	local pulseTween = nil
	local visibilityTween = nil
	local isVisible = false
	local wasOnCooldown = false
	local basePosition = restingPosition

	local function shake()
		task.spawn(function()
			local duration = 0.3
			local magnitude = 5
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
			pulseTween = TweenService:Create(fill, PULSE_TWEEN_INFO, { BackgroundTransparency = 0.5 })
			pulseTween:Play()
		elseif pulseTween then
			pulseTween:Cancel()
			pulseTween = nil
			fill.BackgroundTransparency = 0
		end
	end

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

	-- Polled every frame rather than driven off GetAttributeChangedSignal, same reasoning as
	-- OverheatUI: one source of truth for fill/visibility, nothing discrete to miss.
	RunService.Heartbeat:Connect(function()
		local equipped = currentTool ~= nil and currentTool.Parent == player.Character
		local cooldownFraction = math.clamp(currentTool and currentTool:GetAttribute("RakeCooldownFraction") or 0, 0, 1)
		local onCooldown = (currentTool and currentTool:GetAttribute("RakeOnCooldown")) or false

		fill.Size = UDim2.new(cooldownFraction, 0, 1, 0)
		fill.BackgroundColor3 = onCooldown and BAR_COLOR_LOCKED or BAR_COLOR

		if onCooldown and not wasOnCooldown then
			shake()
		end
		wasOnCooldown = onCooldown
		setPulsing(onCooldown)

		applyVisible(equipped and (onCooldown or cooldownFraction > 0.001))
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
		wasOnCooldown = false
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

return RakeCooldownUI
