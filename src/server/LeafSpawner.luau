local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LeafConfig = require(ReplicatedStorage.Shared.LeafConfig)
local WindConfig = require(ReplicatedStorage.Shared.WindConfig)

local LeafSpawner = {}

local fallingFolder
local groundFolder
local spawnArea
local groundTop
local fallingLeaves = {}
local landedFalling = {}
local restingLeaves = {} -- leaf -> { baseX, baseZ, restY, yaw, disturbing }
local disturbances = {}
local lastPlayerPositions = {} -- player -> Vector3, used to gate disturbance on actual movement
local started = false

local function isInAvoidRegion(x, z)
	for _, region in pairs(LeafConfig.AvoidRegions) do
		local halfX = region.Size.X / 2
		local halfZ = region.Size.Z / 2
		if x >= region.Center.X - halfX and x <= region.Center.X + halfX
			and z >= region.Center.Z - halfZ and z <= region.Center.Z + halfZ then
			return true
		end
	end
	return false
end

-- X/Z sampled from the spawn-area footprint, but the resting height comes from the actual
-- Ground part's surface (not the thin transparent LeafSpawnArea overlay) so leaves are
-- planted on the grass instead of levitating on top of that overlay.
local function randomRestPosition()
	local center = spawnArea.Position
	local size = spawnArea.Size
	local y = groundTop + LeafConfig.LeafSize.Y / 2

	for _ = 1, 10 do
		local x = center.X + (math.random() - 0.5) * size.X
		local z = center.Z + (math.random() - 0.5) * size.Z
		if not isInAvoidRegion(x, z) then
			return Vector3.new(x, y, z)
		end
	end

	return Vector3.new(center.X, y, center.Z)
end

