local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlowerConfig = require(ReplicatedStorage.Shared.BlowerConfig)
local RakeConfig = require(ReplicatedStorage.Shared.RakeConfig)
local SackConfig = require(ReplicatedStorage.Shared.SackConfig)

-- Builds a small, purely-visual Model of a tool for the store's item-preview panel
-- (ItemPreviewUI.luau) -- same part sizes/relative offsets as the real tool builders
-- (BlowerTool.buildTool/RakeTool.buildTool/SackSystem.newSackTool), just without any of the
-- gameplay bits those need (Attachments, ParticleEmitters, WeldConstraints, scripts) since this
-- never leaves a ViewportFrame. Lives in Shared specifically so the client-side preview panel can
-- build one without reaching into ServerScriptService (which it can't) or duplicating full tool-
-- building logic wholesale -- this is deliberately the trimmed-down "how it looks" subset of that.
local ItemPreviewBuilder = {}

local function newPart(model, name, size, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Parent = model
	return part
end

local function buildBlower(colors)
	local model = Instance.new("Model")
	model.Name = "LeafBlower"

	local handle = newPart(model, "Handle", BlowerConfig.BodySize, colors.BodyColor, Enum.Material.DiamondPlate)
	handle.CFrame = CFrame.new(0, 0, 0)

	local accent = newPart(model, "Accent", BlowerConfig.AccentSize, colors.GripColor, Enum.Material.DiamondPlate)
	accent.CFrame = handle.CFrame * CFrame.new(0, 0, 0.4)

	local grip = newPart(model, "Grip", BlowerConfig.GripSize, colors.GripColor, Enum.Material.DiamondPlate)
	grip.CFrame = handle.CFrame * CFrame.new(0, -0.7, 0.4)

	local nozzle = newPart(model, "Nozzle", BlowerConfig.NozzleSize, colors.NozzleColor, Enum.Material.DiamondPlate)
	nozzle.CFrame = handle.CFrame * CFrame.new(0, 0, -BlowerConfig.BodySize.Z / 2 - BlowerConfig.NozzleSize.Z / 2)

	model.PrimaryPart = handle
	return model
end

local function buildRake(colors)
	local model = Instance.new("Model")
	model.Name = "LeafRake"

	local handle = newPart(model, "Handle", RakeConfig.HandleSize, colors.HandleColor, Enum.Material.Wood)
	handle.CFrame = CFrame.new(0, 0, 0)

	local gripOffsetZ = RakeConfig.HandleSize.Z / 2 - RakeConfig.GripSize.Z / 2 - 0.15
	local grip = newPart(model, "Grip", RakeConfig.GripSize, colors.GripColor, Enum.Material.Fabric)
	grip.CFrame = handle.CFrame * CFrame.new(0, 0, gripOffsetZ)

	local head = newPart(model, "Head", RakeConfig.HeadSize, colors.HeadColor, Enum.Material.Metal)
	head.CFrame = handle.CFrame * CFrame.new(0, 0, -RakeConfig.HandleSize.Z / 2 - RakeConfig.HeadSize.Z / 2)

	local tineSpacing = RakeConfig.HeadSize.X / (RakeConfig.TineCount - 1)
	for i = 1, RakeConfig.TineCount do
		local tine = newPart(model, "Tine" .. i, RakeConfig.TineSize, colors.HeadColor, Enum.Material.Metal)
		local xOffset = -RakeConfig.HeadSize.X / 2 + tineSpacing * (i - 1)
		tine.CFrame = head.CFrame * CFrame.new(xOffset, 0, -RakeConfig.HeadSize.Z / 2 - RakeConfig.TineSize.Z / 2)
	end

	model.PrimaryPart = handle
	return model
end

local function buildSack(colors)
	local model = Instance.new("Model")
	model.Name = "LeafSack"

	local body = newPart(model, "Handle", SackConfig.SackBodySize, colors.SackColor, Enum.Material.Fabric)
	body.CFrame = CFrame.new(0, 0, 0)

	local tie = newPart(model, "Tie", SackConfig.SackTieSize, colors.SackTieColor, Enum.Material.Fabric)
	tie.CFrame = body.CFrame * CFrame.new(0, SackConfig.SackBodySize.Y / 2 - 0.05, 0)

	model.PrimaryPart = body
	return model
end

local BUILDERS = {
	LeafBlower = buildBlower,
	LeafRake = buildRake,
	LeafSack = buildSack,
}

-- Returns nil if toolName isn't a known tool -- callers decide how to handle that (ItemPreviewUI
-- just skips showing a model and leaves the viewport empty rather than erroring).
function ItemPreviewBuilder.Build(toolName, colors)
	local builder = BUILDERS[toolName]
	if not builder then
		return nil
	end
	return builder(colors)
end

return ItemPreviewBuilder
