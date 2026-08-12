local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local DailyQuestConfig = require(ReplicatedStorage.Shared.DailyQuestConfig)
local DailyRotation = require(ReplicatedStorage.Shared.DailyRotation)
local NPCConfig = require(ReplicatedStorage.Shared.NPCConfig)
local PanelMotion = require(script.Parent.PanelMotion)
local QuestConfig = require(ReplicatedStorage.Shared.QuestConfig)
local UILayout = require(script.Parent.UILayout)

-- A "Quest Log" panel -- everything the player has in progress or has finished. Two columns: the
-- left is a compact clickable list split into 3 always-visible sections (Dailies, Quests,
-- Completed -- the last one pooling every finished quest of EITHER catalog, so a completed daily
-- doesn't just vanish from the log once it's done); the right is a detail view for whichever row
-- is selected (title, status, quest giver, description/hint, reward). Opened via a button sitting
-- right next to InventoryUI's own backpack button, same dark autumn palette (PANEL_COLOR/
-- STROKE_COLOR) as that panel/StorePanelUI/SettingsUI, since it's meant to read as belonging to
-- that same family of UI.
--
-- Status per quest is read straight off the player's own replicated Attributes (Quest_<id>/
-- QuestStarted_<id> for QuestConfig, set by PlayerQuests.luau; DailyProgress_<id>/
-- DailyProgressDay_<id>/DailyCompletedDay_<id> for DailyQuestConfig, set by DailyQuestSystem.luau) --
-- same "no server round-trip needed, the client already has this" pattern StorePanelUI/InventoryUI
-- already use for owned upgrades/perks/cosmetics. Rows are rebuilt fresh every time the panel opens
-- rather than kept live while closed.
local QuestLogUI = {}

local PANEL_COLOR = Color3.fromRGB(58, 34, 20)
local PANEL_TRANSPARENCY = 0.08
local STROKE_COLOR = Color3.fromRGB(210, 150, 80)
local ROW_COLOR = Color3.fromRGB(70, 44, 26)
local ROW_SELECTED_COLOR = Color3.fromRGB(96, 62, 34)
local DESCRIPTION_COLOR = Color3.fromRGB(210, 190, 170)
local PLACEHOLDER_COLOR = Color3.fromRGB(170, 148, 122)
local DETAIL_LABEL_COLOR = Color3.fromRGB(210, 150, 80)
local SECTION_HEADER_COLOR = Color3.fromRGB(220, 195, 160)

