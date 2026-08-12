local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local PanelMotion = require(script.Parent.PanelMotion)
local ToolIcons = require(script.Parent.ToolIcons)
local UILayout = require(script.Parent.UILayout)

-- The tutorial content Ruisu-the-guide's "Show me!" choice opens (see NPCDialogues.luau) --
-- a static, scrollable explainer covering tools, the cleanup zone, and the shop -- not tied to live
-- game state the way StorePanelUI is, so this never needs to refresh/rebuild its content on open.
--
-- Laid out as one card per topic (icon on the left, short heading + one-line body on the right)
-- instead of a single wall of paragraphs -- reuses ToolIcons.luau's Blower/Rake/Sack icon builders
-- (the exact same shapes HotbarUI/InventoryUI already use, so they're instantly recognizable) rather
-- than inventing new artwork or a map screenshot -- there's no image-upload path in this toolchain,
-- and a hand-drawn map graphic would be a lot of new surface area for a "don't over complicate" ask.
--
-- Every tool here is genuinely click/tap-to-activate, never hold -- see BlowerTool.luau/
-- RakeTool.luau's own Tool.Activated wiring (Blower toggles on/off per click, Rake fires one pull
-- per click then cools down) -- a first pass of this copy incorrectly said "hold," corrected after
-- the user flagged it.
--
-- Same cream/warm-accent card look as MapProgressUI/RoundResultsUI (CARD_COLOR/CARD_STROKE/
-- TITLE_COLOR/DESCRIPTION_COLOR) rather than the darker StorePanelUI/SettingsUI/NPCDialogueUI
-- palette -- this is closer in spirit to an info/notification surface than a transactional one.
-- Sized with the same scale + UISizeConstraint clamp pattern RoundResultsUI's panel uses (both
-- MinSize and MaxSize shrunk from a prior flat-pixel size, not just a floor added under an
-- unchanged ceiling -- see CLAUDE.md's Seventeenth follow-up note on why that matters).
local TutorialPanelUI = {}

local CARD_COLOR = Color3.fromRGB(255, 248, 235)
local CARD_STROKE = Color3.fromRGB(214, 168, 110)
local ROW_COLOR = Color3.fromRGB(248, 235, 212)
local TITLE_COLOR = Color3.fromRGB(92, 58, 28)
local DESCRIPTION_COLOR = Color3.fromRGB(120, 92, 62)
local ACCENT_COLOR = Color3.fromRGB(255, 205, 60)

local PANEL_PADDING = 20
local HEADER_HEIGHT = 30
local ICON_SLOT_SIZE = 48
local ROW_PADDING = 14

