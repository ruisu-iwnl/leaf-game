local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlowerConfig = require(ReplicatedStorage.Shared.BlowerConfig)
local SackConfig = require(ReplicatedStorage.Shared.SackConfig)

-- Shared flat-icon builders for each tool, reused by both HotbarUI and InventoryUI so they stay
-- visually identical without duplicating the shape code. Built from plain Frames using each
-- tool's own real colors (BlowerConfig/SackConfig), not text glyphs or images -- keeps them
-- recognizable and immune to the font-glyph gaps that bit the coin/chevron/gear icons earlier.
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
	body.BackgroundColor3 = BlowerConfig.BodyColor
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
	nozzle.BackgroundColor3 = BlowerConfig.NozzleColor
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
	body.BackgroundColor3 = SackConfig.SackColor
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
	tie.BackgroundColor3 = SackConfig.SackTieColor
	tie.BorderSizePixel = 0
	tie.ZIndex = ICON_ZINDEX + 1
	tie.Parent = body

	local tieCorner = Instance.new("UICorner")
	tieCorner.CornerRadius = UDim.new(0, 3)
	tieCorner.Parent = tie
end

ToolIcons.Builders = {
	LeafBlower = ToolIcons.BuildBlowerIcon,
	LeafSack = ToolIcons.BuildSackIcon,
}

return ToolIcons
