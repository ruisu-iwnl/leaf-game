local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local DailyQuestConfig = require(ReplicatedStorage.Shared.DailyQuestConfig)
local DailyRotation = require(ReplicatedStorage.Shared.DailyRotation)
local PanelMotion = require(script.Parent.PanelMotion)
local QuestConfig = require(ReplicatedStorage.Shared.QuestConfig)
local UILayout = require(script.Parent.UILayout)

-- A "Quest Log" panel -- everything the player has in progress or has finished, split into a
-- "Quests" section (QuestConfig's NPC-driven ones, e.g. Tutorial) and a "Dailies" section
-- (DailyQuestConfig's rotating ones -- see DailyRotation.luau, a pure day-number function this
-- reads directly, the same one DailyQuestSystem.luau uses server-side, so both always agree on
-- which 3 are active today with no remote round-trip needed). Opened via a button sitting right next
-- to InventoryUI's own backpack button, same dark autumn palette (PANEL_COLOR/STROKE_COLOR) as that
-- panel/StorePanelUI/SettingsUI, since it's meant to read as belonging to that same family of UI.
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
local DESCRIPTION_COLOR = Color3.fromRGB(210, 190, 170)
local PLACEHOLDER_COLOR = Color3.fromRGB(170, 148, 122)

local STATUS_COLORS = {
	NotStarted = Color3.fromRGB(90, 58, 36),
	InProgress = Color3.fromRGB(214, 158, 46),
	Completed = Color3.fromRGB(90, 168, 96),
}
local STATUS_LABELS = {
	NotStarted = "Not Started",
	InProgress = "In Progress",
	Completed = "Completed",
}

local BUTTON_SIZE = 48
local BUTTON_GAP = 10
local ROW_HEIGHT = 78
local PANEL_PADDING = 20
local HEADER_HEIGHT = 30

local function getQuestStatus(player, id)
	if player:GetAttribute("Quest_" .. id) == true then
		return "Completed"
	end
	if player:GetAttribute("QuestStarted_" .. id) == true then
		return "InProgress"
	end
	return "NotStarted"
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
	label.TextColor3 = Color3.fromRGB(220, 195, 160)
	label.ZIndex = 12
	label.Parent = parent
end

local function buildPlaceholderRow(parent, layoutOrder, text)
	local label = Instance.new("TextLabel")
	label.Name = "Placeholder" .. layoutOrder
	label.LayoutOrder = layoutOrder
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 30)
	label.Font = Enum.Font.Gotham
	label.Text = text
	label.TextSize = 13
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = PLACEHOLDER_COLOR
	label.ZIndex = 12
	label.Parent = parent
end