-- "▾" (expanded, click to collapse) / "▸" (collapsed, click to expand) -- same escaped-UTF8-bytes
-- convention as the ✓/• glyphs elsewhere in this panel (see showDetail's objective checklist).
local CHEVRON_EXPANDED = "\226\150\190"
local CHEVRON_COLLAPSED = "\226\150\184"

local STATUS_COLORS = {
	NotStarted = Color3.fromRGB(90, 58, 36),
	InProgress = Color3.fromRGB(214, 158, 46),
	Completed = Color3.fromRGB(90, 168, 96),
}
-- The right-side detail panel only ever needs to say "Ongoing" or "Completed" (per the ask) --
-- NotStarted and InProgress both read as "Ongoing" there, though the left-side list rows still
-- show the finer-grained label.
local DETAIL_STATUS_LABELS = {
	NotStarted = "Ongoing",
	InProgress = "Ongoing",
	Completed = "Completed",
}
local STATUS_LABELS = {
	NotStarted = "Not Started",
	InProgress = "In Progress",
	Completed = "Completed",
}

local BUTTON_SIZE = 48
local BUTTON_GAP = 10
local ROW_HEIGHT = 52
local PANEL_PADDING = 16
local HEADER_HEIGHT = 26
local COLUMN_GAP = 14
local LEFT_COLUMN_SCALE = 0.4

-- Floor was (360, 420) -- noticeably bigger than every sibling panel's own mobile floor
-- (StorePanelUI/SettingsUI/InventoryUI all sit at 300x380) and, on a short/landscape mobile screen,
-- tall enough to run past the screen edges outright. Brought down to line up with those -- 320 wide
-- is still enough for the two-column layout to stay legible (rows already TextTruncate/TextWrap
-- rather than overflow), just noticeably less oversized on a phone.
local PANEL_MIN_SIZE = Vector2.new(320, 380)
local PANEL_MAX_SIZE = Vector2.new(820, 580)

-- Was a flat UDim2.new(0.9, 0, 0.78, 0) -- on a typical phone (~375-430 logical px wide), 0.9 of
-- the SCREEN width already exceeds PANEL_MIN_SIZE's own floor above, so that floor alone couldn't
-- actually shrink anything on most real phones -- the scale itself was the dominant factor making
-- this read as oversized/near-edge-to-edge on mobile, more so than StorePanelUI's own considerably
-- narrower 0.6 width scale. Brought down closer to that.
local PANEL_WIDTH_SCALE = 0.72
local PANEL_HEIGHT_SCALE = 0.72

local function getQuestStatus(player, id)
	if player:GetAttribute("Quest_" .. id) == true then
		return "Completed"
	end
	if player:GetAttribute("QuestStarted_" .. id) == true then
		return "InProgress"
	end
	return "NotStarted"
end

-- A chain quest (QuestConfig's RequiresQuest) stays completely hidden -- not even a "locked" row --
-- until its prerequisite is actually completed, per the explicit ask not to reveal follow-up quests
-- early. Reads the SAME Quest_<id> Attribute PlayerQuests.luau/getQuestStatus already use, so this
-- can never disagree with the server's own gating in QuestSystem.StartEligibleQuests.
local function isQuestUnlocked(player, quest)
	return not quest.RequiresQuest or player:GetAttribute("Quest_" .. quest.RequiresQuest) == true
end

-- Live per-objective progress for a multi-step quest (QuestObjectives.luau, server) -- a plain
-- Attribute, same "no remote round-trip needed" pattern as everything else this panel reads.
local function getObjectiveProgress(player, questId, objective)
	return player:GetAttribute(string.format("QuestObjProgress_%s_%s", questId, objective.Id)) or 0
end

local function countCompletedObjectives(player, questId, quest)
	local completed = 0
	for _, objective in ipairs(quest.Objectives) do
		if getObjectiveProgress(player, questId, objective) >= objective.Target then
			completed += 1
		end
	end
	return completed
end

-- "3h 42m left" / "12m left" / "<1m left" -- QuestLogUI's own daily-expiry readout, no other UI
-- needs this formatting today.
local function formatTimeLeft(seconds)
	if seconds <= 0 then
		return "resets any moment"
	end
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	if hours > 0 then
		return string.format("%dh %dm left", hours, minutes)
	elseif minutes > 0 then
		return string.format("%dm left", minutes)
	end
	return "<1m left"
end

-- Dailies have no "Not Started" state worth showing -- if it's part of today's rotating 3, it's
-- already being tracked passively the moment relevant gameplay happens, no accept step. So this
-- only ever returns "Completed" or "InProgress" (0 progress still reads as "in progress," matching
-- "this is one of today's 3, go do it").
local function getDailyStatus(player, id, dayNumber)
	if player:GetAttribute("DailyCompletedDay_" .. id) == dayNumber then
		return "Completed"
	end
	return "InProgress"
end

local function getDailyProgress(player, id, dayNumber)
	if player:GetAttribute("DailyProgressDay_" .. id) ~= dayNumber then
		return 0
	end
	return player:GetAttribute("DailyProgress_" .. id) or 0
end

local function getGiverDisplayName(entry)
	if entry.type ~= "quest" then
		return nil
	end
	local giver = entry.quest.GiverNPC and NPCConfig[entry.quest.GiverNPC]
	return giver and giver.DisplayName or "Unknown"
end

-- Small scroll/checklist icon, plain Frames only (no images/custom assets, same constraint every
-- other icon in this project works under) -- a parchment rectangle with 3 short horizontal "text"
-- bars, immediately distinct from InventoryUI's backpack icon it sits right next to.
local function buildQuestLogIcon(parent)
	local scroll = Instance.new("Frame")
	scroll.Name = "Icon"
	scroll.AnchorPoint = Vector2.new(0.5, 0.5)
	scroll.Position = UDim2.new(0.5, 0, 0.5, 0)
	scroll.Size = UDim2.new(0, 22, 0, 26)
	scroll.BackgroundColor3 = Color3.fromRGB(232, 214, 178)
	scroll.BorderSizePixel = 0
	scroll.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = scroll

	local lineWidths = { 14, 14, 10 }
	local lineYs = { 0.28, 0.5, 0.72 }
	for i = 1, 3 do
		local line = Instance.new("Frame")
		line.Name = "Line" .. i
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Position = UDim2.new(0.5, 0, lineYs[i], 0)
		line.Size = UDim2.new(0, lineWidths[i], 0, 2)
		line.BackgroundColor3 = Color3.fromRGB(150, 110, 60)
		line.BorderSizePixel = 0
		line.Parent = scroll
	end
end

local function buildSectionHeader(parent, layoutOrder, title)
	local label = Instance.new("TextLabel")
	label.Name = "SectionHeader" .. layoutOrder
	label.LayoutOrder = layoutOrder
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 20)
	label.Font = Enum.Font.FredokaOne
	label.Text = title
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = SECTION_HEADER_COLOR
	label.ZIndex = 12
	label.Parent = parent
end

-- Same look as buildSectionHeader, but clickable, with a chevron that flips between
-- CHEVRON_EXPANDED/CHEVRON_COLLAPSED -- used only for "Completed," the one section that can grow
-- long over time (every finished quest, forever). Rather than any automatic "collapse it once it's
-- too long" logic, this is a plain manual toggle -- simpler, and lets the player decide. Returns the
-- title TextLabel and chevron TextLabel so the caller can update their text (title needs the live
-- count, chevron needs the current collapsed state) without rebuilding the header itself.
local function buildCollapsibleSectionHeader(parent, layoutOrder, onClick)
	local header = Instance.new("TextButton")
	header.Name = "SectionHeader" .. layoutOrder
	header.LayoutOrder = layoutOrder
	header.BackgroundTransparency = 1
	header.AutoButtonColor = false
	header.Size = UDim2.new(1, 0, 0, 20)
	header.Text = ""
	header.ZIndex = 12
	header.Parent = parent

	local chevron = Instance.new("TextLabel")
	chevron.Name = "Chevron"
	chevron.BackgroundTransparency = 1
	chevron.Size = UDim2.new(0, 14, 1, 0)
	chevron.Font = Enum.Font.FredokaOne
	chevron.Text = CHEVRON_EXPANDED
	chevron.TextSize = 11
	chevron.TextXAlignment = Enum.TextXAlignment.Left
	chevron.TextColor3 = SECTION_HEADER_COLOR
	chevron.ZIndex = 12
	chevron.Parent = header

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.new(0, 16, 0, 0)
	titleLabel.Size = UDim2.new(1, -16, 1, 0)
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.Text = ""
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextColor3 = SECTION_HEADER_COLOR
	titleLabel.ZIndex = 12
	titleLabel.Parent = header

	header.MouseButton1Click:Connect(onClick)

	return titleLabel, chevron
end

local function buildPlaceholderRow(parent, layoutOrder, text)
	local label = Instance.new("TextLabel")
	label.Name = "Placeholder" .. layoutOrder
	label.LayoutOrder = layoutOrder
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 30)
	label.Font = Enum.Font.Gotham
	label.Text = text
	label.TextSize = 12
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = PLACEHOLDER_COLOR
	label.ZIndex = 12
	label.Parent = parent
