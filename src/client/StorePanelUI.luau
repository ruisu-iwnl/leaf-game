local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local BlowerConfig = require(ReplicatedStorage.Shared.BlowerConfig)
local CosmeticConfig = require(ReplicatedStorage.Shared.CosmeticConfig)
local ItemPreviewUI = require(script.Parent.ItemPreviewUI)
local NPCDialogueUI = require(script.Parent.NPCDialogueUI)
local PanelMotion = require(script.Parent.PanelMotion)
local PerkConfig = require(ReplicatedStorage.Shared.PerkConfig)
local RakeConfig = require(ReplicatedStorage.Shared.RakeConfig)
local SackConfig = require(ReplicatedStorage.Shared.SackConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.UpgradeConfig)

local TOOL_CONFIGS = { LeafBlower = BlowerConfig, LeafRake = RakeConfig, LeafSack = SackConfig }

-- The actual shop window Ruisu's "Yes" opens (see StoreDialogueUI.luau). Shows every upgrade/perk/
-- cosmetic from the real catalogs (UpgradeConfig.luau/PerkConfig.luau/CosmeticConfig.luau -- the
-- same tables PlayerUpgrades.luau already reads server-side, so there's nothing to keep in sync by
-- hand) with its price and whether the player currently owns it. Unowned rows are clickable: buying
-- hands off to Ruisu's own dialogue box (NPCDialogueUI) for a "Buy X for Y Coins?" confirm, invokes
-- the server-authoritative PurchaseSystem, then Ruisu thanks you (or says why it failed) and the
-- shop reopens with the row updated. Cosmetics are tri-state instead of just owned/unowned -- owned-
-- but-not-worn rows offer an instant "Equip" (no confirm dialogue needed, nothing is spent) rather
-- than reusing the buy-confirm flow, since equipping something you already paid for isn't a purchase.
-- Unowned cosmetics skip the text-only buy confirm entirely -- clicking one opens ItemPreviewUI (a
-- rotating 3D ViewportFrame model of the actual item, built by the shared ItemPreviewBuilder) with
-- Buy/Cancel; Buy performs the purchase and Ruisu still delivers the thank-you/failure message
-- afterward, same as Upgrades/Perks. A perk can also be Currency = "Robux" (see PerkConfig.luau) --
-- those skip PurchaseSystem/Coins entirely and go straight to Roblox's own native Game Pass
-- purchase prompt instead, granted server-side by GamePassPerks.luau once Roblox confirms it.
--
-- Same autumn-toned modal look as Settings/Inventory (dark brown, tan stroke, FredokaOne), same
-- PanelMotion open/close + button-press animations as everything else.
local StorePanelUI = {}

local PANEL_COLOR = Color3.fromRGB(58, 34, 20)
local PANEL_TRANSPARENCY = 0.05
local STROKE_COLOR = Color3.fromRGB(210, 150, 80)
local ACCENT_COLOR = Color3.fromRGB(255, 205, 60)
local SECTION_LABEL_COLOR = Color3.fromRGB(220, 195, 160)
local ROW_COLOR = Color3.fromRGB(90, 58, 36)
local ROW_STROKE = Color3.fromRGB(210, 150, 80)
local OWNED_COLOR = Color3.fromRGB(120, 200, 130)
local DESCRIPTION_COLOR = Color3.fromRGB(225, 205, 180)
local BADGE_OUTLINE = Color3.fromRGB(255, 238, 210)
local ROBUX_COLOR = Color3.fromRGB(90, 200, 110)

-- A big chunk of the screen on desktop (clamped at PANEL_MAX_SIZE so it doesn't get silly on a
-- huge monitor), shrinking proportionally on smaller windows/mobile down to PANEL_MIN_SIZE. The
-- header's fixed-width elements (title/coins/close, below) are sized to still fit side-by-side
-- without overlapping even at that floor.
local PANEL_WIDTH_SCALE = 0.6
local PANEL_HEIGHT_SCALE = 0.82
local PANEL_MIN_SIZE = Vector2.new(300, 380)
local PANEL_MAX_SIZE = Vector2.new(780, 820)
local PANEL_PADDING = 14
local HEADER_HEIGHT = 30
local ROW_HEIGHT = 64

local function formatAmount(amount)
	local text = tostring(math.floor(amount))
	return text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

