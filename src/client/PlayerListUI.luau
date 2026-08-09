local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local UILayout = require(script.Parent.UILayout)

-- Custom replacement for Roblox's default player list (hidden by CoinsUI.Start()) -- sits below
-- the Coins pill, top-right, so the two never overlap. Autumn-toned rounded panel (not fully
-- transparent like CoinsUI/SackUI -- this one holds a variable number of rows, so a soft backing
-- keeps it readable regardless of what's behind it). Rows show name + Coins, sorted highest-to-
-- lowest, and the whole thing collapses via the toggle button (useful on mobile).
local PlayerListUI = {}

local PANEL_COLOR = Color3.fromRGB(58, 34, 20)
local PANEL_TRANSPARENCY = 0.25
local STROKE_COLOR = Color3.fromRGB(210, 150, 80)

local function formatAmount(amount)
	local text = tostring(math.floor(amount))
	return text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

local function applyPanelStyle(frame, cornerRadius)
	frame.BackgroundColor3 = PANEL_COLOR
	frame.BackgroundTransparency = PANEL_TRANSPARENCY
	frame.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, cornerRadius)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = STROKE_COLOR
	stroke.Transparency = 0.4
	stroke.Thickness = 1.25
	stroke.Parent = frame
end

-- Two thin rotated bars meeting at a point, not a font glyph -- Unicode triangle characters
-- (▾ / ▸) aren't in Roblox's supported glyph set and rendered as nothing. Rotation = 0 reads as
-- pointing down (expanded); rotating the whole icon -90 degrees turns that into pointing right
-- (collapsed).
local function buildChevron(parent)
	local chevron = Instance.new("Frame")
	chevron.Name = "Chevron"
	chevron.AnchorPoint = Vector2.new(1, 0.5)
	chevron.Position = UDim2.new(1, -12, 0.5, 0)
	chevron.Size = UDim2.new(0, 16, 0, 16)
	chevron.BackgroundTransparency = 1
	chevron.Parent = parent

	local function bar(rotation)
		local b = Instance.new("Frame")
		b.AnchorPoint = Vector2.new(0.5, 1)
		b.Position = UDim2.new(0.5, 0, 0.7, 0)
		b.Size = UDim2.new(0, 2, 0, 9)
		b.Rotation = rotation
		b.BackgroundColor3 = Color3.new(1, 1, 1)
		b.BorderSizePixel = 0
		b.Parent = chevron

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = b
	end

	bar(45)
	bar(-45)

	return chevron
end

local function buildUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PlayerListUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	local toggleButton = Instance.new("TextButton")
	toggleButton.Name = "ToggleButton"
	toggleButton.AnchorPoint = Vector2.new(1, 0)
	toggleButton.Position = UDim2.new(1, -UILayout.EdgeMargin, 0, UILayout.PlayerToggleY)
	toggleButton.Size = UDim2.new(0, UILayout.WidgetWidth, 0, UILayout.PlayerToggleHeight)
	toggleButton.AutoButtonColor = false
	toggleButton.Font = Enum.Font.FredokaOne
	toggleButton.Text = "Players"
	toggleButton.TextSize = 18
	toggleButton.TextColor3 = Color3.new(1, 1, 1)
	toggleButton.Parent = screenGui
	applyPanelStyle(toggleButton, 10)

	local chevron = buildChevron(toggleButton)

	-- Hugs its content on both axes -- anchored at the right edge, so it grows/shrinks leftward as
	-- rows change width instead of reserving a fixed block with wasted space for short names.
	local listPanel = Instance.new("Frame")
	listPanel.Name = "ListPanel"
	listPanel.AnchorPoint = Vector2.new(1, 0)
	listPanel.Position = UDim2.new(1, -UILayout.EdgeMargin, 0, UILayout.PlayerListY)
	listPanel.Size = UDim2.new(0, 0, 0, 0)
	listPanel.AutomaticSize = Enum.AutomaticSize.XY
	listPanel.Parent = screenGui
	applyPanelStyle(listPanel, 12)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = listPanel

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = listPanel

	screenGui.Parent = playerGui
	return toggleButton, chevron, listPanel
end

-- A TextButton, not a plain label -- clicking another player opens Roblox's native friend-request
-- prompt, the same "click a name to add them" behavior the default player list has. Skipped for
-- the local player's own row (sending yourself a friend request doesn't mean anything).
local function newRow(container, player, localPlayer)
	local row = Instance.new("TextButton")
	row.Name = "Row"
	row.Size = UDim2.new(0, 0, 0, 22)
	row.AutomaticSize = Enum.AutomaticSize.X
	row.BackgroundTransparency = 1
	row.AutoButtonColor = false
	row.Font = Enum.Font.FredokaOne
	row.TextSize = 16
	row.TextWrapped = false
	row.TextXAlignment = Enum.TextXAlignment.Right
	row.TextColor3 = Color3.new(1, 1, 1)
	row.Parent = container

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.4
	stroke.Thickness = 1
	stroke.Parent = row

	if player ~= localPlayer then
		row.MouseButton1Click:Connect(function()
			pcall(function()
				StarterGui:SetCore("PromptFriendRequest", player)
			end)
		end)
	end

	return row
end

function PlayerListUI.Start()
	local toggleButton, chevron, listPanel = buildUI()

	local shown = true
	toggleButton.MouseButton1Click:Connect(function()
		shown = not shown
		listPanel.Visible = shown
		chevron.Rotation = shown and 0 or -90
	end)

	local rows = {} -- Player -> { row = TextLabel, coinsConn = RBXScriptConnection? }

	local function coinsOf(player)
		local leaderstats = player:FindFirstChild("leaderstats")
		local coins = leaderstats and leaderstats:FindFirstChild("Coins")
		return coins and coins.Value or 0
	end

	local function refreshRow(player)
		local entry = rows[player]
		if entry then
			entry.row.Text = string.format("%s  %s", player.Name, formatAmount(coinsOf(player)))
		end
	end

	-- Highest Coins first, matching Roblox's own default player list sort feel -- ties broken
	-- alphabetically so the order never jitters between two equal values.
	local function resort()
		local ordered = {}
		for player in pairs(rows) do
			table.insert(ordered, player)
		end
		table.sort(ordered, function(a, b)
			local aValue, bValue = coinsOf(a), coinsOf(b)
			if aValue == bValue then
				return a.Name < b.Name
			end
			return aValue > bValue
		end)
		for index, player in ipairs(ordered) do
			rows[player].row.LayoutOrder = index
		end
	end

	local localPlayer = Players.LocalPlayer

	local function onPlayerAdded(player)
		local entry = { row = newRow(listPanel, player, localPlayer) }
		rows[player] = entry
		refreshRow(player)
		resort()

		task.spawn(function()
			local leaderstats = player:WaitForChild("leaderstats", 10)
			local coins = leaderstats and leaderstats:WaitForChild("Coins", 10)
			if coins and rows[player] == entry then
				entry.coinsConn = coins.Changed:Connect(function()
					refreshRow(player)
					resort()
				end)
				refreshRow(player)
				resort()
			end
		end)
	end

	local function onPlayerRemoving(player)
		local entry = rows[player]
		if entry then
			if entry.coinsConn then
				entry.coinsConn:Disconnect()
			end
			entry.row:Destroy()
			rows[player] = nil
			resort()
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
end

return PlayerListUI
