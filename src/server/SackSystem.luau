local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local SackConfig = require(ReplicatedStorage.Shared.SackConfig)
local LeafSpawner = require(script.Parent.LeafSpawner)

local SackSystem = {}

local SACK_TOOL_NAME = "LeafSack"
local SACK_DELIVERY_INTERVAL = 0.2
local POOF_LIGHT_DIM_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local cleanupZone
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
-- CFrame assignment after the fact.
local function newSackTool(leafCount, position, ownerUserId)
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
	handle.Color = SackConfig.SackColor
	handle.Material = Enum.Material.Fabric
	handle.CanCollide = true
	handle.CastShadow = true
	handle.CFrame = handleCFrame
	handle.Parent = tool

	local tie = Instance.new("Part")
	tie.Name = "Tie"
	tie.Size = SackConfig.SackTieSize
	tie.Color = SackConfig.SackTieColor
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
			if handle and isInCleanupZone(handle.Position) then
				local leafCount = tool:GetAttribute("LeafCount") or 0
				activeSacks[tool] = nil
				LeafSpawner.DeliverToZone(leafCount, handle.Position)

				local ownerUserId = tool:GetAttribute("OwnerUserId")
				local owner = ownerUserId and Players:GetPlayerByUserId(ownerUserId)
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

-- Registration can fail depending on context, so this is all best-effort: if it doesn't work out,
-- the gesture just silently doesn't play rather than breaking leaf collection itself.
local function setupPickupAnimation()
	local ok, sequence = pcall(buildPickupSequence)
	if not ok then
		return
	end
	local registered, animId = pcall(function()
		return KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
	end)
	if not registered or not animId then
		return
	end
	local animation = Instance.new("Animation")
	animation.Name = "SackPickupGesture"
	animation.AnimationId = animId
	pickupAnimation = animation
end

local function playPickupGesture(character)
	if not pickupAnimation then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local track = pickupTracks[humanoid]
	if not track then
		local loaded, newTrack = pcall(function()
			return humanoid:LoadAnimation(pickupAnimation)
		end)
		if not loaded then
			return
		end
		newTrack.Priority = Enum.AnimationPriority.Action
		pickupTracks[humanoid] = newTrack
		track = newTrack
	end

	track:Play(0.05)
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
		playPickupGesture(character)
	end
end

local function onSpawnSack(player)
	local storage = player:GetAttribute("SackStorage") or 0
	if storage <= 0 then
		return
	end

	local activeSackCount = player:GetAttribute("ActiveSackCount") or 0
	if activeSackCount >= SackConfig.MaxActiveSacks then
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

	local tool = newSackTool(storage, finalPosition, player.UserId)
	tool.Parent = Workspace
	playSpawnPoofVFX(finalPosition)

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
end

function SackSystem.Start()
	cleanupZone = Workspace:WaitForChild("CleanupZone")
	groundPart = Workspace:WaitForChild("Ground")
	setupPickupAnimation()
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
