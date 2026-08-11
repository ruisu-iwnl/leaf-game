local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local SackConfig = require(ReplicatedStorage.Shared.SackConfig)
local LeafSpawner = require(script.Parent.LeafSpawner)
local PlayerUpgrades = require(script.Parent.PlayerUpgrades)

local SackSystem = {}

local SACK_TOOL_NAME = "LeafSack"
local SACK_DELIVERY_INTERVAL = 0.2
local POOF_LIGHT_DIM_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local cleanupZone
local lobbyCleanupZone
local groundPart
local remotes
local collectLeafRemote
local spawnSackRemote
local poofVFXPart
local poofSmokeEmitter
local poofFlashEmitter
local poofLight

-- Physical sacks currently loose in the world (equipped in a Character, or dropped) -- NOT ones
-- sitting in a Backpack, since Backpack isn't a Workspace descendant. That's exactly the set that
-- needs checking against the cleanup zone: a stowed sack can't be "in" the zone.
local activeSacks = {}

local function isInCleanupZone(position)
	if not cleanupZone then
		return false
	end
	local halfX = cleanupZone.Size.X / 2
	local halfZ = cleanupZone.Size.Z / 2
	local center = cleanupZone.Position
	return position.X >= center.X - halfX and position.X <= center.X + halfX
		and position.Z >= center.Z - halfZ and position.Z <= center.Z + halfZ
end

-- Lobby counterpart -- kept separate (not folded into isInCleanupZone) so runSackDeliveryLoop can
-- tell which zone a sack landed in and only pay out via the real yard zone, same reasoning as
-- LeafSpawner's isInCleanupZone/isInLobbyCleanupZone split for loose leaves.
local function isInLobbyCleanupZone(position)
	if not lobbyCleanupZone then
		return false
	end
	local halfX = lobbyCleanupZone.Size.X / 2
	local halfZ = lobbyCleanupZone.Size.Z / 2
	local center = lobbyCleanupZone.Position
	return position.X >= center.X - halfX and position.X <= center.X + halfX
		and position.Z >= center.Z - halfZ and position.Z <= center.Z + halfZ
end

-- Ray straight down onto the Ground part specifically (not whatever's underfoot) so a sack always
-- lands on the lawn even if dropped near a tree or the fence.
local function findGroundY(position)
	if not groundPart then
		return position.Y
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { groundPart }
	local result = Workspace:Raycast(position + Vector3.new(0, 10, 0), Vector3.new(0, -30, 0), params)
	if result then
		return result.Position.Y
	end
	return groundPart.Position.Y + groundPart.Size.Y / 2
end

-- One shared, reused Part + several ParticleEmitters + a PointLight for the "poof" when a physical
-- sack spawns -- same reasoning as LeafSpawner's consume VFX: repositioning and re-emitting one set
-- of instances is effectively free, versus creating/destroying a whole effect per spawn. Layered
-- for a much bigger, more theatrical pop: a big lingering smoke cloud, a bright instant flash, an
-- energetic sparkle burst shooting outward, and a real light flash to sell it with actual
-- illumination -- not just one modest puff.
local function setupPoofVFX()
	poofVFXPart = Instance.new("Part")
	poofVFXPart.Name = "SackPoofVFX"
	poofVFXPart.Anchored = true
	poofVFXPart.CanCollide = false
	poofVFXPart.CanQuery = false
	poofVFXPart.CastShadow = false
	poofVFXPart.Transparency = 1
	poofVFXPart.Size = Vector3.new(0.2, 0.2, 0.2)
	poofVFXPart.Parent = Workspace

	-- Big smoke cloud, lingers and billows outward.
	poofSmokeEmitter = Instance.new("ParticleEmitter")
	poofSmokeEmitter.Name = "PoofSmoke"
	poofSmokeEmitter.Enabled = false
	poofSmokeEmitter.Rate = 0
	poofSmokeEmitter.Lifetime = NumberRange.new(0.6, 1.1)
	poofSmokeEmitter.Speed = NumberRange.new(6, 15)
	poofSmokeEmitter.SpreadAngle = Vector2.new(180, 180)
	poofSmokeEmitter.Drag = 1.5
	poofSmokeEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.35, 3.8),
		NumberSequenceKeypoint.new(1, 5.5),
	})
	poofSmokeEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	poofSmokeEmitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(248, 238, 218)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 170, 155)),
	})
	poofSmokeEmitter.LightEmission = 0
	poofSmokeEmitter.Parent = poofVFXPart

	-- Bright instant flash -- the actual "pop" moment.
	poofFlashEmitter = Instance.new("ParticleEmitter")
	poofFlashEmitter.Name = "PoofFlash"
	poofFlashEmitter.Enabled = false
	poofFlashEmitter.Rate = 0
	poofFlashEmitter.Lifetime = NumberRange.new(0.16, 0.16)
	poofFlashEmitter.Speed = NumberRange.new(0, 0)
	poofFlashEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(1, 6),
	})
	poofFlashEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	poofFlashEmitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	poofFlashEmitter.LightEmission = 1
	poofFlashEmitter.Parent = poofVFXPart

	-- Real light flash so the poof actually illuminates the area for an instant, not just particles.
	poofLight = Instance.new("PointLight")
	poofLight.Name = "PoofLight"
	poofLight.Color = Color3.fromRGB(255, 245, 220)
	poofLight.Range = 16
	poofLight.Brightness = 0
	poofLight.Parent = poofVFXPart
