local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig)
local RoundConfig = require(ReplicatedStorage.Shared.RoundConfig)
local PanelMotion = require(script.Parent.PanelMotion)

-- Drives the Lobby's Intermission card, the MapPick vote panel, plus the Loading/Countdown/Active/
-- Results beats that follow them, purely off the Workspace "RoundState" and its related attributes
-- RoundSystem.luau (server) sets -- this script never decides anything about round state itself,
-- only reflects it. There is no manual "Start Round" button anymore -- the loop runs on its own;
-- Intermission is a timed card, and MapPick is a real vote (see below) even when there's only one
-- map/one player to vote with.
--
-- The Intermission card, the MapPick vote panel, the countdown number, the round timer pill, and
-- the map-title/round-end flash text all pop in/out via the same shared PanelMotion (backdrop+panel
-- pop-and-fade) every other panel in the game uses, instead of each one hand-rolling its own
-- tween -- each element gets a small invisible "backdrop" Frame purely so PanelMotion has
-- something to toggle Visible on (these are HUD elements, not modals, so the backdrop itself is
-- never dimmed).
local RoundUI = {}

-- Same cream/warm-accent palette as MapProgressUI/ToastNotificationUI/BadgeNotificationUI, so the
-- Intermission card and the MapPick vote panel both read as the same "kind" of UI as the rest of
-- the game instead of inventing their own look. The MapTally/MapResult announcements reuse the
-- separate big FredokaOne/black-stroke flash treatment instead (see flashLabel below) -- that one's
-- shared with the countdown and round-end banners, not this palette.
local CARD_COLOR = Color3.fromRGB(253, 250, 244)
local CARD_STROKE = Color3.fromRGB(224, 168, 96)
local TITLE_COLOR = Color3.fromRGB(58, 34, 20)
local DESCRIPTION_COLOR = Color3.fromRGB(130, 104, 84)

