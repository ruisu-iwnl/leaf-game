local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ToolIcons = require(script.Parent.ToolIcons)
local UILayout = require(script.Parent.UILayout)

-- A custom "Inventory" panel showing everything the player currently owns/carries (right now:
-- the Blower and, if they're holding one, a Sack), their Coins balance, and a reserved "Active
-- Perks" row for whenever gamepasses/upgrades actually grant perks -- opened via a backpack-
-- shaped button sitting just above the hotbar.
--
-- Item icons use the SAME ToolIcons module/shapes as HotbarUI (ToolIcons.luau sets their ZIndex
-- to 100, well above any card), so the Blower/Sack look identical in both places.
--
-- Every slot's card is fully destroyed and rebuilt (icon included, in one shot) whenever its
-- content changes, rather than mutating a long-lived card in place -- building a bare card first
-- and adding an icon into it later, after it had already been through a layout pass, silently
-- failed to render anything.
local InventoryUI = {}

-- Palette
local PANEL_COLOR = Color3.fromRGB(58, 34, 20)
local PANEL_TRANSPARENCY = 0.08
local STROKE_COLOR = Color3.fromRGB(210, 150, 80)
local EMPTY_CARD_COLOR = Color3.fromRGB(58, 34, 20)
local FILLED_CARD_COLOR = Color3.fromRGB(90, 58, 36)
local CARD_STROKE = Color3.fromRGB(210, 150, 80)
local EQUIPPED_STROKE = Color3.fromRGB(255, 205, 60)
local SECTION_LABEL_COLOR = Color3.fromRGB(220, 195, 160)
local BADGE_OUTLINE = Color3.fromRGB(255, 238, 210)

local DISPLAY_NAMES = {
	LeafBlower = "Blower",
	LeafSack = "Sack",
	LeafRake = "Rake",
}

-- Layout
local BUTTON_SIZE = 48
local CARD_SIZE = 84
local CARD_PADDING = 14
local GRID_COLUMNS = 5
local GRID_ROWS = 2
local TOTAL_SLOTS = GRID_COLUMNS * GRID_ROWS

local PERK_SLOT_SIZE = 44
local PERK_SLOT_PADDING = 10
local PERK_SLOT_COUNT = 6

local PANEL_PADDING = 18
local HEADER_HEIGHT = 30
local SECTION_GAP = 10
local LABEL_HEIGHT = 16
local LABEL_TO_CONTENT_GAP = 6

local ITEMS_GRID_HEIGHT = GRID_ROWS * CARD_SIZE + (GRID_ROWS - 1) * CARD_PADDING
local ITEMS_LABEL_Y = PANEL_PADDING + HEADER_HEIGHT + SECTION_GAP
local ITEMS_GRID_Y = ITEMS_LABEL_Y + LABEL_HEIGHT + LABEL_TO_CONTENT_GAP
local PERKS_LABEL_Y = ITEMS_GRID_Y + ITEMS_GRID_HEIGHT + SECTION_GAP
local PERKS_ROW_Y = PERKS_LABEL_Y + LABEL_HEIGHT + LABEL_TO_CONTENT_GAP

local PANEL_WIDTH = PANEL_PADDING * 2 + GRID_COLUMNS * CARD_SIZE + (GRID_COLUMNS - 1) * CARD_PADDING
local PANEL_HEIGHT = PERKS_ROW_Y + PERK_SLOT_SIZE + PANEL_PADDING

local function formatAmount(amount)
	local text = tostring(math.floor(amount))
	return text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

local function buildBackpackIcon(parent)
	local body = Instance.new("Frame")
	body.Name = "Icon"
	body.AnchorPoint = Vector2.new(0.5, 0.6)
	body.Position = UDim2.new(0.5, 0, 0.5, 0)
	body.Size = UDim2.new(0, 24, 0, 22)
	body.BackgroundColor3 = Color3.fromRGB(150, 96, 50)
	body.BorderSizePixel = 0
	body.Parent = parent

	local bodyCorner = Instance.new("UICorner")
	bodyCorner.CornerRadius = UDim.new(0, 7)
	bodyCorner.Parent = body

	local flap = Instance.new("Frame")
	flap.Name = "Flap"
	flap.AnchorPoint = Vector2.new(0.5, 1)
	flap.Position = UDim2.new(0.5, 0, 0.4, 0)
	flap.Size = UDim2.new(0, 18, 0, 9)
	flap.BackgroundColor3 = Color3.fromRGB(120, 76, 40)
	flap.BorderSizePixel = 0
	flap.Parent = body

	local flapCorner = Instance.new("UICorner")
	flapCorner.CornerRadius = UDim.new(0, 4)
	flapCorner.Parent = flap

	local pocket = Instance.new("Frame")
	pocket.Name = "Pocket"
	pocket.AnchorPoint = Vector2.new(0.5, 1)
	pocket.Position = UDim2.new(0.5, 0, 1, -3)
	pocket.Size = UDim2.new(0, 11, 0, 7)
	pocket.BackgroundColor3 = Color3.fromRGB(120, 76, 40)
	pocket.BorderSizePixel = 0
	pocket.Parent = body

	local pocketCorner = Instance.new("UICorner")
	pocketCorner.CornerRadius = UDim.new(0, 3)
	pocketCorner.Parent = pocket
end

-- Big, bright, high-contrast cream outline -- a dark outline on this panel's dark background
-- barely registered, this does.
local function buildCoinIcon(parent)
	local icon = Instance.new("Frame")
	icon.Name = "CoinIcon"
	icon.Size = UDim2.new(0, 26, 0, 26)
	icon.BackgroundColor3 = Color3.fromRGB(255, 205, 60)
	icon.BorderSizePixel = 0
	icon.ZIndex = 13
	icon.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = icon

	local stroke = Instance.new("UIStroke")
	stroke.Color = BADGE_OUTLINE
	stroke.Transparency = 0.15
	stroke.Thickness = 2
	stroke.Parent = icon
end

-- No icon shape at all -- the card's own outline (see buildSlotCard) is now the only visual
-- marker for a slot, filled or empty, so an empty one just reads as an outlined box with nothing
-- in it rather than needing a dedicated placeholder glyph.
local function buildEmptySlotIcon(_card, _size) end

local function currentTools(player)
	local tools = {}
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") then
				table.insert(tools, child)
			end
		end
	end
	local character = player.Character
	local equipped = character and character:FindFirstChildOfClass("Tool")
	if equipped then
		table.insert(tools, equipped)
	end
	return tools
end

local function buildSectionLabel(panel, y, text)
	local label = Instance.new("TextLabel")
	label.Name = "SectionLabel"
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, PANEL_PADDING, 0, y)
	label.Size = UDim2.new(1, -PANEL_PADDING * 2, 0, LABEL_HEIGHT)
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = SECTION_LABEL_COLOR
	label.ZIndex = 12
	label.Parent = panel
