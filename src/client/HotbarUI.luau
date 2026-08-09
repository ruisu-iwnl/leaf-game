local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ToolIcons = require(script.Parent.ToolIcons)
local UILayout = require(script.Parent.UILayout)

-- Replaces Roblox's default Backpack hotbar (the numbered tool-slot bar) with our own, bottom-
-- right. Same autumn-toned rounded-card look as the player list panel. Icons come from
-- ToolIcons.luau (shared with InventoryUI), built from plain Frames using each tool's own real
-- colors, not text glyphs or images -- keeps them recognizable and immune to the font-glyph gaps
-- that bit the coin/chevron/gear icons earlier.
local HotbarUI = {}

local EDGE_MARGIN = UILayout.HotbarEdgeMargin
local CARD_SIZE = UILayout.HotbarCardSize
local CARD_COLOR = Color3.fromRGB(58, 34, 20)
local CARD_STROKE = Color3.fromRGB(210, 150, 80)
local EQUIPPED_STROKE = Color3.fromRGB(255, 205, 60)

local UNEQUIPPED_TRANSPARENCY = 0.15
local EQUIPPED_TRANSPARENCY = 0.02
local UNEQUIPPED_THICKNESS = 1.5
local EQUIPPED_THICKNESS = 2.5
local EQUIPPED_GROW = 6 -- extra pixels added to both dimensions while equipped

local EQUIP_TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_IN_TWEEN_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT_TWEEN_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function buildSlotCard(container, layoutOrder)
	local card = Instance.new("TextButton")
	card.Name = "Slot"
	card.LayoutOrder = layoutOrder
	card.Size = UDim2.new(0, CARD_SIZE, 0, CARD_SIZE)
	card.BackgroundColor3 = CARD_COLOR
	card.BackgroundTransparency = 0.15
	card.AutoButtonColor = false
	card.Text = ""
	card.BorderSizePixel = 0
	card.ClipsDescendants = true -- keeps icon/badge visually contained while the card pops in/out
	card.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = CARD_STROKE
	stroke.Transparency = 0.4
	stroke.Thickness = 1.5
	stroke.Parent = card

	local keyBadge = Instance.new("TextLabel")
	keyBadge.Name = "KeyBadge"
	keyBadge.Position = UDim2.new(0, 6, 0, 4)
	keyBadge.Size = UDim2.new(0, 16, 0, 16)
	keyBadge.BackgroundTransparency = 1
	keyBadge.Font = Enum.Font.FredokaOne
	keyBadge.Text = tostring(layoutOrder)
	keyBadge.TextSize = 13
	keyBadge.TextColor3 = Color3.fromRGB(230, 220, 205)
	keyBadge.Parent = card

	return card, stroke, keyBadge
end

