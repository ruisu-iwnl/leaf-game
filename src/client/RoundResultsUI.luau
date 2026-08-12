local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PanelMotion = require(script.Parent.PanelMotion)
local RoundConfig = require(ReplicatedStorage.Shared.RoundConfig)
local UILayout = require(script.Parent.UILayout)

-- The Results leaderboard shown between a round ending (goal met or timer expiring -- RoundUI's
-- big "GOAL REACHED!"/"TIME'S UP!" flash covers announcing THAT) and everyone getting faded back
-- to the Lobby. RoundSystem fires the RoundResults remote once, right as it enters the Results
-- state, to every connected client, with every currently-connected player's leaves-delivered-this-
-- round count, a signed Coins bonus/penalty (CoinDelta, see RoundSystem.applyResultsRewards)
-- already applied server-side, and the top scorer flagged IsMVP -- this module just renders
-- whatever it's handed and stays open for RoundConfig.ResultsDurationSeconds (read live off the
-- RoundResultsEndsAt attribute, not a locally-started timer, same server-clock-driven pattern as
-- the countdown/round timer). Also shows a round-level compliment/scold message (performanceLabel)
-- derived purely from RoundEndReason + CleanupZoneProgress, the same way subtitleLabel already
-- derives from Workspace attributes rather than needing its own remote payload. Only actually opens
-- for players with InActiveRound true, though (see RoundSystem.luau) -- a player who wasn't part of
-- the round doesn't get a results panel for it.
--
-- Same cream/warm-accent palette as ToastNotificationUI/StorePanelUI and the same shared
-- backdrop+panel pop animation as every other modal in the game (PanelMotion.new) -- one
-- consistent "this is a game panel" look rather than a bespoke one-off.
local RoundResultsUI = {}

local CARD_COLOR = Color3.fromRGB(253, 250, 244)
local CARD_STROKE = Color3.fromRGB(224, 168, 96)
local TITLE_COLOR = Color3.fromRGB(58, 34, 20)
local SUBTITLE_COLOR = Color3.fromRGB(150, 130, 112)
local ROW_NAME_COLOR = Color3.fromRGB(70, 55, 45)
local ROW_COUNT_COLOR = Color3.fromRGB(130, 104, 84)
local FOOTER_COLOR = Color3.fromRGB(150, 130, 112)
local YOU_NAME_COLOR = Color3.fromRGB(72, 132, 176)

-- Leaf Patron (VIP perk) row treatment -- a royal purple/gold tint, same palette as
-- CosmeticConfig.luau's Patron skins and the rainbow-nameplate/footstep-trail perk effects, so a
-- VIP's Results row reads as visibly distinct even outside the top 3. Only applied when the row
-- isn't already medalled (rank still wins the background -- see addRow) so the two treatments never
-- compete for the same row.
local VIP_ROW_BG = Color3.fromRGB(238, 224, 250)
local VIP_ROW_STROKE = Color3.fromRGB(150, 60, 190)
local VIP_CROWN = "\u{1F451} "

-- Bonus/compliment vs. penalty/scold -- shared by the round-level performance message and each
-- row's individual Coins delta, so the two always read as visually consistent (green = good news,
-- red = bad news) rather than each picking its own palette.
local GOOD_COLOR = Color3.fromRGB(70, 150, 95)
local BAD_COLOR = Color3.fromRGB(190, 80, 70)

-- Top-3 medal treatment -- only ever applied when that rank actually delivered leaves (Count > 0),
-- so an empty round doesn't hand out medals for nothing.
local RANK_MEDALS = { [1] = "\u{1F947}", [2] = "\u{1F948}", [3] = "\u{1F949}" }
local RANK_ROW_BG = {
	[1] = Color3.fromRGB(255, 244, 222),
	[2] = Color3.fromRGB(240, 240, 244),
	[3] = Color3.fromRGB(250, 232, 218),
}
local RANK_STROKE = {
	[1] = Color3.fromRGB(224, 168, 96),
	[2] = Color3.fromRGB(180, 180, 190),
	[3] = Color3.fromRGB(198, 140, 96),
}

