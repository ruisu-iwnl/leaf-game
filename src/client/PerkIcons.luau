-- Shared flat-icon builders for perks, same reasoning/shape as ToolIcons.luau (plain Frames, no
-- images, no rotation+UICorner combos -- see that file's own comment on why rotation is avoided:
-- a known-flaky combination in Roblox's UI renderer). Not every perk needs an entry here --
-- InventoryUI.luau falls back to a perk's plain ShortLabel text (e.g. "2X" for DoubleGrab) for any
-- perk with no Builders entry, same as before this module existed.
local PerkIcons = {}

-- Deliberately way higher than any card's own ZIndex (1 unless a caller sets it higher) --
-- guarantees the icon draws on top of its card regardless of context, same value ToolIcons uses.
local ICON_ZINDEX = 100

-- Lucky Leaf -- a four-leaf clover (4 overlapping circles, no rotation needed since circles are
-- rotation-invariant) with a short stem, plus a small gold dot standing in for the "pot of gold"
-- side of the luck theme without needing a whole pot shape at icon size.
function PerkIcons.BuildLuckyLeafIcon(parent)
	local cloverGreen = Color3.fromRGB(70, 160, 90)
	local cloverGreenDark = Color3.fromRGB(45, 125, 68)
	local stemColor = Color3.fromRGB(58, 110, 60)
	local goldColor = Color3.fromRGB(255, 205, 60)

	-- The clover HEAD is centered a few pixels above the card's true center (headOffsetY), leaving
	-- room for the stem below to still fit inside the card without either one clipping.
	local headOffsetY = -3

	local lobeSize = 15
	local lobeReach = 7
	local lobeOffsets = {
		{ 0, -lobeReach, cloverGreen }, -- top
		{ 0, lobeReach, cloverGreen }, -- bottom
		{ -lobeReach, 0, cloverGreenDark }, -- left
		{ lobeReach, 0, cloverGreenDark }, -- right
	}
	for i, offset in ipairs(lobeOffsets) do
		local lobe = Instance.new("Frame")
		lobe.Name = "Lobe" .. i
		lobe.AnchorPoint = Vector2.new(0.5, 0.5)
		lobe.Position = UDim2.new(0.5, offset[1], 0.5, headOffsetY + offset[2])
		lobe.Size = UDim2.new(0, lobeSize, 0, lobeSize)
		lobe.BackgroundColor3 = offset[3]
		lobe.BorderSizePixel = 0
		lobe.ZIndex = ICON_ZINDEX
		lobe.Parent = parent

		local lobeCorner = Instance.new("UICorner")
		lobeCorner.CornerRadius = UDim.new(1, 0)
		lobeCorner.Parent = lobe
	end

	local stem = Instance.new("Frame")
	stem.Name = "Stem"
	stem.AnchorPoint = Vector2.new(0.5, 0)
	stem.Position = UDim2.new(0.5, 0, 0.5, headOffsetY + 6)
	stem.Size = UDim2.new(0, 3, 0, 11)
	stem.BackgroundColor3 = stemColor
	stem.BorderSizePixel = 0
	stem.ZIndex = ICON_ZINDEX
	stem.Parent = parent

	local sparkle = Instance.new("Frame")
	sparkle.Name = "Sparkle"
	sparkle.AnchorPoint = Vector2.new(0.5, 0.5)
	sparkle.Position = UDim2.new(0.8, 0, 0.22, 0)
	sparkle.Size = UDim2.new(0, 7, 0, 7)
	sparkle.BackgroundColor3 = goldColor
	sparkle.BorderSizePixel = 0
	sparkle.ZIndex = ICON_ZINDEX + 1
	sparkle.Parent = parent

	local sparkleCorner = Instance.new("UICorner")
	sparkleCorner.CornerRadius = UDim.new(1, 0)
	sparkleCorner.Parent = sparkle
end

-- Leaf Patron -- a crown, built entirely from rectangles/circles (no rotation, same reasoning as
-- the clover above): a gold band with 3 spikes rising off it (center spike tallest), each topped
-- with a small royal-purple jewel -- matches the purple+gold palette CosmeticConfig's Patron skins
-- and the rainbow-nameplate/footstep-trail perk effects all share.
function PerkIcons.BuildLeafPatronIcon(parent)
	local gold = Color3.fromRGB(212, 175, 55)
	local goldDark = Color3.fromRGB(178, 140, 40)
	local jewelColor = Color3.fromRGB(150, 60, 190)

	-- Every piece is positioned relative to the band's own top edge (bandTopY) so the spikes/jewels
	-- line up with it regardless of card size.
	local bandTopY = 6

	local band = Instance.new("Frame")
	band.Name = "Band"
	band.AnchorPoint = Vector2.new(0.5, 0)
	band.Position = UDim2.new(0.5, 0, 0.5, bandTopY)
	band.Size = UDim2.new(0, 30, 0, 7)
	band.BackgroundColor3 = gold
	band.BorderSizePixel = 0
	band.ZIndex = ICON_ZINDEX
	band.Parent = parent

	local bandCorner = Instance.new("UICorner")
	bandCorner.CornerRadius = UDim.new(0, 2)
	bandCorner.Parent = band

	local spikes = {
		{ x = -10, height = 8, color = goldDark },
		{ x = 0, height = 13, color = gold },
		{ x = 10, height = 8, color = goldDark },
	}
	for i, spike in ipairs(spikes) do
		local frame = Instance.new("Frame")
		frame.Name = "Spike" .. i
		frame.AnchorPoint = Vector2.new(0.5, 1)
		frame.Position = UDim2.new(0.5, spike.x, 0.5, bandTopY)
		frame.Size = UDim2.new(0, 6, 0, spike.height)
		frame.BackgroundColor3 = spike.color
		frame.BorderSizePixel = 0
		frame.ZIndex = ICON_ZINDEX
		frame.Parent = parent

		local jewel = Instance.new("Frame")
		jewel.Name = "Jewel" .. i
		jewel.AnchorPoint = Vector2.new(0.5, 1)
		jewel.Position = UDim2.new(0.5, 0, 0, 1)
		jewel.Size = UDim2.new(0, 6, 0, 6)
		jewel.BackgroundColor3 = jewelColor
		jewel.BorderSizePixel = 0
		jewel.ZIndex = ICON_ZINDEX + 1
		jewel.Parent = frame

		local jewelCorner = Instance.new("UICorner")
		jewelCorner.CornerRadius = UDim.new(1, 0)
		jewelCorner.Parent = jewel
	end
end

PerkIcons.Builders = {
	LuckyLeaf = PerkIcons.BuildLuckyLeafIcon,
	LeafPatron = PerkIcons.BuildLeafPatronIcon,
}

return PerkIcons