function HotbarUI.Start()
	local hid = pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	if not hid then
		warn("[HotbarUI] couldn't hide the default backpack bar")
	end

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HotbarUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(1, 1)
	container.Position = UDim2.new(1, -EDGE_MARGIN, 1, -EDGE_MARGIN)
	container.Size = UDim2.new(0, 0, 0, CARD_SIZE)
	container.AutomaticSize = Enum.AutomaticSize.X
	container.BackgroundTransparency = 1
	container.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = container

	screenGui.Parent = playerGui

	local slots = {} -- Tool -> { card, stroke, keyBadge }
	local order = {} -- ordered list of Tool, index = slot/key number

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

	local function renumber()
		for index, tool in ipairs(order) do
			local entry = slots[tool]
			entry.card.LayoutOrder = index
			entry.keyBadge.Text = tostring(index)
		end
	end

	-- Only actually tweens on a genuine equipped<->unequipped change (cheap to call every
	-- Heartbeat otherwise) -- grows the card slightly, brightens it, and thickens/golds the
	-- stroke, all animated together so it's unmistakable which tool is active.
	local function setEquippedVisual(entry, equipped)
		if entry.equipped == equipped then
			return
		end
		entry.equipped = equipped

		local size = equipped and CARD_SIZE + EQUIPPED_GROW or CARD_SIZE
		TweenService:Create(entry.card, EQUIP_TWEEN_INFO, {
			Size = UDim2.new(0, size, 0, size),
			BackgroundTransparency = equipped and EQUIPPED_TRANSPARENCY or UNEQUIPPED_TRANSPARENCY,
		}):Play()
		TweenService:Create(entry.stroke, EQUIP_TWEEN_INFO, {
			Color = equipped and EQUIPPED_STROKE or CARD_STROKE,
			Thickness = equipped and EQUIPPED_THICKNESS or UNEQUIPPED_THICKNESS,
			Transparency = equipped and 0.1 or 0.4,
		}):Play()
	end

	local function addSlot(tool)
		if slots[tool] then
			return
		end
		table.insert(order, tool)
		local card, stroke, keyBadge = buildSlotCard(container, #order)
		local iconBuilder = ToolIcons.Builders[tool.Name]
		if iconBuilder then
			iconBuilder(card)
		end
		card.MouseButton1Click:Connect(function()
			toggleTool(tool)
		end)
		slots[tool] = { card = card, stroke = stroke, keyBadge = keyBadge, equipped = false }

		-- Pop-in: starts collapsed/transparent and tweens up to full size. Since the container
		-- auto-sizes off a UIListLayout, this also makes any existing slots slide smoothly out of
		-- the way as this one grows, instead of snapping to a new position instantly.
		card.Size = UDim2.new(0, 0, 0, 0)
		card.BackgroundTransparency = 1
		stroke.Transparency = 1
		TweenService:Create(card, POP_IN_TWEEN_INFO, {
			Size = UDim2.new(0, CARD_SIZE, 0, CARD_SIZE),
			BackgroundTransparency = UNEQUIPPED_TRANSPARENCY,
		}):Play()
		TweenService:Create(stroke, POP_IN_TWEEN_INFO, { Transparency = 0.4 }):Play()
	end

	local function removeSlot(tool)
		local entry = slots[tool]
		if not entry then
			return
		end
		slots[tool] = nil
		local index = table.find(order, tool)
		if index then
			table.remove(order, index)
		end
		renumber()

		-- Pop-out, then destroy once it's actually finished shrinking -- removed from `slots`
		-- above already, so the next Heartbeat poll won't try to process it again mid-animation.
		local tween = TweenService:Create(entry.card, POP_OUT_TWEEN_INFO, {
			Size = UDim2.new(0, 0, 0, 0),
			BackgroundTransparency = 1,
		})
		TweenService:Create(entry.stroke, POP_OUT_TWEEN_INFO, { Transparency = 1 }):Play()
		tween.Completed:Connect(function()
			entry.card:Destroy()
		end)
		tween:Play()
	end

	local function currentTools()
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

	-- Periodic poll rather than Backpack.ChildAdded / equip-related events -- this project has
	-- repeatedly found Tool-equip events unreliable; a cheap Heartbeat scan (there are only ever a
	-- couple of tools) is the pattern that's actually held up everywhere else it's been tried.
	RunService.Heartbeat:Connect(function()
		local tools = currentTools()
		local seen = {}
		for _, tool in ipairs(tools) do
			seen[tool] = true
			if not slots[tool] then
				addSlot(tool)
			end
		end
		for tool in pairs(slots) do
			if not seen[tool] then
				removeSlot(tool)
			end
		end

		local character = player.Character
		for tool, entry in pairs(slots) do
			local equipped = character ~= nil and tool.Parent == character
			setEquippedVisual(entry, equipped)
		end
	end)

	local KEY_TO_INDEX = {
		[Enum.KeyCode.One] = 1,
		[Enum.KeyCode.Two] = 2,
		[Enum.KeyCode.Three] = 3,
	}

	UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		if gameProcessedEvent then
			return
		end
		local index = KEY_TO_INDEX[input.KeyCode]
		if index and order[index] then
			toggleTool(order[index])
		end
	end)
end

return HotbarUI
