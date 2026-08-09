local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local SackConfig = require(ReplicatedStorage.Shared.SackConfig)

local SackUI = {}

local FLASH_TWEEN_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CINCH_TWEEN_INFO = TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_TWEEN_INFO = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- Fully transparent, no card/circle backdrop -- just the icon and text floating over the world,
-- same FredokaOne font as the cleanup zone UI for a consistent look. UIStrokes on the text (not a
-- background panel) are what keep it legible over grass/leaves instead of a dark card.
local function buildUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SackUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0, 1)
	container.Position = UDim2.new(0, 20, 1, -20)
	container.Size = UDim2.new(0, 210, 0, 68)
	container.BackgroundTransparency = 1
	container.Parent = screenGui

	local sackButton = Instance.new("TextButton")
	sackButton.Name = "SackButton"
	sackButton.AnchorPoint = Vector2.new(0, 0.5)
	sackButton.Position = UDim2.new(0, 10, 0.5, 0)
	sackButton.Size = UDim2.new(0, 48, 0, 48)
	sackButton.BackgroundTransparency = 1
	sackButton.AutoButtonColor = false
	sackButton.Text = ""
	sackButton.Parent = container

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.new(1, 0, 1, 0)
	icon.Position = UDim2.new(0.5, 0, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Font = Enum.Font.FredokaOne
	icon.Text = "🧺"
	icon.TextScaled = true
	icon.TextColor3 = Color3.new(1, 1, 1)
	icon.Parent = sackButton

	local iconStroke = Instance.new("UIStroke")
	iconStroke.Color = Color3.new(0, 0, 0)
	iconStroke.Transparency = 0.5
	iconStroke.Thickness = 1.5
	iconStroke.Parent = icon

	local statsFrame = Instance.new("Frame")
	statsFrame.Name = "Stats"
	statsFrame.AnchorPoint = Vector2.new(0, 0.5)
	statsFrame.Position = UDim2.new(0, 62, 0.5, 0)
	statsFrame.Size = UDim2.new(0, 140, 0, 46)
	statsFrame.BackgroundTransparency = 1
	statsFrame.Parent = container

	local statsLayout = Instance.new("UIListLayout")
	statsLayout.FillDirection = Enum.FillDirection.Vertical
	statsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	statsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	statsLayout.Padding = UDim.new(0, 2)
	statsLayout.Parent = statsFrame

	local function newStatLabel(name, layoutOrder)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.LayoutOrder = layoutOrder
		label.Size = UDim2.new(1, 0, 0, 20)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextScaled = true
		label.Parent = statsFrame

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Transparency = 0.5
		stroke.Thickness = 1.25
		stroke.Parent = label

		return label
	end

	local leavesLabel = newStatLabel("LeavesLabel", 1)
	local sacksLabel = newStatLabel("SacksLabel", 2)
	sacksLabel.TextColor3 = Color3.fromRGB(215, 215, 220)

	screenGui.Parent = playerGui

	return sackButton, leavesLabel, sacksLabel, icon
end

function SackUI.Start()
	local player = Players.LocalPlayer
	local remotes = ReplicatedStorage.Shared:WaitForChild("Remotes")
	local spawnSackRemote = remotes:WaitForChild("SpawnSack")

	local sackButton, leavesLabel, sacksLabel, icon = buildUI()
	local baseButtonSize = sackButton.Size
	local baseIconColor = icon.TextColor3

	local function refresh()
		local storage = player:GetAttribute("SackStorage") or 0
		local activeSacks = player:GetAttribute("ActiveSackCount") or 0
		leavesLabel.Text = string.format("🍂 %d / %d", storage, SackConfig.MaxCapacity)
		sacksLabel.Text = string.format("🧺 %d / %d", activeSacks, SackConfig.MaxActiveSacks)
	end

	-- Rejection feedback (empty sack, or already at the active-sack cap): a quick red flash on the
	-- icon itself (no background to flash anymore) rather than letting the click silently do nothing.
	local function flashReject()
		local up = TweenService:Create(icon, FLASH_TWEEN_INFO, { TextColor3 = Color3.fromRGB(255, 90, 80) })
		local down = TweenService:Create(icon, FLASH_TWEEN_INFO, { TextColor3 = baseIconColor })
		up.Completed:Connect(function()
			down:Play()
		end)
		up:Play()
	end

	-- "Tying it off" feedback on a successful sack: the button squishes and rotates like it's being
	-- cinched shut, then pops back with a little overshoot.
	local function playTieAnimation()
		sackButton.Rotation = 0
		local squish = TweenService:Create(sackButton, CINCH_TWEEN_INFO, {
			Size = UDim2.new(baseButtonSize.X.Scale, baseButtonSize.X.Offset + 6, baseButtonSize.Y.Scale, baseButtonSize.Y.Offset - 10),
			Rotation = -12,
		})
		local pop = TweenService:Create(sackButton, POP_TWEEN_INFO, { Size = baseButtonSize, Rotation = 0 })
		squish.Completed:Connect(function(playbackState)
			if playbackState == Enum.PlaybackState.Completed then
				pop:Play()
			end
		end)
		squish:Play()
	end

	sackButton.MouseButton1Click:Connect(function()
		local storage = player:GetAttribute("SackStorage") or 0
		local activeSacks = player:GetAttribute("ActiveSackCount") or 0
		if storage <= 0 or activeSacks >= SackConfig.MaxActiveSacks then
			flashReject()
			return
		end
		spawnSackRemote:FireServer()
		playTieAnimation()
	end)

	refresh()
	player:GetAttributeChangedSignal("SackStorage"):Connect(refresh)
	player:GetAttributeChangedSignal("ActiveSackCount"):Connect(refresh)
end

return SackUI