end

-- Builds one slot's card COMPLETE with its badge already in place (or as an empty placeholder if
-- `tool` is nil) -- everything created together in one call. Explicit Size regardless of which
-- layout it lives in -- UIGridLayout (the item grid) auto-sizes children via CellSize, but
-- UIListLayout (the perks row) does NOT; leaving Size unset there means 0x0/invisible cards.
local function buildSlotCard(parent, layoutOrder, size, tool)
	local card = Instance.new("TextButton")
	card.Name = "Slot" .. layoutOrder
	card.LayoutOrder = layoutOrder
	card.Size = UDim2.new(0, size, 0, size)
	card.AutoButtonColor = false
	card.Active = tool ~= nil
	card.Text = ""
	card.BorderSizePixel = 0
	card.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, size >= 64 and 14 or 10)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Parent = card

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.AnchorPoint = Vector2.new(0.5, 1)
	nameLabel.Position = UDim2.new(0.5, 0, 1, -2)
	nameLabel.Size = UDim2.new(1, -4, 0, 20)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextSize = 18
	nameLabel.TextScaled = false
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0
	nameLabel.ZIndex = 100
	nameLabel.Visible = size >= 64
	nameLabel.Parent = card

	if tool then
		card.BackgroundColor3 = FILLED_CARD_COLOR
		card.BackgroundTransparency = 0
		stroke.Color = CARD_STROKE
		stroke.Transparency = 0.15
		stroke.Thickness = 2
		nameLabel.Text = DISPLAY_NAMES[tool.Name] or tool.Name
		local iconBuilder = ToolIcons.Builders[tool.Name]
		if iconBuilder then
			iconBuilder(card)
		end
	else
		card.BackgroundColor3 = EMPTY_CARD_COLOR
		card.BackgroundTransparency = 0.35
		stroke.Color = CARD_STROKE
		stroke.Transparency = 0.45
		stroke.Thickness = 2
		nameLabel.Text = ""
		buildEmptySlotIcon(card, size)
	end

	return card, stroke, nameLabel
end

