local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")
local Workspace = game:GetService("Workspace")

local LeafSpawner = require(script.Parent.LeafSpawner)
local PlayerUpgrades = require(script.Parent.PlayerUpgrades)
local QuestObjectives = require(script.Parent.QuestObjectives)
local RakeConfig = require(ReplicatedStorage.Shared.RakeConfig)

-- Second leaf-collection tool alongside the Blower: instead of pushing leaves away, it drags
-- leaves in front of the player back toward them -- specifically meant to fix leaves that end up
-- stuck in map corners/edges, which the Blower can only ever push further away, never recover.
-- Click-to-use (not hold/toggle like the Blower): one click pulls everything currently in the
-- cone, then it's locked out for RakeConfig.RakeCooldownDuration seconds -- same cooldown-bar
-- presentation as the Blower's overheat lockout (see RakeCooldownUI.luau), just a fixed timer
-- instead of a heat buildup. Same build/AncestryChanged-equip conventions as BlowerTool.luau (see
-- that file for the reasoning behind each pattern reused here); no backpack/hose -- this tool
-- doesn't need them.
local RakeTool = {}

local TOOL_NAME = "LeafRake"

-- Sweep gesture played on use -- same "one AnimationTrack, Action priority, layered on top of the
-- default Animate script" approach as SackSystem's pickup/tie-off gestures (see that file's long
-- comment for why a raw Motor6D tween doesn't work here: the default Animate script overwrites it
-- every frame, so it has to go through a real AnimationTrack instead). Published asset from the
-- start (RakeConfig.RakeSweepAnimationId), no Studio-only baking step needed.
local sweepAnimation
local sweepTracks = setmetatable({}, { __mode = "k" }) -- Humanoid -> AnimationTrack, one load per character

local function setupSweepAnimation()
	if RakeConfig.RakeSweepAnimationId == "" then
		return
	end
	local animation = Instance.new("Animation")
	animation.Name = "RakeSweepGesture"
	animation.AnimationId = RakeConfig.RakeSweepAnimationId
	sweepAnimation = animation
end

local function ensureSweepTrack(humanoid)
	if not sweepAnimation then
		return nil
	end
	local track = sweepTracks[humanoid]
	if not track then
		local loaded, newTrack = pcall(function()
			return humanoid:LoadAnimation(sweepAnimation)
		end)
		if not loaded then
			return nil
		end
		newTrack.Priority = Enum.AnimationPriority.Action
		sweepTracks[humanoid] = newTrack
		track = newTrack
	end
	return track
end

-- LoadAnimation has a one-time cost of its own on top of content download -- pre-creating the
-- track the instant the character spawns gives it a head start before the player can realistically
-- get a rake use off, same reasoning as SackSystem's warmGestureTracks.
local function warmSweepTrack(character)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end
	ensureSweepTrack(humanoid)
end