end

-- A compact, clickable left-column row -- just the name and a small status/progress line, styling
-- itself as "selected" or not via updateSelected rather than being rebuilt on every click, so the
-- list's scroll position survives clicking around inside it.
local function buildListRow(parent, layoutOrder, entry, onClick)
	local row = Instance.new("TextButton")
	row.Name = "Row" .. layoutOrder
	row.LayoutOrder = layoutOrder
	row.AutoButtonColor = false
	row.BackgroundColor3 = ROW_COLOR
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BorderSizePixel = 0
	row.Text = ""
	row.ZIndex = 12
	row.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = row

	local stroke = Instance.new("UIStroke")
	stroke.Color = STROKE_COLOR
	stroke.Transparency = 0.5
	stroke.Thickness = 1
	stroke.Parent = row

	local dot = Instance.new("Frame")
	dot.Name = "StatusDot"
	dot.AnchorPoint = Vector2.new(0, 0.5)
	dot.Position = UDim2.new(0, 10, 0.5, 0)
	dot.Size = UDim2.new(0, 8, 0, 8)
	dot.BackgroundColor3 = STATUS_COLORS[entry.status]
	dot.BorderSizePixel = 0
	dot.ZIndex = 13
	dot.Parent = row

	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.new(0, 26, 0, 6)
	nameLabel.Size = UDim2.new(1, -34, 0, 18)
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.Text = entry.quest.Name
	nameLabel.TextSize = 14
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.ZIndex = 13
	nameLabel.Parent = row

	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "Sub"
	subLabel.BackgroundTransparency = 1
	subLabel.Position = UDim2.new(0, 26, 0, 26)
	subLabel.Size = UDim2.new(1, -34, 0, 16)
	subLabel.Font = Enum.Font.Gotham
	subLabel.Text = entry.progressText or STATUS_LABELS[entry.status]
	subLabel.TextSize = 11
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.TextColor3 = PLACEHOLDER_COLOR
	subLabel.ZIndex = 13
	subLabel.Parent = row

	row.MouseButton1Click:Connect(onClick)

	local function updateSelected(isSelected)
		row.BackgroundColor3 = isSelected and ROW_SELECTED_COLOR or ROW_COLOR
		stroke.Transparency = isSelected and 0.1 or 0.5
		stroke.Thickness = isSelected and 1.5 or 1
	end

	return row, updateSelected
end