end

local function playSpawnPoofVFX(position)
	if not poofVFXPart then
		return
	end
	poofVFXPart.CFrame = CFrame.new(position)
	poofSmokeEmitter:Emit(45)
	poofFlashEmitter:Emit(1)

	poofLight.Brightness = 4
	TweenService:Create(poofLight, POOF_LIGHT_DIM_INFO, { Brightness = 0 }):Play()
end

-- A simple brown drawstring sack -- body + a smaller "tied" band near the top, both plain Parts
-- (no custom assets, matching how every other prop in this game is built). Takes the target world
-- position directly and sets both parts' CFrames from it up front, rather than building at the
-- origin and repositioning after -- Tool isn't a Model/PVInstance, so it has no PivotTo, and a
-- WeldConstraint only keeps two parts together through physics simulation, not through a direct
-- CFrame assignment after the fact. `colors` (SackConfig.Cosmetics.<id>) is resolved by the
-- caller, which already knows the owning player -- this function stays agnostic to cosmetics as a
-- concept, same as it's agnostic to everything else about who owns it beyond ownerUserId.
local function newSackTool(leafCount, position, ownerUserId, colors)
	colors = colors or SackConfig.Cosmetics.Default

	local tool = Instance.new("Tool")
	tool.Name = SACK_TOOL_NAME
	tool.RequiresHandle = true
	tool.CanBeDropped = true
	tool:SetAttribute("LeafCount", leafCount)
	tool:SetAttribute("OwnerUserId", ownerUserId)

	local handleCFrame = CFrame.new(position)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = SackConfig.SackBodySize
	handle.Color = colors.SackColor
	handle.Material = Enum.Material.Fabric
	handle.CanCollide = true
	handle.CastShadow = true
	handle.CFrame = handleCFrame
	handle.Parent = tool

	local tie = Instance.new("Part")
	tie.Name = "Tie"
	tie.Size = SackConfig.SackTieSize
	tie.Color = colors.SackTieColor
	tie.Material = Enum.Material.Fabric
	tie.CanCollide = false
	tie.CastShadow = false
	tie.CFrame = handleCFrame * CFrame.new(0, SackConfig.SackBodySize.Y / 2 - 0.05, 0)
	tie.Parent = tool

	local tieWeld = Instance.new("WeldConstraint")
	tieWeld.Part0 = handle
	tieWeld.Part1 = tie
	tieWeld.Parent = tie

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickupPrompt"
	prompt.ActionText = "Pick Up"
	prompt.ObjectText = "Leaf Sack"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = SackConfig.PickupPromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = handle

	prompt.Triggered:Connect(function(player)
		-- Only pickup-able while it's actually sitting loose -- ignore late/duplicate triggers
		-- once someone's already grabbed it.
		if tool.Parent ~= Workspace then
			return
		end
		local backpack = player:FindFirstChild("Backpack")
		if backpack then
			tool.Parent = backpack
		end
	end)

	return tool
