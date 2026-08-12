local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local PanelMotion = require(script.Parent.PanelMotion)
local PerformanceMode = require(script.Parent.PerformanceMode)
local TopBar = require(script.Parent.TopBar)
local VIPColorPickerUI = require(script.Parent.VIPColorPickerUI)

-- Same autumn-toned rounded-panel look as InventoryUI/PlayerListUI (dark brown, tan stroke,
-- FredokaOne) instead of the old generic dark-gray/Gotham modal, so all of this project's custom
-- panels read as one consistent design.
--
-- Two rows (VIP Effects toggle, Trail Color) only exist for Leaf Patron owners -- built once
-- up front (same as Fast Mode) but Visible = false / panel shrunk back down for everyone else,
-- re-checked every time the panel opens (Players.LocalPlayer:GetAttribute("Perk_LeafPatron"),
-- same replicated Attribute VIPEffects.luau itself reads) rather than kept live while closed --
-- ownership can't change while this menu is the only thing open, so there's nothing to react to
-- mid-session that Open() itself won't already catch next time.
local SettingsUI = {}

local PANEL_COLOR = Color3.fromRGB(58, 34, 20)
local PANEL_TRANSPARENCY = 0.08
local STROKE_COLOR = Color3.fromRGB(210, 150, 80)
local ON_COLOR = Color3.fromRGB(255, 205, 60)
local OFF_COLOR = Color3.fromRGB(90, 58, 36)

local BASE_PANEL_HEIGHT = 140
local VIP_PANEL_HEIGHT = 224
local VIP_ROW_Y = 116
local TRAIL_ROW_Y = 162

local function buildToggleRow(parent, name, y, labelText)
	local row = Instance.new("Frame")
	row.Name = name
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -36, 0, 36)
	row.Position = UDim2.new(0, 18, 0, y)
	row.ZIndex = 12
	row.Parent = parent

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0.6, 0, 1, 0)
	label.Font = Enum.Font.FredokaOne
	label.Text = labelText
	label.TextSize = 18
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.new(1, 1, 1)
	label.ZIndex = 12
	label.Parent = row

	local toggleTrack = Instance.new("TextButton")
	toggleTrack.Name = "Toggle"
	toggleTrack.AnchorPoint = Vector2.new(1, 0.5)
	toggleTrack.Position = UDim2.new(1, 0, 0.5, 0)
	toggleTrack.Size = UDim2.new(0, 52, 0, 28)
	toggleTrack.BackgroundColor3 = OFF_COLOR
	toggleTrack.AutoButtonColor = false
	toggleTrack.Text = ""
	toggleTrack.ZIndex = 12
	toggleTrack.Parent = row
	PanelMotion.AnimateButton(toggleTrack)

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = toggleTrack

	local trackStroke = Instance.new("UIStroke")
	trackStroke.Color = STROKE_COLOR
	trackStroke.Transparency = 0.5
	trackStroke.Thickness = 1.25
	trackStroke.Parent = toggleTrack

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Position = UDim2.new(0, 2, 0.5, 0)
	knob.Size = UDim2.new(0, 24, 0, 24)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.ZIndex = 13
	knob.Parent = toggleTrack

	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob

	return row, toggleTrack, knob
end

local function buildUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	-- The gear button itself lives in TopBar.luau, shared with CoinsUI, so the two can never end
	-- up overlapping regardless of how wide the Coins number gets -- this module only wires up
	-- what happens when it's clicked.
	local gearButton = TopBar.Build().gearButton
	PanelMotion.AnimateButton(gearButton)

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SettingsUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	-- Purely a visual dimmer + input blocker for the 3D world behind it -- NOT a button. Closing
	-- on an outside click is handled by an explicit screen-bounds check (see SettingsUI.Start),
	-- not click passthrough/Active chains -- those turned out unreliable for nested
	-- Backdrop -> Panel -> content buttons (a click on the toggle also reaching Backdrop's own
	-- click handler and closing the panel immediately, discovered and fixed in InventoryUI).
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Active = true
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.Visible = false
	backdrop.ZIndex = 10
	backdrop.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Active = true
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.Size = UDim2.new(0, 280, 0, BASE_PANEL_HEIGHT)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = PANEL_TRANSPARENCY
	panel.BorderSizePixel = 0
	panel.ZIndex = 11
	panel.Parent = backdrop

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 16)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = STROKE_COLOR
	panelStroke.Transparency = 0.35
	panelStroke.Thickness = 1.5
	panelStroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -50, 0, 26)
	title.Position = UDim2.new(0, 18, 0, 16)
	title.Font = Enum.Font.FredokaOne
	title.Text = "Settings"
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.new(1, 1, 1)
	title.ZIndex = 12
	title.Parent = panel

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -12, 0, 12)
	closeButton.Size = UDim2.new(0, 28, 0, 28)
	closeButton.BackgroundTransparency = 1
	closeButton.AutoButtonColor = false
	closeButton.Font = Enum.Font.FredokaOne
	closeButton.Text = "X"
	closeButton.TextSize = 18
	closeButton.TextColor3 = Color3.new(1, 1, 1)
	closeButton.ZIndex = 12
	closeButton.Parent = panel
	PanelMotion.AnimateButton(closeButton)

	local fastModeRow, fastModeToggle, fastModeKnob = buildToggleRow(panel, "FastModeRow", 70, "Fast Mode")

	local vipEffectsRow, vipEffectsToggle, vipEffectsKnob = buildToggleRow(panel, "VIPEffectsRow", VIP_ROW_Y, "VIP Effects")
	vipEffectsRow.Visible = false

	local trailColorRow = Instance.new("Frame")
	trailColorRow.Name = "TrailColorRow"
	trailColorRow.BackgroundTransparency = 1
	trailColorRow.Size = UDim2.new(1, -36, 0, 36)
	trailColorRow.Position = UDim2.new(0, 18, 0, TRAIL_ROW_Y)
	trailColorRow.Visible = false
	trailColorRow.ZIndex = 12
	trailColorRow.Parent = panel

	local trailColorLabel = Instance.new("TextLabel")
	trailColorLabel.Name = "Label"
	trailColorLabel.BackgroundTransparency = 1
	trailColorLabel.Size = UDim2.new(0.6, 0, 1, 0)
	trailColorLabel.Font = Enum.Font.FredokaOne
	trailColorLabel.Text = "Trail Color"
	trailColorLabel.TextSize = 18
	trailColorLabel.TextXAlignment = Enum.TextXAlignment.Left
	trailColorLabel.TextColor3 = Color3.new(1, 1, 1)
	trailColorLabel.ZIndex = 12
	trailColorLabel.Parent = trailColorRow

	local trailColorButton = Instance.new("TextButton")
	trailColorButton.Name = "OpenButton"
	trailColorButton.AnchorPoint = Vector2.new(1, 0.5)
	trailColorButton.Position = UDim2.new(1, 0, 0.5, 0)
	trailColorButton.Size = UDim2.new(0, 84, 0, 30)
	trailColorButton.BackgroundColor3 = OFF_COLOR
	trailColorButton.AutoButtonColor = false
	trailColorButton.Font = Enum.Font.FredokaOne
	trailColorButton.Text = "Choose"
	trailColorButton.TextSize = 15
	trailColorButton.TextColor3 = Color3.new(1, 1, 1)
	trailColorButton.ZIndex = 12
	trailColorButton.Parent = trailColorRow
	PanelMotion.AnimateButton(trailColorButton)

	local trailColorButtonCorner = Instance.new("UICorner")
	trailColorButtonCorner.CornerRadius = UDim.new(0, 8)
	trailColorButtonCorner.Parent = trailColorButton

	screenGui.Parent = playerGui

	return gearButton, backdrop, panel, closeButton,
		fastModeToggle, fastModeKnob,
		vipEffectsRow, vipEffectsToggle, vipEffectsKnob,
		trailColorRow, trailColorButton