local function buildUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "QuestLogUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	-- Explicitly the highest-priority panel in the game (alongside InventoryUI) -- see
	-- UILayout.DisplayOrder's own top comment for the full tier list/reasoning. Used to default to
	-- 0, tied with SackUI/RoundUI/PlayerListUI/MapProgressUI/AFKUI's toast, which made stacking
	-- among them incidental rather than deliberate.
	screenGui.DisplayOrder = UILayout.DisplayOrder.TopPanel

	-- Sits just left of InventoryUI's own button, same row, same size -- "besides the inventory
	-- panel icon" per the ask, not folded into TopBar's separate top-right stack.
	local button = Instance.new("TextButton")
	button.Name = "QuestLogButton"
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(
		1, -UILayout.HotbarEdgeMargin - (BUTTON_SIZE + BUTTON_GAP),
		1, -(UILayout.HotbarEdgeMargin + UILayout.HotbarCardSize + 10)
	)
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

	buildQuestLogIcon(button)
	PanelMotion.AnimateButton(button)

	-- Small dot shown while at least one quest is in progress -- purely a discoverability nudge, no
	-- unread/seen-tracking beyond "is anything active right now."
	local badgeDot = Instance.new("Frame")
	badgeDot.Name = "BadgeDot"
	badgeDot.AnchorPoint = Vector2.new(1, 0)
	badgeDot.Position = UDim2.new(1, 4, 0, -4)
	badgeDot.Size = UDim2.new(0, 14, 0, 14)
	badgeDot.BackgroundColor3 = Color3.fromRGB(255, 205, 60)
	badgeDot.BorderSizePixel = 0
	badgeDot.Visible = false
	badgeDot.ZIndex = 13
	badgeDot.Parent = button

	local badgeDotCorner = Instance.new("UICorner")
	badgeDotCorner.CornerRadius = UDim.new(1, 0)
	badgeDotCorner.Parent = badgeDot

	local badgeDotStroke = Instance.new("UIStroke")
	badgeDotStroke.Color = PANEL_COLOR
	badgeDotStroke.Thickness = 2
	badgeDotStroke.Parent = badgeDot

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
	panel.Size = UDim2.new(PANEL_WIDTH_SCALE, 0, PANEL_HEIGHT_SCALE, 0)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = PANEL_TRANSPARENCY
	panel.BorderSizePixel = 0
	panel.ZIndex = 11
	panel.Parent = backdrop

	local panelConstraint = Instance.new("UISizeConstraint")
	panelConstraint.MinSize = PANEL_MIN_SIZE
	panelConstraint.MaxSize = PANEL_MAX_SIZE
	panelConstraint.Parent = panel

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 18)
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
	title.Size = UDim2.new(1, -PANEL_PADDING * 2 - 40, 0, HEADER_HEIGHT)
	title.Font = Enum.Font.FredokaOne
	title.Text = "Quest Log"
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

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.new(0, PANEL_PADDING, 0, PANEL_PADDING + HEADER_HEIGHT + 12)
	body.Size = UDim2.new(1, -PANEL_PADDING * 2, 1, -(PANEL_PADDING * 2 + HEADER_HEIGHT + 12))
	body.ZIndex = 12
	body.Parent = panel

	-- Left column: the clickable quest list.
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.Size = UDim2.new(LEFT_COLUMN_SCALE, -(COLUMN_GAP / 2), 1, 0)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = STROKE_COLOR
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ZIndex = 12
	scroll.Parent = body

	local scrollPadding = Instance.new("UIPadding")
	scrollPadding.PaddingLeft = UDim.new(0, 4)
	scrollPadding.PaddingRight = UDim.new(0, 4)
	scrollPadding.PaddingTop = UDim.new(0, 4)
	scrollPadding.PaddingBottom = UDim.new(0, 4)
	scrollPadding.Parent = scroll

	local scrollLayout = Instance.new("UIListLayout")
	scrollLayout.FillDirection = Enum.FillDirection.Vertical
	scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
	scrollLayout.Padding = UDim.new(0, 8)
	scrollLayout.Parent = scroll

	-- Vertical divider between the two columns.
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.AnchorPoint = Vector2.new(0.5, 0)
	divider.Position = UDim2.new(LEFT_COLUMN_SCALE, 0, 0, 0)
	divider.Size = UDim2.new(0, 1, 1, 0)
	divider.BackgroundColor3 = STROKE_COLOR
	divider.BackgroundTransparency = 0.5
	divider.BorderSizePixel = 0
	divider.ZIndex = 12
	divider.Parent = body

	-- Right column: the selected quest's detail view.
	local detail = Instance.new("ScrollingFrame")
	detail.Name = "Detail"
	detail.Position = UDim2.new(LEFT_COLUMN_SCALE, COLUMN_GAP / 2, 0, 0)
	detail.Size = UDim2.new(1 - LEFT_COLUMN_SCALE, -(COLUMN_GAP / 2), 1, 0)
	detail.BackgroundTransparency = 1
	detail.BorderSizePixel = 0
	detail.ScrollBarThickness = 6
	detail.ScrollBarImageColor3 = STROKE_COLOR
	detail.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	detail.CanvasSize = UDim2.new(0, 0, 0, 0)
	detail.AutomaticCanvasSize = Enum.AutomaticSize.Y
	detail.ZIndex = 12
	detail.Parent = body

	local detailPadding = Instance.new("UIPadding")
	detailPadding.PaddingLeft = UDim.new(0, 4)
	detailPadding.PaddingRight = UDim.new(0, 8)
	detailPadding.Parent = detail

	local detailLayout = Instance.new("UIListLayout")
	detailLayout.FillDirection = Enum.FillDirection.Vertical
	detailLayout.SortOrder = Enum.SortOrder.LayoutOrder
	detailLayout.Padding = UDim.new(0, 10)
	detailLayout.Parent = detail

	local placeholderLabel = Instance.new("TextLabel")
	placeholderLabel.Name = "Placeholder"
	placeholderLabel.LayoutOrder = 1
	placeholderLabel.BackgroundTransparency = 1
	placeholderLabel.Size = UDim2.new(1, 0, 0, 40)
	placeholderLabel.Font = Enum.Font.Gotham
	placeholderLabel.Text = "Select a quest on the left to view its details."
	placeholderLabel.TextWrapped = true
	placeholderLabel.TextSize = 13
	placeholderLabel.TextXAlignment = Enum.TextXAlignment.Left
	placeholderLabel.TextYAlignment = Enum.TextYAlignment.Top
	placeholderLabel.TextColor3 = PLACEHOLDER_COLOR
	placeholderLabel.ZIndex = 13
	placeholderLabel.Parent = detail

	local detailName = Instance.new("TextLabel")
	detailName.Name = "DetailName"
	detailName.LayoutOrder = 1
	detailName.BackgroundTransparency = 1
	detailName.AutomaticSize = Enum.AutomaticSize.Y
	detailName.Size = UDim2.new(1, 0, 0, 0)
	detailName.Font = Enum.Font.FredokaOne
	detailName.Text = ""
	detailName.TextWrapped = true
	detailName.TextSize = 20
	detailName.TextXAlignment = Enum.TextXAlignment.Left
	detailName.TextColor3 = Color3.new(1, 1, 1)
	detailName.ZIndex = 13
	detailName.Visible = false
	detailName.Parent = detail

	local detailStatusPill = Instance.new("Frame")
	detailStatusPill.Name = "DetailStatusPill"
	detailStatusPill.LayoutOrder = 2
	detailStatusPill.Size = UDim2.new(0, 96, 0, 24)
	detailStatusPill.BackgroundColor3 = STATUS_COLORS.NotStarted
	detailStatusPill.BorderSizePixel = 0
	detailStatusPill.ZIndex = 13
	detailStatusPill.Visible = false
	detailStatusPill.Parent = detail

	local detailStatusPillCorner = Instance.new("UICorner")
	detailStatusPillCorner.CornerRadius = UDim.new(1, 0)
	detailStatusPillCorner.Parent = detailStatusPill

	local detailStatusLabel = Instance.new("TextLabel")
	detailStatusLabel.Name = "Label"
	detailStatusLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	detailStatusLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	detailStatusLabel.Size = UDim2.new(1, -10, 1, -4)
	detailStatusLabel.BackgroundTransparency = 1
	detailStatusLabel.Font = Enum.Font.FredokaOne
	detailStatusLabel.Text = ""
	detailStatusLabel.TextScaled = true
	detailStatusLabel.TextColor3 = Color3.new(1, 1, 1)
	detailStatusLabel.TextXAlignment = Enum.TextXAlignment.Center
	detailStatusLabel.TextYAlignment = Enum.TextYAlignment.Center
	detailStatusLabel.ZIndex = 14
	detailStatusLabel.Parent = detailStatusPill

	local detailStatusConstraint = Instance.new("UITextSizeConstraint")
	detailStatusConstraint.MaxTextSize = 13
	detailStatusConstraint.Parent = detailStatusLabel

	local detailGiver = Instance.new("TextLabel")
	detailGiver.Name = "DetailGiver"
	detailGiver.LayoutOrder = 3
	detailGiver.BackgroundTransparency = 1
	detailGiver.AutomaticSize = Enum.AutomaticSize.Y
	detailGiver.Size = UDim2.new(1, 0, 0, 0)
	detailGiver.Font = Enum.Font.Gotham
	detailGiver.Text = ""
	detailGiver.TextWrapped = true
	detailGiver.TextSize = 13
	detailGiver.TextXAlignment = Enum.TextXAlignment.Left
	detailGiver.TextColor3 = DETAIL_LABEL_COLOR
	detailGiver.ZIndex = 13
	detailGiver.Visible = false
	detailGiver.Parent = detail

	local detailDescriptionHeader = Instance.new("TextLabel")
	detailDescriptionHeader.Name = "DetailDescriptionHeader"
	detailDescriptionHeader.LayoutOrder = 4
	detailDescriptionHeader.BackgroundTransparency = 1
	detailDescriptionHeader.Size = UDim2.new(1, 0, 0, 16)
	detailDescriptionHeader.Font = Enum.Font.FredokaOne
	detailDescriptionHeader.Text = "What to do"
	detailDescriptionHeader.TextSize = 12
	detailDescriptionHeader.TextXAlignment = Enum.TextXAlignment.Left
	detailDescriptionHeader.TextColor3 = DETAIL_LABEL_COLOR
	detailDescriptionHeader.ZIndex = 13
	detailDescriptionHeader.Visible = false
	detailDescriptionHeader.Parent = detail

	local detailDescription = Instance.new("TextLabel")
	detailDescription.Name = "DetailDescription"
	detailDescription.LayoutOrder = 5
	detailDescription.BackgroundTransparency = 1
	detailDescription.AutomaticSize = Enum.AutomaticSize.Y
	detailDescription.Size = UDim2.new(1, 0, 0, 0)
	detailDescription.Font = Enum.Font.Gotham
	detailDescription.Text = ""
	detailDescription.TextWrapped = true
	detailDescription.TextSize = 14
	detailDescription.TextXAlignment = Enum.TextXAlignment.Left
	detailDescription.TextYAlignment = Enum.TextYAlignment.Top
	detailDescription.TextColor3 = DESCRIPTION_COLOR
	detailDescription.ZIndex = 13
	detailDescription.Visible = false
	detailDescription.Parent = detail

	local detailReward = Instance.new("TextLabel")
	detailReward.Name = "DetailReward"
	detailReward.LayoutOrder = 6
	detailReward.BackgroundTransparency = 1
	detailReward.AutomaticSize = Enum.AutomaticSize.Y
	detailReward.Size = UDim2.new(1, 0, 0, 0)
	detailReward.Font = Enum.Font.FredokaOne
	detailReward.Text = ""
	detailReward.TextWrapped = true
	detailReward.TextSize = 14
	detailReward.TextXAlignment = Enum.TextXAlignment.Left
	detailReward.TextColor3 = Color3.fromRGB(255, 205, 60)
	detailReward.ZIndex = 13
	detailReward.Visible = false
	detailReward.Parent = detail

	local detailWidgets = {
		placeholder = placeholderLabel,
		name = detailName,
		statusPill = detailStatusPill,
		statusLabel = detailStatusLabel,
		giver = detailGiver,
		descriptionHeader = detailDescriptionHeader,
		description = detailDescription,
		reward = detailReward,
	}

	screenGui.Parent = playerGui
	return button, badgeDot, backdrop, panel, closeButton, scroll, detailWidgets
