local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlowerConfig = require(ReplicatedStorage.Shared.BlowerConfig)
local RakeConfig = require(ReplicatedStorage.Shared.RakeConfig)
local SackConfig = require(ReplicatedStorage.Shared.SackConfig)

-- Shared flat-icon builders for each tool, reused by both HotbarUI and InventoryUI so they stay
-- visually identical without duplicating the shape code. Built from plain Frames using each
-- tool's own real colors (BlowerConfig/SackConfig), not text glyphs or images -- keeps them
-- recognizable and immune to the font-glyph gaps that bit the coin/chevron/gear icons earlier.
--
-- Always the Default cosmetic -- a LocalScript can't reach the server-only PlayerUpgrades module
-- that resolves a player's actual chosen skin, so these match whatever the player is ACTUALLY
-- holding only as long as every player is still on Default (true until real skins exist to buy).
-- Once cosmetics ship for real, this'll need the player's choice replicated down as an Attribute.
local BlowerColors = BlowerConfig.Cosmetics.Default
local RakeColors = RakeConfig.Cosmetics.Default
local SackColors = SackConfig.Cosmetics.Default

local ToolIcons = {}

-- Deliberately way higher than any card's own ZIndex (1 unless a caller sets it higher) --
-- guarantees the icon draws on top of its card regardless of context.
local ICON_ZINDEX = 100

function ToolIcons.BuildBlowerIcon(parent)
	local body = Instance.new("Frame")
	body.Name = "Icon"
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.new(0.5, -2, 0.5, 0)
	body.Size = UDim2.new(0, 32, 0, 20)
	-- No Rotation here -- Rotation + UICorner on the same Frame is a known-flaky combination in
	-- Roblox's UI renderer (this is exactly what made this icon invisible while the un-rotated
	-- coin icon, right next to it in the same panel, rendered fine).
	body.BackgroundColor3 = BlowerColors.BodyColor
	body.BorderSizePixel = 0
	body.ZIndex = ICON_ZINDEX
	body.Parent = parent

	local bodyCorner = Instance.new("UICorner")
	bodyCorner.CornerRadius = UDim.new(0, 6)
	bodyCorner.Parent = body

	local nozzle = Instance.new("Frame")
	nozzle.Name = "Nozzle"
	nozzle.AnchorPoint = Vector2.new(0, 0.5)
	nozzle.Position = UDim2.new(1, -3, 0.5, 0)
	nozzle.Size = UDim2.new(0, 11, 0, 11)
	nozzle.BackgroundColor3 = BlowerColors.NozzleColor
	nozzle.BorderSizePixel = 0
	nozzle.ZIndex = ICON_ZINDEX + 1
	nozzle.Parent = body

	local nozzleCorner = Instance.new("UICorner")
	nozzleCorner.CornerRadius = UDim.new(0, 3)
	nozzleCorner.Parent = nozzle
end

function ToolIcons.BuildSackIcon(parent)
	local body = Instance.new("Frame")
	body.Name = "Icon"
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.new(0.5, 0, 0.5, 3)
	body.Size = UDim2.new(0, 30, 0, 26)
	body.BackgroundColor3 = SackColors.SackColor
	body.BorderSizePixel = 0
	body.ZIndex = ICON_ZINDEX
	body.Parent = parent

	local bodyCorner = Instance.new("UICorner")
	bodyCorner.CornerRadius = UDim.new(0, 9)
	bodyCorner.Parent = body

	local tie = Instance.new("Frame")
	tie.Name = "Tie"
	tie.AnchorPoint = Vector2.new(0.5, 1)
	tie.Position = UDim2.new(0.5, 0, 0, 3)
	tie.Size = UDim2.new(0, 14, 0, 8)
	tie.BackgroundColor3 = SackColors.SackTieColor
	tie.BorderSizePixel = 0
	tie.ZIndex = ICON_ZINDEX + 1
	tie.Parent = body

	local tieCorner = Instance.new("UICorner")
	tieCorner.CornerRadius = UDim.new(0, 3)
	tieCorner.Parent = tie
end

-- A vertical handle with a horizontal head bar and a row of short tines -- reads as a rake at a
-- glance, same "plain Frames, no rotation, no glyphs" approach as the other icons.
function ToolIcons.BuildRakeIcon(parent)
	local handle = Instance.new("Frame")
	handle.Name = "Icon"
	handle.AnchorPoint = Vector2.new(0.5, 0.5)
	handle.Position = UDim2.new(0.5, 0, 0.5, 3)
	handle.Size = UDim2.new(0, 5, 0, 24)
	handle.BackgroundColor3 = RakeColors.HandleColor
	handle.BorderSizePixel = 0
	handle.ZIndex = ICON_ZINDEX
	handle.Parent = parent

	local handleCorner = Instance.new("UICorner")
	handleCorner.CornerRadius = UDim.new(1, 0)
	handleCorner.Parent = handle

	local head = Instance.new("Frame")
	head.Name = "Head"
	head.AnchorPoint = Vector2.new(0.5, 1)
	head.Position = UDim2.new(0.5, 0, 0, 2)
	head.Size = UDim2.new(0, 26, 0, 6)
	head.BackgroundColor3 = RakeColors.HeadColor
	head.BorderSizePixel = 0
	head.ZIndex = ICON_ZINDEX + 1
	head.Parent = handle

	local headCorner = Instance.new("UICorner")
	headCorner.CornerRadius = UDim.new(0, 2)
	headCorner.Parent = head

	for i = 1, 4 do
		local tine = Instance.new("Frame")
		tine.Name = "Tine" .. i
		tine.AnchorPoint = Vector2.new(0.5, 0)
		tine.Position = UDim2.new((i - 1) / 3, 0, 1, 0)
		tine.Size = UDim2.new(0, 2, 0, 6)
		tine.BackgroundColor3 = RakeColors.HeadColor
		tine.BorderSizePixel = 0
		tine.ZIndex = ICON_ZINDEX + 1
		tine.Parent = head
	end
end

ToolIcons.Builders = {
	LeafBlower = ToolIcons.BuildBlowerIcon,
	LeafSack = ToolIcons.BuildSackIcon,
	LeafRake = ToolIcons.BuildRakeIcon,
}

return ToolIcons
