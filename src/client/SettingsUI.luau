local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local PerformanceMode = require(script.Parent.PerformanceMode)
local TopBar = require(script.Parent.TopBar)

-- Same autumn-toned rounded-panel look as InventoryUI/PlayerListUI (dark brown, tan stroke,
-- FredokaOne) instead of the old generic dark-gray/Gotham modal, so all of this project's custom
-- panels read as one consistent design.
local SettingsUI = {}

local PANEL_COLOR = Color3.fromRGB(58, 34, 20)
local PANEL_TRANSPARENCY = 0.08
local STROKE_COLOR = Color3.fromRGB(210, 150, 80)
local ON_COLOR = Color3.fromRGB(255, 205, 60)
local OFF_COLOR = Color3.fromRGB(90, 58, 36)

local function buildUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	-- The gear button itself lives in TopBar.luau, shared with CoinsUI, so the two can never end
	-- up overlapping regardless of how wide the Coins number gets -- this module only wires up
	-- what happens when it's clicked.
	local gearButton = TopBar.Build().gearButton

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
	panel.Size = UDim2.new(0, 280, 0, 140)
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

	local row = Instance.new("Frame")
	row.Name = "FastModeRow"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -36, 0, 36)
	row.Position = UDim2.new(0, 18, 0, 70)
	row.ZIndex = 12
	row.Parent = panel

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0.6, 0, 1, 0)
	label.Font = Enum.Font.FredokaOne
	label.Text = "Fast Mode"
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

	screenGui.Parent = playerGui

	return gearButton, backdrop, panel, closeButton, toggleTrack, knob
end

local function setToggleVisual(toggleTrack, knob, isOn)
	toggleTrack.BackgroundColor3 = isOn and ON_COLOR or OFF_COLOR
	local knobPosition = isOn and UDim2.new(1, -26, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
	knob.Position = knobPosition
end

function SettingsUI.Start()
	local gearButton, backdrop, panel, closeButton, toggleTrack, knob = buildUI()

	local isOn = PerformanceMode.IsEnabled()
	setToggleVisual(toggleTrack, knob, isOn)

	local outsideClickConn = nil

	local function pointInside(guiObject, screenPos)
		local topLeft = guiObject.AbsolutePosition
		local size = guiObject.AbsoluteSize
		return screenPos.X >= topLeft.X and screenPos.X <= topLeft.X + size.X
			and screenPos.Y >= topLeft.Y and screenPos.Y <= topLeft.Y + size.Y
	end

	local function closeModal()
		backdrop.Visible = false
		if outsideClickConn then
			outsideClickConn:Disconnect()
			outsideClickConn = nil
		end
	end

	local function openModal()
		backdrop.Visible = true
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

	toggleTrack.MouseButton1Click:Connect(function()
		isOn = not isOn
		PerformanceMode.SetEnabled(isOn)
		setToggleVisual(toggleTrack, knob, isOn)
	end)
end

return SettingsUI