-- Small standalone icons for the two non-tool cards -- same "plain Frames, no images" approach as
-- ToolIcons.luau, just not shared there since nothing else in the game needs a cleanup-zone or
-- shop icon specifically (matches this project's established "small local copy rather than a
-- shared module for a one-off shape" convention).
local function buildZoneIcon(parent)
	local swatch = Instance.new("Frame")
	swatch.Name = "Icon"
	swatch.AnchorPoint = Vector2.new(0.5, 0.5)
	swatch.Position = UDim2.new(0.5, 0, 0.5, 0)
	swatch.Size = UDim2.new(0, 32, 0, 32)
	swatch.BackgroundColor3 = ACCENT_COLOR
	swatch.BorderSizePixel = 0
	swatch.ZIndex = 13
	swatch.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = swatch

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.4
	stroke.Thickness = 2
	stroke.Parent = swatch
end

local function buildCoinIcon(parent)
	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.new(0.5, 0, 0.5, 0)
	icon.Size = UDim2.new(0, 32, 0, 32)
	icon.BackgroundColor3 = ACCENT_COLOR
	icon.BorderSizePixel = 0
	icon.ZIndex = 13
	icon.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = icon

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(140, 95, 20)
	stroke.Thickness = 2
	stroke.Parent = icon
end

-- One entry per card -- add a new one here for future content (e.g. a new tool) rather than
-- touching the build logic below. IconBuilder(parent) draws into a fixed ICON_SLOT_SIZE square.
local SECTIONS = {
	{
		IconBuilder = ToolIcons.BuildBlowerIcon,
		Heading = "Blower",
		Body = "Click to turn the wind on and push leaves into piles. Click again to turn it off.",
	},
	{
		IconBuilder = ToolIcons.BuildRakeIcon,
		Heading = "Rake",
		Body = "Click to sweep nearby leaves toward you. Short cooldown between uses.",
	},
	{
		IconBuilder = ToolIcons.BuildSackIcon,
		Heading = "Sack",
		Body = "Click or tap a leaf to collect it. Use the sack icon (bottom-left) to pack your leaves into a carryable bag.",
	},
	{
		IconBuilder = buildZoneIcon,
		Heading = "Cleanup Zone",
		Body = "Deliver leaves to the glowing zone to earn Coins and help finish the round.",
	},
	{
		IconBuilder = buildCoinIcon,
		Heading = "The Shop",
		Body = "Visit Ruisu's shop booth in the Lobby to spend Coins on Upgrades, Perks, and Cosmetics.",
	},
}

local function buildCard(parent, layoutOrder, iconBuilder, heading, body)
	local card = Instance.new("Frame")
	card.Name = "Card" .. layoutOrder
	card.LayoutOrder = layoutOrder
	card.BackgroundColor3 = ROW_COLOR
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BorderSizePixel = 0
	card.ZIndex = 12
	card.Parent = parent

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 12)
	cardCorner.Parent = card

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = CARD_STROKE
	cardStroke.Transparency = 0.5
	cardStroke.Thickness = 1
	cardStroke.Parent = card

	local cardPadding = Instance.new("UIPadding")
	cardPadding.PaddingTop = UDim.new(0, ROW_PADDING)
	cardPadding.PaddingBottom = UDim.new(0, ROW_PADDING)
	cardPadding.PaddingLeft = UDim.new(0, ROW_PADDING)
	cardPadding.PaddingRight = UDim.new(0, ROW_PADDING)
	cardPadding.Parent = card

	local iconSlot = Instance.new("Frame")
	iconSlot.Name = "IconSlot"
	iconSlot.BackgroundTransparency = 1
	iconSlot.Size = UDim2.new(0, ICON_SLOT_SIZE, 0, ICON_SLOT_SIZE)
	iconSlot.ZIndex = 12
	iconSlot.Parent = card
	iconBuilder(iconSlot)

	local textArea = Instance.new("Frame")
	textArea.Name = "TextArea"
	textArea.Position = UDim2.new(0, ICON_SLOT_SIZE + 12, 0, 0)
	textArea.Size = UDim2.new(1, -(ICON_SLOT_SIZE + 12), 0, 0)
	textArea.AutomaticSize = Enum.AutomaticSize.Y
	textArea.BackgroundTransparency = 1
	textArea.ZIndex = 12
	textArea.Parent = card

	local headingLabel = Instance.new("TextLabel")
	headingLabel.Name = "Heading"
	headingLabel.BackgroundTransparency = 1
	headingLabel.Size = UDim2.new(1, 0, 0, 20)
	headingLabel.Font = Enum.Font.FredokaOne
	headingLabel.Text = heading
	headingLabel.TextSize = 16
	headingLabel.TextXAlignment = Enum.TextXAlignment.Left
	headingLabel.TextColor3 = TITLE_COLOR
	headingLabel.ZIndex = 13
	headingLabel.Parent = textArea

	local bodyLabel = Instance.new("TextLabel")
	bodyLabel.Name = "Body"
	bodyLabel.Position = UDim2.new(0, 0, 0, 22)
	bodyLabel.Size = UDim2.new(1, 0, 0, 0)
	bodyLabel.AutomaticSize = Enum.AutomaticSize.Y
	bodyLabel.BackgroundTransparency = 1
	bodyLabel.Font = Enum.Font.Gotham
	bodyLabel.Text = body
	bodyLabel.TextSize = 13
	bodyLabel.TextWrapped = true
	bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
	bodyLabel.TextYAlignment = Enum.TextYAlignment.Top
	bodyLabel.TextColor3 = DESCRIPTION_COLOR
	bodyLabel.ZIndex = 13
	bodyLabel.Parent = textArea

	return card
