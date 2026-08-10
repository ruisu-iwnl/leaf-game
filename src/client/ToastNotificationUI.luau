local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Generic top-center toast notification -- the shared shell any feature can push a message through
-- via ToastNotificationUI.Show({ tierColor, glyph, eyebrow, title, description, duration? }),
-- instead of every feature (badges now, whatever else later) rebuilding its own card/animation/
-- queue from scratch. Same "one shared system, thin per-feature wrappers" shape as
-- NPCDialogueUI.luau (generic dialogue box) + StoreDialogueUI.luau (Ruisu's thin content on top of
-- it) elsewhere in this project. BadgeNotificationUI.luau is this module's only current caller.
--
-- Deliberately its own bespoke animation rather than reusing PanelMotion -- PanelMotion is built
-- around a backdrop+panel MODAL pair (dims/blocks the world behind it), which is wrong for a toast
-- that shouldn't interrupt play at all. White/cream card, warm autumn accent colors, a colored
-- medal (tier/category color chosen by the caller) with a centered glyph, and a one-shot diagonal
-- shine sweep on top of the slide+pop entrance.
--
-- The card's top corners are deliberately square, not rounded -- an opaque same-color topMask sits
-- above the rounded `fill` layer, covering its top corners AND the curved portion of its stroke
-- (Roblox's UICorner has no per-corner radius control, so "round some corners only" always needs
-- this kind of overlap-mask; there's no simpler built-in way). The colored accentBar then caps the
-- now-square top edge cleanly, with the border only picking back up part way down the sides,
-- curving into the two (still rounded) bottom corners.
local ToastNotificationUI = {}

local CARD_COLOR = Color3.fromRGB(253, 250, 244)
local CARD_STROKE = Color3.fromRGB(224, 168, 96)
local EYEBROW_COLOR = Color3.fromRGB(214, 122, 44)
local TITLE_COLOR = Color3.fromRGB(58, 34, 20)
local DESCRIPTION_COLOR = Color3.fromRGB(130, 104, 84)
local DEFAULT_TIER_COLOR = Color3.fromRGB(210, 150, 80)

local CARD_WIDTH = 380
local CARD_HEIGHT = 86
local CORNER_RADIUS = 18
local TOP_MASK_HEIGHT = CORNER_RADIUS + 2 -- corner radius plus a little extra to fully cover the stroke's curve
local RESTING_Y = 18
local HIDDEN_Y = -(CARD_HEIGHT + 20)

local ENTER_TWEEN_INFO = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local EXIT_TWEEN_INFO = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SHINE_TWEEN_INFO = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local DEFAULT_HOLD_DURATION = 3

local function buildUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ToastNotificationUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 60

	-- Purely a positioning/animation wrapper -- no background of its own (see `fill` below), so
	-- there's nothing here to fade in/out, only slide (Position) and pop (UIScale) to animate.
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Active = false -- purely a notification, never blocks clicks to anything under/behind it
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, HIDDEN_Y)
	card.Size = UDim2.new(0, CARD_WIDTH, 0, CARD_HEIGHT)
	card.BackgroundTransparency = 1
	card.BorderSizePixel = 0
	card.ClipsDescendants = true
	card.Visible = false
	card.ZIndex = 30
	card.Parent = screenGui

	local scale = Instance.new("UIScale")
	scale.Scale = 0.85
	scale.Parent = card

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = CARD_COLOR
	fill.BorderSizePixel = 0
	fill.ZIndex = 30
	fill.Parent = card

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, CORNER_RADIUS)
	fillCorner.Parent = fill

	local fillStroke = Instance.new("UIStroke")
	fillStroke.Color = CARD_STROKE
	fillStroke.Transparency = 0.2
	fillStroke.Thickness = 1.5
	fillStroke.Parent = fill

	-- See the file-level comment -- masks fill's rounded top corners (and their stroke) flat.
	local topMask = Instance.new("Frame")
	topMask.Name = "TopMask"
	topMask.Size = UDim2.new(1, 0, 0, TOP_MASK_HEIGHT)
	topMask.BackgroundColor3 = CARD_COLOR
	topMask.BorderSizePixel = 0
	topMask.ZIndex = 31
	topMask.Parent = card

	-- Category/tier-colored cap along the (now square) top edge -- set fresh each Show().
	local accentBar = Instance.new("Frame")
	accentBar.Name = "AccentBar"
	accentBar.BorderSizePixel = 0
	accentBar.Size = UDim2.new(1, 0, 0, 4)
	accentBar.ZIndex = 32
	accentBar.Parent = card

	local medalHolder = Instance.new("Frame")
	medalHolder.Name = "MedalHolder"
	medalHolder.AnchorPoint = Vector2.new(0, 0.5)
	medalHolder.Position = UDim2.new(0, 16, 0.5, 6)
	medalHolder.Size = UDim2.new(0, 54, 0, 54)
	medalHolder.BackgroundTransparency = 1
	medalHolder.ZIndex = 32
	medalHolder.Parent = card

	local medal = Instance.new("Frame")
	medal.Name = "Medal"
	medal.Size = UDim2.new(1, 0, 1, 0)
	medal.BorderSizePixel = 0
	medal.ZIndex = 32
	medal.Parent = medalHolder

	local medalCorner = Instance.new("UICorner")
	medalCorner.CornerRadius = UDim.new(1, 0)
	medalCorner.Parent = medal

	local medalStroke = Instance.new("UIStroke")
	medalStroke.Color = Color3.new(1, 1, 1)
	medalStroke.Transparency = 0.35
	medalStroke.Thickness = 2
	medalStroke.Parent = medal

	-- Anchored/sized to exactly the medal's own center rather than filling the whole circle.
	-- FredokaOne's "★" glyph doesn't sit centered within its own reported text bounds -- its ink
	-- sits visibly up and to the left of the box's true geometric center regardless of box size
	-- (confirmed by screenshot: the same offset showed up at a smaller box size too, so it isn't a
	-- box-size issue) -- Position is nudged down-right by a few percent to compensate for that,
	-- on top of TextXAlignment/TextYAlignment = Center handling the box itself.
	local medalGlyph = Instance.new("TextLabel")
	medalGlyph.Name = "Glyph"
	medalGlyph.AnchorPoint = Vector2.new(0.5, 0.5)
	medalGlyph.Position = UDim2.new(0.54, 0, 0.56, 0)
	medalGlyph.Size = UDim2.new(0.76, 0, 0.76, 0)
	medalGlyph.BackgroundTransparency = 1
	medalGlyph.Font = Enum.Font.FredokaOne
	medalGlyph.TextScaled = true
	medalGlyph.TextXAlignment = Enum.TextXAlignment.Center
	medalGlyph.TextYAlignment = Enum.TextYAlignment.Center
	medalGlyph.TextColor3 = Color3.new(1, 1, 1)
	medalGlyph.ZIndex = 33
	medalGlyph.Parent = medal

	local textArea = Instance.new("Frame")
	textArea.Name = "TextArea"
	textArea.Position = UDim2.new(0, 84, 0, 10)
	textArea.Size = UDim2.new(1, -84 - 16, 0, CARD_HEIGHT - 20 + 6)
	textArea.BackgroundTransparency = 1
	textArea.ZIndex = 32
	textArea.Parent = card

	local eyebrow = Instance.new("TextLabel")
	eyebrow.Name = "Eyebrow"
	eyebrow.Size = UDim2.new(1, 0, 0, 16)
	eyebrow.BackgroundTransparency = 1
	eyebrow.Font = Enum.Font.FredokaOne
	eyebrow.TextSize = 12
	eyebrow.TextXAlignment = Enum.TextXAlignment.Left
	eyebrow.TextColor3 = EYEBROW_COLOR
	eyebrow.ZIndex = 33
	eyebrow.Parent = textArea

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Position = UDim2.new(0, 0, 0, 16)
	titleLabel.Size = UDim2.new(1, 0, 0, 22)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.TextSize = 19
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextColor3 = TITLE_COLOR
	titleLabel.ZIndex = 33
	titleLabel.Parent = textArea

	local descriptionLabel = Instance.new("TextLabel")
	descriptionLabel.Name = "Description"
	descriptionLabel.Position = UDim2.new(0, 0, 0, 40)
	descriptionLabel.Size = UDim2.new(1, 0, 0, 18)
	descriptionLabel.BackgroundTransparency = 1
	descriptionLabel.Font = Enum.Font.FredokaOne
	descriptionLabel.TextSize = 13
	descriptionLabel.TextWrapped = true
	descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
	descriptionLabel.TextColor3 = DESCRIPTION_COLOR
	descriptionLabel.ZIndex = 33
	descriptionLabel.Parent = textArea

	-- The one-shot shine sweep -- a narrow bright bar, angled, tweened across the card's width once
	-- per Show(). Card.ClipsDescendants keeps it from spilling past the card's own bounds.
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.AnchorPoint = Vector2.new(0.5, 0.5)
	shine.Position = UDim2.new(0, -60, 0.5, 0)
	shine.Rotation = 20
	shine.Size = UDim2.new(0, 50, 2, 0)
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BorderSizePixel = 0
	shine.ZIndex = 34
	shine.Parent = card

	local shineGradient = Instance.new("UIGradient")
	shineGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	shineGradient.Parent = shine

	screenGui.Parent = playerGui
	return card, scale, accentBar, medal, medalGlyph, eyebrow, titleLabel, descriptionLabel, shine