local function buildQuestRow(parent, layoutOrder, quest, status, progressText)
	local row = Instance.new("Frame")
	row.Name = "QuestRow" .. layoutOrder
	row.LayoutOrder = layoutOrder
	row.BackgroundColor3 = ROW_COLOR
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BorderSizePixel = 0
	row.ZIndex = 12
	row.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = row

	local stroke = Instance.new("UIStroke")
	stroke.Color = STROKE_COLOR
	stroke.Transparency = 0.5
	stroke.Thickness = 1
	stroke.Parent = row

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.new(0, 14, 0, 8)
	nameLabel.Size = UDim2.new(1, -108, 0, 20)
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.Text = quest.Name
	nameLabel.TextSize = 16
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.ZIndex = 13
	nameLabel.Parent = row

	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "Description"
	descLabel.BackgroundTransparency = 1
	descLabel.Position = UDim2.new(0, 14, 0, 30)
	descLabel.Size = UDim2.new(1, -28, 0, 34)
	descLabel.Font = Enum.Font.Gotham
	descLabel.Text = progressText and string.format("%s (%s)", quest.Description or "", progressText) or (quest.Description or "")
	descLabel.TextSize = 12
	descLabel.TextWrapped = true
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextYAlignment = Enum.TextYAlignment.Top
	descLabel.TextColor3 = DESCRIPTION_COLOR
	descLabel.ZIndex = 13
	descLabel.Parent = row

	-- A separate pill (background Frame) + label (text) pair, not one TextLabel doing both --
	-- FredokaOne's glyphs don't sit centered within their own reported text bounds (same issue
	-- ToastNotificationUI.luau's medal glyph has, see its own comment on why), and a single-piece
	-- TextLabel had no room to compensate for that while also guaranteeing "Not Started"/"In
	-- Progress" actually fit the pill's width. TextScaled + a UITextSizeConstraint ceiling fixes
	-- both at once: the label always centers on the pill's true geometric center, and shrinks
	-- instead of overflowing if the pill's too narrow for its text.
	local statusBadge = Instance.new("Frame")
	statusBadge.Name = "Status"
	statusBadge.AnchorPoint = Vector2.new(1, 0)
	statusBadge.Position = UDim2.new(1, -10, 0, 8)
	statusBadge.Size = UDim2.new(0, 88, 0, 22)
	statusBadge.BackgroundColor3 = STATUS_COLORS[status]
	statusBadge.BorderSizePixel = 0
	statusBadge.ZIndex = 13
	statusBadge.Parent = row

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(1, 0)
	badgeCorner.Parent = statusBadge

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Label"
	statusLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	statusLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	statusLabel.Size = UDim2.new(1, -12, 1, -4)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.FredokaOne
	statusLabel.Text = STATUS_LABELS[status]
	statusLabel.TextScaled = true
	statusLabel.TextColor3 = Color3.new(1, 1, 1)
	statusLabel.TextXAlignment = Enum.TextXAlignment.Center
	statusLabel.TextYAlignment = Enum.TextYAlignment.Center
	statusLabel.ZIndex = 14
	statusLabel.Parent = statusBadge

	local statusLabelConstraint = Instance.new("UITextSizeConstraint")
	statusLabelConstraint.MaxTextSize = 11
	statusLabelConstraint.Parent = statusLabel

	local rewardCoins = quest.Reward and quest.Reward.Coins
	if rewardCoins and rewardCoins > 0 then
		local rewardLabel = Instance.new("TextLabel")
		rewardLabel.Name = "Reward"
		rewardLabel.AnchorPoint = Vector2.new(1, 0)
		rewardLabel.Position = UDim2.new(1, -10, 0, 34)
		rewardLabel.Size = UDim2.new(0, 88, 0, 16)
		rewardLabel.BackgroundTransparency = 1
		rewardLabel.Font = Enum.Font.FredokaOne
		rewardLabel.Text = string.format("+%d Coins", rewardCoins)
		rewardLabel.TextSize = 11
		rewardLabel.TextXAlignment = Enum.TextXAlignment.Right
		rewardLabel.TextColor3 = Color3.fromRGB(255, 205, 60)
		rewardLabel.ZIndex = 13
		rewardLabel.Parent = row
	end

	return row
end

local function buildUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "QuestLogUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

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
	panel.Size = UDim2.new(0.86, 0, 0.72, 0)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = PANEL_TRANSPARENCY
	panel.BorderSizePixel = 0
	panel.ZIndex = 11
	panel.Parent = backdrop

	local panelConstraint = Instance.new("UISizeConstraint")
	panelConstraint.MinSize = Vector2.new(300, 360)
	panelConstraint.MaxSize = Vector2.new(440, 520)
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

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.Position = UDim2.new(0, PANEL_PADDING, 0, PANEL_PADDING + HEADER_HEIGHT + 12)
	scroll.Size = UDim2.new(1, -PANEL_PADDING * 2, 1, -(PANEL_PADDING * 2 + HEADER_HEIGHT + 12))
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = STROKE_COLOR
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
	scrollLayout.Padding = UDim.new(0, 12)
	scrollLayout.Parent = scroll

	screenGui.Parent = playerGui
	return button, badgeDot, backdrop, panel, closeButton, scroll
end

function QuestLogUI.Start()
	local player = Players.LocalPlayer
	local button, badgeDot, backdrop, panel, closeButton, scroll = buildUI()
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

	local function rebuildRows()
		for _, child in ipairs(scroll:GetChildren()) do
			if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
				child:Destroy()
			end
		end

		local dayNumber = DailyRotation.GetCurrentDayNumber()
		local todaysDailyIds = DailyRotation.GetTodaysDailyIds(dayNumber)

		local questRows = {}
		for id, quest in pairs(QuestConfig) do
			table.insert(questRows, { id = id, quest = quest })
		end
		table.sort(questRows, function(a, b) return a.quest.Name < b.quest.Name end)

		local layoutOrder = 0

		layoutOrder += 1
		buildSectionHeader(scroll, layoutOrder, "Quests")
		if #questRows == 0 then
			layoutOrder += 1
			buildPlaceholderRow(scroll, layoutOrder, "Nothing here yet -- check back soon!")
		else
			for _, entry in ipairs(questRows) do
				layoutOrder += 1
				buildQuestRow(scroll, layoutOrder, entry.quest, getQuestStatus(player, entry.id))
			end
		end

		layoutOrder += 1
		buildSectionHeader(scroll, layoutOrder, "Dailies")
		if #todaysDailyIds == 0 then
			layoutOrder += 1
			buildPlaceholderRow(scroll, layoutOrder, "No dailies yet -- check back soon!")
		else
			for _, id in ipairs(todaysDailyIds) do
				local quest = DailyQuestConfig.Quests[id]
				if quest then
					layoutOrder += 1
					local status = getDailyStatus(player, id, dayNumber)
					local progressText = status == "Completed" and nil
						or string.format("%d/%d", getDailyProgress(player, id, dayNumber), quest.Target)
					buildQuestRow(scroll, layoutOrder, quest, status, progressText)
				end
			end
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