end

local function buildUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TutorialPanelUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = UILayout.DisplayOrder.Panel

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
	panel.Size = UDim2.new(0.86, 0, 0.72, 0)
	panel.BackgroundColor3 = CARD_COLOR
	panel.BorderSizePixel = 0
	panel.ZIndex = 11
	panel.Parent = backdrop

	local panelConstraint = Instance.new("UISizeConstraint")
	panelConstraint.MinSize = Vector2.new(300, 360)
	panelConstraint.MaxSize = Vector2.new(460, 520)
	panelConstraint.Parent = panel

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 18)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = CARD_STROKE
	panelStroke.Transparency = 0.2
	panelStroke.Thickness = 1.5
	panelStroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, PANEL_PADDING, 0, PANEL_PADDING)
	title.Size = UDim2.new(1, -PANEL_PADDING * 2 - 40, 0, HEADER_HEIGHT)
	title.Font = Enum.Font.FredokaOne
	title.Text = "How to Play"
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = TITLE_COLOR
	title.ZIndex = 12
	title.Parent = panel

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -12, 0, 12)
	closeButton.Size = UDim2.new(0, 32, 0, 32)
	closeButton.BackgroundColor3 = ACCENT_COLOR
	closeButton.AutoButtonColor = false
	closeButton.Font = Enum.Font.FredokaOne
	closeButton.Text = "Got it!"
	closeButton.TextSize = 12
	closeButton.TextColor3 = TITLE_COLOR
	closeButton.ZIndex = 12
	closeButton.Parent = panel
	PanelMotion.AnimateButton(closeButton)

	local closeButtonCorner = Instance.new("UICorner")
	closeButtonCorner.CornerRadius = UDim.new(0, 10)
	closeButtonCorner.Parent = closeButton

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.Position = UDim2.new(0, PANEL_PADDING, 0, PANEL_PADDING + HEADER_HEIGHT + 12)
	scroll.Size = UDim2.new(1, -PANEL_PADDING * 2, 1, -(PANEL_PADDING * 2 + HEADER_HEIGHT + 12))
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = CARD_STROKE
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ZIndex = 12
	scroll.Parent = panel

	local scrollPadding = Instance.new("UIPadding")
	scrollPadding.PaddingLeft = UDim.new(0, 4)
	scrollPadding.PaddingRight = UDim.new(0, 4)
	scrollPadding.PaddingTop = UDim.new(0, 4)
	scrollPadding.PaddingBottom = UDim.new(0, 4)
	scrollPadding.Parent = scroll

	local scrollLayout = Instance.new("UIListLayout")
	scrollLayout.FillDirection = Enum.FillDirection.Vertical
	scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
	scrollLayout.Padding = UDim.new(0, 10)
	scrollLayout.Parent = scroll

	for i, section in ipairs(SECTIONS) do
		buildCard(scroll, i, section.IconBuilder, section.Heading, section.Body)
	end

	screenGui.Parent = playerGui
	return backdrop, panel, closeButton
end

function TutorialPanelUI.Start()
	local backdrop, panel, closeButton = buildUI()
	local motion = PanelMotion.new(panel, backdrop)

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

	function TutorialPanelUI.Open()
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

	function TutorialPanelUI.Close()
		closePanel()
	end

	closeButton.MouseButton1Click:Connect(closePanel)
end

return TutorialPanelUI