end

function ToastNotificationUI.Start()
	local card, scale, accentBar, medal, medalGlyph, eyebrow, titleLabel, descriptionLabel, shine = buildUI()

	local queue = {}
	local processing = false

	local function playShine()
		shine.Position = UDim2.new(0, -60, 0.5, 0)
		TweenService:Create(shine, SHINE_TWEEN_INFO, { Position = UDim2.new(1, 60, 0.5, 0) }):Play()
	end

	local function showOne(config)
		local tierColor = config.tierColor or DEFAULT_TIER_COLOR
		accentBar.BackgroundColor3 = tierColor
		medal.BackgroundColor3 = tierColor
		medalGlyph.Text = config.glyph or ""
		eyebrow.Text = config.eyebrow or ""
		titleLabel.Text = config.title or ""
		descriptionLabel.Text = config.description or ""

		card.Visible = true
		card.Position = UDim2.new(0.5, 0, 0, HIDDEN_Y)
		scale.Scale = 0.85

		local enterTween = TweenService:Create(card, ENTER_TWEEN_INFO, {
			Position = UDim2.new(0.5, 0, 0, RESTING_Y),
		})
		TweenService:Create(scale, ENTER_TWEEN_INFO, { Scale = 1 }):Play()
		enterTween:Play()
		enterTween.Completed:Wait()

		playShine()
		task.wait(config.duration or DEFAULT_HOLD_DURATION)

		local exitTween = TweenService:Create(card, EXIT_TWEEN_INFO, {
			Position = UDim2.new(0.5, 0, 0, HIDDEN_Y),
		})
		exitTween:Play()
		exitTween.Completed:Wait()
		card.Visible = false
	end

	local function processQueue()
		if processing then
			return
		end
		processing = true
		while #queue > 0 do
			local config = table.remove(queue, 1)
			showOne(config)
		end
		processing = false
	end

	-- config: { tierColor?, glyph?, eyebrow?, title?, description?, duration? }. Queued -- multiple
	-- Show() calls in quick succession play one after another, never overlapping, since there's only
	-- ever this one card instance being reused.
	function ToastNotificationUI.Show(config)
		table.insert(queue, config)
		task.spawn(processQueue)
	end
end

return ToastNotificationUI
