local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local PanelMotion = require(script.Parent.PanelMotion)

-- Opened from SettingsUI.luau's "Trail Color" row (Leaf Patron owners only) -- 3 draggable RGB
-- sliders + a live swatch preview, or a "Rainbow" button to go back to the default animated cycle.
-- Saving invokes VIPPreferences.luau's SetVIPTrailColor RemoteFunction (server-validated, persisted
-- via SaveSystem) -- VIPEffects.luau (every client, not just this one) picks the new value up off
-- the replicated VIPTrailColor Attribute with no further plumbing needed here.
--
-- Same autumn-toned panel look as SettingsUI, layered ABOVE it (higher ZIndex) rather than closing
-- Settings first and reopening after -- there's no proximity-based auto-close to fight here (unlike
-- StorePanelUI's Ruisu-distance close), so there's nothing forcing the close-then-reopen dance that
-- pattern needs elsewhere in this game.
local VIPColorPickerUI = {}

local PANEL_COLOR = Color3.fromRGB(58, 34, 20)
local STROKE_COLOR = Color3.fromRGB(210, 150, 80)
local TRACK_COLOR = Color3.fromRGB(90, 58, 36)
local ACCENT_COLOR = Color3.fromRGB(255, 205, 60)

local CHANNELS = {
	{ label = "R", color = Color3.fromRGB(230, 90, 90) },
	{ label = "G", color = Color3.fromRGB(90, 200, 110) },
	{ label = "B", color = Color3.fromRGB(90, 140, 230) },
}

local DEFAULT_RGB = { 160, 70, 230 } -- the old fixed trail purple, used as a fallback/first-open value

local function clamp255(n)
	return math.clamp(math.floor(n + 0.5), 0, 255)
end

local function toHex(rgb)
	return string.format("#%02X%02X%02X", clamp255(rgb[1]), clamp255(rgb[2]), clamp255(rgb[3]))
end

local function fromHex(hex)
	local r = tonumber(hex:sub(2, 3), 16)
	local g = tonumber(hex:sub(4, 5), 16)
	local b = tonumber(hex:sub(6, 7), 16)
	if not (r and g and b) then
		return nil
	end
	return { r, g, b }
end