end

-- Public: every physical sack this player currently has -- Backpack (stowed) and equipped
-- (Character) both -- as a flat list of each one's leaf count. Used by SaveSystem to persist them
-- across sessions; see SackSystem.RestoreSacks for the other half.
function SackSystem.GetPlayerSackLeafCounts(player)
	local counts = {}

	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") and child.Name == SACK_TOOL_NAME then
				table.insert(counts, child:GetAttribute("LeafCount") or 0)
			end
		end
	end

	local character = player.Character
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") and child.Name == SACK_TOOL_NAME then
				table.insert(counts, child:GetAttribute("LeafCount") or 0)
			end
		end
	end

	return counts
end

-- Public: recalculates ActiveSackCount from the REAL sack Tools this player currently has,
-- overwriting whatever the attribute happened to read before -- self-heals any drift between the
-- counter and reality (which is exactly what causes the UI showing "2/3" with nothing actually in
-- the hotbar), regardless of what caused it. Used automatically at the end of RestoreSacks, and
-- exposed for AdminCommands' :fixsacks in case a desync ever turns up some other way.
function SackSystem.ResyncActiveSackCount(player)
	player:SetAttribute("ActiveSackCount", #SackSystem.GetPlayerSackLeafCounts(player))
end

-- Public: recreates physical sacks straight into this player's Backpack from a saved leaf-count
-- list (see GetPlayerSackLeafCounts) -- called once by SaveSystem right after a player's data
-- loads in. Placed directly into Backpack rather than dropped in the world via the pickup prompt,
-- since these are being handed back, not freshly spawned; exact position barely matters since it
-- isn't visible until equipped (Roblox re-grips it to the hand at that point regardless).
function SackSystem.RestoreSacks(player, leafCounts)
	if not leafCounts or #leafCounts == 0 then
		return
	end

	-- Roblox destroys and recreates Backpack (re-cloning StarterPack fresh into it) on every
	-- character spawn, including the very first one -- not just death/respawn. SaveSystem's
	-- DataStore read is an async network call that often resolves BEFORE that first spawn actually
	-- happens, so adding a sack straight into Backpack at that point meant it frequently got added
	-- to an instance that was about to be wiped a moment later -- exactly why the leaf COUNT (plain
	-- saved data) survived but the physical Tool never did. Waiting for the Character to exist
	-- first guarantees this runs after that spawn-time reset, not racing it.
	if not player.Character then
		local attempts = 0
		while not player.Character and attempts < 100 and player.Parent do
			task.wait(0.1)
			attempts += 1
		end
	end

	local backpack = player:WaitForChild("Backpack", 5)
	if not backpack then
		return
	end

	local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local position = rootPart and rootPart.Position or Vector3.new(0, 0, 0)
	local colors = SackConfig.Cosmetics[PlayerUpgrades.GetCosmetic(player, SACK_TOOL_NAME)] or SackConfig.Cosmetics.Default

	for _, leafCount in ipairs(leafCounts) do
		if leafCount > 0 then
			local tool = newSackTool(leafCount, position, player.UserId, colors)
			tool.Parent = backpack
		end
	end

	-- Recomputed from the real sacks that now exist, not added on top of whatever the attribute
	-- happened to already read -- see ResyncActiveSackCount's comment.
	SackSystem.ResyncActiveSackCount(player)
end

local function onWorkspaceDescendantAdded(descendant)
	if descendant:IsA("Tool") and descendant.Name == SACK_TOOL_NAME then
		activeSacks[descendant] = true
	end
end

local function onWorkspaceDescendantRemoving(descendant)
	activeSacks[descendant] = nil
end

-- Periodic (not per-frame) position check against the cleanup zone, same pattern as leaf
-- consumption -- covers both "carried in while equipped" and "dropped inside the zone" without
-- needing any actual throw physics.
local function runSackDeliveryLoop()
	while true do
		for tool in pairs(activeSacks) do
			local handle = tool.Parent and tool:FindFirstChild("Handle")
			local inYardZone = handle and isInCleanupZone(handle.Position)
			local inLobbyZone = handle and not inYardZone and isInLobbyCleanupZone(handle.Position)
			if inYardZone or inLobbyZone then
				local leafCount = tool:GetAttribute("LeafCount") or 0
				activeSacks[tool] = nil

				local ownerUserId = tool:GetAttribute("OwnerUserId")
				local owner = ownerUserId and Players:GetPlayerByUserId(ownerUserId)
				if inYardZone then
					LeafSpawner.DeliverToZone(leafCount, handle.Position, owner)
				else
					LeafSpawner.DeliverToLobbyZone(leafCount, handle.Position)
				end

				if owner then
					owner:SetAttribute("ActiveSackCount", math.max((owner:GetAttribute("ActiveSackCount") or 1) - 1, 0))
				end

				tool:Destroy()
			end
		end
		task.wait(SACK_DELIVERY_INTERVAL)
	end
end

-- Why the previous version silently did nothing: a live Humanoid rig's Motor6Ds aren't a plain
-- property you can just Tween. The default "Animate" script (running client-side, on the owning
-- player's machine) continuously drives every joint through the Animator to play idle/walk/run --
-- and that's what actually gets replicated as the character's real pose. A raw server-side
-- Motor6D.C0 tween gets overwritten by that every frame, so it never actually rendered.
--
-- The correct way to layer a custom gesture on top of the existing idle/walk animation is a real
-- AnimationTrack with Enum.AnimationPriority.Action, which the Animator blends in on top of
-- whatever's already playing for just the joints it defines. That normally means authoring an
-- Animation in Studio's animation editor and uploading it -- not available here -- but
-- KeyframeSequenceProvider:RegisterKeyframeSequence lets a script build one procedurally and get a
-- usable AnimationId back, no Studio editor or upload required.
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local pickupAnimation
local pickupTracks = setmetatable({}, { __mode = "k" }) -- Humanoid -> AnimationTrack, one load per character

local tieSackAnimation
local tieSackTracks = setmetatable({}, { __mode = "k" })

local function buildPickupSequence()
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = "SackPickupGesture"
	sequence.Priority = Enum.AnimationPriority.Action
	sequence.Loop = false

	-- "Swings west instead of north" is a ~90-degree-off error, not a flipped sign -- that means the
	-- shoulder reach was on the WRONG AXIS entirely (Z), not just the wrong direction on the right
	-- one. Swapped the reach onto X instead. Also cut way down to a fast 3-keyframe snap (rest ->
	-- grab -> rest) instead of the multi-phase version -- asked to mimic a quick pickup, not a
	-- deliberate slow one.
	local function addKeyframe(time, pose)
		local keyframe = Instance.new("Keyframe")
		keyframe.Time = time

		local torsoPose = Instance.new("Pose")
		torsoPose.Name = "UpperTorso"
		torsoPose.CFrame = CFrame.new()
		torsoPose.EasingStyle = Enum.PoseEasingStyle.Cubic
		torsoPose.Parent = keyframe

		local upperPose = Instance.new("Pose")
		upperPose.Name = "RightUpperArm"
		upperPose.CFrame = CFrame.Angles(math.rad(pose.shoulder or 0), 0, math.rad(pose.sway or 0))
		upperPose.EasingStyle = Enum.PoseEasingStyle.Cubic
		upperPose.Parent = torsoPose

		local lowerPose = Instance.new("Pose")
		lowerPose.Name = "RightLowerArm"
		lowerPose.CFrame = CFrame.Angles(math.rad(pose.elbow or 0), 0, 0)
		lowerPose.EasingStyle = Enum.PoseEasingStyle.Cubic
		lowerPose.Parent = upperPose

		local handPose = Instance.new("Pose")
		handPose.Name = "RightHand"
		handPose.CFrame = CFrame.Angles(math.rad(pose.wrist or 0), 0, 0)
		handPose.EasingStyle = Enum.PoseEasingStyle.Cubic
		handPose.Parent = lowerPose

		keyframe.Parent = sequence
	end

	-- CONFIRMED (do not flip without live test feedback again): shoulder = +95 at the grab peak is
	-- correct on RightUpperArm's X axis. Z on the same joint is the lateral axis (that's what
	-- produced the earlier "swings west" bug when it was misused as the main reach) -- now used
	-- deliberately, at small magnitude, for a bit of natural sway. A small rebound keyframe before
	-- rest smooths the return out instead of snapping straight back.
	local REST = { shoulder = 0, sway = 0, elbow = 0, wrist = 0 }

	addKeyframe(0, REST)
	-- Fast snap forward-and-down into the grab, with a slight sideways sway.
	addKeyframe(0.15, { shoulder = 95, sway = 12, elbow = -60, wrist = -30 })
	-- Small rebound the other way, easing the return instead of snapping straight to rest.
	addKeyframe(0.28, { shoulder = -15, sway = -8, elbow = 10, wrist = 5 })
	addKeyframe(0.42, REST)

	return sequence
end

-- KeyframeSequenceProvider:RegisterKeyframeSequence is restricted to LocalUserSecurity -- it only
-- works when this is actually running inside Roblox Studio, never on a live published server. So
-- once SackConfig.PickupAnimationId is filled in (see setup instructions there), that baked id is
-- used directly via a plain Animation instance everywhere, and the registration call below never
-- runs at all in production. Left blank, this auto-bakes in Studio and prints the id to copy in --
-- a one-time step, same as e.g. enabling DataStore access, that genuinely can't be scripted away.
local function setupPickupAnimation()
	if SackConfig.PickupAnimationId ~= "" then
		local animation = Instance.new("Animation")
		animation.Name = "SackPickupGesture"
		animation.AnimationId = SackConfig.PickupAnimationId
		pickupAnimation = animation
		return
	end

	local ok, sequence = pcall(buildPickupSequence)
	if not ok then
		return
	end
	local registered, animId = pcall(function()
		return KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
	end)
	if not registered or not animId then
		warn("[SackSystem] couldn't bake the pickup animation -- this only works inside Roblox Studio")
		return
	end

	print(string.format(
		"[SackSystem] baked pickup animation id: %s -- paste this into SackConfig.PickupAnimationId so it also works in the published game",
		animId
	))

	local animation = Instance.new("Animation")
	animation.Name = "SackPickupGesture"
	animation.AnimationId = animId
	pickupAnimation = animation
end

-- Published as a real Animation asset via Studio's Clip Editor from the start (no Studio-only
-- baking step needed, unlike the pickup gesture's history) -- see SackConfig.TieSackAnimationId.
local function setupTieSackAnimation()
	if SackConfig.TieSackAnimationId == "" then
		return
	end
	local animation = Instance.new("Animation")
	animation.Name = "SackTieGesture"
	animation.AnimationId = SackConfig.TieSackAnimationId
	tieSackAnimation = animation
end

-- Shared by both gestures (pickup and tie-off): one load per Humanoid, cached in `trackCache`.
local function ensureTrack(humanoid, animation, trackCache)
	if not animation then
		return nil
	end
	local track = trackCache[humanoid]
	if not track then
		local loaded, newTrack = pcall(function()
			return humanoid:LoadAnimation(animation)
		end)
		if not loaded then
			return nil
		end
		newTrack.Priority = Enum.AnimationPriority.Action
		trackCache[humanoid] = newTrack
		track = newTrack
	end
	return track
end

local function playGesture(character, animation, trackCache)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local track = ensureTrack(humanoid, animation, trackCache)
	if track then
		track:Play(0.05)
	end
end

-- LoadAnimation (creating the AnimationTrack) has a one-time cost of its own on top of the
-- client's content download -- previously that only ever happened lazily on the very first actual
-- gesture, the worst possible moment. Pre-creating both tracks the instant the character spawns
-- gives it the maximum possible head start before the player can realistically reach a leaf.
local function warmGestureTracks(character)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end
	ensureTrack(humanoid, pickupAnimation, pickupTracks)
	ensureTrack(humanoid, tieSackAnimation, tieSackTracks)
end

local function onCollectLeaf(player, leaf)
	if typeof(leaf) ~= "Instance" or not leaf:IsA("BasePart") or leaf.Name ~= "Leaf" or not leaf.Parent then
		return
	end

	local storage = player:GetAttribute("SackStorage") or 0
	if storage >= SackConfig.MaxCapacity then
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end
	-- Hands-free only: can't click-collect while holding the blower, the sack, or anything else.
	if character:FindFirstChildOfClass("Tool") then
		return
	end
	if (leaf.Position - rootPart.Position).Magnitude > SackConfig.CollectMaxDistance then
		return
	end

	if LeafSpawner.CollectLeaf(leaf) then
		player:SetAttribute("SackStorage", storage + 1)
		playGesture(character, pickupAnimation, pickupTracks)
	end
end

local function onSpawnSack(player)
	local storage = player:GetAttribute("SackStorage") or 0
	if storage <= 0 then
		return
	end

	local activeSackCount = player:GetAttribute("ActiveSackCount") or 0
	local effectiveConfig = PlayerUpgrades.GetEffectiveConfig(player, SACK_TOOL_NAME)
	if activeSackCount >= effectiveConfig.MaxActiveSacks then
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local dropPosition = rootPart.Position + rootPart.CFrame.LookVector * 3
	local groundY = findGroundY(dropPosition)
	local finalPosition = Vector3.new(dropPosition.X, groundY + SackConfig.SackBodySize.Y / 2, dropPosition.Z)

	local colors = SackConfig.Cosmetics[PlayerUpgrades.GetCosmetic(player, SACK_TOOL_NAME)] or SackConfig.Cosmetics.Default
	local tool = newSackTool(storage, finalPosition, player.UserId, colors)
	tool.Parent = Workspace
	playSpawnPoofVFX(finalPosition)
	playGesture(character, tieSackAnimation, tieSackTracks)

	player:SetAttribute("SackStorage", 0)
	player:SetAttribute("ActiveSackCount", activeSackCount + 1)
end

local function onPlayerAdded(player)
	if player:GetAttribute("SackStorage") == nil then
		player:SetAttribute("SackStorage", 0)
	end
	if player:GetAttribute("ActiveSackCount") == nil then
		player:SetAttribute("ActiveSackCount", 0)
	end

	player.CharacterAdded:Connect(warmGestureTracks)
	if player.Character then
		warmGestureTracks(player.Character)
	end
end

-- Called by RoundSystem right after it reparents the round's map into Workspace (same moment it
-- calls LeafSpawner.StartYardRound()), passing that map folder directly (MapConfig-driven -- see
-- RoundSystem.luau -- rather than this module hardcoding "Map1" itself). The folder is guaranteed
-- present by then, so this never needs to wait/time out. Yard sack delivery is nil-guarded
-- (isInCleanupZone) everywhere it's read, so cleanupZone/groundPart being nil during Intermission
-- (no round active) is expected, not an error.
function SackSystem.StartYardRound(map1)
	if not map1 then
		warn("[SackSystem] StartYardRound called without a map folder -- RoundSystem should pass one in.")
		return
	end
	cleanupZone = map1:WaitForChild("CleanupZone")
	groundPart = map1:WaitForChild("Ground")
