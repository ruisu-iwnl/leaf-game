local Players = game:GetService("Players")

local PerformanceMode = require(script.Parent.PerformanceMode)

local SettingsUI = {}

local ON_COLOR = Color3.fromRGB(76, 175, 80)
local OFF_COLOR = Color3.fromRGB(80, 80, 80)

local function buildUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SettingsUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	local gearButton = Instance.new("TextButton")
	gearButton.Name = "GearButton"
	gearButton.AnchorPoint = Vector2.new(0, 0.5)
	gearButton.Position = UDim2.new(0, 20, 0.5, 0)
	gearButton.Size = UDim2.new(0, 44, 0, 44)
	gearButton.BackgroundColor3 = Color3.new(0, 0, 0)
	gearButton.BackgroundTransparency = 0.5
	gearButton.AutoButtonColor = false
	gearButton.Font = Enum.Font.GothamBold
	gearButton.Text = "⚙"
	gearButton.TextScaled = true
	gearButton.TextColor3 = Color3.new(1, 1, 1)
	gearButton.Parent = screenGui

	local gearCorner = Instance.new("UICorner")
	gearCorner.CornerRadius = UDim.new(1, 0)
	gearCorner.Parent = gearButton

	-- Backdrop doubles as a click-outside-to-close button.
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.Visible = false
	backdrop.ZIndex = 10
	backdrop.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Active = true -- blocks clicks from passing through to the backdrop underneath
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.Size = UDim2.new(0, 260, 0, 130)
	panel.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	panel.BorderSizePixel = 0
	panel.ZIndex = 11
	panel.Parent = backdrop

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -50, 0, 30)
	title.Position = UDim2.new(0, 14, 0, 10)
	title.Font = Enum.Font.GothamBold
	title.Text = "Settings"
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.new(1, 1, 1)
	title.ZIndex = 12
	title.Parent = panel

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -8, 0, 8)
	closeButton.Size = UDim2.new(0, 28, 0, 28)
	closeButton.BackgroundTransparency = 1
	closeButton.AutoButtonColor = false
	closeButton.Font = Enum.Font.GothamBold
	closeButton.Text = "X"
	closeButton.TextScaled = true
	closeButton.TextColor3 = Color3.new(1, 1, 1)
	closeButton.ZIndex = 12
	closeButton.Parent = panel

	local row = Instance.new("Frame")
	row.Name = "FastModeRow"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -28, 0, 36)
	row.Position = UDim2.new(0, 14, 0, 60)
	row.ZIndex = 12
	row.Parent = panel

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0.6, 0, 1, 0)
	label.Font = Enum.Font.Gotham
	label.Text = "Fast Mode"
	label.TextScaled = true
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

	return gearButton, backdrop, closeButton, toggleTrack, knob
end

local function setToggleVisual(toggleTrack, knob, isOn)
	toggleTrack.BackgroundColor3 = isOn and ON_COLOR or OFF_COLOR
	local knobPosition = isOn and UDim2.new(1, -26, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
	knob.Position = knobPosition
end

function SettingsUI.Start()
	local gearButton, backdrop, closeButton, toggleTrack, knob = buildUI()

	local isOn = PerformanceMode.IsEnabled()
	setToggleVisual(toggleTrack, knob, isOn)

	local function closeModal()
		backdrop.Visible = false
	end

	gearButton.MouseButton1Click:Connect(function()
		backdrop.Visible = true
	end)
	closeButton.MouseButton1Click:Connect(closeModal)
	backdrop.MouseButton1Click:Connect(closeModal)

	toggleTrack.MouseButton1Click:Connect(function()
		isOn = not isOn
		PerformanceMode.SetEnabled(isOn)
		setToggleVisual(toggleTrack, knob, isOn)
	end)
end

return SettingsUI