end

function QuestLogUI.Start()
	local player = Players.LocalPlayer
	local button, badgeDot, backdrop, panel, closeButton, scroll, detailWidgets = buildUI()
	local motion = PanelMotion.new(panel, backdrop)

	local outsideClickConn = nil
	local selectedKey = nil
	local rowRefs = {} -- key -> updateSelected(isSelected)
	local entriesByKey = {} -- key -> entry
	-- Persists across multiple Open()s within this client session (not saved -- resets on rejoin,
	-- same as everything else this panel doesn't persist) so toggling it once doesn't need to be
	-- redone every time the panel is reopened.
	local completedCollapsed = false

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

	local function showDetail(entry)
		local w = detailWidgets
		w.placeholder.Visible = false

		w.name.Text = entry.quest.Name
		w.name.Visible = true

		w.statusLabel.Text = DETAIL_STATUS_LABELS[entry.status]
		w.statusPill.BackgroundColor3 = STATUS_COLORS[entry.status]
		w.statusPill.Visible = true

		local giverName = getGiverDisplayName(entry)
		w.giver.Text = giverName and ("Quest Giver: " .. giverName) or "Quest Giver: None (always available)"
		w.giver.Visible = true

		w.descriptionHeader.Visible = true
		if entry.quest.Objectives then
			-- A checklist, one line per objective -- each line IS the hint (what to do), plus its
			-- own live progress, rather than one flat Description doing double duty.
			local lines = { entry.quest.Description or "" }
			for _, objective in ipairs(entry.quest.Objectives) do
				local progress = getObjectiveProgress(player, entry.id, objective)
				local done = progress >= objective.Target
				table.insert(lines, string.format(
					"%s %s (%d/%d)",
					done and "\226\156\147" or "\226\128\162",
					objective.Description,
					progress, objective.Target
				))
			end
			w.description.Text = table.concat(lines, "\n")
		else
			w.description.Text = entry.progressText
				and string.format("%s\n\nProgress: %s", entry.quest.Description or "", entry.progressText)
				or (entry.quest.Description or "")
		end
		w.description.Visible = true

		local rewardCoins = entry.quest.Reward and entry.quest.Reward.Coins
		if rewardCoins and rewardCoins > 0 then
			w.reward.Text = string.format("Reward: +%d Coins", rewardCoins)
			w.reward.Visible = true
		else
			w.reward.Text = ""
			w.reward.Visible = false
		end
	end

	local function clearDetail()
		local w = detailWidgets
		w.placeholder.Visible = true
		w.name.Visible = false
		w.statusPill.Visible = false
		w.giver.Visible = false
		w.descriptionHeader.Visible = false
		w.description.Visible = false
		w.reward.Visible = false
	end

	local function selectEntry(key)
		if not entriesByKey[key] then
			selectedKey = nil
			clearDetail()
			return
		end

		if selectedKey and rowRefs[selectedKey] then
			rowRefs[selectedKey](false)
		end
		selectedKey = key
		if rowRefs[selectedKey] then
			rowRefs[selectedKey](true)
		end
		showDetail(entriesByKey[key])
	end

	local function rebuildRows()
		for _, child in ipairs(scroll:GetChildren()) do
			if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
				child:Destroy()
			end
		end
		rowRefs = {}
		entriesByKey = {}

		local dayNumber = DailyRotation.GetCurrentDayNumber()
		local todaysDailyIds = DailyRotation.GetTodaysDailyIds(dayNumber)

		local questEntries = {}
		for id, quest in pairs(QuestConfig) do
			-- A chain quest whose prerequisite isn't done yet is skipped entirely -- not shown as
			-- locked, not shown at all -- see isQuestUnlocked's own comment.
			if isQuestUnlocked(player, quest) then
				local status = getQuestStatus(player, id)
				local progressText = nil
				if quest.Objectives and status ~= "Completed" then
					progressText = string.format(
						"%d/%d objectives",
						countCompletedObjectives(player, id, quest),
						#quest.Objectives
					)
				end
				table.insert(questEntries, {
					key = "quest:" .. id,
					type = "quest",
					id = id,
					quest = quest,
					status = status,
					progressText = progressText,
				})
			end
		end
		table.sort(questEntries, function(a, b) return a.quest.Name < b.quest.Name end)

		local secondsUntilRotation = DailyRotation.GetSecondsUntilNextRotation(dayNumber)
		local dailyEntries = {}
		-- Iterates todaysDailyIds ONCE, so a given daily id can only ever produce one entry here --
		-- and since a daily's completion is scoped to a specific day number (see getDailyStatus), a
		-- past completion from a day it's since rotated OUT of is never revisited either. Between
		-- those two things, the same daily can never show up twice in "Completed" -- the shared
		-- dedupe guard in addRowTo below (see its own comment) is the hard backstop for that, not the
		-- only thing preventing it.
		for _, id in ipairs(todaysDailyIds) do
			local quest = DailyQuestConfig.Quests[id]
			if quest then
				local status = getDailyStatus(player, id, dayNumber)
				local progressText = status == "Completed" and nil
					or string.format(
						"%d/%d \226\128\162 %s",
						getDailyProgress(player, id, dayNumber), quest.Target,
						formatTimeLeft(secondsUntilRotation)
					)
				table.insert(dailyEntries, {
					key = "daily:" .. id,
					type = "daily",
					id = id,
					quest = quest,
					status = status,
					progressText = progressText,
				})
			end
		end

		local activeQuestEntries, completedEntries = {}, {}
		for _, entry in ipairs(questEntries) do
			if entry.status == "Completed" then
				table.insert(completedEntries, entry)
			else
				table.insert(activeQuestEntries, entry)
			end
		end
		local activeDailyEntries = {}
		for _, entry in ipairs(dailyEntries) do
			if entry.status == "Completed" then
				table.insert(completedEntries, entry)
			else
				table.insert(activeDailyEntries, entry)
			end
		end
		table.sort(completedEntries, function(a, b) return a.quest.Name < b.quest.Name end)

		local layoutOrder = 0
		local firstEntry = nil

		-- The one place a row actually gets created and registered, shared by every section
		-- (Dailies/Quests build straight into `scroll`; Completed builds into its own nested
		-- `completedBody`, see below) -- entriesByKey being keyed by "quest:<id>"/"daily:<id>" means
		-- a given id can only ever be registered once per rebuild; a second attempt (which shouldn't
		-- happen, given how questEntries/dailyEntries/completedEntries are built above, but this
		-- makes it a hard guarantee rather than an assumption) is silently skipped instead of
		-- producing a visibly duplicated row.
		local function addRowTo(container, order, entry)
			if entriesByKey[entry.key] then
				return
			end
			entriesByKey[entry.key] = entry
			local row, updateSelected = buildListRow(container, order, entry, function()
				selectEntry(entry.key)
			end)
			rowRefs[entry.key] = updateSelected
			firstEntry = firstEntry or entry
		end

		local function addRow(entry)
			layoutOrder += 1
			addRowTo(scroll, layoutOrder, entry)
		end

		layoutOrder += 1
		buildSectionHeader(scroll, layoutOrder, "Dailies")
		if #activeDailyEntries == 0 then
			layoutOrder += 1
			buildPlaceholderRow(scroll, layoutOrder, "No dailies active right now.")
		else
			for _, entry in ipairs(activeDailyEntries) do
				addRow(entry)
			end
		end

		layoutOrder += 1
		buildSectionHeader(scroll, layoutOrder, "Quests")
		if #activeQuestEntries == 0 then
			layoutOrder += 1
			buildPlaceholderRow(scroll, layoutOrder, "Nothing here yet -- check back soon!")
		else
			for _, entry in ipairs(activeQuestEntries) do
				addRow(entry)
			end
		end

		-- Completed: a collapsible section (chevron header, click to toggle) since this is the one
		-- list that only ever grows, forever, across every quest ever finished -- unlike Dailies/
		-- Quests, which naturally stay small. Its rows live in their OWN Frame (completedBody, with
		-- its own UIListLayout) rather than directly in `scroll`, so toggling is just flipping one
		-- Frame's Visible instead of touching N individual rows.
		layoutOrder += 1
		local completedTitleLabel, completedChevron = buildCollapsibleSectionHeader(scroll, layoutOrder, function()
			completedCollapsed = not completedCollapsed
			completedChevron.Text = completedCollapsed and CHEVRON_COLLAPSED or CHEVRON_EXPANDED
			-- selection: closing the section is otherwise a bit disorienting if the detail panel
			-- is currently showing something that just went out of view. Left as-is (not
			-- auto-clearing) since the row is still logically selected, just scrolled/hidden away --
			-- same spirit as scrolling a long list past the selected row without deselecting it.
		end)
		completedTitleLabel.Text = string.format("Completed (%d)", #completedEntries)

		layoutOrder += 1
		local completedBody = Instance.new("Frame")
		completedBody.Name = "CompletedBody"
		completedBody.LayoutOrder = layoutOrder
		completedBody.BackgroundTransparency = 1
		completedBody.AutomaticSize = Enum.AutomaticSize.Y
		completedBody.Size = UDim2.new(1, 0, 0, 0)
		completedBody.ZIndex = 12
		completedBody.Parent = scroll

		local completedBodyLayout = Instance.new("UIListLayout")
		completedBodyLayout.FillDirection = Enum.FillDirection.Vertical
		completedBodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
		completedBodyLayout.Padding = UDim.new(0, 8)
		completedBodyLayout.Parent = completedBody

		local completedBodyOrder = 0
		if #completedEntries == 0 then
			completedBodyOrder += 1
			buildPlaceholderRow(completedBody, completedBodyOrder, "No completed quests yet.")
		else
			for _, entry in ipairs(completedEntries) do
				completedBodyOrder += 1
				addRowTo(completedBody, completedBodyOrder, entry)
			end
		end

		completedChevron.Text = completedCollapsed and CHEVRON_COLLAPSED or CHEVRON_EXPANDED
		completedBody.Visible = not completedCollapsed

		if selectedKey and entriesByKey[selectedKey] then
			selectEntry(selectedKey)
		elseif firstEntry then
			selectEntry(firstEntry.key)
		else
			selectedKey = nil
			clearDetail()
		end
	end

	local function refreshBadgeDot()
		for id in pairs(QuestConfig) do
			if getQuestStatus(player, id) == "InProgress" then
				badgeDot.Visible = true
				return
			end
		end

		local dayNumber = DailyRotation.GetCurrentDayNumber()
		for _, id in ipairs(DailyRotation.GetTodaysDailyIds(dayNumber)) do
			if getDailyStatus(player, id, dayNumber) == "InProgress" then
				badgeDot.Visible = true
				return
			end
		end

		badgeDot.Visible = false
	end

	local function openPanel()
		rebuildRows()
		motion.Show()
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

	refreshBadgeDot()
	for id in pairs(QuestConfig) do
		player:GetAttributeChangedSignal("Quest_" .. id):Connect(refreshBadgeDot)
		player:GetAttributeChangedSignal("QuestStarted_" .. id):Connect(refreshBadgeDot)
	end
	-- Only wires up listeners for TODAY's active daily ids -- if the day rolls over while this
	-- session is still running, the badge dot simply won't react live to that specific edge case
	-- (the panel itself is still always correct, since rebuildRows recomputes the rotation fresh on
	-- every Open()) -- a known, low-stakes simplification, not worth a live day-boundary watcher.
	for _, id in ipairs(DailyRotation.GetTodaysDailyIds()) do
		player:GetAttributeChangedSignal("DailyProgress_" .. id):Connect(refreshBadgeDot)
		player:GetAttributeChangedSignal("DailyCompletedDay_" .. id):Connect(refreshBadgeDot)
	end
end

return QuestLogUI
