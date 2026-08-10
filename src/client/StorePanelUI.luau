local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local NPCDialogueUI = require(script.Parent.NPCDialogueUI)
local PanelMotion = require(script.Parent.PanelMotion)
local PerkConfig = require(ReplicatedStorage.Shared.PerkConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.UpgradeConfig)

-- The actual shop window Ruisu's "Yes" opens (see StoreDialogueUI.luau). Shows every upgrade/perk
-- from the real catalogs (UpgradeConfig.luau/PerkConfig.luau -- the same tables PlayerUpgrades.luau
-- already reads server-side, so there's nothing to keep in sync by hand) with its price and
-- whether the player currently owns it, plus a placeholder Cosmetics section. Unowned rows are
-- clickable: buying hands off to Ruisu's own dialogue box (NPCDialogueUI) for a "Buy X for Y
-- Coins?" confirm, invokes the server-authoritative PurchaseSystem, then Ruisu thanks you (or says
-- why it failed) and the shop reopens with the row updated.
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
-- a plain Frame, nothing to click.
local function buildItemRow(parent, layoutOrder, name, description, price, isOwned, onBuy)
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
	local cosmeticsRows = buildSection(scroll, 3, "Cosmetics")

	local cosmeticsPlaceholder = Instance.new("TextLabel")
	cosmeticsPlaceholder.Name = "Placeholder"
	cosmeticsPlaceholder.BackgroundTransparency = 1
	cosmeticsPlaceholder.Size = UDim2.new(1, 0, 0, 30)
	cosmeticsPlaceholder.Font = Enum.Font.FredokaOne
	cosmeticsPlaceholder.Text = "No skins for sale yet -- check back soon!"
	cosmeticsPlaceholder.TextSize = 14
	cosmeticsPlaceholder.TextXAlignment = Enum.TextXAlignment.Left
	cosmeticsPlaceholder.TextColor3 = DESCRIPTION_COLOR
	cosmeticsPlaceholder.ZIndex = 12
	cosmeticsPlaceholder.Parent = cosmeticsRows

	screenGui.Parent = playerGui
	return backdrop, panel, closeButton, coinsLabel, upgradesRows, perksRows
end

function StorePanelUI.Start()
	local player = Players.LocalPlayer
	local backdrop, panel, closeButton, coinsLabel, upgradesRows, perksRows = buildUI()
	local motion = PanelMotion.new(panel, backdrop)

	local remotes = ReplicatedStorage.Shared:WaitForChild("Remotes")
	local purchaseItemFunction = remotes:WaitForChild("PurchaseItem")

	local leaderstats = player:WaitForChild("leaderstats")
	local coins = leaderstats:WaitForChild("Coins")

	-- Forward-declared: refresh()'s row callbacks close over this before it's actually assigned
	-- below, but refresh() itself is never CALLED until well after that assignment happens.
	local attemptPurchase

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
			buildItemRow(perksRows, i, perk.Name, perk.Description, perk.Price, isOwned, function()
				attemptPurchase("Perk", id, perk)
			end)
		end
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