end

-- Called by RoundSystem right before it hides the map at round end -- clears the yard references
-- (rather than leaving them stale-but-pointing-at-real-parts) so a sack can't accidentally
-- register a delivery against yard coordinates while the map is hidden and nothing should be there.
function SackSystem.StopYardRound()
	cleanupZone = nil
	groundPart = nil
end

-- Called by RoundSystem right as a fresh round starts Loading, before anyone's teleported --
-- wipes anything this player could otherwise carry INTO the round to cheese an instant delivery:
-- their click-collected leaf counter (SackStorage) and every physical LeafSack Tool they're
-- holding, wherever it currently is (equipped in Character, stowed in Backpack, or dropped loose
-- in Workspace). Not a delivery -- these leaves are just discarded, not paid out, since carrying
-- them into a new round in the first place would have been the exploit.
function SackSystem.ResetPlayerForRound(player)
	player:SetAttribute("SackStorage", 0)
	player:SetAttribute("ActiveSackCount", 0)

	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, tool in ipairs(backpack:GetChildren()) do
			if tool:IsA("Tool") and tool.Name == SACK_TOOL_NAME then
				tool:Destroy()
			end
		end
	end

	local character = player.Character
	if character then
		for _, tool in ipairs(character:GetChildren()) do
			if tool:IsA("Tool") and tool.Name == SACK_TOOL_NAME then
				tool:Destroy()
			end
		end
	end

	for tool in pairs(activeSacks) do
		if tool:GetAttribute("OwnerUserId") == player.UserId then
			activeSacks[tool] = nil
			tool:Destroy()
		end
	end
