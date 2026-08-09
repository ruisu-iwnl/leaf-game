local Players = game:GetService("Players")

local UILayout = require(script.Parent.UILayout)

-- Row 1 of the top-right stack: the settings gear and the Coins readout, built as ONE row so a
-- single UIListLayout reflows them together automatically -- two independently positioned widgets
-- only ever line up correctly for one assumed Coins width, and start overlapping once the number
-- grows past that (large balances, etc.).
--
-- CoinsUI and SettingsUI both call TopBar.Build(); only the first call actually constructs
-- anything, the memoized result is handed back to whichever asks second -- so there's exactly one
-- row/ScreenGui no matter which client module happens to start first.
local TopBar = {}

local built = nil

local function buildGearIcon(button)
	local barY = { 0.28, 0.5, 0.72 }
	local knobX = { 0.68, 0.32, 0.55 }

	for i = 1, 3 do
		local bar = Instance.new("Frame")
		bar.Name = "Bar" .. i
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.new(0.5, 0, barY[i], 0)
		bar.Size = UDim2.new(0, 22, 0, 2)
		bar.BackgroundColor3 = Color3.new(1, 1, 1)
		bar.BackgroundTransparency = 0.1
		bar.BorderSizePixel = 0
		bar.Parent = button

		local knob = Instance.new("Frame")
		knob.Name = "Knob"
		knob.AnchorPoint = Vector2.new(0.5, 0.5)
		knob.Position = UDim2.new(knobX[i], 0, 0.5, 0)
		knob.Size = UDim2.new(0, 8, 0, 8)
		knob.BackgroundColor3 = Color3.new(1, 1, 1)
		knob.BorderSizePixel = 0
		knob.Parent = bar

		local knobCorner = Instance.new("UICorner")
		knobCorner.CornerRadius = UDim.new(1, 0)
		knobCorner.Parent = knob
	end
end

local function buildCoinIcon(parent, layoutOrder)
	local icon = Instance.new("Frame")
	icon.Name = "CoinIcon"
	icon.LayoutOrder = layoutOrder
	icon.Size = UDim2.new(0, 32, 0, 32)
	icon.BackgroundColor3 = Color3.fromRGB(255, 205, 60)
	icon.Parent = parent

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(1, 0)
	iconCorner.Parent = icon

	local iconStroke = Instance.new("UIStroke")
	iconStroke.Color = Color3.fromRGB(140, 95, 20)
	iconStroke.Thickness = 2
	iconStroke.Parent = icon

	-- Thin inner ring, just for a bit of coin-like detail rather than a flat circle.
	local innerRing = Instance.new("Frame")
	innerRing.Name = "InnerRing"
	innerRing.AnchorPoint = Vector2.new(0.5, 0.5)
	innerRing.Position = UDim2.new(0.5, 0, 0.5, 0)
	innerRing.Size = UDim2.new(0, 22, 0, 22)
	innerRing.BackgroundTransparency = 1
	innerRing.Parent = icon

	local innerCorner = Instance.new("UICorner")
	innerCorner.CornerRadius = UDim.new(1, 0)
	innerCorner.Parent = innerRing

	local innerStroke = Instance.new("UIStroke")
	innerStroke.Color = Color3.fromRGB(140, 95, 20)
	innerStroke.Transparency = 0.35
	innerStroke.Thickness = 1
	innerStroke.Parent = innerRing
end

function TopBar.Build()
	if built then
		return built
	end

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TopBar"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	-- Hugs its own content on the X axis, anchored at the right edge -- grows leftward as the
	-- Coins number gets wider, and the gear just gets pushed along with it instead of overlapped.
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.AnchorPoint = Vector2.new(1, 0)
	row.Position = UDim2.new(1, -UILayout.EdgeMargin, 0, UILayout.CoinsY)
	row.Size = UDim2.new(0, 0, 0, UILayout.CoinsHeight)
	row.AutomaticSize = Enum.AutomaticSize.X
	row.BackgroundTransparency = 1
	row.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 14)
	layout.Parent = row

	local gearButton = Instance.new("TextButton")
	gearButton.Name = "GearButton"
	gearButton.LayoutOrder = 1
	gearButton.Size = UDim2.new(0, UILayout.GearSize, 0, UILayout.GearSize)
	gearButton.BackgroundTransparency = 1
	gearButton.AutoButtonColor = false
	gearButton.Text = ""
	gearButton.Parent = row
	buildGearIcon(gearButton)

	buildCoinIcon(row, 2)

	local amountLabel = Instance.new("TextLabel")
	amountLabel.Name = "Amount"
	amountLabel.LayoutOrder = 3
	amountLabel.Size = UDim2.new(0, 0, 1, 0)
	amountLabel.AutomaticSize = Enum.AutomaticSize.X
	amountLabel.BackgroundTransparency = 1
	amountLabel.Font = Enum.Font.FredokaOne
	amountLabel.Text = "0"
	amountLabel.TextScaled = false
	amountLabel.TextSize = 26
	amountLabel.TextWrapped = false
	amountLabel.TextXAlignment = Enum.TextXAlignment.Left
	amountLabel.TextColor3 = Color3.new(1, 1, 1)
	amountLabel.Parent = row

	local amountStroke = Instance.new("UIStroke")
	amountStroke.Color = Color3.new(0, 0, 0)
	amountStroke.Transparency = 0.35
	amountStroke.Thickness = 1.5
	amountStroke.Parent = amountLabel

	screenGui.Parent = playerGui

	built = {
		gearButton = gearButton,
		amountLabel = amountLabel,
	}
	return built
end

return TopBar