local function createLeaf(restPosition)
	local leaf = Instance.new("Part")
	leaf.Name = "Leaf"
	leaf.Anchored = true
	leaf.CanCollide = false
	leaf.CastShadow = false
	leaf.Size = LeafConfig.LeafSize
	leaf.Color = LeafConfig.Colors[math.random(1, #LeafConfig.Colors)]
	leaf.Material = Enum.Material.Grass
	leaf.TopSurface = Enum.SurfaceType.Smooth
	leaf.BottomSurface = Enum.SurfaceType.Smooth
	leaf.CFrame = CFrame.new(restPosition)
	return leaf
end

-- Tracks a leaf as "at rest" so the wind-disturbance scan can find and nudge it.
local function markResting(leaf, restPosition, yaw)
	restingLeaves[leaf] = {
		baseX = restPosition.X,
		baseZ = restPosition.Z,
		restY = restPosition.Y,
		yaw = yaw,
		disturbing = false,
	}
end

-- Fades a leaf out and removes it. Called once a leaf's lifetime on the ground expires.
local function despawnLeaf(leaf)
	if not leaf or not leaf.Parent then
		return
	end
	restingLeaves[leaf] = nil
	local tween = TweenService:Create(leaf, TweenInfo.new(LeafConfig.DespawnFadeDuration, Enum.EasingStyle.Sine), { Transparency = 1 })
	tween.Completed:Connect(function()
		leaf:Destroy()
	end)
	tween:Play()
end

-- Scheduled once per leaf via task.delay (cheap engine-side timer, no per-frame polling) rather than
-- tracking ages in a list, so despawning many leaves stays optimized as the leaf count grows.
local function scheduleDespawn(leaf, lifetimeMin, lifetimeMax)
	local lifetime = lifetimeMin + math.random() * (lifetimeMax - lifetimeMin)
	task.delay(lifetime, despawnLeaf, leaf)
end

-- Same as scheduleDespawn, but also removes the leaf from the landedFalling FIFO once its
-- natural lifetime expires, so that list only ever tracks leaves that are still alive.
local function scheduleFallingDespawn(leaf)
	local lifetime = LeafConfig.FallingLifetimeMin + math.random() * (LeafConfig.FallingLifetimeMax - LeafConfig.FallingLifetimeMin)
	task.delay(lifetime, function()
		local index = table.find(landedFalling, leaf)
		if index then
			table.remove(landedFalling, index)
		end
		despawnLeaf(leaf)
	end)
end

-- Kicks off a scripted (non-physics) fall: eased descent + wind-carried drift + sideways sway +
-- tumble, driven by one shared Heartbeat loop. The leaf's landing spot (restPosition) stays fixed
-- (already avoid-region-checked); wind instead offsets where it visually SPAWNS, upwind of that
-- landing spot, so it appears to be blown in from the current wind direction as it falls.
local function beginFall(leaf, restPosition)
	local fallHeight = LeafConfig.FallHeightMin + math.random() * (LeafConfig.FallHeightMax - LeafConfig.FallHeightMin)
	local fallSpeed = LeafConfig.FallSpeedMin + math.random() * (LeafConfig.FallSpeedMax - LeafConfig.FallSpeedMin)
	local duration = fallHeight / fallSpeed
	local swayAmplitude = LeafConfig.SwayAmplitudeMin + math.random() * (LeafConfig.SwayAmplitudeMax - LeafConfig.SwayAmplitudeMin)
	local tumbleAmplitude = math.rad(LeafConfig.TumbleAmplitudeDegreesMin + math.random() * (LeafConfig.TumbleAmplitudeDegreesMax - LeafConfig.TumbleAmplitudeDegreesMin))
	local swayFreqX = 1.2 + math.random() * 1.3
	local swayFreqZ = 1.2 + math.random() * 1.3
	local flutterMult = LeafConfig.FlutterFreqMultiplierMin + math.random() * (LeafConfig.FlutterFreqMultiplierMax - LeafConfig.FlutterFreqMultiplierMin)

	local windName = Workspace:GetAttribute("WindDirection")
	local windVector = (windName and WindConfig.Vectors[windName]) or Vector3.new(0, 0, 0)
	local driftVariance = LeafConfig.WindFallDriftVarianceMin + math.random() * (LeafConfig.WindFallDriftVarianceMax - LeafConfig.WindFallDriftVarianceMin)
	local windDrift = LeafConfig.WindFallDriftPerSecond * duration * driftVariance
	local spawnBaseX = restPosition.X - windVector.X * windDrift
	local spawnBaseZ = restPosition.Z - windVector.Z * windDrift

	local state = {
		part = leaf,
		baseX = restPosition.X,
		baseZ = restPosition.Z,
		spawnBaseX = spawnBaseX,
		spawnBaseZ = spawnBaseZ,
		restY = restPosition.Y,
		spawnY = restPosition.Y + fallHeight,
		duration = duration,
		elapsed = 0,
		swayAmplitude = swayAmplitude,
		swayFreqX = swayFreqX,
		swayFreqZ = swayFreqZ,
		flutterFreqX = swayFreqX * flutterMult,
		flutterFreqZ = swayFreqZ * flutterMult,
		phaseX = math.random() * math.pi * 2,
		phaseZ = math.random() * math.pi * 2,
		flutterPhaseX = math.random() * math.pi * 2,
		flutterPhaseZ = math.random() * math.pi * 2,
		spinSpeed = (math.random() - 0.5) * 6,
		tumbleAmplitude = tumbleAmplitude,
		tumbleFreq = 1 + math.random() * 1.5,
		initialYaw = math.rad(math.random(0, 360)),
	}

	leaf.CFrame = CFrame.new(spawnBaseX, state.spawnY, spawnBaseZ)
	table.insert(fallingLeaves, state)
end

-- Sway/tumble amplitude fades to exactly 0 as t approaches 1, so the leaf's swept path
-- naturally converges on (baseX, restY, baseZ) with no snap when it lands. The sway/flutter
-- itself orbits a wind anchor that glides from the upwind spawn point to the landing spot
-- (same easing as the vertical fall), so the whole trajectory reads as wind-carried.
local function computeLeafCFrame(state, t)
	local yEase = t * t * (3 - 2 * t)
	local y = state.spawnY - (state.spawnY - state.restY) * yEase

	local windAnchorX = state.spawnBaseX + (state.baseX - state.spawnBaseX) * yEase
	local windAnchorZ = state.spawnBaseZ + (state.baseZ - state.spawnBaseZ) * yEase

	local driftFactor = 1 - t
	local flutterScale = LeafConfig.FlutterAmplitudeRatio

	local swayX = math.sin(t * state.swayFreqX * math.pi * 2 + state.phaseX)
	local flutterX = math.sin(t * state.flutterFreqX * math.pi * 2 + state.flutterPhaseX) * flutterScale
	local x = windAnchorX + (swayX + flutterX) * state.swayAmplitude * driftFactor

	local swayZ = math.cos(t * state.swayFreqZ * math.pi * 2 + state.phaseZ)
	local flutterZ = math.cos(t * state.flutterFreqZ * math.pi * 2 + state.flutterPhaseZ) * flutterScale
	local z = windAnchorZ + (swayZ + flutterZ) * state.swayAmplitude * driftFactor

	local yaw = state.initialYaw + state.spinSpeed * state.elapsed
	local tumbleX = math.sin(state.elapsed * state.tumbleFreq * math.pi * 2) * state.tumbleAmplitude * driftFactor
	local tumbleZ = math.cos(state.elapsed * state.tumbleFreq * math.pi * 2 * 0.7) * state.tumbleAmplitude * driftFactor

	return CFrame.new(x, y, z) * CFrame.Angles(tumbleX, yaw, tumbleZ)
end

-- Pushes a resting leaf to an actual new spot a short distance away (not back to where it
-- started) so repeated gusts genuinely relocate it over time instead of springing back like
-- a boomerang. Guarded by rest.disturbing so a lingering player doesn't restart it mid-glide.
local function triggerDisturbance(leaf, fromPosition)
	local rest = restingLeaves[leaf]
	if not rest or rest.disturbing then
		return
	end

	local dirX = rest.baseX - fromPosition.X
	local dirZ = rest.baseZ - fromPosition.Z
	local length = math.sqrt(dirX * dirX + dirZ * dirZ)
	if length < 0.001 then
		dirX, dirZ = 1, 0
	else
		dirX, dirZ = dirX / length, dirZ / length
	end

	local pushDistance = LeafConfig.WindPushMin + math.random() * (LeafConfig.WindPushMax - LeafConfig.WindPushMin)
	local targetX = rest.baseX + dirX * pushDistance
	local targetZ = rest.baseZ + dirZ * pushDistance

	-- Don't drag a leaf into the cleanup zone fence or house footprint.
	if isInAvoidRegion(targetX, targetZ) then
		return
	end

	rest.disturbing = true

	local spin = math.rad(LeafConfig.WindSpinDegreesMin + math.random() * (LeafConfig.WindSpinDegreesMax - LeafConfig.WindSpinDegreesMin))
		* (math.random() < 0.5 and -1 or 1)

	table.insert(disturbances, {
		part = leaf,
		rest = rest,
		startX = rest.baseX,
		startZ = rest.baseZ,
		targetX = targetX,
		targetZ = targetZ,
		startYaw = rest.yaw,
		targetYaw = rest.yaw + spin,
		liftHeight = LeafConfig.WindLiftMin + math.random() * (LeafConfig.WindLiftMax - LeafConfig.WindLiftMin),
		duration = LeafConfig.WindDurationMin + math.random() * (LeafConfig.WindDurationMax - LeafConfig.WindDurationMin),
		elapsed = 0,
	})
end

-- Glides the leaf from its old spot to the new one (smoothstep), with a small hop mid-glide.
-- Once it arrives, the leaf's resting position is updated to the new spot for good.
local function updateDisturbances(dt)
	for i = #disturbances, 1, -1 do
		local state = disturbances[i]
		state.elapsed += dt
		local t = math.clamp(state.elapsed / state.duration, 0, 1)
		local ease = t * t * (3 - 2 * t)
		local hop = math.sin(t * math.pi)

		if state.part.Parent then
			local x = state.startX + (state.targetX - state.startX) * ease
			local z = state.startZ + (state.targetZ - state.startZ) * ease
			local y = state.rest.restY + state.liftHeight * hop
			local yaw = state.startYaw + (state.targetYaw - state.startYaw) * ease
			state.part.CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
		end

		if t >= 1 then
			state.rest.baseX = state.targetX
			state.rest.baseZ = state.targetZ
			state.rest.yaw = state.targetYaw
			state.rest.disturbing = false
			table.remove(disturbances, i)
		end
	end
end

local function updateFallingLeaves(dt)
	for i = #fallingLeaves, 1, -1 do
		local state = fallingLeaves[i]
		state.elapsed += dt
		local t = math.clamp(state.elapsed / state.duration, 0, 1)

		state.part.CFrame = computeLeafCFrame(state, t)

		if t >= 1 then
			table.remove(fallingLeaves, i)

			local landedYaw = state.initialYaw + state.spinSpeed * state.elapsed
			markResting(state.part, Vector3.new(state.baseX, state.restY, state.baseZ), landedYaw)

			table.insert(landedFalling, state.part)
			if #landedFalling > LeafConfig.FallingMaxLanded then
				local oldest = table.remove(landedFalling, 1)
				despawnLeaf(oldest)
			end
			scheduleFallingDespawn(state.part)
		end
	end
end

-- Hysteresis refill: fills up to FallingTargetCount then pauses, and only starts topping up
-- again once the total on-map count drops to FallingResumeBelow (via natural despawns, or later,
-- players clearing leaves at the cleanup zone). Avoids both "stuck at cap forever" and "never stops".
local function runFallingSpawnLoop()
	local refilling = true
	while true do
		local currentTotal = #fallingFolder:GetChildren()

		if refilling and currentTotal >= LeafConfig.FallingTargetCount then
			refilling = false
		elseif not refilling and currentTotal <= LeafConfig.FallingResumeBelow then
			refilling = true
		end

		if refilling and #fallingLeaves < LeafConfig.FallingMaxConcurrent then
			local toSpawn = math.min(
				LeafConfig.FallingSpawnBatchSize,
				LeafConfig.FallingTargetCount - currentTotal,
				LeafConfig.FallingMaxConcurrent - #fallingLeaves
			)
			for _ = 1, math.max(toSpawn, 0) do
				local restPosition = randomRestPosition()
				local leaf = createLeaf(restPosition)
				leaf.Parent = fallingFolder
				beginFall(leaf, restPosition)
			end
		end

		task.wait(LeafConfig.FallingSpawnInterval)
	end
end

-- Places a leaf directly at rest with a random yaw, no fall animation, for ambient ground clutter.
local function spawnGroundLeaf()
	local restPosition = randomRestPosition()
	local leaf = createLeaf(restPosition)
	local yaw = math.rad(math.random(0, 360))
	leaf.CFrame = CFrame.new(restPosition) * CFrame.Angles(0, yaw, 0)
	leaf.Parent = groundFolder
	markResting(leaf, restPosition, yaw)
	scheduleDespawn(leaf, LeafConfig.GroundLifetimeMin, LeafConfig.GroundLifetimeMax)
end

local function runGroundSpawnLoop()
	while true do
		local currentCount = #groundFolder:GetChildren()
		if currentCount < LeafConfig.GroundMaxLeaves then
			local toSpawn = math.min(LeafConfig.GroundSpawnBatchSize, LeafConfig.GroundMaxLeaves - currentCount)
			for _ = 1, toSpawn do
				spawnGroundLeaf()
			end
		end
		task.wait(LeafConfig.GroundSpawnInterval)
	end
end

-- Periodic (not per-frame) spatial query around each player, using the engine's own broadphase
-- rather than looping every leaf in Lua, so this stays cheap regardless of leaf count.
-- Only runs the query when the player has actually moved since the last tick, so standing still
-- next to a leaf (even right on top of it) never triggers a disturbance.
local function runWindDisturbanceLoop()
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { fallingFolder, groundFolder }

	while true do
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				local position = rootPart.Position
				local lastPosition = lastPlayerPositions[player]
				local movedDistance = lastPosition and (position - lastPosition).Magnitude or 0
				lastPlayerPositions[player] = position

				if movedDistance > LeafConfig.WindMinMoveDistance then
					local nearbyParts = Workspace:GetPartBoundsInRadius(position, LeafConfig.WindDisturbRadius, overlapParams)
					for _, part in ipairs(nearbyParts) do
						triggerDisturbance(part, position)
					end
				end
			end
		end
		task.wait(LeafConfig.WindScanInterval)
	end
end

Players.PlayerRemoving:Connect(function(player)
	lastPlayerPositions[player] = nil
end)

function LeafSpawner.Start()
	if started then
		return
	end
	started = true

	spawnArea = Workspace:WaitForChild("LeafSpawnArea")
	local ground = Workspace:WaitForChild("Ground")
	groundTop = ground.Position.Y + ground.Size.Y / 2

	local leavesFolder = Instance.new("Folder")
	leavesFolder.Name = "Leaves"
	leavesFolder.Parent = Workspace

	fallingFolder = Instance.new("Folder")
	fallingFolder.Name = "Falling"
	fallingFolder.Parent = leavesFolder

	groundFolder = Instance.new("Folder")
	groundFolder.Name = "Ground"
	groundFolder.Parent = leavesFolder

	RunService.Heartbeat:Connect(function(dt)
		updateFallingLeaves(dt)
		updateDisturbances(dt)
	end)

	task.spawn(runFallingSpawnLoop)
	task.spawn(runGroundSpawnLoop)
	task.spawn(runWindDisturbanceLoop)
end

return LeafSpawner
