local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- A REAL physical board in the Lobby (Workspace.StartingLobby.HallOfFameBoard, placed via direct
-- rbxlx surgery -- see CLAUDE.md's "Building a new map" process for why Workspace geometry can't be
-- added any other way) showing the all-time top players by lifetime leaves cleaned
-- (HallOfFameSystem.luau, server, backed by an OrderedDataStore). A SurfaceGui, not a BillboardGui
-- and not a screen-space ScreenGui panel -- SurfaceGui reads as a genuine sign/plaque mounted on the
-- world object, the same choice this project already made for every Cleanup Zone sign. Needs no
-- explicit visibility gating at all -- it's simply not visible once a round teleports a player
-- RoundConfig.MapAwayOffset (10,000 studs) away from the Lobby, the same way every other physical
-- Lobby prop (the NPC rigs, the shop booth) already works with zero code for it.
--
-- Rendered on BOTH Front and Back faces (two SurfaceGuis, identical content) rather than picking one
-- -- the board's actual placement/rotation in leaf.rbxlx isn't something this script controls (the
-- user repositions/re-orients it by hand in Studio, same as every other piece of map geometry -- see
-- CLAUDE.md), so hand-computing "which single face is the readable one" from its CFrame would silently
-- break the instant it's moved/rotated again. Double-siding costs nothing meaningful (two static text
-- panels) and removes that fragility entirely.
local HallOfFameUI = {}

local TITLE_COLOR = Color3.fromRGB(255, 236, 200)
local RANK_COLOR = Color3.fromRGB(214, 180, 140)
local NAME_COLOR = Color3.fromRGB(240, 228, 210)
local COUNT_COLOR = Color3.fromRGB(214, 180, 140)
local YOU_NAME_COLOR = Color3.fromRGB(120, 190, 255)
local PLACEHOLDER_COLOR = Color3.fromRGB(180, 160, 140)
local BACKGROUND_COLOR = Color3.fromRGB(24, 24, 28)
local ACCENT_COLOR = Color3.fromRGB(90, 200, 255)

-- Same medal glyphs RoundResultsUI.luau's own top-3 rows use, so a top-3 Hall of Fame entry reads
-- consistently with a top-3 round finish rather than inventing a new look.
local RANK_MEDALS = { [1] = "\u{1F947}", [2] = "\u{1F948}", [3] = "\u{1F949}" }

local MAX_ROWS = 15
local TITLE_HEIGHT_SCALE = 0.09
local ROW_GAP = 0.015

local function buildFaceUI(board, face)
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "HallOfFameSurface" .. face.Name
	surfaceGui.Face = face
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = 60
	surfaceGui.LightInfluence = 0
	surfaceGui.Parent = board

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.new(1, 0, 1, 0)
	background.BackgroundColor3 = BACKGROUND_COLOR
	background.BorderSizePixel = 0
	background.Parent = surfaceGui

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = background

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, TITLE_HEIGHT_SCALE, 0)
	title.Font = Enum.Font.FredokaOne
	title.Text = "TOP PLAYERS"
	title.TextColor3 = TITLE_COLOR
	title.TextScaled = true
	title.Parent = background

	local titleUnderline = Instance.new("Frame")
	titleUnderline.Name = "Underline"
	titleUnderline.Position = UDim2.new(0, 0, TITLE_HEIGHT_SCALE, 0)
	titleUnderline.Size = UDim2.new(1, 0, 0, 2)
	titleUnderline.BackgroundColor3 = ACCENT_COLOR
	titleUnderline.BorderSizePixel = 0
	titleUnderline.Parent = background

	local rowsFrame = Instance.new("Frame")
	rowsFrame.Name = "Rows"
	rowsFrame.BackgroundTransparency = 1
	rowsFrame.Position = UDim2.new(0, 0, TITLE_HEIGHT_SCALE + ROW_GAP, 0)
	rowsFrame.Size = UDim2.new(1, 0, 1 - TITLE_HEIGHT_SCALE - ROW_GAP, 0)
	rowsFrame.Parent = background

	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.FillDirection = Enum.FillDirection.Vertical
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowsLayout.Parent = rowsFrame

	local placeholderLabel = Instance.new("TextLabel")
	placeholderLabel.Name = "Placeholder"
	placeholderLabel.LayoutOrder = 1
	placeholderLabel.BackgroundTransparency = 1
	placeholderLabel.Size = UDim2.new(1, 0, 1 / MAX_ROWS, 0)
	placeholderLabel.Font = Enum.Font.Gotham
	placeholderLabel.Text = "No scores yet -- be the first!"
	placeholderLabel.TextColor3 = PLACEHOLDER_COLOR
	placeholderLabel.TextScaled = true
	placeholderLabel.TextXAlignment = Enum.TextXAlignment.Left
	placeholderLabel.Parent = rowsFrame

	return rowsFrame, placeholderLabel