local function buildCoinIcon(parent, size)
	local icon = Instance.new("Frame")
	icon.Name = "CoinIcon"
	icon.Size = UDim2.new(0, size, 0, size)
	icon.BackgroundColor3 = ACCENT_COLOR
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

	return icon
end

-- Roblox's own Robux/currency glyph isn't something this project builds from plain Frames the way
-- everything else is (it's a specific official symbol, not a simple shape) -- a green "R$" badge
-- reads as "this costs real money" at a glance without needing an image asset, same spirit as every
-- other icon in this game.
local function buildRobuxBadge(parent, size)
	local badge = Instance.new("Frame")
	badge.Name = "RobuxBadge"
	badge.Size = UDim2.new(0, size, 0, size)
	badge.BackgroundColor3 = ROBUX_COLOR
	badge.BorderSizePixel = 0
	badge.ZIndex = 13
	badge.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = badge

	local stroke = Instance.new("UIStroke")
	stroke.Color = BADGE_OUTLINE
	stroke.Transparency = 0.15
	stroke.Thickness = 2
	stroke.Parent = badge

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = "R$"
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.ZIndex = 14
	label.Parent = badge

	local labelPadding = Instance.new("UIPadding")
	labelPadding.PaddingTop = UDim.new(0, 3)
	labelPadding.PaddingBottom = UDim.new(0, 3)
	labelPadding.Parent = label

	return badge
end

local function buildSectionLabel(parent, layoutOrder, text)
	local label = Instance.new("TextLabel")
	label.Name = "SectionLabel"
	label.LayoutOrder = layoutOrder
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 16)
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = SECTION_LABEL_COLOR
	label.ZIndex = 12
	label.Parent = parent
end