function RoundUI.Start()
	-- init.client.luau starts every UI module in one sequential list -- an untimed WaitForChild
	-- here could block every module after it if Remotes/the remote itself were ever slow/missing.
	-- Deferred + timed, same pattern as the other fixes this session.
	task.spawn(function()
		local player = Players.LocalPlayer
		local playerGui = player:WaitForChild("PlayerGui")

		local remotes = ReplicatedStorage.Shared:WaitForChild("Remotes", 15)
		if not remotes then
			warn("[RoundUI] ReplicatedStorage.Shared.Remotes not found after 15s -- round UI disabled this session.")
			return
		end
		local screenFadeRemote = remotes:WaitForChild("RoundScreenFade", 15)
		local mapVoteRemote = remotes:WaitForChild("SubmitMapVote", 15)
		local mapVoteUpdateRemote = remotes:WaitForChild("MapVoteUpdate", 15)
		if not screenFadeRemote or not mapVoteRemote or not mapVoteUpdateRemote then
			warn("[RoundUI] Round remotes not found after 15s -- round UI disabled this session.")
			return
		end

		local screenGui = Instance.new("ScreenGui")
		screenGui.Name = "RoundUI"
		screenGui.ResetOnSpawn = false
		screenGui.IgnoreGuiInset = true

		-- Small cream info card -- title + subtitle -- built identically for both the Intermission
		-- "Starting in Ns..." card and the MapPick "map name + difficulty" card below, so the two
		-- adjacent phases read as the same UI element with different text, not two different
		-- designs. Same top-center slot the old Start button/Loading label used.
		local function createInfoCard()
			local backdrop = Instance.new("Frame")
			backdrop.Name = "Backdrop"
			backdrop.Active = false
			backdrop.AnchorPoint = Vector2.new(0.5, 0)
			backdrop.Position = UDim2.new(0.5, 0, 0, 24)
			backdrop.Size = UDim2.new(0, 260, 0, 74)
			backdrop.BackgroundTransparency = 1
			backdrop.Visible = false
			backdrop.Parent = screenGui

			local panel = Instance.new("Frame")
			panel.Name = "Panel"
			panel.Size = UDim2.new(1, 0, 1, 0)
			panel.BackgroundColor3 = CARD_COLOR
			panel.BorderSizePixel = 0
			panel.Parent = backdrop

			local panelCorner = Instance.new("UICorner")
			panelCorner.CornerRadius = UDim.new(0, 14)
			panelCorner.Parent = panel

			local panelStroke = Instance.new("UIStroke")
			panelStroke.Color = CARD_STROKE
			panelStroke.Transparency = 0.2
			panelStroke.Thickness = 1.5
			panelStroke.Parent = panel

			local titleLabel = Instance.new("TextLabel")
			titleLabel.Name = "Title"
			titleLabel.Position = UDim2.new(0, 16, 0, 12)
			titleLabel.Size = UDim2.new(1, -32, 0, 22)
			titleLabel.BackgroundTransparency = 1
			titleLabel.Font = Enum.Font.FredokaOne
			titleLabel.TextSize = 18
			titleLabel.TextXAlignment = Enum.TextXAlignment.Left
			titleLabel.TextColor3 = TITLE_COLOR
			titleLabel.Text = ""
			titleLabel.Parent = panel

			local subtitleLabel = Instance.new("TextLabel")
			subtitleLabel.Name = "Subtitle"
			subtitleLabel.Position = UDim2.new(0, 16, 0, 40)
			subtitleLabel.Size = UDim2.new(1, -32, 0, 20)
			subtitleLabel.BackgroundTransparency = 1
			subtitleLabel.Font = Enum.Font.FredokaOne
			subtitleLabel.TextSize = 13
			subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
			subtitleLabel.TextColor3 = DESCRIPTION_COLOR
			subtitleLabel.Text = ""
			subtitleLabel.Parent = panel

			return backdrop, PanelMotion.new(panel, backdrop), titleLabel, subtitleLabel
		end

		-- Shared "top-center status" text -- plain transparent background, FredokaOne + black
		-- stroke, no pill/background box (distinct from createInfoCard's cream cards above, which
		-- have real title+subtitle content and, for MapPick, buttons). Used for every plain
		-- single-line status message pinned to the top-center slot: the Loading label and the
		-- NotInRound pill (which itself covers both "Round in Progress" and "Round ending..." --
		-- same widget, different text depending on state). These used to be two different designs
		-- (Loading was plain text; NotInRound was a dark rounded pill with a white stroke) -- now
		-- both share this one builder so they read as the same kind of status message.
		local function createStatusLabel(textSize)
			local backdrop = Instance.new("Frame")
			backdrop.Name = "Backdrop"
			backdrop.Active = false
			backdrop.AnchorPoint = Vector2.new(0.5, 0)
			backdrop.Position = UDim2.new(0.5, 0, 0, 24)
			backdrop.Size = UDim2.new(0, 280, 0, 52)
			backdrop.BackgroundTransparency = 1
			backdrop.Visible = false
			backdrop.Parent = screenGui

			local label = Instance.new("TextLabel")
			label.Name = "Label"
			label.Size = UDim2.new(1, 0, 1, 0)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.FredokaOne
			label.TextSize = textSize
			label.TextColor3 = Color3.fromRGB(255, 240, 220)
			label.Text = ""
			label.Parent = backdrop

			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.new(0, 0, 0)
			stroke.Transparency = 0.4
			stroke.Thickness = 2
			stroke.Parent = label

			return backdrop, PanelMotion.new(label, backdrop), label
		end

		-- Shown during Intermission -- a live "Starting in Ns..." countdown to the next round.
		local _, intermissionMotion, intermissionTitle, intermissionSubtitle = createInfoCard()
		intermissionTitle.Text = "Next Round"

		-- Shown instead of the Intermission/MapPick cards whenever the local player is currently
		-- marked AFK (AFKUI.luau's toggle, RoundSystem.luau's IsAFK attribute) -- they're sitting
		-- this round out, so neither "Starting in Ns..." nor a vote panel they can't use applies to
		-- them. Covers every pre-round Lobby phase (Intermission/MapPick/MapTally/MapResult); once
		-- Loading actually begins they get the existing NotInRound pill instead (see below), same as
		-- any other non-participant.
		local _, afkMotion, afkTitle, afkSubtitle = createInfoCard()
		afkTitle.Text = "You're AFK"
		afkSubtitle.Text = "Toggle off to join the next round!"

		-- Shown during Loading (map revealing/building, before anyone's teleported in).
		local _, loadingMotion, loadingLabel = createStatusLabel(26)
		loadingLabel.Text = "Loading map..."

		-- Big "3... 2... 1... GO" number, dead center -- shown once the numeric countdown phase
		-- actually starts (after the map-title flash below has already played). Wrapped in its own
		-- invisible backdrop purely so PanelMotion has a Frame pair to pop/hide.
		local countdownBackdrop = Instance.new("Frame")
		countdownBackdrop.Name = "CountdownBackdrop"
		countdownBackdrop.Active = false
		countdownBackdrop.AnchorPoint = Vector2.new(0.5, 0.5)
		countdownBackdrop.Position = UDim2.new(0.5, 0, 0.4, 0)
		countdownBackdrop.Size = UDim2.new(0, 240, 0, 160)
		countdownBackdrop.BackgroundTransparency = 1
		countdownBackdrop.Visible = false
		countdownBackdrop.Parent = screenGui

		local countdownLabel = Instance.new("TextLabel")
		countdownLabel.Name = "CountdownLabel"
		countdownLabel.Size = UDim2.new(1, 0, 1, 0)
		countdownLabel.BackgroundTransparency = 1
		countdownLabel.Font = Enum.Font.FredokaOne
		countdownLabel.TextSize = 96
		countdownLabel.TextColor3 = Color3.fromRGB(255, 221, 170)
		countdownLabel.Text = ""
		countdownLabel.Parent = countdownBackdrop

		local countdownStroke = Instance.new("UIStroke")
		countdownStroke.Color = Color3.new(0, 0, 0)
		countdownStroke.Transparency = 0.3
		countdownStroke.Thickness = 3
		countdownStroke.Parent = countdownLabel

		local countdownMotion = PanelMotion.new(countdownLabel, countdownBackdrop)

		-- Shown during Active -- a small persistent "time left this round" pill, same top-center
		-- slot the Start button/Loading label use (never visible at the same time as either, since
		-- they're all gated to mutually exclusive RoundStates). Same backdrop-wrap pattern as the
		-- countdown above.
		local roundTimerBackdrop = Instance.new("Frame")
		roundTimerBackdrop.Name = "RoundTimerBackdrop"
		roundTimerBackdrop.Active = false
		roundTimerBackdrop.AnchorPoint = Vector2.new(0.5, 0)
		roundTimerBackdrop.Position = UDim2.new(0.5, 0, 0, 24)
		roundTimerBackdrop.Size = UDim2.new(0, 140, 0, 44)
		roundTimerBackdrop.BackgroundTransparency = 1
		roundTimerBackdrop.Visible = false
		roundTimerBackdrop.Parent = screenGui

		local roundTimerLabel = Instance.new("TextLabel")
		roundTimerLabel.Name = "RoundTimerLabel"
		roundTimerLabel.Size = UDim2.new(1, 0, 1, 0)
		roundTimerLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
		roundTimerLabel.BackgroundTransparency = 0.25
		roundTimerLabel.Font = Enum.Font.FredokaOne
		roundTimerLabel.TextSize = 24
		roundTimerLabel.TextColor3 = Color3.fromRGB(255, 240, 220)
		roundTimerLabel.Text = ""
		roundTimerLabel.Parent = roundTimerBackdrop

		local roundTimerCorner = Instance.new("UICorner")
		roundTimerCorner.CornerRadius = UDim.new(0, 10)
		roundTimerCorner.Parent = roundTimerLabel

		local roundTimerStroke = Instance.new("UIStroke")
		roundTimerStroke.Color = Color3.new(1, 1, 1)
		roundTimerStroke.Transparency = 0.75
		roundTimerStroke.Thickness = 1.25
		roundTimerStroke.Parent = roundTimerLabel

		local roundTimerMotion = PanelMotion.new(roundTimerLabel, roundTimerBackdrop)

		-- Shown in the SAME top-center slot as the round timer pill above, but only for players who
		-- are NOT part of the current round (RoundSystem.luau's per-player InActiveRound attribute
		-- -- false for anyone who joined after this round's players were already teleported onto the
		-- map). Covers Countdown/Active/Results, mutually exclusive with the timer pill/countdown
		-- number/results banner+leaderboard, which are all gated to inRound-only elsewhere in this
		-- file -- a non-participant just gets this one plain status message instead of any of that.
		-- Same createStatusLabel design as the Loading label above (used to be its own separate dark
		-- pill design with a white stroke -- now unified).
		local _, notInRoundMotion, notInRoundLabel = createStatusLabel(20)

		-- One shared big centered "flash" text -- reused for the pre-countdown map title ("THE
		-- YARD"), the Results-entry banner ("GOAL REACHED!"/"TIME'S UP!"), the MapTally pause
		-- ("Tallying votes...") and the MapResult reveal ("NEXT MAP" + name + difficulty/players),
		-- so every round-related announcement in the game reads the same way instead of each one
		-- inventing its own treatment. Same FredokaOne + black stroke look as countdownLabel above,
		-- and the same PanelMotion pop/fade as everything else in this file. Sized tall enough
		-- (170px) for the MapResult reveal's three lines; TextScaled handles the rest for shorter,
		-- single-line uses.
		local flashBackdrop = Instance.new("Frame")
		flashBackdrop.Name = "FlashBackdrop"
		flashBackdrop.Active = false
		flashBackdrop.AnchorPoint = Vector2.new(0.5, 0.5)
		flashBackdrop.Position = UDim2.new(0.5, 0, 0.4, 0)
		flashBackdrop.Size = UDim2.new(0, 700, 0, 170)
		flashBackdrop.BackgroundTransparency = 1
		flashBackdrop.Visible = false
		flashBackdrop.ZIndex = 25
		flashBackdrop.Parent = screenGui

		local flashLabel = Instance.new("TextLabel")
		flashLabel.Name = "FlashLabel"
		flashLabel.Size = UDim2.new(1, 0, 1, 0)
		flashLabel.BackgroundTransparency = 1
		flashLabel.Font = Enum.Font.FredokaOne
		flashLabel.TextScaled = true
		flashLabel.TextColor3 = Color3.fromRGB(255, 221, 170)
		flashLabel.Text = ""
		flashLabel.ZIndex = 25
		flashLabel.Parent = flashBackdrop

		local flashPadding = Instance.new("UIPadding")
		flashPadding.PaddingLeft = UDim.new(0, 12)
		flashPadding.PaddingRight = UDim.new(0, 12)
		flashPadding.Parent = flashLabel

		local flashStroke = Instance.new("UIStroke")
		flashStroke.Color = Color3.new(0, 0, 0)
		flashStroke.Transparency = 0.3
		flashStroke.Thickness = 3
		flashStroke.Parent = flashLabel

		local flashMotion = PanelMotion.new(flashLabel, flashBackdrop)

		-- Shown during MapPick, dead center -- a REAL vote, not a passive announcement: one compact
		-- row per ballot slot (name/difficulty on the left, a Vote button + live count on the
		-- right). Clicking fires SubmitMapVote even with only one map/one player on the roster, so
		-- the phase always reads as an actual choice being made, never skipped.
		-- Cream card background, same CARD_COLOR/CARD_STROKE/TITLE_COLOR/DESCRIPTION_COLOR theme as
		-- MapProgressUI, so this reads as a real panel you interact with -- not the flashy
		-- transparent big-text treatment used for the countdown/tally/result announcements, which
		-- doesn't suit something with buttons on it. The Vote button itself still reuses the old
		-- Start button's green-pill look.
		--
		-- Rows are a compact horizontal layout (~64px each) in a plain (non-scrolling) list, sized
		-- so all of them are always visible at once, no scrollbar. The card's width is Scale-based
		-- with a UISizeConstraint clamp (300-380px) instead of a flat pixel width, so it fits narrow
		-- mobile screens without overflowing edge-to-edge.
		--
		-- BALLOT_SIZE (not #MapConfig) is what the panel is sized/built for -- RoundSystem randomly
		-- samples RoundConfig.MapPickBallotSize maps out of the full MapConfig pool each round (see
		-- RoundMapPickCandidates below), so the pool can keep growing past 3 without ever needing
		-- this panel reworked again: it's always exactly BALLOT_SIZE rows, just re-labeled with
		-- whichever maps this round's ballot contains.
		local MAP_VOTE_ROW_HEIGHT = 64
		local MAP_PICK_HEADER_HEIGHT = 24
		local CARD_PADDING = 16
		local ROW_LIST_GAP = 8
		local BALLOT_SIZE = math.max(1, math.min(RoundConfig.MapPickBallotSize, #MapConfig))
		local mapPickRowListHeight = (BALLOT_SIZE * MAP_VOTE_ROW_HEIGHT) + (math.max(BALLOT_SIZE - 1, 0) * ROW_LIST_GAP)
		local mapPickPanelHeight = CARD_PADDING + MAP_PICK_HEADER_HEIGHT + 8 + mapPickRowListHeight + CARD_PADDING

		local mapPickBackdrop = Instance.new("Frame")
		mapPickBackdrop.Name = "MapPickBackdrop"
		mapPickBackdrop.Active = false
		mapPickBackdrop.AnchorPoint = Vector2.new(0.5, 0.5)
		mapPickBackdrop.Position = UDim2.new(0.5, 0, 0.45, 0)
		mapPickBackdrop.Size = UDim2.new(0.86, 0, 0, mapPickPanelHeight)
		mapPickBackdrop.BackgroundTransparency = 1
		mapPickBackdrop.Visible = false
		mapPickBackdrop.ZIndex = 25
		mapPickBackdrop.Parent = screenGui

		-- Clamps the card's actual on-screen width between a phone-safe minimum and a desktop-sane
		-- maximum, so the 0.86-scale Size above tracks the viewport instead of a single fixed pixel
		-- width that would either overflow a narrow phone or look tiny on a wide monitor.
		local mapPickSizeConstraint = Instance.new("UISizeConstraint")
		mapPickSizeConstraint.MinSize = Vector2.new(300, 0)
		mapPickSizeConstraint.MaxSize = Vector2.new(380, 10000)
		mapPickSizeConstraint.Parent = mapPickBackdrop

		local mapPickPanel = Instance.new("Frame")
		mapPickPanel.Name = "Panel"
		mapPickPanel.Size = UDim2.new(1, 0, 1, 0)
		mapPickPanel.BackgroundColor3 = CARD_COLOR
		mapPickPanel.BorderSizePixel = 0
		mapPickPanel.ZIndex = 25
		mapPickPanel.Parent = mapPickBackdrop

		local mapPickPanelCorner = Instance.new("UICorner")
		mapPickPanelCorner.CornerRadius = UDim.new(0, 16)
		mapPickPanelCorner.Parent = mapPickPanel

		local mapPickPanelStroke = Instance.new("UIStroke")
		mapPickPanelStroke.Color = CARD_STROKE
		mapPickPanelStroke.Transparency = 0.2
		mapPickPanelStroke.Thickness = 1.5
		mapPickPanelStroke.Parent = mapPickPanel

		local mapPickHeader = Instance.new("TextLabel")
		mapPickHeader.Name = "Header"
		mapPickHeader.Position = UDim2.new(0, 0, 0, CARD_PADDING)
		mapPickHeader.Size = UDim2.new(1, 0, 0, MAP_PICK_HEADER_HEIGHT)
		mapPickHeader.BackgroundTransparency = 1
		mapPickHeader.Font = Enum.Font.FredokaOne
		mapPickHeader.TextSize = 18
		mapPickHeader.TextColor3 = TITLE_COLOR
		mapPickHeader.Text = "Vote for the next map"
		mapPickHeader.ZIndex = 26
		mapPickHeader.Parent = mapPickPanel

		local rowList = Instance.new("Frame")
		rowList.Name = "RowList"
		rowList.Position = UDim2.new(0, CARD_PADDING, 0, CARD_PADDING + MAP_PICK_HEADER_HEIGHT + 8)
		rowList.Size = UDim2.new(1, -CARD_PADDING * 2, 0, mapPickRowListHeight)
		rowList.BackgroundTransparency = 1
		rowList.ZIndex = 26
		rowList.Parent = mapPickPanel

		local rowListLayout = Instance.new("UIListLayout")
		rowListLayout.FillDirection = Enum.FillDirection.Vertical
		rowListLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowListLayout.Padding = UDim.new(0, ROW_LIST_GAP)
		rowListLayout.Parent = rowList

		local VOTE_BUTTON_COLOR = Color3.fromRGB(110, 200, 130)
		local VOTED_BUTTON_COLOR = Color3.fromRGB(80, 170, 105)

		-- mapById: MapConfig Id -> entry, so a ballot (just a list of Ids from the server) can be
		-- turned back into DisplayName/Category/RecommendedPlayers without a server round-trip.
		local mapById = {}
		for _, mapEntry in ipairs(MapConfig) do
			mapById[mapEntry.Id] = mapEntry
		end

		-- `mapVoteRows[mapId]` -> the row slot currently showing that map, so vote-tally updates and
		-- the local "which one did I pick" highlight can both be applied per row without rescanning
		-- children. Rebuilt (not recreated) every ballot -- see applyBallot below.
		local mapVoteRows = {}
		local myMapVote = nil

		local function refreshMapVoteButtons()
			for id, row in pairs(mapVoteRows) do
				if id == myMapVote then
					row.Button.Text = "Voted ✓"
					row.Button.BackgroundColor3 = VOTED_BUTTON_COLOR
				else
					row.Button.Text = "Vote"
					row.Button.BackgroundColor3 = VOTE_BUTTON_COLOR
				end
			end
		end

		-- BALLOT_SIZE reusable row slots, built once and re-labeled every round instead of being
		-- torn down and rebuilt -- a row's Vote button doesn't capture a specific map at creation
		-- time (it can't, the map it represents changes round to round); it reads whichever mapId
		-- applyBallot most recently stamped onto its "MapId" attribute at click time instead.
		local rowSlots = {}
		for index = 1, BALLOT_SIZE do
			-- Subtle background per row (barely-tinted, same warm family as CARD_COLOR/CARD_STROKE)
			-- so compact rows still read as distinct candidates rather than running together.
			local row = Instance.new("Frame")
			row.Name = "Row" .. index
			row.LayoutOrder = index
			row.Size = UDim2.new(1, 0, 0, MAP_VOTE_ROW_HEIGHT)
			row.BackgroundColor3 = Color3.fromRGB(245, 238, 226)
			row.BorderSizePixel = 0
			row.ZIndex = 26
			row.Parent = rowList

			local rowCorner = Instance.new("UICorner")
			rowCorner.CornerRadius = UDim.new(0, 10)
			rowCorner.Parent = row

			-- Left: map name + difficulty/players, stacked and left-aligned. Right: Vote button +
			-- live count, stacked and right-aligned -- a horizontal split instead of a vertical stack
			-- is what keeps each row short enough for all of them to fit without scrolling.
			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "MapName"
			nameLabel.Position = UDim2.new(0, 12, 0, 8)
			nameLabel.Size = UDim2.new(0.56, -12, 0, 22)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Font = Enum.Font.FredokaOne
			nameLabel.TextSize = 18
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextColor3 = TITLE_COLOR
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.Text = ""
			nameLabel.ZIndex = 27
			nameLabel.Parent = row

			local infoLabel = Instance.new("TextLabel")
			infoLabel.Name = "Info"
			infoLabel.Position = UDim2.new(0, 12, 0, 32)
			infoLabel.Size = UDim2.new(0.56, -12, 0, 24)
			infoLabel.BackgroundTransparency = 1
			infoLabel.Font = Enum.Font.FredokaOne
			infoLabel.TextSize = 12
			infoLabel.TextXAlignment = Enum.TextXAlignment.Left
			infoLabel.TextWrapped = true
			infoLabel.TextColor3 = DESCRIPTION_COLOR
			infoLabel.Text = ""
			infoLabel.ZIndex = 27
			infoLabel.Parent = row

			local voteButton = Instance.new("TextButton")
			voteButton.Name = "VoteButton"
			voteButton.AnchorPoint = Vector2.new(1, 0)
			voteButton.Position = UDim2.new(1, -12, 0, 10)
			-- 44px tall -- a touch-friendly minimum tap target, not just a desktop click target.
			voteButton.Size = UDim2.new(0, 92, 0, 34)
			voteButton.BackgroundColor3 = VOTE_BUTTON_COLOR
			voteButton.Font = Enum.Font.FredokaOne
			voteButton.TextSize = 15
			voteButton.TextColor3 = Color3.new(1, 1, 1)
			voteButton.Text = "Vote"
			voteButton.ZIndex = 27
			voteButton.Parent = row

			local voteButtonCorner = Instance.new("UICorner")
			voteButtonCorner.CornerRadius = UDim.new(0, 10)
			voteButtonCorner.Parent = voteButton

			local voteButtonStroke = Instance.new("UIStroke")
			voteButtonStroke.Color = Color3.new(0, 0, 0)
			voteButtonStroke.Transparency = 0.6
			voteButtonStroke.Thickness = 1.5
			voteButtonStroke.Parent = voteButton

			PanelMotion.AnimateButton(voteButton)

			local countLabel = Instance.new("TextLabel")
			countLabel.Name = "Count"
			countLabel.AnchorPoint = Vector2.new(1, 0)
			countLabel.Position = UDim2.new(1, -12, 0, 46)
			countLabel.Size = UDim2.new(0, 92, 0, 14)
			countLabel.BackgroundTransparency = 1
			countLabel.Font = Enum.Font.FredokaOne
			countLabel.TextSize = 11
			countLabel.TextXAlignment = Enum.TextXAlignment.Right
			countLabel.TextColor3 = DESCRIPTION_COLOR
			countLabel.Text = "0 votes"
			countLabel.ZIndex = 27
			countLabel.Parent = row

			voteButton.Activated:Connect(function()
				local mapId = voteButton:GetAttribute("MapId")
				if not mapId then
					return
				end
				mapVoteRemote:FireServer(mapId)
				myMapVote = mapId
				refreshMapVoteButtons()
			end)

			rowSlots[index] = { Row = row, NameLabel = nameLabel, InfoLabel = infoLabel, Button = voteButton, CountLabel = countLabel }
		end

		-- Reads RoundMapPickCandidates (comma-separated MapConfig Ids, set fresh every MapPick
		-- phase by RoundSystem's pickRandomBallot) and re-labels the fixed row slots above to match
		-- -- this is what actually makes the panel show a different random subset/order each round
		-- instead of the same fixed list every time.
		local function applyBallot()
			local candidatesAttr = Workspace:GetAttribute("RoundMapPickCandidates") or ""
			mapVoteRows = {}
			local index = 0
			for id in string.gmatch(candidatesAttr, "[^,]+") do
				index += 1
				local slot = rowSlots[index]
				if not slot then
					break
				end
				local mapEntry = mapById[id]
				if mapEntry then
					slot.NameLabel.Text = mapEntry.DisplayName
					slot.InfoLabel.Text = string.format("%s · %s players", mapEntry.Category or "", mapEntry.RecommendedPlayers or "")
					slot.CountLabel.Text = "0 votes"
					slot.Row.Visible = true
					slot.Button:SetAttribute("MapId", id)
					mapVoteRows[id] = slot
				end
			end
			-- A ballot smaller than BALLOT_SIZE (only possible if MapConfig itself has fewer entries
			-- than RoundConfig.MapPickBallotSize) hides any leftover unlabeled slots instead of
			-- showing an empty row.
			for i = index + 1, BALLOT_SIZE do
				rowSlots[i].Row.Visible = false
			end
			refreshMapVoteButtons()
		end

		Workspace:GetAttributeChangedSignal("RoundMapPickToken"):Connect(applyBallot)
		applyBallot()

		mapVoteUpdateRemote.OnClientEvent:Connect(function(counts)
			for id, row in pairs(mapVoteRows) do
				local count = (counts and counts[id]) or 0
				row.CountLabel.Text = string.format("%d vote%s", count, count == 1 and "" or "s")
			end
		end)

		local mapPickMotion = PanelMotion.new(mapPickPanel, mapPickBackdrop)

		-- Full-screen fade overlay for Lobby<->map transitions -- server tells us Out/In + a
		-- duration (RoundScreenFade remote) around the moment it actually teleports us, so the
		-- teleport itself always happens while this is opaque, never visible as a jump-cut.
		local fadeOverlay = Instance.new("Frame")
		fadeOverlay.Name = "FadeOverlay"
		fadeOverlay.Size = UDim2.new(1, 0, 1, 0)
		fadeOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
		fadeOverlay.BackgroundTransparency = 1
		fadeOverlay.BorderSizePixel = 0
		fadeOverlay.Visible = false
		fadeOverlay.ZIndex = 50
		fadeOverlay.Parent = screenGui

		screenGui.Parent = playerGui

		-- Edge-triggered (only calls Show()/Hide() when the card's own visibility condition
		-- actually flips), same reasoning as countdownShown/roundTimerShown below -- PanelMotion
		-- plays a fresh tween every call, so calling it on every RoundState signal firing (even a
		-- no-op re-set of the same state) would restart the tween needlessly. In practice RoundState
		-- only ever fires on a real change, but this stays correct even if that ever isn't true.
		local intermissionCardShown = false
		local mapPickCardShown = false
		local afkCardShown = false
		local loadingShown = false

		local function applyState(roundState)
			local isAFK = player:GetAttribute("IsAFK") == true

			-- Not shown to an AFK player -- they get the AFK card instead (see showAfkCard below),
			-- since "Loading map..." would misleadingly suggest they're about to be part of it.
			local showLoading = roundState == "Loading" and not isAFK
			if showLoading and not loadingShown then
				loadingShown = true
				loadingMotion.Show()
			elseif not showLoading and loadingShown then
				loadingShown = false
				loadingMotion.Hide()
			end

			local showIntermission = roundState == "Intermission" and not isAFK
			if showIntermission and not intermissionCardShown then
				intermissionCardShown = true
				intermissionMotion.Show()
			elseif not showIntermission and intermissionCardShown then
				intermissionCardShown = false
				intermissionMotion.Hide()
			end

			local showMapPick = roundState == "MapPick" and not isAFK
			if showMapPick and not mapPickCardShown then
				mapPickCardShown = true
				-- Fresh vote every phase -- a vote from a previous round (or a stale local click)
				-- must never carry over and pre-select a button before the player's chosen anything
				-- this time. The server already resets its own tally at the start of every
				-- runMapPick() and broadcasts the zero count; this just matches that client-side.
				myMapVote = nil
				refreshMapVoteButtons()
				mapPickMotion.Show()
			elseif not showMapPick and mapPickCardShown then
				mapPickCardShown = false
				mapPickMotion.Hide()
			end

			-- Includes Loading -- the player hasn't actually been teleported anywhere during it (see
			-- RoundSystem.luau's IsAFK doc comment), same reasoning AFKUI.luau's toggle-allowed
			-- window uses, so the AFK card should still cover them right up until Countdown.
			local showAfkCard = isAFK and (
				roundState == "Intermission"
				or roundState == "MapPick"
				or roundState == "MapTally"
				or roundState == "MapResult"
				or roundState == "Loading"
			)
			if showAfkCard and not afkCardShown then
				afkCardShown = true
				afkMotion.Show()
			elseif not showAfkCard and afkCardShown then
				afkCardShown = false
				afkMotion.Hide()
			end
		end

		Workspace:GetAttributeChangedSignal("RoundState"):Connect(function()
			applyState(Workspace:GetAttribute("RoundState"))
		end)
		-- IsAFK can flip without RoundState changing at all (toggling the icon while sitting in
		-- Intermission, say) -- re-run the same state logic off the current RoundState so the
		-- Intermission/MapPick/AFK cards swap immediately instead of waiting for the next RoundState
		-- signal.
		player:GetAttributeChangedSignal("IsAFK"):Connect(function()
			applyState(Workspace:GetAttribute("RoundState"))
		end)
		applyState(Workspace:GetAttribute("RoundState") or "Intermission")

		screenFadeRemote.OnClientEvent:Connect(function(direction, duration)
			duration = duration or RoundConfig.FadeSeconds
			if direction == "Out" then
				fadeOverlay.Visible = true
				TweenService:Create(fadeOverlay, TweenInfo.new(duration, Enum.EasingStyle.Quad), {
					BackgroundTransparency = 0,
				}):Play()
			else
				local tween = TweenService:Create(fadeOverlay, TweenInfo.new(duration, Enum.EasingStyle.Quad), {
					BackgroundTransparency = 1,
				})
				tween:Play()
				tween.Completed:Connect(function(playbackState)
					if playbackState == Enum.PlaybackState.Completed then
						fadeOverlay.Visible = false
					end
				end)
			end
		end)

		-- Pop in, hold, pop out via PanelMotion. `flashToken` guards against a stale deferred Hide()
		-- (from an older call whose hold just elapsed) clobbering a newer call that already started
		-- its own Show() -- PanelMotion's own Show()/Hide() already cancel any in-flight tween of
		-- theirs when called again, so this only needs to stop the *scheduling*, not the animation.
		local flashToken = 0
		local function showFlash(text, holdSeconds)
			flashToken += 1
			local myToken = flashToken

			flashLabel.Text = text
			flashMotion.Show()

			task.wait(holdSeconds)
			if myToken ~= flashToken then
				return
			end
			flashMotion.Hide()
		end

		-- RoundMapTitleToken bumps every round even when the same map is picked twice in a row (see
		-- RoundSystem.luau's comment on why RoundMapTitle's text alone can't be trusted to change).
		-- Gated on InActiveRound -- this fires right after the round's own teleport, so a player who
		-- isn't part of this round (still in the Lobby) shouldn't see it flash a map name for a
		-- round they're not on.
		Workspace:GetAttributeChangedSignal("RoundMapTitleToken"):Connect(function()
			local title = Workspace:GetAttribute("RoundMapTitle")
			if title and player:GetAttribute("InActiveRound") == true then
				task.spawn(showFlash, title, math.max(RoundConfig.MapTitleFlashSeconds - 0.6, 0.8))
			end
		end)

		-- RoundMapResultToken (same always-changing-token reasoning as RoundMapTitleToken above) is
		-- the vote's own reveal -- fires right as RoundState enters MapResult, right after the
		-- MapTally pause below, showing which map actually won.
		Workspace:GetAttributeChangedSignal("RoundMapResultToken"):Connect(function()
			local mapName = Workspace:GetAttribute("RoundMapResultName")
			if mapName then
				local category = Workspace:GetAttribute("RoundMapResultCategory")
				local recommendedPlayers = Workspace:GetAttribute("RoundMapResultPlayers")
				local text = string.format(
					"NEXT MAP\n%s\n%s · %s players recommended",
					mapName, category or "", recommendedPlayers or ""
				)
				task.spawn(showFlash, text, RoundConfig.MapResultSeconds)
			end
		end)

		Workspace:GetAttributeChangedSignal("RoundState"):Connect(function()
			local roundState = Workspace:GetAttribute("RoundState")
			-- Results banner gated on InActiveRound (same reasoning as the map-title flash above --
			-- "round results" shouldn't announce itself to someone who wasn't in the round). MapTally
			-- is deliberately NOT gated -- it's part of the shared pre-round vote, which still applies
			-- to everyone connected at the time.
			if roundState == "Results" and player:GetAttribute("InActiveRound") == true then
				local reason = Workspace:GetAttribute("RoundEndReason")
				local text = reason == "Goal" and "GOAL REACHED!" or "TIME'S UP!"
				task.spawn(showFlash, text, RoundConfig.ResultsBannerHoldSeconds)
			elseif roundState == "MapTally" then
				task.spawn(showFlash, "Tallying votes...", RoundConfig.MapTallySeconds)
			end
		end)

		-- Both computed fresh from the server clock every frame while visible (RoundCountdownEndsAt/
		-- RoundEndsAt, Workspace:GetServerTimeNow()) rather than counting down locally, so neither
		-- can drift out of sync with when the server actually changes state -- same pattern
		-- LeafMotion/MapProgressUI already use for anything timing-sensitive. Show()/Hide() are only
		-- called on the rising/falling edge (tracked via the two `*Shown` flags) since PanelMotion
		-- plays a fresh tween every call -- calling it every frame would spam tweens.
		local countdownShown = false
		local roundTimerShown = false
		local notInRoundShown = false

		RunService.Heartbeat:Connect(function()
			local roundState = Workspace:GetAttribute("RoundState")
			local inRound = player:GetAttribute("InActiveRound") == true

			-- countdownEndsAt is nil during the map-title-flash phase (RoundSystem clears it at the
			-- start of every Loading and only sets it once the flash finishes), so this label simply
			-- doesn't show until the real numeric countdown begins. Also gated on inRound -- a
			-- non-participant gets the NotInRound pill below instead.
			local countdownEndsAt = Workspace:GetAttribute("RoundCountdownEndsAt")
			local showCountdown = roundState == "Countdown" and countdownEndsAt ~= nil and inRound
			if showCountdown and not countdownShown then
				countdownShown = true
				countdownMotion.Show()
			elseif not showCountdown and countdownShown then
				countdownShown = false
				countdownMotion.Hide()
			end
			if showCountdown then
				local remaining = countdownEndsAt - Workspace:GetServerTimeNow()
				countdownLabel.Text = remaining <= 0 and "GO!" or tostring(math.ceil(remaining))
			end

			local showRoundTimer = roundState == "Active" and inRound
			if showRoundTimer and not roundTimerShown then
				roundTimerShown = true
				roundTimerMotion.Show()
			elseif not showRoundTimer and roundTimerShown then
				roundTimerShown = false
				roundTimerMotion.Hide()
			end
			if showRoundTimer then
				local endsAt = Workspace:GetAttribute("RoundEndsAt")
				if endsAt then
					local remaining = math.max(endsAt - Workspace:GetServerTimeNow(), 0)
					local minutes = math.floor(remaining / 60)
					local seconds = math.floor(remaining % 60)
					roundTimerLabel.Text = string.format("%d:%02d", minutes, seconds)
				end
			end

			-- Same top-center slot as the countdown/timer above, shown instead of them whenever this
			-- player isn't part of the current round -- covers the same three states (Countdown/
			-- Active/Results) those and the results banner+leaderboard are gated to.
			local notInRoundText = nil
			if not inRound then
				if roundState == "Countdown" or roundState == "Active" then
					notInRoundText = "Round in Progress"
				elseif roundState == "Results" then
					notInRoundText = "Round ending..."
				end
			end
			local showNotInRound = notInRoundText ~= nil
			if showNotInRound and not notInRoundShown then
				notInRoundShown = true
				notInRoundMotion.Show()
			elseif not showNotInRound and notInRoundShown then
				notInRoundShown = false
				notInRoundMotion.Hide()
			end
			if showNotInRound then
				notInRoundLabel.Text = notInRoundText
			end

			-- The Intermission card's Show()/Hide() is edge-triggered in applyState above (fires once
			-- on the RoundState change) -- this just keeps its subtitle text ticking down while it's
			-- up, same server-clock-driven pattern as the countdown/timer above. RoundIntermissionEndsAt
			-- stays nil (see RoundSystem.runIntermission) until at least one player is actually active,
			-- so there's a real "nothing to count down to yet" state to show here, not just a blank.
			if roundState == "Intermission" then
				local endsAt = Workspace:GetAttribute("RoundIntermissionEndsAt")
				if endsAt then
					local remaining = math.max(math.ceil(endsAt - Workspace:GetServerTimeNow()), 0)
					intermissionSubtitle.Text = string.format("Starting in %ds...", remaining)
				else
					intermissionSubtitle.Text = "Waiting for players..."
				end
			end
		end)
	end)
end

return RoundUI