end

function SackSystem.Start()
	-- StartingLobby lookup deferred to its own thread, same reasoning/pattern as LeafSpawner.Start()
	-- -- Lobby sack delivery just doesn't work until it resolves, not a hang blocking every system
	-- after this one (Remotes creation below, which several other systems' Start() calls need,
	-- stays synchronous and unaffected). Map1/yard fields are handled by StartYardRound/StopYardRound
	-- above instead of here -- see LeafSpawner's matching comment for why boot-time was wrong for them.
	task.spawn(function()
		local startingLobby = Workspace:WaitForChild("StartingLobby", 15)
		if not startingLobby then
			warn("[SackSystem] Workspace.StartingLobby not found after 15s -- Lobby sack delivery disabled this session.")
			return
		end
		lobbyCleanupZone = startingLobby:WaitForChild("LobbyCleanupZone")
	end)

	setupPickupAnimation()
	setupTieSackAnimation()
	setupPoofVFX()

	remotes = ReplicatedStorage.Shared:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage.Shared
	end

	collectLeafRemote = remotes:FindFirstChild("CollectLeaf") or Instance.new("RemoteEvent")
	collectLeafRemote.Name = "CollectLeaf"
	collectLeafRemote.Parent = remotes

	spawnSackRemote = remotes:FindFirstChild("SpawnSack") or Instance.new("RemoteEvent")
	spawnSackRemote.Name = "SpawnSack"
	spawnSackRemote.Parent = remotes

	collectLeafRemote.OnServerEvent:Connect(onCollectLeaf)
	spawnSackRemote.OnServerEvent:Connect(onSpawnSack)

	Workspace.DescendantAdded:Connect(onWorkspaceDescendantAdded)
	Workspace.DescendantRemoving:Connect(onWorkspaceDescendantRemoving)
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		onWorkspaceDescendantAdded(descendant)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	task.spawn(runSackDeliveryLoop)
end

return SackSystem