-- Builds one R/G/B row (label, live value readout, a draggable track+handle+fill). `onChanged(value)`
-- fires on every drag update; the returned `setValue(value)` function moves the slider FROM code
-- (re-syncing to a just-loaded color) WITHOUT re-firing onChanged, so opening the panel never
-- immediately re-triggers a "the player changed this" callback for a value it just loaded itself.
local function buildSlider(parent, yPos, channel, onChanged)
	local row = Instance.new("Frame")
	row.Name = channel.label .. "Row"
	row.Position = UDim2.new(0, 16, 0, yPos)
	row.Size = UDim2.new(1, -32, 0, 26)
	row.BackgroundTransparency = 1
	row.ZIndex = 32
	row.Parent = parent

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(0, 18, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = channel.label
	label.TextColor3 = channel.color
	label.TextSize = 16
	label.ZIndex = 32
	label.Parent = row

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "Value"
	valueLabel.AnchorPoint = Vector2.new(1, 0)
	valueLabel.Position = UDim2.new(1, 0, 0, 0)
	valueLabel.Size = UDim2.new(0, 34, 1, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Font = Enum.Font.FredokaOne
	valueLabel.TextSize = 14
	valueLabel.TextColor3 = Color3.new(1, 1, 1)
	valueLabel.Text = "0"
	valueLabel.ZIndex = 32
	valueLabel.Parent = row

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.new(0, 24, 0.5, -6)
	track.Size = UDim2.new(1, -24 - 40, 0, 12)
	track.BackgroundColor3 = TRACK_COLOR
	track.BorderSizePixel = 0
	track.ZIndex = 32
	track.Parent = row

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = channel.color
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.ZIndex = 33
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local handle = Instance.new("Frame")
	handle.Name = "Handle"
	handle.AnchorPoint = Vector2.new(0.5, 0.5)
	handle.Position = UDim2.new(0, 0, 0.5, 0)
	handle.Size = UDim2.new(0, 16, 0, 16)
	handle.BackgroundColor3 = Color3.new(1, 1, 1)
	handle.ZIndex = 34
	handle.Parent = track

	local handleCorner = Instance.new("UICorner")
	handleCorner.CornerRadius = UDim.new(1, 0)
	handleCorner.Parent = handle

	local function moveTo(relative)
		relative = math.clamp(relative, 0, 1)
		fill.Size = UDim2.new(relative, 0, 1, 0)
		handle.Position = UDim2.new(relative, 0, 0.5, 0)
		valueLabel.Text = tostring(clamp255(relative * 255))
	end

	local dragging = false

	local function setFromX(x)
		local size = track.AbsoluteSize.X
		if size <= 0 then
			return
		end
		local relative = math.clamp((x - track.AbsolutePosition.X) / size, 0, 1)
		moveTo(relative)
		onChanged(clamp255(relative * 255))
	end

	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
		end
	end)

	local function setValue(value)
		moveTo(value / 255)
	end

	return setValue
end

local function buildUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "VIPColorPickerUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 25 -- above SettingsUI's default (0), same "layered on top" reasoning as the module comment

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Active = true
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.Visible = false
	backdrop.ZIndex = 30
	backdrop.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Active = true
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.Size = UDim2.new(0, 300, 0, 260)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BorderSizePixel = 0
	panel.ZIndex = 31
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
	title.Position = UDim2.new(0, 18, 0, 14)
	title.Font = Enum.Font.FredokaOne
	title.Text = "Trail Color"
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.new(1, 1, 1)
	title.ZIndex = 32
	title.Parent = panel

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -12, 0, 10)
	closeButton.Size = UDim2.new(0, 28, 0, 28)
	closeButton.BackgroundTransparency = 1
	closeButton.AutoButtonColor = false
	closeButton.Font = Enum.Font.FredokaOne
	closeButton.Text = "X"
	closeButton.TextSize = 18
	closeButton.TextColor3 = Color3.new(1, 1, 1)
	closeButton.ZIndex = 32
	closeButton.Parent = panel
	PanelMotion.AnimateButton(closeButton)

	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.Position = UDim2.new(0, 18, 0, 48)
	swatch.Size = UDim2.new(0, 44, 0, 44)
	swatch.BackgroundColor3 = Color3.fromRGB(table.unpack(DEFAULT_RGB))
	swatch.BorderSizePixel = 0
	swatch.ZIndex = 32
	swatch.Parent = panel

	local swatchCorner = Instance.new("UICorner")
	swatchCorner.CornerRadius = UDim.new(0, 10)
	swatchCorner.Parent = swatch

	local swatchStroke = Instance.new("UIStroke")
	swatchStroke.Color = STROKE_COLOR
	swatchStroke.Transparency = 0.2
	swatchStroke.Thickness = 1.5
	swatchStroke.Parent = swatch

	local rainbowButton = Instance.new("TextButton")
	rainbowButton.Name = "RainbowButton"
	rainbowButton.Position = UDim2.new(0, 74, 0, 48)
	rainbowButton.Size = UDim2.new(1, -74 - 18, 0, 44)
	rainbowButton.BackgroundColor3 = TRACK_COLOR
	rainbowButton.AutoButtonColor = false
	rainbowButton.Font = Enum.Font.FredokaOne
	rainbowButton.Text = "Use Rainbow"
	rainbowButton.TextSize = 16
	rainbowButton.TextColor3 = Color3.new(1, 1, 1)
	rainbowButton.ZIndex = 32
	rainbowButton.Parent = panel
	PanelMotion.AnimateButton(rainbowButton)

	local rainbowCorner = Instance.new("UICorner")
	rainbowCorner.CornerRadius = UDim.new(0, 10)
	rainbowCorner.Parent = rainbowButton

	local rainbowStroke = Instance.new("UIStroke")
	rainbowStroke.Name = "SelectedStroke"
	rainbowStroke.Color = ACCENT_COLOR
	rainbowStroke.Thickness = 2
	rainbowStroke.Transparency = 1 -- shown (Transparency 0) only while Rainbow is the active selection
	rainbowStroke.Parent = rainbowButton

	local saveButton = Instance.new("TextButton")
	saveButton.Name = "SaveButton"
	saveButton.AnchorPoint = Vector2.new(0.5, 1)
	saveButton.Position = UDim2.new(0.5, 0, 1, -16)
	saveButton.Size = UDim2.new(1, -36, 0, 38)
	saveButton.BackgroundColor3 = ACCENT_COLOR
	saveButton.AutoButtonColor = false
	saveButton.Font = Enum.Font.FredokaOne
	saveButton.Text = "Save"
	saveButton.TextSize = 18
	saveButton.TextColor3 = Color3.fromRGB(58, 34, 20)
	saveButton.ZIndex = 32
	saveButton.Parent = panel
	PanelMotion.AnimateButton(saveButton)

	local saveCorner = Instance.new("UICorner")
	saveCorner.CornerRadius = UDim.new(0, 10)
	saveCorner.Parent = saveButton

	screenGui.Parent = playerGui
	return backdrop, panel, closeButton, swatch, rainbowButton, rainbowStroke, saveButton