end

local function setToggleVisual(toggleTrack, knob, isOn)
	toggleTrack.BackgroundColor3 = isOn and ON_COLOR or OFF_COLOR
	local knobPosition = isOn and UDim2.new(1, -26, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
	knob.Position = knobPosition
end

function SettingsUI.Start()
	local gearButton, backdrop, panel, closeButton,
		fastModeToggle, fastModeKnob,
		vipEffectsRow, vipEffectsToggle, vipEffectsKnob,
		trailColorRow, trailColorButton = buildUI()
	local motion = PanelMotion.new(panel, backdrop)
	local player = Players.LocalPlayer

	local remotes = ReplicatedStorage.Shared:WaitForChild("Remotes")
	local setVIPEffectsEnabledFunction = remotes:WaitForChild("SetVIPEffectsEnabled")

	local isFastModeOn = PerformanceMode.IsEnabled()
	setToggleVisual(fastModeToggle, fastModeKnob, isFastModeOn)

	local isVIPEffectsOn = true

	local outsideClickConn = nil

	local function pointInside(guiObject, screenPos)
		local topLeft = guiObject.AbsolutePosition
		local size = guiObject.AbsoluteSize
		return screenPos.X >= topLeft.X and screenPos.X <= topLeft.X + size.X
			and screenPos.Y >= topLeft.Y and screenPos.Y <= topLeft.Y + size.Y
	end

	local function closeModal()
		motion.Hide()
		if outsideClickConn then
			outsideClickConn:Disconnect()
			outsideClickConn = nil
		end
	end

	local function openModal()
		local ownsVIP = player:GetAttribute("Perk_LeafPatron") == true
		vipEffectsRow.Visible = ownsVIP
		trailColorRow.Visible = ownsVIP
		panel.Size = UDim2.new(0, 280, 0, ownsVIP and VIP_PANEL_HEIGHT or BASE_PANEL_HEIGHT)
		if ownsVIP then
			isVIPEffectsOn = player:GetAttribute("VIPEffectsEnabled") ~= false
			setToggleVisual(vipEffectsToggle, vipEffectsKnob, isVIPEffectsOn)
		end

		motion.Show()
		-- Explicit screen-bounds check instead of click passthrough -- see the Backdrop comment
		-- in buildUI for why.
		if not outsideClickConn then
			outsideClickConn = UserInputService.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.Touch then
					return
				end
				local pos = input.Position
				if not pointInside(panel, pos) and not pointInside(gearButton, pos) then
					closeModal()
				end
			end)
		end
	end

	gearButton.MouseButton1Click:Connect(openModal)
	closeButton.MouseButton1Click:Connect(closeModal)

	fastModeToggle.MouseButton1Click:Connect(function()
		isFastModeOn = not isFastModeOn
		PerformanceMode.SetEnabled(isFastModeOn)
		setToggleVisual(fastModeToggle, fastModeKnob, isFastModeOn)
	end)

	vipEffectsToggle.MouseButton1Click:Connect(function()
		local newValue = not isVIPEffectsOn
		local result = setVIPEffectsEnabledFunction:InvokeServer(newValue)
		if result and result.success then
			isVIPEffectsOn = newValue
			setToggleVisual(vipEffectsToggle, vipEffectsKnob, isVIPEffectsOn)
		else
			warn(string.format(
				"[SettingsUI] couldn't toggle VIP effects: %s",
				(result and result.reason) or "unknown error"
			))
		end
	end)

	trailColorButton.MouseButton1Click:Connect(function()
		VIPColorPickerUI.Open()
	end)
end

return SettingsUI
