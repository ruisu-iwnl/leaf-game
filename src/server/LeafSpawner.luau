local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LeafConfig = require(ReplicatedStorage.Shared.LeafConfig)
local LeafMotion = require(ReplicatedStorage.Shared.LeafMotion)
local WindConfig = require(ReplicatedStorage.Shared.WindConfig)

-- Leaf motion (falling + wind/blower glides) used to be simulated server-side on a per-Heartbeat
-- loop that wrote each moving leaf's CFrame directly, every tick, for the whole game to see via
-- ordinary property replication. That looked smooth at low ping, but choppy/laggy at higher ping:
-- Roblox doesn't interpolate Anchored-part CFrame changes the way it does physics-driven parts,
-- so each client just snaps to whatever CFrame value last arrived, and a backlog of that much
-- replication traffic (up to ~300 leaves updating 60x/second) arriving in a burst under high ping
-- could stall a client's frame entirely, making everything else (UI tweens included) hitch too.
--
-- Now the server only decides WHEN and WHERE a leaf's motion happens (spawn/target position,
-- duration, wind, obstacle bounces -- all unchanged) and replicates those PARAMETERS once, via
-- Attributes, when the motion starts (see beginFall/startGlide). Each client then renders the
-- actual frame-by-frame motion locally (LeafRenderer.luau), using the exact same math
-- (LeafMotion.luau) and a server-synced clock (Workspace:GetServerTimeNow()) so playback is smooth
-- regardless of ping -- latency only delays noticing a leaf started moving, never the smoothness
-- of the motion itself. The server schedules each motion's end with a single task.delay instead of
-- polling every leaf every frame, which is also just less server work overall.
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
local fallingLeaves = {} -- part -> state, only leaves CURRENTLY falling (for the blower's mid-air redirect)
local landedFalling = {}
local restingLeaves = {} -- leaf -> { baseX, baseZ, restY, yaw, disturbing }
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

-- Small random per-landing height bump so a leaf landing wherever other leaves already are reads as
-- settling into a pile instead of always lying dead flat. Reuses the same tuning range the initial
-- ground clusters stack with, so a leaf that gets blown into an existing pile looks consistent with
-- one that spawned there.
--
-- Baked directly into the replicated restY (FallRestY/GlideRestY) that the motion converges toward,
-- NOT added after the fact to the final CFrame: the client renders every frame straight from those
-- attributes (LeafRenderer.luau), so a bump applied only in the server's landing callback below would
-- just get overwritten by the client's own next Heartbeat render. The leaf's tracked rest.restY (the
-- flat, constant ground height used as the baseline for its NEXT glide) is deliberately never updated
-- with this bump, so repeated moves can't make a leaf drift upward over a play session -- each landing
-- rolls a fresh small bump off the same stable floor instead of stacking on the previous one.
local function randomStackHeight()
	return LeafConfig.GroundStackHeightMin + math.random() * (LeafConfig.GroundStackHeightMax - LeafConfig.GroundStackHeightMin)
end

-- Kicks off a scripted (non-physics) fall: eased descent + wind-carried drift + sideways sway +
-- tumble. The leaf's landing spot (restPosition) stays fixed (already avoid-region-checked); wind
-- instead offsets where it visually SPAWNS, upwind of that landing spot, so it appears to be blown
-- in from the current wind direction as it falls.
--
-- The motion itself is replicated as PARAMETERS (Attributes), not a per-frame CFrame stream --
-- clients render it locally via LeafMotion/LeafRenderer. This function only sets the leaf's
-- starting pose directly; task.delay schedules the landing at the exact computed duration.
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
	local spawnY = restPosition.Y + fallHeight
	-- The flat ground height plus a fresh random pile bump -- see randomStackHeight's comment.
	local groundY = restPosition.Y
	local restY = groundY + randomStackHeight()

	-- Kept as the params table LeafMotion.ComputeFalling expects -- also what ApplyBlow mutates
	-- (baseX/baseZ) to redirect a still-falling leaf caught in the blower's cone.
	local state = {
		part = leaf,
		baseX = restPosition.X,
		baseZ = restPosition.Z,
		spawnBaseX = spawnBaseX,
		spawnBaseZ = spawnBaseZ,
		restY = restY,
		spawnY = spawnY,
		duration = duration,
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

	leaf.CFrame = CFrame.new(spawnBaseX, spawnY, spawnBaseZ)

	leaf:SetAttribute("FallSpawnX", spawnBaseX)
	leaf:SetAttribute("FallSpawnY", spawnY)
	leaf:SetAttribute("FallSpawnZ", spawnBaseZ)
	leaf:SetAttribute("FallTargetX", state.baseX)
	leaf:SetAttribute("FallTargetZ", state.baseZ)
	leaf:SetAttribute("FallRestY", state.restY)
	leaf:SetAttribute("FallSwayAmplitude", swayAmplitude)
	leaf:SetAttribute("FallSwayFreqX", swayFreqX)
	leaf:SetAttribute("FallSwayFreqZ", swayFreqZ)
	leaf:SetAttribute("FallPhaseX", state.phaseX)
	leaf:SetAttribute("FallPhaseZ", state.phaseZ)
	leaf:SetAttribute("FallFlutterFreqX", state.flutterFreqX)
	leaf:SetAttribute("FallFlutterFreqZ", state.flutterFreqZ)
	leaf:SetAttribute("FallFlutterPhaseX", state.flutterPhaseX)
	leaf:SetAttribute("FallFlutterPhaseZ", state.flutterPhaseZ)
	leaf:SetAttribute("FallInitialYaw", state.initialYaw)
	leaf:SetAttribute("FallSpinSpeed", state.spinSpeed)
	leaf:SetAttribute("FallTumbleAmplitude", tumbleAmplitude)
	leaf:SetAttribute("FallTumbleFreq", state.tumbleFreq)
	leaf:SetAttribute("MotionDuration", duration)
	leaf:SetAttribute("MotionKind", "Fall")
	-- Set LAST: this is the one attribute clients watch to detect a new motion, so everything else
	-- it needs is guaranteed to already be in place (same replication batch) by the time it fires.
	leaf:SetAttribute("MotionStart", Workspace:GetServerTimeNow())

	fallingLeaves[leaf] = state

	task.delay(duration, function()
		fallingLeaves[leaf] = nil
		if not leaf.Parent then
			return
		end

		local landedYaw = state.initialYaw + state.spinSpeed * duration
		local finalCFrame = LeafMotion.ComputeFalling(state, duration)
		leaf.CFrame = finalCFrame
		-- Tracked at the stable, unbumped ground height (not finalCFrame's actual bumped Y) so this
		-- leaf's NEXT glide keeps computing from a fixed baseline instead of drifting upward over
		-- repeated moves. See randomStackHeight's comment.
		markResting(leaf, Vector3.new(finalCFrame.Position.X, groundY, finalCFrame.Position.Z), landedYaw)

		table.insert(landedFalling, leaf)
		if #landedFalling > LeafConfig.FallingMaxLanded then
			local oldest = table.remove(landedFalling, 1)
			despawnLeaf(oldest)
		end
		scheduleFallingDespawn(leaf)
	end)
end

-- Core "glide to a new resting spot" mechanic shared by the small footstep wind-disturbance nudge
-- and the blower's much bigger push -- only the distance/duration/lift/spin differ between them.
-- `player` (optional, nil for footstep nudges) is who gets credited with the coin reward if this
-- glide happens to land the leaf in the cleanup zone.
--
-- Same replicate-parameters-once approach as beginFall -- see the top-of-file note.
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

	-- A fresh random pile bump for wherever this glide lands -- see randomStackHeight's comment.
	-- rest.restY itself (the flat, constant ground height) is never modified, only read.
	local landingRestY = rest.restY + randomStackHeight()

	local params = {
		startX = rest.baseX,
		startZ = rest.baseZ,
		restY = landingRestY,
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
	}

	leaf:SetAttribute("GlideStartX", params.startX)
	leaf:SetAttribute("GlideStartZ", params.startZ)
	leaf:SetAttribute("GlideRestY", params.restY)
	leaf:SetAttribute("GlideTargetX", params.targetX)
	leaf:SetAttribute("GlideTargetZ", params.targetZ)
	leaf:SetAttribute("GlideStartYaw", params.startYaw)
	leaf:SetAttribute("GlideTargetYaw", params.targetYaw)
	leaf:SetAttribute("GlideLiftHeight", params.liftHeight)
	leaf:SetAttribute("GlideTumbleAmplitude", params.tumbleAmplitude)
	leaf:SetAttribute("GlideTumbleFreq", params.tumbleFreq)
	leaf:SetAttribute("GlidePerpX", params.perpX)
	leaf:SetAttribute("GlidePerpZ", params.perpZ)
	leaf:SetAttribute("GlideSwayAmplitude", params.swayAmplitude)
	leaf:SetAttribute("GlideSwayFreq", params.swayFreq)
	leaf:SetAttribute("GlideSwayPhase", params.swayPhase)
	leaf:SetAttribute("GlideFlutterFreq", params.flutterFreq)
	leaf:SetAttribute("GlideFlutterPhase", params.flutterPhase)
	leaf:SetAttribute("GlidePeakTime", params.peakTime)
	leaf:SetAttribute("GlideFallExponent", params.fallExponent)
	leaf:SetAttribute("MotionDuration", duration)
	leaf:SetAttribute("MotionKind", "Glide")
	-- Set LAST -- see the matching note in beginFall.
	leaf:SetAttribute("MotionStart", Workspace:GetServerTimeNow())

	task.delay(duration, function()
		if isInCleanupZone(targetX, targetZ) then
			consumeLeaf(leaf, targetX, rest.restY, targetZ, player)
		else
			if leaf.Parent then
				-- landingRestY (baked into params.restY above) already carries this landing's pile
				-- bump, so the leaf converges on it exactly -- matches what every client already
				-- rendered on its own last frame, no extra write needed.
				leaf.CFrame = LeafMotion.ComputeGlide(params, duration)
			end
			rest.baseX = targetX
			rest.baseZ = targetZ
			rest.yaw = params.targetYaw
			rest.disturbing = false
		end
	end)
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

		local fallingCount = 0
		for _ in pairs(fallingLeaves) do
			fallingCount += 1
		end

		if refilling and fallingCount < LeafConfig.FallingMaxConcurrent then
			local toSpawn = math.min(
				LeafConfig.FallingSpawnBatchSize,
				LeafConfig.FallingTargetCount - currentTotal,
				LeafConfig.FallingMaxConcurrent - fallingCount
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

-- Places a small pile of leaves clustered around one random ground spot, each stacked a little
-- higher than the last (not one flat leaf) -- reads as a real pile at a glance without any actual
-- physics: every leaf is still Anchored/non-colliding, the "stacking" is just deliberate Y offsets
-- baked in once at spawn time, same as any other resting leaf otherwise (fully collectible/blowable).
local function spawnGroundCluster()
	local center = randomRestPosition()
	local stackHeight = 0

	for _ = 1, LeafConfig.GroundClusterSize do
		local angle = math.random() * math.pi * 2
		local radius = math.random() * LeafConfig.GroundClusterRadius
		local x = center.X + math.cos(angle) * radius
		local z = center.Z + math.sin(angle) * radius
		stackHeight += LeafConfig.GroundStackHeightMin + math.random() * (LeafConfig.GroundStackHeightMax - LeafConfig.GroundStackHeightMin)
		local restPosition = Vector3.new(x, center.Y + stackHeight, z)

		local leaf = createLeaf(restPosition)
		local yaw = math.rad(math.random(0, 360))
		leaf.CFrame = CFrame.new(restPosition) * CFrame.Angles(0, yaw, 0)
		leaf.Parent = groundFolder
		markResting(leaf, restPosition, yaw)
		scheduleDespawn(leaf, LeafConfig.GroundLifetimeMin, LeafConfig.GroundLifetimeMax)
	end
end

-- Same hysteresis idea as runFallingSpawnLoop: fills up to GroundMaxLeaves then pauses, and only
-- resumes once the on-map total has actually dropped to GroundResumeBelow.
local function runGroundSpawnLoop()
	local refilling = true
	while true do
		local currentCount = #groundFolder:GetChildren()

		if refilling and currentCount >= LeafConfig.GroundMaxLeaves then
			refilling = false
		elseif not refilling and currentCount <= LeafConfig.GroundResumeBelow then
			refilling = true
		end

		if refilling then
			local remaining = LeafConfig.GroundMaxLeaves - currentCount
			local clustersToSpawn = math.min(LeafConfig.GroundSpawnBatchSize, math.ceil(remaining / LeafConfig.GroundClusterSize))
			for _ = 1, math.max(clustersToSpawn, 0) do
				spawnGroundCluster()
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

	for leaf, state in pairs(fallingLeaves) do
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
					-- Re-replicate the redirected target so clients mid-render pick up the change
					-- live -- see LeafRenderer.luau, which reads these fresh every frame rather
					-- than caching them at motion start.
					leaf:SetAttribute("FallTargetX", newX)
					leaf:SetAttribute("FallTargetZ", newZ)
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

	task.spawn(runFallingSpawnLoop)
	task.spawn(runGroundSpawnLoop)
	task.spawn(runWindDisturbanceLoop)
end

return LeafSpawner