end

function VIPColorPickerUI.Start()
	local backdrop, panel, closeButton, swatch, rainbowButton, rainbowStroke, saveButton = buildUI()
	local motion = PanelMotion.new(panel, backdrop)

	local remotes = ReplicatedStorage.Shared:WaitForChild("Remotes")
	local setTrailColorFunction = remotes:WaitForChild("SetVIPTrailColor")

	-- currentRGB always holds a real color (even in Rainbow mode) so the swatch has something
	-- concrete to show, and Save has a real hex fallback if the player never touches a slider.
	local currentRGB = table.clone(DEFAULT_RGB)
	local isRainbow = true

	local function updateSwatch()
		swatch.BackgroundColor3 = Color3.fromRGB(table.unpack(currentRGB))
	end

	local function setRainbowSelected(selected)
		isRainbow = selected
		rainbowStroke.Transparency = selected and 0 or 1
	end

	-- Built here (not in buildUI) so each slider's onChanged can close directly over currentRGB --
	-- dragging any slider writes that channel's value in and drops out of Rainbow mode, since
	-- picking an RGB value IS how you leave it.
	local sliderSetters = {}
	for i, channel in ipairs(CHANNELS) do
		sliderSetters[i] = buildSlider(panel, 104 + (i - 1) * 32, channel, function(value)
			currentRGB[i] = value
			setRainbowSelected(false)
			updateSwatch()
		end)
	end

	local function syncSlidersToRGB()
		for i, setValue in ipairs(sliderSetters) do
			setValue(currentRGB[i])
		end
		updateSwatch()
	end

	rainbowButton.MouseButton1Click:Connect(function()
		setRainbowSelected(true)
	end)

	local outsideClickConn = nil

	local function pointInside(guiObject, screenPos)
		local topLeft = guiObject.AbsolutePosition
		local size = guiObject.AbsoluteSize
		return screenPos.X >= topLeft.X and screenPos.X <= topLeft.X + size.X
			and screenPos.Y >= topLeft.Y and screenPos.Y <= topLeft.Y + size.Y
	end

	local function close()
		motion.Hide()
		if outsideClickConn then
			outsideClickConn:Disconnect()
			outsideClickConn = nil
		end
	end

	function VIPColorPickerUI.Open()
		local player = Players.LocalPlayer
		local saved = player:GetAttribute("VIPTrailColor") or "Rainbow"
		if saved == "Rainbow" then
			setRainbowSelected(true)
			currentRGB = table.clone(DEFAULT_RGB)
		else
			setRainbowSelected(false)
			currentRGB = fromHex(saved) or table.clone(DEFAULT_RGB)
		end
		syncSlidersToRGB()

		motion.Show()
		if not outsideClickConn then
			outsideClickConn = UserInputService.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.Touch then
					return
				end
				if not pointInside(panel, input.Position) then
					close()
				end
			end)
		end
	end

	closeButton.MouseButton1Click:Connect(close)

	saveButton.MouseButton1Click:Connect(function()
		local colorValue = isRainbow and "Rainbow" or toHex(currentRGB)
		local result = setTrailColorFunction:InvokeServer(colorValue)
		if not (result and result.success) then
			warn(string.format(
				"[VIPColorPickerUI] couldn't save trail color: %s",
				(result and result.reason) or "unknown error"
			))
		end
		close()
	end)
end

return VIPColorPickerUI