local function buildUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "InventoryUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	-- Sits just above the hotbar, right-aligned to match it.
	local button = Instance.new("TextButton")
	button.Name = "InventoryButton"
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(1, -UILayout.HotbarEdgeMargin, 1, -(UILayout.HotbarEdgeMargin + UILayout.HotbarCardSize + 10))
	button.Size = UDim2.new(0, BUTTON_SIZE, 0, BUTTON_SIZE)
	button.BackgroundColor3 = PANEL_COLOR
	button.BackgroundTransparency = 0.15
	button.AutoButtonColor = false
	button.Text = ""
	button.BorderSizePixel = 0
	button.Parent = screenGui

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 12)
	buttonCorner.Parent = button

	local buttonStroke = Instance.new("UIStroke")
	buttonStroke.Color = STROKE_COLOR
	buttonStroke.Transparency = 0.4
	buttonStroke.Thickness = 1.5
	buttonStroke.Parent = button

	buildBackpackIcon(button)

	-- Purely a visual dimmer + input blocker for the 3D world behind it -- NOT a button. Closing
	-- on an outside click is handled by an explicit screen-bounds check (see InventoryUI.Start),
	-- not by click passthrough/Active chains -- those turned out unreliable here: clicks on cards
	-- nested inside Backdrop -> Panel -> Grid -> Card kept also reaching Backdrop's own click
	-- handler and closing the panel immediately, no matter how Active was set on the frames in
	-- between.
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
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0, PANEL_HEIGHT)
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
	title.Position = UDim2.new(0, PANEL_PADDING, 0, PANEL_PADDING)
	title.Size = UDim2.new(0, 140, 0, HEADER_HEIGHT)
	title.Font = Enum.Font.FredokaOne
	title.Text = "Inventory"
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

	-- Coins readout, same row as the title, ending just before the close button.
	local coinsHolder = Instance.new("Frame")
	coinsHolder.Name = "Coins"
	coinsHolder.AnchorPoint = Vector2.new(1, 0)
	coinsHolder.Position = UDim2.new(1, -48, 0, PANEL_PADDING)
	coinsHolder.Size = UDim2.new(0, 130, 0, HEADER_HEIGHT)
	coinsHolder.BackgroundTransparency = 1
	coinsHolder.ZIndex = 12
	coinsHolder.Parent = panel

	local coinsLayout = Instance.new("UIListLayout")
	coinsLayout.FillDirection = Enum.FillDirection.Horizontal
	coinsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	coinsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	coinsLayout.Padding = UDim.new(0, 8)
	coinsLayout.Parent = coinsHolder

	local coinIconHolder = Instance.new("Frame")
	coinIconHolder.Name = "CoinIconHolder"
	coinIconHolder.LayoutOrder = 1
	coinIconHolder.Size = UDim2.new(0, 26, 0, 26)
	coinIconHolder.BackgroundTransparency = 1
	coinIconHolder.ZIndex = 12
	coinIconHolder.Parent = coinsHolder
	buildCoinIcon(coinIconHolder)

	local coinsLabel = Instance.new("TextLabel")
	coinsLabel.Name = "CoinsLabel"
	coinsLabel.LayoutOrder = 2
	coinsLabel.Size = UDim2.new(0, 0, 1, 0)
	coinsLabel.AutomaticSize = Enum.AutomaticSize.X
	coinsLabel.BackgroundTransparency = 1
	coinsLabel.Font = Enum.Font.FredokaOne
	coinsLabel.Text = "0"
	coinsLabel.TextSize = 18
	coinsLabel.TextColor3 = Color3.new(1, 1, 1)
	coinsLabel.ZIndex = 12
	coinsLabel.Parent = coinsHolder

	buildSectionLabel(panel, ITEMS_LABEL_Y, "Items")

	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.new(0, PANEL_PADDING, 0, ITEMS_GRID_Y)
	grid.Size = UDim2.new(1, -PANEL_PADDING * 2, 0, ITEMS_GRID_HEIGHT)
	grid.ZIndex = 12
	grid.Parent = panel

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, CARD_SIZE, 0, CARD_SIZE)
	gridLayout.CellPadding = UDim2.new(0, CARD_PADDING, 0, CARD_PADDING)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	local slots = {}
	for i = 1, TOTAL_SLOTS do
		local card, stroke, nameLabel = buildSlotCard(grid, i, CARD_SIZE, nil)
		slots[i] = {
			parent = grid,
			layoutOrder = i,
			size = CARD_SIZE,
			card = card,
			stroke = stroke,
			nameLabel = nameLabel,
			tool = nil,
			clickConn = nil,
		}
	end

	-- Reserved for whenever gamepasses/upgrades actually grant perks -- always shown empty for
	-- now, same visual language as an empty item slot, just smaller and unclickable.
	buildSectionLabel(panel, PERKS_LABEL_Y, "Active Perks")

	local perksRow = Instance.new("Frame")
	perksRow.Name = "PerksRow"
	perksRow.BackgroundTransparency = 1
	perksRow.Position = UDim2.new(0, PANEL_PADDING, 0, PERKS_ROW_Y)
	perksRow.Size = UDim2.new(1, -PANEL_PADDING * 2, 0, PERK_SLOT_SIZE)
	perksRow.ZIndex = 12
	perksRow.Parent = panel

	local perksLayout = Instance.new("UIListLayout")
	perksLayout.FillDirection = Enum.FillDirection.Horizontal
	perksLayout.SortOrder = Enum.SortOrder.LayoutOrder
	perksLayout.Padding = UDim.new(0, PERK_SLOT_PADDING)
	perksLayout.Parent = perksRow

	for i = 1, PERK_SLOT_COUNT do
		buildSlotCard(perksRow, i, PERK_SLOT_SIZE, nil)
	end

	screenGui.Parent = playerGui
	return button, backdrop, panel, closeButton, slots, coinsLabel