-- One row per catalog entry -- name + description on the left, price (or an Owned badge) on the
-- right. `isOwned` is read fresh each call from the real PlayerUpgrades attribute, so this always
-- reflects the truth. Unowned rows are a real TextButton (the whole row is the click target, not
-- just the price -- bigger, more forgiving, especially on mobile) wired to `onBuy`; owned rows are
-- a plain Frame, nothing to click. `currency` defaults to "Coins" (numeric price + coin icon);
-- "Robux" shows a green R$ badge instead -- `price` is ignored in that case, since a Game Pass's
-- real price lives entirely on Roblox's website, not in this game's own data (see PerkConfig.luau).
local function buildItemRow(parent, layoutOrder, name, description, price, isOwned, onBuy, currency)
	local row = Instance.new(isOwned and "Frame" or "TextButton")
	row.Name = "Row" .. layoutOrder
	row.LayoutOrder = layoutOrder
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3 = ROW_COLOR
	row.BorderSizePixel = 0
	row.ZIndex = 12
	if not isOwned then
		row.AutoButtonColor = false
		row.Text = ""
	end
	row.Parent = parent

	if not isOwned and onBuy then
		row.MouseButton1Click:Connect(onBuy)
		PanelMotion.AnimateButton(row)
	end

	-- Backed off from a full Scale-1 pill (which pushes both ends into an exact semicircle -- the
	-- single tightest curvature Roblox's stroke renderer can draw) to a generous but non-maximal
	-- fixed radius. The full-pill version still showed an artifact concentrated exactly at the
	-- leftmost/rightmost points -- the single point of maximum curvature -- so this steps back from
	-- that degenerate case rather than pushing further into it.
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = row

	local stroke = Instance.new("UIStroke")
	stroke.Color = ROW_STROKE
	stroke.Transparency = isOwned and 0.1 or 0.45
	stroke.Thickness = isOwned and 2 or 1.5
	stroke.Parent = row

	local rightWidth = 88

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.new(0, 14, 0, 8)
	nameLabel.Size = UDim2.new(1, -14 - rightWidth - 10, 0, 20)
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.Text = name
	nameLabel.TextSize = 17
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.ZIndex = 13
	nameLabel.Parent = row

	local descriptionLabel = Instance.new("TextLabel")
	descriptionLabel.Name = "Description"
	descriptionLabel.BackgroundTransparency = 1
	descriptionLabel.Position = UDim2.new(0, 14, 0, 30)
	descriptionLabel.Size = UDim2.new(1, -14 - rightWidth - 10, 0, 26)
	descriptionLabel.Font = Enum.Font.FredokaOne
	descriptionLabel.Text = description
	descriptionLabel.TextSize = 13
	descriptionLabel.TextWrapped = true
	descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
	descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top
	descriptionLabel.TextColor3 = DESCRIPTION_COLOR
	descriptionLabel.ZIndex = 13
	descriptionLabel.Parent = row

	if isOwned then
		local ownedLabel = Instance.new("TextLabel")
		ownedLabel.Name = "Owned"
		ownedLabel.AnchorPoint = Vector2.new(1, 0.5)
		ownedLabel.Position = UDim2.new(1, -14, 0.5, 0)
		ownedLabel.Size = UDim2.new(0, rightWidth, 0, 24)
		ownedLabel.BackgroundTransparency = 1
		ownedLabel.Font = Enum.Font.FredokaOne
		ownedLabel.Text = "Owned"
		ownedLabel.TextSize = 15
		ownedLabel.TextXAlignment = Enum.TextXAlignment.Right
		ownedLabel.TextColor3 = OWNED_COLOR
		ownedLabel.ZIndex = 13
		ownedLabel.Parent = row
	else
		local priceHolder = Instance.new("Frame")
		priceHolder.Name = "Price"
		priceHolder.AnchorPoint = Vector2.new(1, 0.5)
		priceHolder.Position = UDim2.new(1, -14, 0.5, 0)
		priceHolder.Size = UDim2.new(0, rightWidth, 0, 24)
		priceHolder.BackgroundTransparency = 1
		priceHolder.ZIndex = 13
		priceHolder.Parent = row

		local priceLayout = Instance.new("UIListLayout")
		priceLayout.FillDirection = Enum.FillDirection.Horizontal
		priceLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		priceLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		priceLayout.Padding = UDim.new(0, 6)
		priceLayout.Parent = priceHolder

		if currency == "Robux" then
			local robuxHolder = Instance.new("Frame")
			robuxHolder.Name = "RobuxIconHolder"
			robuxHolder.LayoutOrder = 1
			robuxHolder.Size = UDim2.new(0, 20, 0, 20)
			robuxHolder.BackgroundTransparency = 1
			robuxHolder.ZIndex = 13
			robuxHolder.Parent = priceHolder
			buildRobuxBadge(robuxHolder, 20)

			local buyLabel = Instance.new("TextLabel")
			buyLabel.Name = "Amount"
			buyLabel.LayoutOrder = 2
			buyLabel.Size = UDim2.new(0, 0, 1, 0)
			buyLabel.AutomaticSize = Enum.AutomaticSize.X
			buyLabel.BackgroundTransparency = 1
			buyLabel.Font = Enum.Font.FredokaOne
			buyLabel.Text = "Buy"
			buyLabel.TextSize = 16
			buyLabel.TextColor3 = Color3.new(1, 1, 1)
			buyLabel.ZIndex = 13
			buyLabel.Parent = priceHolder
		else
			local coinHolder = Instance.new("Frame")
			coinHolder.Name = "CoinIconHolder"
			coinHolder.LayoutOrder = 1
			coinHolder.Size = UDim2.new(0, 20, 0, 20)
			coinHolder.BackgroundTransparency = 1
			coinHolder.ZIndex = 13
			coinHolder.Parent = priceHolder
			buildCoinIcon(coinHolder, 20)

			local priceLabel = Instance.new("TextLabel")
			priceLabel.Name = "Amount"
			priceLabel.LayoutOrder = 2
			priceLabel.Size = UDim2.new(0, 0, 1, 0)
			priceLabel.AutomaticSize = Enum.AutomaticSize.X
			priceLabel.BackgroundTransparency = 1
			priceLabel.Font = Enum.Font.FredokaOne
			priceLabel.Text = formatAmount(price)
			priceLabel.TextSize = 16
			priceLabel.TextColor3 = Color3.new(1, 1, 1)
			priceLabel.ZIndex = 13
			priceLabel.Parent = priceHolder
		end
	end

	return row
end

-- Same visual shape as buildItemRow, but tri-state instead of owned/unowned: "unowned" shows a
-- price (clicking buys it), "owned" shows an "Equip" prompt (clicking equips it, no confirm/spend
-- involved), "equipped" shows a non-clickable "Equipped" badge -- the one state that's currently
-- active for that tool can't itself be clicked away, only replaced by picking a different row.
local function buildCosmeticRow(parent, layoutOrder, name, description, price, state, onClick)
	local clickable = state ~= "equipped"
	local row = Instance.new(clickable and "TextButton" or "Frame")
	row.Name = "Row" .. layoutOrder
	row.LayoutOrder = layoutOrder
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3 = ROW_COLOR
	row.BorderSizePixel = 0
	row.ZIndex = 12
	if clickable then
		row.AutoButtonColor = false
		row.Text = ""
	end
	row.Parent = parent

	if clickable and onClick then
		row.MouseButton1Click:Connect(onClick)
		PanelMotion.AnimateButton(row)
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = row

	local stroke = Instance.new("UIStroke")
	stroke.Color = ROW_STROKE
	stroke.Transparency = state == "equipped" and 0.1 or 0.45
	stroke.Thickness = state == "equipped" and 2 or 1.5
	stroke.Parent = row

	local rightWidth = 88

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.new(0, 14, 0, 8)
	nameLabel.Size = UDim2.new(1, -14 - rightWidth - 10, 0, 20)
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.Text = name
	nameLabel.TextSize = 17
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.ZIndex = 13
	nameLabel.Parent = row

	local descriptionLabel = Instance.new("TextLabel")
	descriptionLabel.Name = "Description"
	descriptionLabel.BackgroundTransparency = 1
	descriptionLabel.Position = UDim2.new(0, 14, 0, 30)
	descriptionLabel.Size = UDim2.new(1, -14 - rightWidth - 10, 0, 26)
	descriptionLabel.Font = Enum.Font.FredokaOne
	descriptionLabel.Text = description
	descriptionLabel.TextSize = 13
	descriptionLabel.TextWrapped = true
	descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
	descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top
	descriptionLabel.TextColor3 = DESCRIPTION_COLOR
	descriptionLabel.ZIndex = 13
	descriptionLabel.Parent = row

	if state == "equipped" then
		local equippedLabel = Instance.new("TextLabel")
		equippedLabel.Name = "Equipped"
		equippedLabel.AnchorPoint = Vector2.new(1, 0.5)
		equippedLabel.Position = UDim2.new(1, -14, 0.5, 0)
		equippedLabel.Size = UDim2.new(0, rightWidth, 0, 24)
		equippedLabel.BackgroundTransparency = 1
		equippedLabel.Font = Enum.Font.FredokaOne
		equippedLabel.Text = "Equipped"
		equippedLabel.TextSize = 14
		equippedLabel.TextXAlignment = Enum.TextXAlignment.Right
		equippedLabel.TextColor3 = OWNED_COLOR
		equippedLabel.ZIndex = 13
		equippedLabel.Parent = row
	elseif state == "owned" then
		local equipLabel = Instance.new("TextLabel")
		equipLabel.Name = "EquipPrompt"
		equipLabel.AnchorPoint = Vector2.new(1, 0.5)
		equipLabel.Position = UDim2.new(1, -14, 0.5, 0)
		equipLabel.Size = UDim2.new(0, rightWidth, 0, 24)
		equipLabel.BackgroundTransparency = 1
		equipLabel.Font = Enum.Font.FredokaOne
		equipLabel.Text = "Equip"
		equipLabel.TextSize = 15
		equipLabel.TextXAlignment = Enum.TextXAlignment.Right
		equipLabel.TextColor3 = ACCENT_COLOR
		equipLabel.ZIndex = 13
		equipLabel.Parent = row
	else
		local priceHolder = Instance.new("Frame")
		priceHolder.Name = "Price"
		priceHolder.AnchorPoint = Vector2.new(1, 0.5)
		priceHolder.Position = UDim2.new(1, -14, 0.5, 0)
		priceHolder.Size = UDim2.new(0, rightWidth, 0, 24)
		priceHolder.BackgroundTransparency = 1
		priceHolder.ZIndex = 13
		priceHolder.Parent = row

		local priceLayout = Instance.new("UIListLayout")
		priceLayout.FillDirection = Enum.FillDirection.Horizontal
		priceLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		priceLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		priceLayout.Padding = UDim.new(0, 6)
		priceLayout.Parent = priceHolder

		local coinHolder = Instance.new("Frame")
		coinHolder.Name = "CoinIconHolder"
		coinHolder.LayoutOrder = 1
		coinHolder.Size = UDim2.new(0, 20, 0, 20)
		coinHolder.BackgroundTransparency = 1
		coinHolder.ZIndex = 13
		coinHolder.Parent = priceHolder
		buildCoinIcon(coinHolder, 20)

		local priceLabel = Instance.new("TextLabel")
		priceLabel.Name = "Amount"
		priceLabel.LayoutOrder = 2
		priceLabel.Size = UDim2.new(0, 0, 1, 0)
		priceLabel.AutomaticSize = Enum.AutomaticSize.X
		priceLabel.BackgroundTransparency = 1
		priceLabel.Font = Enum.Font.FredokaOne
		priceLabel.Text = formatAmount(price)
		priceLabel.TextSize = 16
		priceLabel.TextColor3 = Color3.new(1, 1, 1)
		priceLabel.ZIndex = 13
		priceLabel.Parent = priceHolder
	end

	return row
end

local function buildSection(parent, layoutOrder, title)
	local container = Instance.new("Frame")
	container.Name = title .. "Section"
	container.LayoutOrder = layoutOrder
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, 0, 0, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.ZIndex = 12
	container.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = container

	buildSectionLabel(container, 1, title)

	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.LayoutOrder = 2
	rows.BackgroundTransparency = 1
	rows.Size = UDim2.new(1, 0, 0, 0)
	rows.AutomaticSize = Enum.AutomaticSize.Y
	rows.ZIndex = 12
	rows.Parent = container

	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.FillDirection = Enum.FillDirection.Vertical
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowsLayout.Padding = UDim.new(0, 8)
	rowsLayout.Parent = rows

	return rows
end

local function buildUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "StorePanelUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

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
	-- Scale-based (a fraction of the actual screen), not a fixed pixel size, so this genuinely
	-- fills more of a desktop window -- clamped by the UISizeConstraint below so it doesn't become
	-- absurd on an ultrawide/4K display, and doesn't shrink below a floor that's still comfortably
	-- readable on a smaller/mobile screen.
	panel.Size = UDim2.new(PANEL_WIDTH_SCALE, 0, PANEL_HEIGHT_SCALE, 0)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = PANEL_TRANSPARENCY
	panel.BorderSizePixel = 0
	panel.ZIndex = 11
	panel.Parent = backdrop

	local panelSizeConstraint = Instance.new("UISizeConstraint")
	panelSizeConstraint.MinSize = PANEL_MIN_SIZE
	panelSizeConstraint.MaxSize = PANEL_MAX_SIZE
	panelSizeConstraint.Parent = panel

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
	title.Size = UDim2.new(0, 136, 0, HEADER_HEIGHT)
	title.Font = Enum.Font.FredokaOne
	title.Text = "Ruisu's Shop"
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

	-- Coins readout, same row as the title, ending just before the close button -- same layout as
	-- InventoryUI's own Coins row.
	local coinsHolder = Instance.new("Frame")
	coinsHolder.Name = "Coins"
	coinsHolder.AnchorPoint = Vector2.new(1, 0)
	coinsHolder.Position = UDim2.new(1, -44, 0, PANEL_PADDING)
	coinsHolder.Size = UDim2.new(0, 100, 0, HEADER_HEIGHT)
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
	buildCoinIcon(coinIconHolder, 26)

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

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.Position = UDim2.new(0, PANEL_PADDING, 0, PANEL_PADDING + HEADER_HEIGHT + 12)
	scroll.Size = UDim2.new(1, -PANEL_PADDING * 2, 1, -(PANEL_PADDING * 2 + HEADER_HEIGHT + 12))
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = STROKE_COLOR
	-- Roblox's scrollbar overlays the last few pixels of content by default -- with the Cosmetics
	-- sections added, this panel now scrolls far enough that the scrollbar sits directly on top of
	-- (and visually clips) the rightmost rows' UIStroke outline. Reserving real layout space for it
	-- instead of overlaying keeps every row's outline fully visible regardless of scroll position.
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ZIndex = 12
	scroll.Parent = panel

	-- ScrollingFrame clips its content by default, and the rows fill 100% of its width with no
	-- inset of their own -- so their left/right edges sat exactly on that clip boundary. UIStroke
	-- draws HALF its thickness outside the frame's own edge (default Border mode), so that outer
	-- half was getting clipped off right at the boundary -- the actual cause of the cut-off
	-- outline. A few pixels of breathing room here is enough for the stroke to fully render.
	local scrollPadding = Instance.new("UIPadding")
	scrollPadding.PaddingLeft = UDim.new(0, 4)
	scrollPadding.PaddingRight = UDim.new(0, 4)
	scrollPadding.PaddingTop = UDim.new(0, 4)
	scrollPadding.PaddingBottom = UDim.new(0, 4)
	scrollPadding.Parent = scroll

	local scrollLayout = Instance.new("UIListLayout")
	scrollLayout.FillDirection = Enum.FillDirection.Vertical
	scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
	scrollLayout.Padding = UDim.new(0, 16)
	scrollLayout.Parent = scroll

	local upgradesRows = buildSection(scroll, 1, "Upgrades")
	local perksRows = buildSection(scroll, 2, "Perks")
	local blowerSkinRows = buildSection(scroll, 3, "Blower Skins")
	local rakeSkinRows = buildSection(scroll, 4, "Rake Skins")
	local sackSkinRows = buildSection(scroll, 5, "Sack Skins")

	screenGui.Parent = playerGui
	return backdrop, panel, closeButton, coinsLabel, upgradesRows, perksRows,
		blowerSkinRows, rakeSkinRows, sackSkinRows
end

function StorePanelUI.Start()
	local player = Players.LocalPlayer
	local backdrop, panel, closeButton, coinsLabel, upgradesRows, perksRows,
		blowerSkinRows, rakeSkinRows, sackSkinRows = buildUI()
	local motion = PanelMotion.new(panel, backdrop)

	local remotes = ReplicatedStorage.Shared:WaitForChild("Remotes")
	local purchaseItemFunction = remotes:WaitForChild("PurchaseItem")
	local equipCosmeticFunction = remotes:WaitForChild("EquipCosmetic")

	local leaderstats = player:WaitForChild("leaderstats")
	local coins = leaderstats:WaitForChild("Coins")

	-- Forward-declared: refresh()'s row callbacks close over these before they're actually assigned
	-- below, but refresh() itself is never CALLED until well after those assignments happen.
	local attemptPurchase
	local attemptEquip
	local previewCosmetic
	local promptRobuxPurchase

	-- Sorted once at Start() (catalogs don't change at runtime) so row order stays stable across
	-- refreshes instead of shuffling with Lua's unspecified pairs() order.
	local upgradeIds = {}
	for id in pairs(UpgradeConfig) do
		table.insert(upgradeIds, id)
	end
	table.sort(upgradeIds)

	local perkIds = {}
	for id in pairs(PerkConfig) do
		table.insert(perkIds, id)
	end
	table.sort(perkIds)

	local cosmeticIdsByTool = { LeafBlower = {}, LeafRake = {}, LeafSack = {} }
	for id, cosmetic in pairs(CosmeticConfig) do
		table.insert(cosmeticIdsByTool[cosmetic.Tool], id)
	end
	for _, ids in pairs(cosmeticIdsByTool) do
		table.sort(ids)
	end

	-- Rebuilds one tool's skin section: a "Default" row (always available, free) followed by every
	-- purchasable skin for that tool -- exactly one row ends up "equipped" at a time, matching
	-- whichever cosmetic id PlayerUpgrades currently has set for this tool (read directly off the
	-- Player's own replicated Attributes, same as Upgrade_*/Perk_* above -- no server module needed
	-- client-side for this).
	local function refreshCosmeticSection(rows, toolName)
		for _, child in ipairs(rows:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		local equippedId = player:GetAttribute("Cosmetic_" .. toolName) or "Default"

		buildCosmeticRow(rows, 1, "Default", "The original look.", 0,
			equippedId == "Default" and "equipped" or "owned", function()
				attemptEquip(toolName, "Default")
			end)

		for i, id in ipairs(cosmeticIdsByTool[toolName]) do
			local cosmetic = CosmeticConfig[id]
			local owned = player:GetAttribute("CosmeticOwned_" .. id) == true
			local state = equippedId == id and "equipped" or (owned and "owned" or "unowned")
			buildCosmeticRow(rows, i + 1, cosmetic.Name, cosmetic.Description, cosmetic.Price, state, function()
				if state == "unowned" then
					previewCosmetic(toolName, id, cosmetic)
				else
					attemptEquip(toolName, id)
				end
			end)
		end
	end

	local function refresh()
		coinsLabel.Text = formatAmount(coins.Value)

		-- GuiObject, not Frame -- unowned rows are TextButtons now (clickable), which aren't a
		-- Frame subclass; GuiObject is the common ancestor of both while still excluding the
		-- UIListLayout instance that also lives in this same container.
		for _, child in ipairs(upgradesRows:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for i, id in ipairs(upgradeIds) do
			local upgrade = UpgradeConfig[id]
			local isOwned = player:GetAttribute("Upgrade_" .. id) == true
			buildItemRow(upgradesRows, i, upgrade.Name, upgrade.Description, upgrade.Price, isOwned, function()
				attemptPurchase("Upgrade", id, upgrade)
			end)
		end

		for _, child in ipairs(perksRows:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for i, id in ipairs(perkIds) do
			local perk = PerkConfig[id]
			local isOwned = player:GetAttribute("Perk_" .. id) == true
			local onBuy
			if perk.Currency == "Robux" then
				onBuy = function()
					promptRobuxPurchase(perk)
				end
			else
				onBuy = function()
					attemptPurchase("Perk", id, perk)
				end
			end
			buildItemRow(perksRows, i, perk.Name, perk.Description, perk.Price, isOwned, onBuy, perk.Currency)
		end

		refreshCosmeticSection(blowerSkinRows, "LeafBlower")
		refreshCosmeticSection(rakeSkinRows, "LeafRake")
		refreshCosmeticSection(sackSkinRows, "LeafSack")
	end

	-- Kept live even while closed (cheap, a single Changed connection) so the balance is never
	-- stale the moment the panel opens -- unlike ownership, which only needs refreshing on open
	-- since nothing changes it while browsing yet.
	coins.Changed:Connect(function()
		coinsLabel.Text = formatAmount(coins.Value)
	end)

	local outsideClickConn = nil

	local function pointInside(guiObject, screenPos)
		local topLeft = guiObject.AbsolutePosition
		local size = guiObject.AbsoluteSize
		return screenPos.X >= topLeft.X and screenPos.X <= topLeft.X + size.X
			and screenPos.Y >= topLeft.Y and screenPos.Y <= topLeft.Y + size.Y
	end

	local function closePanel()
		motion.Hide()
		if outsideClickConn then
			outsideClickConn:Disconnect()
			outsideClickConn = nil
		end
	end

	-- Hands off to Ruisu's own dialogue box for the confirm/result -- reads as Ruisu actually
	-- talking to you about the purchase, not a separate generic "are you sure?" popup. The shop
	-- panel closes while that's happening and reopens once it's done (refreshed, so a successful
	-- purchase's row immediately shows "Owned").
	attemptPurchase = function(itemType, itemId, item)
		closePanel()
		NPCDialogueUI.Show({
			rigName = "Ruisu",
			displayName = "Ruisu",
			question = string.format("Buy %s for %d Coins?", item.Name, item.Price),
			choices = {
				{
					text = "No",
					onClick = function()
						NPCDialogueUI.Close()
						StorePanelUI.Open()
					end,
				},
				{
					text = "Yes",
					accent = true,
					onClick = function()
						local result = purchaseItemFunction:InvokeServer(itemType, itemId)
						if result and result.success then
							NPCDialogueUI.SayAndClose("Thank you for your purchase!", 1.5)
						else
							NPCDialogueUI.SayAndClose((result and result.reason) or "Something went wrong -- try again.", 1.5)
						end
						task.delay(1.5, function()
							StorePanelUI.Open()
						end)
					end,
				},
			},
		})
	end

	-- Shows a single Ruisu line with no choices, auto-closing after `duration` -- same shape as
	-- NPCDialogueUI.SayAndClose, but usable when the dialogue box isn't already open (unlike
	-- SayAndClose, which only changes the text/closes a box some earlier Show already opened).
	local function showRuisuMessage(text, duration)
		NPCDialogueUI.Show({
			rigName = "Ruisu",
			displayName = "Ruisu",
			question = text,
			choices = {},
		})
		task.delay(duration, function()
			NPCDialogueUI.Close()
			StorePanelUI.Open()
		end)
	end

	-- Unowned cosmetics open a 3D preview instead of a text-only buy confirm -- Buy performs the
	-- purchase directly (no separate "Buy X for Y Coins?" step, the preview panel's price/Buy/Cancel
	-- already covers that) and Ruisu still delivers the thank-you/failure message afterward, same as
	-- Upgrades/Perks.
	previewCosmetic = function(toolName, id, cosmetic)
		closePanel()
		local toolConfig = TOOL_CONFIGS[toolName]
		local colors = toolConfig and toolConfig.Cosmetics[id]
		ItemPreviewUI.Show({
			toolName = toolName,
			colors = colors,
			name = cosmetic.Name,
			description = cosmetic.Description,
			price = cosmetic.Price,
			onCancel = function()
				StorePanelUI.Open()
			end,
			onBuy = function()
				local result = purchaseItemFunction:InvokeServer("Cosmetic", id)
				if result and result.success then
					showRuisuMessage("Thank you for your purchase!", 1.5)
				else
					showRuisuMessage((result and result.reason) or "Something went wrong -- try again.", 1.5)
				end
			end,
		})
	end

	-- Equipping isn't a purchase -- nothing's spent, no confirm dialogue needed -- just an instant
	-- server-validated swap (see PurchaseSystem.EquipCosmetic) followed by re-rendering the row
	-- states in place so the new "Equipped" badge shows up immediately.
	attemptEquip = function(toolName, cosmeticId)
		local result = equipCosmeticFunction:InvokeServer(toolName, cosmeticId)
		if not (result and result.success) then
			warn(string.format(
				"[StorePanelUI] couldn't equip %s: %s",
				cosmeticId, (result and result.reason) or "unknown error"
			))
		end
		refresh()
	end

	-- Robux-currency perks skip PurchaseSystem entirely -- straight to Roblox's own native purchase
	-- prompt, which IS the confirm dialogue (it shows the real price and its own Buy/Cancel; nothing
	-- in this game controls or even knows that price -- see PerkConfig.luau). The actual grant
	-- happens server-side (GamePassPerks.luau) once Roblox confirms the purchase; the
	-- PromptGamePassPurchaseFinished listener below just reacts to it for the UI's sake.
	promptRobuxPurchase = function(perk)
		closePanel()
		if not perk.GamePassId or perk.GamePassId == 0 then
			showRuisuMessage("This one isn't set up yet -- check back soon!", 1.5)
			return
		end
		local ok = pcall(function()
			MarketplaceService:PromptGamePassPurchase(player, perk.GamePassId)
		end)
		if not ok then
			showRuisuMessage("Something went wrong -- try again.", 1.5)
		end
	end

	-- Fires (client-side) whenever ANY Game Pass purchase prompt this player saw finishes, not just
	-- ones opened from this store -- filtered down to Robux perks this catalog actually knows about.
	-- A successful purchase already replicated the granted Perk_<id> Attribute by the time this
	-- fires (GamePassPerks.luau grants it server-side the moment Roblox confirms it), so reopening/
	-- refreshing here just makes the row's new "Owned" state visible without needing to reopen the
	-- panel by hand.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(finishedPlayer, gamePassId, wasPurchased)
		if finishedPlayer ~= player then
			return
		end
		local matchedPerk
		for _, id in ipairs(perkIds) do
			local perk = PerkConfig[id]
			if perk.GamePassId == gamePassId then
				matchedPerk = perk
				break
			end
		end
		if not matchedPerk then
			return
		end
		if wasPurchased then
			showRuisuMessage("Thank you for your purchase!", 1.5)
		else
			StorePanelUI.Open()
		end
	end)

	function StorePanelUI.Open()
		refresh()
		motion.Show()
		if not outsideClickConn then
			outsideClickConn = UserInputService.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.Touch then
					return
				end
				if not pointInside(panel, input.Position) then
					closePanel()
				end
			end)
		end
	end

	closeButton.MouseButton1Click:Connect(closePanel)

	-- Live while open would need per-attribute listeners for every catalog entry (a lot of
	-- churn for a panel that's only ever open briefly) -- refreshing once on open is enough since
	-- nothing can actually change ownership from in here yet anyway.
end

return StorePanelUI
