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
local cleanupZone
local consumeVFXPart
local consumeEmitter
local consumeFlashEmitter
local leavesCleanedCount = 0
local zoneCycleCount = 0
local fallingLeaves = {}
local landedFalling = {}
local restingLeaves = {} -- leaf -> { baseX, baseZ, restY, yaw, disturbing }
local disturbances = {}
local lastPlayerPositions = {} -- player -> Vector3, used to gate disturbance on actual movement
local started = false
local deliveryListeners = {}

-- Fired whenever leaves land in the cleanup zone with a known delivering player (blown in, or a
-- sack drop-off) -- kept as a plain callback list rather than requiring MoneySystem directly, so
-- this module still doesn't need to know Coins/players exist as a concept, just that "someone"
-- may be listening. Deliveries with no attributable player (e.g. wind-drifted, nobody blowing)
-- simply never fire this.
local function notifyDelivery(player, count)
	if not player then
		return
	end
	for _, callback in ipairs(deliveryListeners) do
		callback(player, count)
	end
end

function LeafSpawner.OnLeafDelivered(callback)
	table.insert(deliveryListeners, callback)
end

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

-- The CleanupZone part itself (not an AvoidRegion -- leaves must be able to be pushed in). Used
-- both to keep leaves from randomly spawning/landing there on their own (see randomRestPosition)
-- and to detect when a glide delivers one, so it only ever "arrives" via being blown/nudged in.
local function isInCleanupZone(x, z)
	if not cleanupZone then
		return false
	end
	local halfX = cleanupZone.Size.X / 2
	local halfZ = cleanupZone.Size.Z / 2
	local center = cleanupZone.Position
	return x >= center.X - halfX and x <= center.X + halfX
		and z >= center.Z - halfZ and z <= center.Z + halfZ
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
		if not isInAvoidRegion(x, z) and not isInCleanupZone(x, z) then
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

-- Fires a quick outward particle burst at a delivered leaf's position. Reuses one shared
-- Part+ParticleEmitter (just repositioned each call) instead of creating/destroying an Instance
-- per leaf -- with potentially thousands of leaves delivered per minute, that's the difference
-- between "free" and a real cost. Emit() schedules its particles immediately and doesn't care that
-- the emitter gets moved again right after, so this stays cheap even for a burst of deliveries in
-- the same frame.
local function playConsumeVFX(position)
	if not consumeVFXPart then
		return
	end
	-- Lifted slightly above the leaf/ground so the burst reads clearly instead of half-clipping
	-- into the floor.
	consumeVFXPart.CFrame = CFrame.new(position + Vector3.new(0, 0.4, 0))
	consumeEmitter:Emit(18)
	consumeFlashEmitter:Emit(1)
end

-- Drives the billboard progress bar: a repeating quota (0 -> 100% every CleanupZoneGoal leaves),
-- not a lifetime total. Accepts a count > 1 (the sack system can deliver up to SackConfig
-- .MaxCapacity leaves in one go) -- any overshoot past the goal carries over as the start of the
-- next lap instead of being discarded, so a big delivery never silently "loses" leaves worth of
-- progress. Guarded with a generation counter (not the old "still 0" check, since the remainder
-- carried over is no longer always exactly 0) so a big batch completing several laps within the
-- same reset delay can't have a stale reset clobber a newer lap's already-in-progress fill.
local zoneResetGeneration = 0

local function registerZoneProgress(count)
	local goal = LeafConfig.CleanupZoneGoal
	zoneCycleCount += count

	if zoneCycleCount >= goal then
		zoneCycleCount = zoneCycleCount % goal
		zoneResetGeneration += 1
		local myGeneration = zoneResetGeneration
		Workspace:SetAttribute("CleanupZoneCount", goal)
		Workspace:SetAttribute("CleanupZoneProgress", 1)
		task.delay(LeafConfig.CleanupZoneResetDelay, function()
			if zoneResetGeneration == myGeneration then
				Workspace:SetAttribute("CleanupZoneCount", zoneCycleCount)
				Workspace:SetAttribute("CleanupZoneProgress", zoneCycleCount / goal)
			end
		end)
	else
		Workspace:SetAttribute("CleanupZoneCount", zoneCycleCount)
		Workspace:SetAttribute("CleanupZoneProgress", zoneCycleCount / goal)
	end
