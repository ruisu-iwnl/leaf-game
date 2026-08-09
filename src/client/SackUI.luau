local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local SackConfig = require(ReplicatedStorage.Shared.SackConfig)
local UILayout = require(script.Parent.UILayout)

local SackUI = {}

local FLASH_TWEEN_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CINCH_TWEEN_INFO = TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_TWEEN_INFO = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- Moved into the top-right stack, below Coins -- one combined row (active sacks + leaf storage)
-- instead of the old separate icon-button-plus-two-line block, so it reads as part of the same
-- stack as Coins/Player list rather than a separate floating widget. The whole row is the click
-- target (bigger, more forgiving tap area than a small icon alone, especially on mobile).
local function buildUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SackUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	local button = Instance.new("TextButton")
	button.Name = "SackButton"
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -UILayout.EdgeMargin, 0, UILayout.SackY)
	button.Size = UDim2.new(0, 0, 0, UILayout.SackHeight)
	button.AutomaticSize = Enum.AutomaticSize.X
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	button.Font = Enum.Font.FredokaOne
	button.Text = ""
	button.TextSize = 22
	button.TextWrapped = false
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Parent = screenGui

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.4
	stroke.Thickness = 1.25
	stroke.Parent = button

	screenGui.Parent = playerGui
	return button
end

function SackUI.Start()
	local player = Players.LocalPlayer
	local remotes = ReplicatedStorage.Shared:WaitForChild("Remotes")
	local spawnSackRemote = remotes:WaitForChild("SpawnSack")

	local button = buildUI()
	local baseTextColor = button.TextColor3

	local function refresh()
		local storage = player:GetAttribute("SackStorage") or 0
		local activeSacks = player:GetAttribute("ActiveSackCount") or 0
		button.Text = string.format(
			"\xF0\x9F\xA7\xBA %d/%d   \xF0\x9F\x8D\x82 %d/%d",
			activeSacks, SackConfig.MaxActiveSacks,
			storage, SackConfig.MaxCapacity
		)
	end

	-- Rejection feedback (empty sack, or already at the active-sack cap): a quick red flash.
	local function flashReject()
		local up = TweenService:Create(button, FLASH_TWEEN_INFO, { TextColor3 = Color3.fromRGB(255, 90, 80) })
		local down = TweenService:Create(button, FLASH_TWEEN_INFO, { TextColor3 = baseTextColor })
		up.Completed:Connect(function()
			down:Play()
		end)
		up:Play()
	end

	-- "Tying it off" feedback on a successful sack: a quick squish-and-pop. Only the height/
	-- rotation are tweened -- width stays under AutomaticSize, so it can't fight that.
	local function playTieAnimation()
		local baseSize = button.Size
		button.Rotation = 0
		local squish = TweenService:Create(button, CINCH_TWEEN_INFO, {
			Size = UDim2.new(baseSize.X.Scale, baseSize.X.Offset, baseSize.Y.Scale, baseSize.Y.Offset - 6),
			Rotation = -4,
		})
		local pop = TweenService:Create(button, POP_TWEEN_INFO, { Size = baseSize, Rotation = 0 })
		squish.Completed:Connect(function(playbackState)
			if playbackState == Enum.PlaybackState.Completed then
				pop:Play()
			end
		end)
		squish:Play()
	end

	button.MouseButton1Click:Connect(function()
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