end

local function buildRow(parent, layoutOrder, rank, name, value, isLocalPlayer)
	local row = Instance.new("Frame")
	row.Name = "Row" .. layoutOrder
	row.LayoutOrder = layoutOrder
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 1 / MAX_ROWS, 0)
	row.Parent = parent

	local rankLabel = Instance.new("TextLabel")
	rankLabel.Name = "Rank"
	rankLabel.BackgroundTransparency = 1
	rankLabel.Size = UDim2.new(0.14, 0, 1, 0)
	rankLabel.Font = Enum.Font.FredokaOne
	rankLabel.Text = RANK_MEDALS[rank] or ("#" .. rank)
	rankLabel.TextColor3 = RANK_COLOR
	rankLabel.TextScaled = true
	rankLabel.TextXAlignment = Enum.TextXAlignment.Left
	rankLabel.Parent = row

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.new(0.16, 0, 0, 0)
	nameLabel.Size = UDim2.new(0.6, 0, 1, 0)
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.Text = name
	nameLabel.TextColor3 = isLocalPlayer and YOU_NAME_COLOR or NAME_COLOR
	nameLabel.TextScaled = true
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = row

	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "Count"
	countLabel.BackgroundTransparency = 1
	countLabel.AnchorPoint = Vector2.new(1, 0)
	countLabel.Position = UDim2.new(1, 0, 0, 0)
	countLabel.Size = UDim2.new(0.24, 0, 1, 0)
	countLabel.Font = Enum.Font.Gotham
	countLabel.Text = string.format("%d", value)
	countLabel.TextColor3 = COUNT_COLOR
	countLabel.TextScaled = true
	countLabel.TextXAlignment = Enum.TextXAlignment.Right
	countLabel.Parent = row
end

local function fillRows(rowsFrame, placeholderLabel, player, entries)
	for _, child in ipairs(rowsFrame:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	if not entries or #entries == 0 then
		local clone = placeholderLabel:Clone()
		clone.Parent = rowsFrame
		return
	end

	for i, entry in ipairs(entries) do
		if i > MAX_ROWS then
			break
		end
		buildRow(rowsFrame, i, i, entry.Name, entry.Value, entry.Name == player.Name)
	end
end

function HallOfFameUI.Start()
	local player = Players.LocalPlayer

	task.spawn(function()
		-- Recursive lookup (StartingLobby, not straight under Workspace), same reasoning as
		-- NPCDialogueUI.buildPortraitInto's own rig lookup. StreamingEnabled means the Lobby's own
		-- content can take a moment to actually stream in, so this retries for a while instead of
		-- giving up on the very first miss.
		local board = Workspace:FindFirstChild("HallOfFameBoard", true)
		if not board then
			local deadline = os.clock() + 15
			while not board and os.clock() < deadline do
				task.wait(0.5)
				board = Workspace:FindFirstChild("HallOfFameBoard", true)
			end
		end
		if not board then
			warn("[HallOfFameUI] Workspace...HallOfFameBoard not found after 15s -- leaderboard display disabled this session.")
			return
		end

		local existing = board:FindFirstChild("HallOfFameSurfaceFront") or board:FindFirstChild("HallOfFameSurfaceBack")
		if existing then
			for _, child in ipairs(board:GetChildren()) do
				if child:IsA("SurfaceGui") then
					child:Destroy()
				end
			end
		end

		local frontRows, frontPlaceholder = buildFaceUI(board, Enum.NormalId.Front)
		local backRows, backPlaceholder = buildFaceUI(board, Enum.NormalId.Back)

		local function rebuildRows(entries)
			fillRows(frontRows, frontPlaceholder, player, entries)
			fillRows(backRows, backPlaceholder, player, entries)
		end

		local remotes = ReplicatedStorage.Shared:WaitForChild("Remotes", 15)
		local hallOfFameUpdatedRemote = remotes and remotes:WaitForChild("HallOfFameUpdated", 15)
		if not hallOfFameUpdatedRemote then
			warn("[HallOfFameUI] HallOfFameUpdated remote not found after 15s -- leaderboard display disabled this session.")
			return
		end

		hallOfFameUpdatedRemote.OnClientEvent:Connect(rebuildRows)
	end)
end

return HallOfFameUI