end

-- A leaf "arriving" in the cleanup zone: untracked, VFX'd, and destroyed in one shot so it can
-- never be double-counted (no lingering state anywhere still references it afterward). Increments
-- the shared LeavesCleaned count -- exposed as a Workspace attribute for later steps (UI, rewards)
-- to read without this module needing to know about players/coins yet.
local function consumeLeaf(leaf, x, y, z, player)
	restingLeaves[leaf] = nil
	playConsumeVFX(Vector3.new(x, y, z))
	leavesCleanedCount += 1
	Workspace:SetAttribute("LeavesCleaned", leavesCleanedCount)
	registerZoneProgress(1)
	notifyDelivery(player, 1)
	leaf:Destroy()
end

-- Public equivalent of consumeLeaf, for deliveries that aren't a single tracked leaf part -- the
-- sack system's whole reason for existing. `position` (optional) plays the same VFX burst a
-- blown-in leaf gets, just once for the whole batch rather than once per leaf. `player` (optional)
-- is who should be credited for the delivery, e.g. the sack's owner.
function LeafSpawner.DeliverToZone(count, position, player)
	if count <= 0 then
		return
	end
	if position then
		playConsumeVFX(position)
	end
	leavesCleanedCount += count
	Workspace:SetAttribute("LeavesCleaned", leavesCleanedCount)
	registerZoneProgress(count)
	notifyDelivery(player, count)
end

-- A leaf picked directly off the ground into a player's sack (as opposed to blown into the
-- cleanup zone) -- only resting leaves are collectible this way, and only ones not already
-- mid-glide, matching the same guard ApplyBlow uses. Returns false (does nothing) if the leaf
-- wasn't a valid, currently-resting leaf, so callers can't be tricked into double-counting one.
function LeafSpawner.CollectLeaf(leaf)
	local rest = restingLeaves[leaf]
	if not rest or rest.disturbing then
		return false
	end
	restingLeaves[leaf] = nil

	local tween = TweenService:Create(leaf, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = Vector3.new(0.05, 0.02, 0.05),
		Transparency = 1,
	})
	tween.Completed:Connect(function()
		leaf:Destroy()
	end)
	tween:Play()

	return true
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