end

function InventoryUI.Start()
	local player = Players.LocalPlayer
	local button, backdrop, panel, closeButton, slots, coinsLabel = buildUI()

	local leaderstats = player:WaitForChild("leaderstats")
	local coins = leaderstats:WaitForChild("Coins")

	local function toggleTool(tool)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		if tool.Parent == character then
			humanoid:UnequipTools()
		else
			humanoid:EquipTool(tool)
		end
	end

	-- Destroys and fully rebuilds a slot's card (badge included) whenever its tool changes.
	local function setSlotTool(slot, tool)
		if slot.tool == tool then
			return
		end

		if slot.clickConn then
			slot.clickConn:Disconnect()
			slot.clickConn = nil
		end
		slot.card:Destroy()

		local card, stroke, nameLabel = buildSlotCard(slot.parent, slot.layoutOrder, slot.size, tool)
		slot.card = card
		slot.stroke = stroke
		slot.nameLabel = nameLabel
		slot.tool = tool

		if tool then
			slot.clickConn = card.MouseButton1Click:Connect(function()
				toggleTool(tool)
			end)
		end
	end

	local function refresh()
		local tools = currentTools(player)
		local character = player.Character

		for i, slot in ipairs(slots) do
			local tool = tools[i]
			setSlotTool(slot, tool)
			if tool then
				local equipped = character ~= nil and tool.Parent == character
				slot.stroke.Color = equipped and EQUIPPED_STROKE or CARD_STROKE
				slot.stroke.Thickness = equipped and 2.5 or 1.5
				slot.stroke.Transparency = equipped and 0.1 or 0.4
			end
		end

		coinsLabel.Text = formatAmount(coins.Value)
	end

	-- Builds the initial state now, before the panel's ever been shown, and again on
	-- CharacterAdded in case Character/Backpack weren't loaded yet at Start().
	refresh()
	player.CharacterAdded:Connect(refresh)

	local heartbeatConn = nil
	local outsideClickConn = nil

	local function pointInside(guiObject, screenPos)
		local topLeft = guiObject.AbsolutePosition
		local size = guiObject.AbsoluteSize
		return screenPos.X >= topLeft.X and screenPos.X <= topLeft.X + size.X
			and screenPos.Y >= topLeft.Y and screenPos.Y <= topLeft.Y + size.Y
	end

	local function closePanel()
		backdrop.Visible = false
		if heartbeatConn then
			heartbeatConn:Disconnect()
			heartbeatConn = nil
		end
		if outsideClickConn then
			outsideClickConn:Disconnect()
			outsideClickConn = nil
		end
	end

	local function openPanel()
		backdrop.Visible = true
		refresh()
		-- Keeps the panel live (equip highlight, new/removed tools, Coins) only while actually open.
		if not heartbeatConn then
			heartbeatConn = RunService.Heartbeat:Connect(refresh)
		end
		-- Explicit screen-bounds check instead of click passthrough -- only actually closes on a
		-- real click/tap outside both the panel and the toggle button (clicking the toggle again
		-- while open would otherwise instantly close-then-reopen).
		if not outsideClickConn then
			outsideClickConn = UserInputService.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.Touch then
					return
				end
				local pos = input.Position
				if not pointInside(panel, pos) and not pointInside(button, pos) then
					closePanel()
				end
			end)
		end
	end

	button.MouseButton1Click:Connect(openPanel)
	closeButton.MouseButton1Click:Connect(closePanel)
end

return InventoryUI