local PANEL_WIDTH = 420
local PANEL_HEIGHT = 414 -- grew by 22 to fit the new performanceLabel line below the subtitle
local ROW_HEIGHT = 40

function RoundResultsUI.Start()
	task.spawn(function()
		local player = Players.LocalPlayer
		local playerGui = player:WaitForChild("PlayerGui")

		local remotes = ReplicatedStorage.Shared:WaitForChild("Remotes", 15)
		local roundResultsRemote = remotes and remotes:WaitForChild("RoundResults", 15)
		if not roundResultsRemote then
			warn("[RoundResultsUI] RoundResults remote not found after 15s -- results panel disabled this session.")
			return
		end

		local screenGui = Instance.new("ScreenGui")
		screenGui.Name = "RoundResultsUI"
		screenGui.ResetOnSpawn = false
		screenGui.IgnoreGuiInset = true
		screenGui.DisplayOrder = UILayout.DisplayOrder.Banner

		local backdrop = Instance.new("Frame")
		backdrop.Name = "Backdrop"
		backdrop.Active = false
		backdrop.Size = UDim2.new(1, 0, 1, 0)
		backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
		backdrop.BackgroundTransparency = 0.55
		backdrop.BorderSizePixel = 0
		backdrop.Visible = false
		backdrop.ZIndex = 39
		backdrop.Parent = screenGui

		local panel = Instance.new("Frame")
		panel.Name = "Panel"
		panel.AnchorPoint = Vector2.new(0.5, 0.5)
		panel.Position = UDim2.new(0.5, 0, 0.45, 0)
		-- Scale-based (not a flat PANEL_WIDTH/PANEL_HEIGHT pixel size) so this shrinks on narrow/short
		-- mobile screens instead of overflowing them -- same "scale + UISizeConstraint clamp" approach
		-- RoundUI's MapPick vote panel already uses for the same reason. The clamp's MaxSize is exactly
		-- PANEL_WIDTH/PANEL_HEIGHT, so desktop/tablet rendering is completely unchanged; only small
		-- screens actually hit the scale-driven shrink.
		panel.Size = UDim2.new(0.88, 0, 0.68, 0)
		panel.BackgroundColor3 = CARD_COLOR
		panel.BorderSizePixel = 0
		panel.ZIndex = 40
		panel.Parent = backdrop

		local panelSizeConstraint = Instance.new("UISizeConstraint")
		panelSizeConstraint.MinSize = Vector2.new(300, 340)
		panelSizeConstraint.MaxSize = Vector2.new(PANEL_WIDTH, PANEL_HEIGHT)
		panelSizeConstraint.Parent = panel

		local panelCorner = Instance.new("UICorner")
		panelCorner.CornerRadius = UDim.new(0, 20)
		panelCorner.Parent = panel

		local panelStroke = Instance.new("UIStroke")
		panelStroke.Color = CARD_STROKE
		panelStroke.Transparency = 0.15
		panelStroke.Thickness = 2
		panelStroke.Parent = panel

		local titleLabel = Instance.new("TextLabel")
		titleLabel.Name = "Title"
		titleLabel.Position = UDim2.new(0, 0, 0, 18)
		titleLabel.Size = UDim2.new(1, 0, 0, 34)
		titleLabel.BackgroundTransparency = 1
		titleLabel.Font = Enum.Font.FredokaOne
		titleLabel.TextSize = 28
		titleLabel.TextColor3 = TITLE_COLOR
		titleLabel.Text = "Round Results"
		titleLabel.ZIndex = 41
		titleLabel.Parent = panel

		-- "Goal Reached!   500 / 500 leaves cleared" -- filled in once the results remote fires (see
		-- below), since it depends on RoundEndReason/CleanupZoneCount which are only meaningful once
		-- the round has actually ended.
		local subtitleLabel = Instance.new("TextLabel")
		subtitleLabel.Name = "Subtitle"
		subtitleLabel.Position = UDim2.new(0, 0, 0, 50)
		subtitleLabel.Size = UDim2.new(1, 0, 0, 20)
		subtitleLabel.BackgroundTransparency = 1
		subtitleLabel.Font = Enum.Font.FredokaOne
		subtitleLabel.TextSize = 14
		subtitleLabel.TextColor3 = SUBTITLE_COLOR
		subtitleLabel.Text = ""
		subtitleLabel.ZIndex = 41
		subtitleLabel.Parent = panel

		-- The compliment/scold line -- "Amazing work!"/"So close!"/"let's move faster next time" --
		-- driven purely by RoundEndReason + CleanupZoneProgress (see below), same "read off shared
		-- Workspace attributes, no extra remote payload needed" approach the subtitle above already
		-- uses. RoundConfig.ResultsGoodProgressThreshold is the SAME value RoundSystem's
		-- applyResultsRewards uses server-side to decide the Coins penalty, so this message and each
		-- row's Coins delta below can never disagree about how the round went.
		local performanceLabel = Instance.new("TextLabel")
		performanceLabel.Name = "Performance"
		performanceLabel.Position = UDim2.new(0, 16, 0, 72)
		performanceLabel.Size = UDim2.new(1, -32, 0, 20)
		performanceLabel.BackgroundTransparency = 1
		performanceLabel.Font = Enum.Font.FredokaOne
		performanceLabel.TextSize = 13
		performanceLabel.TextWrapped = true
		performanceLabel.TextColor3 = SUBTITLE_COLOR
		performanceLabel.Text = ""
		performanceLabel.ZIndex = 41
		performanceLabel.Parent = panel

		local rowsFrame = Instance.new("ScrollingFrame")
		rowsFrame.Name = "Rows"
		rowsFrame.Position = UDim2.new(0, 16, 0, 100)
		rowsFrame.Size = UDim2.new(1, -32, 1, -100 - 46)
		rowsFrame.BackgroundTransparency = 1
		rowsFrame.BorderSizePixel = 0
		rowsFrame.ScrollBarThickness = 4
		rowsFrame.ScrollBarImageColor3 = CARD_STROKE
		rowsFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
		rowsFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
		rowsFrame.ZIndex = 41
		rowsFrame.Parent = panel

		local rowsLayout = Instance.new("UIListLayout")
		rowsLayout.FillDirection = Enum.FillDirection.Vertical
		rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowsLayout.Padding = UDim.new(0, 6)
		rowsLayout.Parent = rowsFrame

		local footerLabel = Instance.new("TextLabel")
		footerLabel.Name = "Footer"
		footerLabel.AnchorPoint = Vector2.new(0.5, 1)
		footerLabel.Position = UDim2.new(0.5, 0, 1, -14)
		footerLabel.Size = UDim2.new(1, -32, 0, 22)
		footerLabel.BackgroundTransparency = 1
		footerLabel.Font = Enum.Font.FredokaOne
		footerLabel.TextSize = 15
		footerLabel.TextColor3 = FOOTER_COLOR
		footerLabel.Text = ""
		footerLabel.ZIndex = 41
		footerLabel.Parent = panel

		screenGui.Parent = playerGui

		local controller = PanelMotion.new(panel, backdrop)

		local function clearRows()
			for _, child in ipairs(rowsFrame:GetChildren()) do
				if child:IsA("Frame") then
					child:Destroy()
				end
			end
		end

		local localPlayerName = player.Name

		local function addRow(rank, entry)
			local medalled = entry.Count > 0 and RANK_MEDALS[rank] ~= nil
			local isYou = entry.Name == localPlayerName
			local isVIP = entry.IsVIP == true

			local row = Instance.new("Frame")
			row.Name = "Row" .. rank
			row.LayoutOrder = rank
			row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
			if medalled then
				row.BackgroundColor3 = RANK_ROW_BG[rank]
				row.BackgroundTransparency = 0
			elseif isVIP then
				row.BackgroundColor3 = VIP_ROW_BG
				row.BackgroundTransparency = 0
			else
				row.BackgroundColor3 = CARD_COLOR
				row.BackgroundTransparency = 1
			end
			row.BorderSizePixel = 0
			row.ZIndex = 41
			row.Parent = rowsFrame

			local rowCorner = Instance.new("UICorner")
			rowCorner.CornerRadius = UDim.new(0, 10)
			rowCorner.Parent = row

			if medalled then
				local rowStroke = Instance.new("UIStroke")
				rowStroke.Color = RANK_STROKE[rank]
				rowStroke.Transparency = 0.2
				rowStroke.Thickness = 1.5
				rowStroke.Parent = row
			elseif isVIP then
				local rowStroke = Instance.new("UIStroke")
				rowStroke.Color = VIP_ROW_STROKE
				rowStroke.Transparency = 0.15
				rowStroke.Thickness = 1.5
				rowStroke.Parent = row
			elseif isYou then
				local rowStroke = Instance.new("UIStroke")
				rowStroke.Color = YOU_NAME_COLOR
				rowStroke.Transparency = 0.4
				rowStroke.Thickness = 1.25
				rowStroke.Parent = row
			end

			local rankLabel = Instance.new("TextLabel")
			rankLabel.Name = "Rank"
			rankLabel.Position = UDim2.new(0, 10, 0, 0)
			rankLabel.Size = UDim2.new(0, 32, 1, 0)
			rankLabel.BackgroundTransparency = 1
			rankLabel.Font = Enum.Font.FredokaOne
			rankLabel.TextSize = medalled and 20 or 16
			rankLabel.TextColor3 = ROW_COUNT_COLOR
			rankLabel.Text = medalled and RANK_MEDALS[rank] or ("#" .. rank)
			rankLabel.ZIndex = 42
			rankLabel.Parent = row

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "PlayerName"
			nameLabel.Position = UDim2.new(0, 46, 0, 0)
			nameLabel.Size = UDim2.new(1, -46 - 90, 1, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Font = Enum.Font.FredokaOne
			nameLabel.TextSize = 18
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextColor3 = ROW_NAME_COLOR
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.Text = (isVIP and VIP_CROWN or "") .. entry.Name .. (isYou and " (You)" or "")
			nameLabel.ZIndex = 42
			nameLabel.Parent = row

			if entry.IsMVP then
				nameLabel.TextColor3 = TITLE_COLOR
			elseif isYou then
				nameLabel.TextColor3 = YOU_NAME_COLOR
			elseif isVIP then
				nameLabel.TextColor3 = VIP_ROW_STROKE
			end

			-- Count is either the only line in this column (vertically centered against nameLabel,
			-- same as before the Coins-delta feature existed) or the TOP of a 2-line stack with
			-- CoinDelta below it -- which one depends on whether this round actually applied a
			-- delta (CoinDelta ~= 0), decided BEFORE building either label so both can be positioned
			-- correctly the first time instead of countLabel always sitting pinned near the top of
			-- the row (that was the bug: with no delta, there's no second line, so a top-pinned
			-- count label reads as misaligned against the vertically-centered name/rank next to it).
			local coinDelta = entry.CoinDelta or 0
			local hasCoinDelta = coinDelta ~= 0

			local countLabel = Instance.new("TextLabel")
			countLabel.Name = "Count"
			countLabel.AnchorPoint = Vector2.new(1, 0)
			countLabel.Size = UDim2.new(0, 90, 0, 16)
			if hasCoinDelta then
				countLabel.Position = UDim2.new(1, -14, 0, 4)
			else
				-- Centered in the full row height, matching nameLabel's own vertical centering.
				countLabel.Position = UDim2.new(1, -14, 0.5, -8)
			end
			countLabel.BackgroundTransparency = 1
			countLabel.Font = Enum.Font.FredokaOne
			countLabel.TextSize = 16
			countLabel.TextXAlignment = Enum.TextXAlignment.Right
			countLabel.TextColor3 = ROW_COUNT_COLOR
			countLabel.Text = tostring(entry.Count) .. " leaves"
			countLabel.ZIndex = 42
			countLabel.Parent = row

			if hasCoinDelta then
				local coinDeltaLabel = Instance.new("TextLabel")
				coinDeltaLabel.Name = "CoinDelta"
				coinDeltaLabel.AnchorPoint = Vector2.new(1, 0)
				coinDeltaLabel.Position = UDim2.new(1, -14, 0, 22)
				coinDeltaLabel.Size = UDim2.new(0, 90, 0, 14)
				coinDeltaLabel.BackgroundTransparency = 1
				coinDeltaLabel.Font = Enum.Font.FredokaOne
				coinDeltaLabel.TextSize = 12
				coinDeltaLabel.TextXAlignment = Enum.TextXAlignment.Right
				coinDeltaLabel.TextColor3 = coinDelta > 0 and GOOD_COLOR or BAD_COLOR
				coinDeltaLabel.Text = string.format("%s%d coins", coinDelta > 0 and "+" or "", coinDelta)
				coinDeltaLabel.ZIndex = 42
				coinDeltaLabel.Parent = row
			end
		end

		roundResultsRemote.OnClientEvent:Connect(function(results)
			-- Gated on InActiveRound (RoundSystem.luau's per-player attribute) -- the remote fires to
			-- everyone connected, but "round results" shouldn't pop up for a player who wasn't
			-- actually part of the round (joined after this round's teleport already happened).
			if player:GetAttribute("InActiveRound") ~= true then
				return
			end

			clearRows()
			if typeof(results) == "table" then
				for i, entry in ipairs(results) do
					addRow(i, entry)
				end
			end

			local reason = Workspace:GetAttribute("RoundEndReason")
			local delivered = Workspace:GetAttribute("CleanupZoneCount") or 0
			local goal = Workspace:GetAttribute("RoundGoal") or delivered
			local reasonText = reason == "Goal" and "Goal Reached!" or "Time's Up!"
			subtitleLabel.Text = string.format("%s   %d / %d leaves cleared", reasonText, delivered, goal)

			-- Same compliment/scold split RoundSystem.applyResultsRewards uses for the actual Coins
			-- math, off the same RoundConfig.ResultsGoodProgressThreshold -- so this message and each
			-- row's Coins delta above always agree.
			local progress = Workspace:GetAttribute("CleanupZoneProgress") or 0
			if reason == "Goal" then
				performanceLabel.Text = "Amazing work! The goal was reached before time ran out -- bonus coins for everyone who helped!"
				performanceLabel.TextColor3 = GOOD_COLOR
			elseif progress >= RoundConfig.ResultsGoodProgressThreshold then
				performanceLabel.Text = "So close! Great effort out there -- almost had it."
				performanceLabel.TextColor3 = GOOD_COLOR
			else
				local leftPercent = math.floor((1 - math.min(progress, 1)) * 100 + 0.5)
				performanceLabel.Text = string.format(
					"Time ran out with %d%% still uncleaned... let's move faster next round!",
					leftPercent
				)
				performanceLabel.TextColor3 = BAD_COLOR
			end

			controller.Show()
		end)

		Workspace:GetAttributeChangedSignal("RoundState"):Connect(function()
			if Workspace:GetAttribute("RoundState") ~= "Results" then
				controller.Hide()
			end
		end)

		RunService.Heartbeat:Connect(function()
			if Workspace:GetAttribute("RoundState") ~= "Results" then
				return
			end
			local endsAt = Workspace:GetAttribute("RoundResultsEndsAt")
			if not endsAt then
				footerLabel.Text = ""
				return
			end
			local remaining = math.max(endsAt - Workspace:GetServerTimeNow(), 0)
			footerLabel.Text = string.format("Returning to the Lobby in %ds...", math.ceil(remaining))
		end)
	end)
end

return RoundResultsUI