-- If a glide's straight-line path would pass through solid geometry (a wall, fence, tree trunk),
-- reflects the leaf off the surface normal instead of just stopping dead at it -- like a leaf
-- actually deflecting off a wall rather than getting stuck against it. Raycast at roughly leaf
-- height, excluding the leaf folders themselves (leaves shouldn't block leaves).
local function clampTargetForObstacles(fromX, fromZ, y, targetX, targetZ)
	local rayHeight = y + 0.5
	local fromPos = Vector3.new(fromX, rayHeight, fromZ)
	local toPos = Vector3.new(targetX, rayHeight, targetZ)
	local offset = toPos - fromPos
	local distance = offset.Magnitude
	if distance < 0.05 then
		return targetX, targetZ
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { fallingFolder, groundFolder }

	local result = Workspace:Raycast(fromPos, offset, raycastParams)
	if result then
		local incomingDir = offset.Unit
		local hitPoint = fromPos + incomingDir * math.max(result.Distance - LeafConfig.ObstacleClearance, 0.1)

		local flatNormal = Vector3.new(result.Normal.X, 0, result.Normal.Z)
		if flatNormal.Magnitude > 0.01 then
			flatNormal = flatNormal.Unit
			local reflected = incomingDir - 2 * incomingDir:Dot(flatNormal) * flatNormal
			local leftoverDistance = math.max(distance - result.Distance, 0) * LeafConfig.BounceEnergyRatio
			local bounceTarget = hitPoint + reflected * leftoverDistance

			-- Check the bounce path too (e.g. bouncing straight into a second wall at a corner):
			-- one more clamp, no further recursive bouncing.
			local bounceOffset = bounceTarget - hitPoint
			if bounceOffset.Magnitude > 0.05 then
				local bounceResult = Workspace:Raycast(hitPoint, bounceOffset, raycastParams)
				if bounceResult then
					local safeBounceDistance = math.max(bounceResult.Distance - LeafConfig.ObstacleClearance, 0.1)
					bounceTarget = hitPoint + bounceOffset.Unit * safeBounceDistance
				end
			end

			targetX, targetZ = bounceTarget.X, bounceTarget.Z
		else
			targetX, targetZ = hitPoint.X, hitPoint.Z
		end
	end

	-- Hard backstop independent of the raycast above: a target can never end up outside the
	-- playable area at all, regardless of grazing angles or thin geometry at the map's edge.
	local halfX = spawnArea.Size.X / 2 - 2
	local halfZ = spawnArea.Size.Z / 2 - 2
	local center = spawnArea.Position
	targetX = math.clamp(targetX, center.X - halfX, center.X + halfX)
	targetZ = math.clamp(targetZ, center.Z - halfZ, center.Z + halfZ)

	return targetX, targetZ
end

-- Core "glide to a new resting spot" mechanic shared by the small footstep wind-disturbance nudge
-- and the blower's much bigger push -- only the distance/duration/lift/spin differ between them.
-- `player` (optional, nil for footstep nudges) is who gets credited with the coin reward if this
-- glide happens to land the leaf in the cleanup zone.
local function startGlide(leaf, rest, targetX, targetZ, duration, liftHeight, spinDegrees, player)
	targetX, targetZ = clampTargetForObstacles(rest.baseX, rest.baseZ, rest.restY, targetX, targetZ)

	-- Don't drag a leaf into the cleanup zone fence or house footprint.
	if isInAvoidRegion(targetX, targetZ) then
		return
	end

	rest.disturbing = true

	local spin = math.rad(spinDegrees) * (math.random() < 0.5 and -1 or 1)
	local tumbleAmplitude = math.rad(LeafConfig.GlideTumbleAmplitudeDegreesMin
		+ math.random() * (LeafConfig.GlideTumbleAmplitudeDegreesMax - LeafConfig.GlideTumbleAmplitudeDegreesMin))
	local tumbleFreq = LeafConfig.GlideTumbleFreqMin + math.random() * (LeafConfig.GlideTumbleFreqMax - LeafConfig.GlideTumbleFreqMin)

	-- Sideways sway happens perpendicular to the straight start->target line, so it reads as the
	-- leaf getting swept side to side while airborne instead of just travelling in a dead-straight
	-- path. Falls back to an arbitrary perpendicular if start and target are (almost) the same point.
	local travelDx = targetX - rest.baseX
	local travelDz = targetZ - rest.baseZ
	local travelLength = math.sqrt(travelDx * travelDx + travelDz * travelDz)
	local perpX, perpZ
	if travelLength > 0.01 then
		perpX, perpZ = -travelDz / travelLength, travelDx / travelLength
	else
		perpX, perpZ = 1, 0
	end

	local swayAmplitude = travelLength * LeafConfig.GlideSwayAmplitudeRatio
	local swayFreq = LeafConfig.GlideSwayFreqMin + math.random() * (LeafConfig.GlideSwayFreqMax - LeafConfig.GlideSwayFreqMin)
	local swayPhase = math.random() * math.pi * 2
	local flutterFreq = swayFreq * (1.4 + math.random() * 0.6)
	local flutterPhase = math.random() * math.pi * 2

	-- Randomized per-leaf so a whole batch doesn't rise/fall in obvious lockstep.
	local peakTime = LeafConfig.GlidePeakTimeMin + math.random() * (LeafConfig.GlidePeakTimeMax - LeafConfig.GlidePeakTimeMin)
	local fallExponent = LeafConfig.GlideFallExponentMin + math.random() * (LeafConfig.GlideFallExponentMax - LeafConfig.GlideFallExponentMin)

	table.insert(disturbances, {
		part = leaf,
		rest = rest,
		startX = rest.baseX,
		startZ = rest.baseZ,
		targetX = targetX,
		targetZ = targetZ,
		startYaw = rest.yaw,
		targetYaw = rest.yaw + spin,
		liftHeight = liftHeight,
		tumbleAmplitude = tumbleAmplitude,
		tumbleFreq = tumbleFreq,
		perpX = perpX,
		perpZ = perpZ,
		swayAmplitude = swayAmplitude,
		swayFreq = swayFreq,
		swayPhase = swayPhase,
		flutterFreq = flutterFreq,
		flutterPhase = flutterPhase,
		peakTime = peakTime,
		fallExponent = fallExponent,
		duration = duration,
		elapsed = 0,
		player = player,
	})
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
	local liftHeight = LeafConfig.WindLiftMin + math.random() * (LeafConfig.WindLiftMax - LeafConfig.WindLiftMin)
	local duration = LeafConfig.WindDurationMin + math.random() * (LeafConfig.WindDurationMax - LeafConfig.WindDurationMin)
	local spinDegrees = LeafConfig.WindSpinDegreesMin + math.random() * (LeafConfig.WindSpinDegreesMax - LeafConfig.WindSpinDegreesMin)

	startGlide(leaf, rest, targetX, targetZ, duration, liftHeight, spinDegrees)
end

-- Same idea, but with the blower's much bigger distance/duration, and pushed along a fixed
-- direction (where the player is aiming) instead of radially away from a point. Each leaf's
-- direction gets a random rotation within BlowDirectionJitterDegrees so a whole batch scatters
-- naturally instead of every leaf flying in one perfectly parallel line.
local function blowRestingLeaf(leaf, rest, direction, blowConfig, player)
	local jitterRad = math.rad((math.random() - 0.5) * 2 * blowConfig.BlowDirectionJitterDegrees)
	local cos, sin = math.cos(jitterRad), math.sin(jitterRad)
	local jitteredX = direction.X * cos - direction.Z * sin
	local jitteredZ = direction.X * sin + direction.Z * cos

	local pushDistance = blowConfig.BlowPushDistanceMin + math.random() * (blowConfig.BlowPushDistanceMax - blowConfig.BlowPushDistanceMin)
	local targetX = rest.baseX + jitteredX * pushDistance
	local targetZ = rest.baseZ + jitteredZ * pushDistance
	local liftHeight = blowConfig.BlowLiftMin + math.random() * (blowConfig.BlowLiftMax - blowConfig.BlowLiftMin)
	local duration = blowConfig.BlowDurationMin + math.random() * (blowConfig.BlowDurationMax - blowConfig.BlowDurationMin)
	local spinDegrees = blowConfig.BlowSpinDegreesMin + math.random() * (blowConfig.BlowSpinDegreesMax - blowConfig.BlowSpinDegreesMin)

	startGlide(leaf, rest, targetX, targetZ, duration, liftHeight, spinDegrees, player)
end

-- Glides the leaf from its old spot to the new one, but not in a straight line: a perpendicular
-- sway (plus a faster flutter layered on top) sweeps it side to side, and the vertical motion is
-- asymmetric -- quick rise to a per-leaf peak, then a slow, lingering drift back down that only
-- settles right at the very end -- rather than a symmetric bounce, so it reads as featherweight
-- and caught in moving air rather than hopping directly from A to B. Everything (sway, flutter,
-- tumble) is scaled by the same envelope, so it's exactly 0 at the start/end -- it still lands
-- precisely on target, flat. Once it arrives, the leaf's resting position updates for good.
local function updateDisturbances(dt)
	for i = #disturbances, 1, -1 do
		local state = disturbances[i]
		state.elapsed += dt
		local t = math.clamp(state.elapsed / state.duration, 0, 1)
		local ease = t * t * (3 - 2 * t)

		local envelope
		if t <= state.peakTime then
			envelope = math.sin((t / state.peakTime) * math.pi / 2)
		else
			local fallT = (t - state.peakTime) / (1 - state.peakTime)
			envelope = (1 - fallT) ^ state.fallExponent
		end

		if state.part.Parent then
			-- Driven by real elapsed seconds (not t, which is 0-1 over the whole glide) so the
			-- sway/flutter rate stays consistent regardless of how long any given glide lasts.
			local sway = (math.sin(state.elapsed * state.swayFreq * math.pi * 2 + state.swayPhase)
				+ math.sin(state.elapsed * state.flutterFreq * math.pi * 2 + state.flutterPhase) * 0.4) * state.swayAmplitude * envelope

			local x = state.startX + (state.targetX - state.startX) * ease + state.perpX * sway
			local z = state.startZ + (state.targetZ - state.startZ) * ease + state.perpZ * sway

			local verticalFlutter = math.sin(state.elapsed * state.flutterFreq * math.pi * 2 + state.flutterPhase + 1)
				* state.liftHeight * LeafConfig.GlideVerticalFlutterRatio * envelope
			local y = state.rest.restY + state.liftHeight * envelope + verticalFlutter

			local yaw = state.startYaw + (state.targetYaw - state.startYaw) * ease
			local tumbleX = math.sin(state.elapsed * state.tumbleFreq * math.pi * 2) * state.tumbleAmplitude * envelope
			local tumbleZ = math.cos(state.elapsed * state.tumbleFreq * math.pi * 2 * 0.7) * state.tumbleAmplitude * envelope
			state.part.CFrame = CFrame.new(x, y, z) * CFrame.Angles(tumbleX, yaw, tumbleZ)
		end

		if t >= 1 then
			if isInCleanupZone(state.targetX, state.targetZ) then
				consumeLeaf(state.part, state.targetX, state.rest.restY, state.targetZ, state.player)
			else
				state.rest.baseX = state.targetX
				state.rest.baseZ = state.targetZ
				state.rest.yaw = state.targetYaw
				state.rest.disturbing = false
			end
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

-- Called by BlowerTool on a timer while a player's blower is equipped: pushes every resting leaf
-- within the cone further along `direction`, and nudges the landing target of any still-falling
-- leaf caught in the cone so it visibly redirects as it drops. `blowConfig` is BlowerConfig itself
-- (a plain table of Blow* tuning values) -- this module doesn't need to know it's from the blower.
-- `player` is who's holding the blower, credited with coins for any leaf this push lands in the
-- cleanup zone.
function LeafSpawner.ApplyBlow(player, origin, direction, blowConfig)
	local cosHalfAngle = math.cos(math.rad(blowConfig.BlowConeAngleDegrees / 2))
	local range = blowConfig.BlowRange

	for leaf, rest in pairs(restingLeaves) do
		if not rest.disturbing then
			local toLeafX = rest.baseX - origin.X
			local toLeafZ = rest.baseZ - origin.Z
			local distance = math.sqrt(toLeafX * toLeafX + toLeafZ * toLeafZ)
			if distance > 0.05 and distance <= range then
				local dot = (toLeafX * direction.X + toLeafZ * direction.Z) / distance
				if dot >= cosHalfAngle then
					blowRestingLeaf(leaf, rest, direction, blowConfig, player)
				end
			end
		end
	end

	for _, state in ipairs(fallingLeaves) do
		local toLeafX = state.baseX - origin.X
		local toLeafZ = state.baseZ - origin.Z
		local distance = math.sqrt(toLeafX * toLeafX + toLeafZ * toLeafZ)
		if distance <= range then
			local dot = distance > 0.05 and (toLeafX * direction.X + toLeafZ * direction.Z) / distance or 1
			if dot >= cosHalfAngle then
				local wantedX = state.baseX + direction.X * blowConfig.FallingRedirectPerTick
				local wantedZ = state.baseZ + direction.Z * blowConfig.FallingRedirectPerTick
				-- Same obstacle clamp as resting leaves -- this path was missing it before, which
				-- is why leaves being blown mid-air could still sail through walls/boundary edges.
				local newX, newZ = clampTargetForObstacles(state.baseX, state.baseZ, state.restY, wantedX, wantedZ)
				if not isInAvoidRegion(newX, newZ) then
					state.baseX = newX
					state.baseZ = newZ
				end
			end
		end
	end
end

function LeafSpawner.Start()
	if started then
		return
	end
	started = true

	spawnArea = Workspace:WaitForChild("LeafSpawnArea")
	cleanupZone = Workspace:WaitForChild("CleanupZone")
	local ground = Workspace:WaitForChild("Ground")
	groundTop = ground.Position.Y + ground.Size.Y / 2

	-- Single reused VFX source for every leaf consumed by the cleanup zone -- see playConsumeVFX.
	consumeVFXPart = Instance.new("Part")
	consumeVFXPart.Name = "LeafConsumeVFX"
	consumeVFXPart.Anchored = true
	consumeVFXPart.CanCollide = false
	consumeVFXPart.CanQuery = false
	consumeVFXPart.CastShadow = false
	consumeVFXPart.Transparency = 1
	consumeVFXPart.Size = Vector3.new(0.2, 0.2, 0.2)
	consumeVFXPart.CFrame = CFrame.new(cleanupZone.Position)
	consumeVFXPart.Parent = Workspace

	-- Bright sparkle burst, arcing outward/upward then falling -- color deliberately far from the
	-- CleanupZone platform's own gold/orange tint (and from the leaves themselves) so it reads
	-- clearly against both instead of blending in.
	consumeEmitter = Instance.new("ParticleEmitter")
	consumeEmitter.Name = "ConsumeBurst"
	consumeEmitter.Enabled = false
	consumeEmitter.Rate = 0
	consumeEmitter.Lifetime = NumberRange.new(0.25, 0.45)
	consumeEmitter.Speed = NumberRange.new(10, 18)
	consumeEmitter.SpreadAngle = Vector2.new(55, 55)
	consumeEmitter.Acceleration = Vector3.new(0, -28, 0)
	consumeEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.5, 0.65),
		NumberSequenceKeypoint.new(1, 0),
	})
	consumeEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	consumeEmitter.Color = ColorSequence.new(Color3.fromRGB(150, 255, 190))
	consumeEmitter.LightEmission = 1
	consumeEmitter.LightInfluence = 0
	consumeEmitter.Parent = consumeVFXPart

	-- A single big, bright, near-instant flash layered under the sparkles -- the actual "pop" that
	-- catches the eye even mid-blow when a dozen other leaves are moving on screen.
	consumeFlashEmitter = Instance.new("ParticleEmitter")
	consumeFlashEmitter.Name = "ConsumeFlash"
	consumeFlashEmitter.Enabled = false
	consumeFlashEmitter.Rate = 0
	consumeFlashEmitter.Lifetime = NumberRange.new(0.18, 0.18)
	consumeFlashEmitter.Speed = NumberRange.new(0, 0)
	consumeFlashEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.6),
		NumberSequenceKeypoint.new(1, 3.4),
	})
	consumeFlashEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	consumeFlashEmitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	consumeFlashEmitter.LightEmission = 1
	consumeFlashEmitter.LightInfluence = 0
	consumeFlashEmitter.Parent = consumeVFXPart

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