local function playSweepGesture(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local track = ensureSweepTrack(humanoid)
	if track then
		track:Play(0.05)
	end
end

local function weldTo(part0, part1)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part0
	weld.Part1 = part1
	weld.Parent = part1
end

local function newPart(name, size, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.Wood
	part.CanCollide = false
	part.CastShadow = false
	part.Massless = true
	return part
end

-- Builds the one-and-only tool template. Roblox clones this into every player's Backpack
-- automatically (that's what StarterPack does), so this only ever needs to be built once. Always
-- uses the Default cosmetic -- each clone gets recolored to its owning player's actual chosen skin
-- the moment watchTool detects a real equip (see applyCosmetic below), since a single shared
-- template can't know who it'll belong to ahead of time.
local function buildTool()
	local tool = Instance.new("Tool")
	tool.Name = TOOL_NAME
	tool.RequiresHandle = true
	tool.CanBeDropped = false

	local defaultColors = RakeConfig.Cosmetics.Default

	local handle = newPart("Handle", RakeConfig.HandleSize, defaultColors.HandleColor, Enum.Material.Wood)
	handle.Parent = tool

	-- Where the decorative Grip cylinder sits, near the pole's near/top end -- also reused below
	-- for Tool.Grip's own position offset, so the hand actually grips at the same spot the model
	-- visually shows a hand-grip.
	local gripOffsetZ = RakeConfig.HandleSize.Z / 2 - RakeConfig.GripSize.Z / 2 - 0.15
	local grip = newPart("Grip", RakeConfig.GripSize, defaultColors.GripColor, Enum.Material.Fabric)
	grip.CFrame = handle.CFrame * CFrame.new(0, 0, gripOffsetZ)
	grip.Parent = tool
	weldTo(handle, grip)

	-- Crossbar at the far end (local -Z, matching this project's "front = -Z" convention), with
	-- a row of thin tines welded to it sticking further forward -- reads as a rake head at a glance
	-- without needing a custom mesh.
	local head = newPart("Head", RakeConfig.HeadSize, defaultColors.HeadColor, Enum.Material.Metal)
	head.CFrame = handle.CFrame * CFrame.new(0, 0, -RakeConfig.HandleSize.Z / 2 - RakeConfig.HeadSize.Z / 2)
	head.Parent = tool
	weldTo(handle, head)

	local tineSpacing = RakeConfig.HeadSize.X / (RakeConfig.TineCount - 1)
	for i = 1, RakeConfig.TineCount do
		local tine = newPart("Tine" .. i, RakeConfig.TineSize, defaultColors.HeadColor, Enum.Material.Metal)
		local xOffset = -RakeConfig.HeadSize.X / 2 + tineSpacing * (i - 1)
		tine.CFrame = head.CFrame * CFrame.new(xOffset, 0, -RakeConfig.HeadSize.Z / 2 - RakeConfig.TineSize.Z / 2)
		tine.Parent = tool
		weldTo(head, tine)
	end

	local dustAttachment = Instance.new("Attachment")
	dustAttachment.Name = "DustAttachment"
	dustAttachment.Position = Vector3.new(0, 0, -RakeConfig.HeadSize.Z / 2)
	dustAttachment.Parent = head

	-- Enabled stays permanently false -- this never streams continuously, only ever fires a single
	-- Emit() burst per use (see performRake below), same one-shot pattern LeafSpawner's own
	-- playConsumeVFX uses for the cleanup-zone sparkle.
	local dustEmitter = Instance.new("ParticleEmitter")
	dustEmitter.Name = "DustEmitter"
	dustEmitter.Enabled = false
	dustEmitter.Lifetime = NumberRange.new(RakeConfig.ParticleLifetimeMin, RakeConfig.ParticleLifetimeMax)
	dustEmitter.Speed = NumberRange.new(RakeConfig.ParticleSpeedMin, RakeConfig.ParticleSpeedMax)
	dustEmitter.SpreadAngle = Vector2.new(RakeConfig.ConeAngleDegrees, RakeConfig.ConeAngleDegrees)
	dustEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	dustEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	dustEmitter.Color = ColorSequence.new(Color3.fromRGB(170, 140, 95))
	dustEmitter.LightEmission = 0
	dustEmitter.Parent = dustAttachment

	-- Held vertically for now (long axis up-down) instead of the default forward-pointing grip a
	-- Handle built along Z normally gets -- a placeholder for the one-handed case until there's a
	-- real two-handed raking animation. Rotating +90 degrees around X turns the handle's local -Z
	-- (the head/tine end -- this project's "front" convention) to point down rather than forward.
	-- Deliberately NO position offset here (unlike the first pass): Handle.CFrame = Hand.CFrame *
	-- Grip, so a pure-rotation Grip guarantees the Handle's own origin sits exactly AT the hand
	-- regardless of how the hand itself happens to be oriented in the equip pose -- the previous
	-- position offset assumed the hand's local axes point in specific world directions, which
	-- turned out wrong and pushed the whole rake away from the hand instead of just sliding the
	-- grip point along it.
	tool.Grip = CFrame.Angles(math.rad(90), 0, 0)

	return tool
end

-- Same reasoning as BlowerTool's getAimOriginDirection: direction comes from the character's
-- HumanoidRootPart (always reliably horizontal), not the tool's own CFrame. Unlike the Blower, the
-- origin returned here is the PLAYER's own root position rather than the tool's head -- it doubles
-- as both the eligibility cone's apex and the point leaves get pulled toward.
local function getAimOriginDirection(tool)
	local character = tool.Parent
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return nil, nil
	end
	local lookVector = rootPart.CFrame.LookVector
	local direction = Vector3.new(lookVector.X, 0, lookVector.Z)
	if direction.Magnitude <= 0.01 then
		return nil, nil
	end
	return rootPart.Position, direction.Unit
end

-- Recolors this specific clone to its owning player's currently-equipped skin -- called the moment
-- watchTool detects a real equip, since the shared StarterPack template (see buildTool) has no way
-- to know who it'll belong to ahead of time. Tines are direct children of the Tool itself (not of
-- Head -- see buildTool), so they're matched by name rather than by parent.
local function applyCosmetic(tool, player)
	local colors = RakeConfig.Cosmetics[PlayerUpgrades.GetCosmetic(player, TOOL_NAME)] or RakeConfig.Cosmetics.Default

	local handle = tool:FindFirstChild("Handle")
	local grip = tool:FindFirstChild("Grip")
	local head = tool:FindFirstChild("Head")

	if handle then
		handle.Color = colors.HandleColor
	end
	if grip then
		grip.Color = colors.GripColor
	end
	if head then
		head.Color = colors.HeadColor
	end

	for _, child in ipairs(tool:GetChildren()) do
		if child:IsA("BasePart") and child.Name:match("^Tine%d+$") then
			child.Color = colors.HeadColor
		end
	end
end

-- Watches one specific tool instance for the rest of its life -- same AncestryChanged
-- equip/unequip reliability pattern as BlowerTool.watchTool (see that file's comment for why
-- AncestryChanged specifically, over Backpack/PlayerAdded/ChildAdded).
local function watchTool(tool)
	local head = tool:WaitForChild("Head")
	local dustAttachment = head:WaitForChild("DustAttachment")
	local dustEmitter = dustAttachment:WaitForChild("DustEmitter")

	do
		local initialPlayer = Players:GetPlayerFromCharacter(tool.Parent)
		if initialPlayer then
			applyCosmetic(tool, initialPlayer)
		end
	end

	local onCooldown = false
	-- RakeCooldownFraction: 1 the instant it's used, ticking down to 0 over RakeCooldownDuration --
	-- RakeCooldownUI.luau reads these two exactly like OverheatUI reads HeatFraction/Overheated.
	tool:SetAttribute("RakeCooldownFraction", 0)
	tool:SetAttribute("RakeOnCooldown", false)

	-- Ticks the cooldown bar down to 0 over RakeCooldownDuration seconds, then unlocks. task.wait()
	-- with no argument resumes next frame, same per-frame granularity as Blower's Heartbeat-driven
	-- heat, without needing a standing connection for a lockout that's only ever running briefly.
	local function runCooldown(player)
		onCooldown = true
		tool:SetAttribute("RakeOnCooldown", true)
		local effectiveConfig = player and PlayerUpgrades.GetEffectiveConfig(player, TOOL_NAME) or RakeConfig
		local duration = effectiveConfig.RakeCooldownDuration
		local startTime = os.clock()
		while true do
			local elapsed = os.clock() - startTime
			local fraction = math.clamp(1 - elapsed / duration, 0, 1)
			tool:SetAttribute("RakeCooldownFraction", fraction)
			if fraction <= 0 then
				break
			end
			task.wait()
		end
		onCooldown = false
		tool:SetAttribute("RakeOnCooldown", false)
	end

	local function performRake()
		local player = Players:GetPlayerFromCharacter(tool.Parent)
		local origin, direction = getAimOriginDirection(tool)
		if origin then
			local effectiveConfig = player and PlayerUpgrades.GetEffectiveConfig(player, TOOL_NAME) or RakeConfig
			LeafSpawner.ApplyRake(player, origin, direction, effectiveConfig)
			dustEmitter:Emit(RakeConfig.ParticleBurstCount)
			playSweepGesture(tool.Parent)
			if player then
				-- A real rake use (not a no-op click with nowhere to aim) -- feeds chain quests
				-- like Getting Started II's "use the Rake 5 times" objective (see QuestConfig.luau).
				-- No daily quest reuses this type today, unlike DeliverLeaves/CollectViaSack.
				QuestObjectives.RecordProgress(player, "UseRake", 1)
			end
		end
		task.spawn(runCooldown, player)
	end

	tool.Activated:Connect(function()
		if onCooldown then
			return
		end
		performRake()
	end)

	tool.AncestryChanged:Connect(function()
		local player = Players:GetPlayerFromCharacter(tool.Parent)
		if player then
			applyCosmetic(tool, player)
		end
	end)
end

local watchedTools = setmetatable({}, { __mode = "k" })

local function onWorkspaceDescendantAdded(descendant)
	if descendant:IsA("Tool") and descendant.Name == TOOL_NAME and not watchedTools[descendant] then
		watchedTools[descendant] = true
		watchTool(descendant)
	end
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(warmSweepTrack)
	if player.Character then
		warmSweepTrack(player.Character)
	end
end

-- Called by PurchaseSystem's EquipCosmetic handler right after a skin change is validated -- repaints
-- the rake itself (whether it's currently equipped or just sitting in the Backpack) so a skin swap
-- is visible immediately instead of only on the next equip.
function RakeTool.RefreshCosmetic(player)
	local character = player.Character
	local tool = character and character:FindFirstChild(TOOL_NAME)
	if not tool then
		local backpack = player:FindFirstChild("Backpack")
		tool = backpack and backpack:FindFirstChild(TOOL_NAME)
	end
	if tool then
		applyCosmetic(tool, player)
	end
end

function RakeTool.Start()
	if not StarterPack:FindFirstChild(TOOL_NAME) then
		buildTool().Parent = StarterPack
	end

	setupSweepAnimation()

	Workspace.DescendantAdded:Connect(onWorkspaceDescendantAdded)
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		onWorkspaceDescendantAdded(descendant)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
end

return RakeTool
