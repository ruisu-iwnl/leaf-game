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

-- Yard leaf spawning is now round-triggered (see StartYardRound/StopYardRound near the bottom),
-- not an always-on-at-boot toggle -- RoundSystem calls these as Map1 gets revealed/hidden.
-- Lobby leaves are separate and always-on, unaffected by round state.
local yardRoundActive = false

-- Forward-declared: defined near the bottom (after Start()), but Start() itself calls it from
-- inside a task.spawn closure that only actually runs later, once the whole module has loaded --
-- Lua's lexical scoping still needs the `local` in scope at the point Start() is written, though.
local startLeafSpawning

local fallingFolder
local groundFolder
local spawnArea
local groundTop
local cleanupZone
local lobbyGround
local lobbyGroundTop
local lobbyCleanupZone
local consumeVFXPart
local consumeEmitter
local consumeFlashEmitter
-- nil = use LeafConfig.GoldenLeafChance normally. Set by the :goldenleaf admin command
-- (AdminCommands.luau) for testing -- e.g. 1 makes every Yard leaf spawn golden, without touching
-- LeafConfig.luau itself (which every other system also reads, so mutating it directly at runtime
-- would be an easy way to leave a debug value baked in by accident).
local goldenLeafChanceOverride = nil
local leavesCleanedCount = 0
local zoneCycleCount = 0
-- Set fresh each round by StartYardRound(map1, mapEntry), from that map's own MapConfig entry --
-- how many leaves this specific map spawns/requires, replacing what used to be one hardcoded pair
-- of global LeafConfig constants shared by every map. Lobby spawning is untouched by this -- it
-- still always uses LeafConfig.FallingTargetCount/GroundMaxLeaves directly, since the Lobby isn't
-- one of the maps in the pool.
local yardFallingTarget = 0
local yardGroundTarget = 0
local yardGoal = 0
local yardAvoidRegions = {}
local fallingLeaves = {} -- part -> state, only leaves CURRENTLY falling (for the blower's mid-air redirect)
local restingLeaves = {} -- leaf -> { baseX, baseZ, restY, yaw, disturbing }
local lastPlayerPositions = {} -- player -> Vector3, used to gate disturbance on actual movement
local started = false
local deliveryListeners = {}

-- Fired whenever leaves land in the cleanup zone with a known delivering player (blown in, raked
-- in, footstep-nudged in, or a sack drop-off) -- kept as a plain callback list rather than
-- requiring MoneySystem directly, so this module still doesn't need to know Coins/players exist as
-- a concept, just that "someone" may be listening. Only truly unattributable deliveries (no player
-- anywhere in the causal chain) skip this. `bonusCoins` (optional, defaults to 0) is a flat
-- pre-multiplier amount on top of the normal count-based payout -- today only ever set by
-- consumeLeaf, for a Golden Leaf (see LeafConfig.luau's own comment).
local function notifyDelivery(player, count, bonusCoins)
	if not player then
		return
	end
	for _, callback in ipairs(deliveryListeners) do
		callback(player, count, bonusCoins or 0)
	end
end

function LeafSpawner.OnLeafDelivered(callback)
	table.insert(deliveryListeners, callback)
end

-- Testing hook for :goldenleaf (AdminCommands.luau). `chance` is a plain 0-1 fraction applied to
-- every Yard leaf spawned from this point on (already-spawned leaves are unaffected either way,
-- same as any other spawn-time roll) -- pass nil to reset back to LeafConfig.GoldenLeafChance's
-- normal value. Kept as a runtime override rather than mutating LeafConfig.luau directly, since
-- that table is shared/read by other systems too -- a debug value written straight into it would be
-- easy to accidentally leave baked in.
function LeafSpawner.SetGoldenLeafChanceOverride(chance)
	goldenLeafChanceOverride = chance
end

function LeafSpawner.GetGoldenLeafChance()
	return goldenLeafChanceOverride or LeafConfig.GoldenLeafChance
end

-- Each map's own MapConfig entry now owns its AvoidRegions (set into yardAvoidRegions by
-- StartYardRound below) -- these are obstacle footprints (a building, a sign post) specific to
-- that map's layout, not a game-wide constant. Center values are authored as offsets FROM
-- spawnArea's own (live) Position rather than literal world coordinates, so a region moves with
-- its map instead of staying pinned to wherever the map happened to sit when authored -- keeps
-- working under RoundSystem translating the whole map away from the Lobby each round (see
-- RoundConfig.MapAwayOffset).
-- Lobby leaves (zone ~= "Yard") never intersect these regions -- they're the active round map's
-- own obstacles, not anything in the Lobby's own layout.
local function isInAvoidRegion(x, z, zone)
	if zone ~= "Yard" or not spawnArea then
		return false
	end
	local originX, originZ = spawnArea.Position.X, spawnArea.Position.Z
	for _, region in pairs(yardAvoidRegions) do
		local halfX = region.Size.X / 2
		local halfZ = region.Size.Z / 2
		local centerX = originX + region.Center.X
		local centerZ = originZ + region.Center.Z
		if x >= centerX - halfX and x <= centerX + halfX
			and z >= centerZ - halfZ and z <= centerZ + halfZ then
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
		if not isInAvoidRegion(x, z, "Yard") and not isInCleanupZone(x, z) then
			return Vector3.new(x, y, z)
		end
	end

	return Vector3.new(center.X, y, center.Z)
end

-- Lobby counterpart of isInCleanupZone -- kept as a separate function (rather than folding into
-- isInCleanupZone) so the glide-landing callback below can tell which zone a leaf actually landed
-- in and reward coins only for the real yard zone, never the Lobby's decorative one.
local function isInLobbyCleanupZone(x, z)
	if not lobbyCleanupZone then
		return false
	end
	local halfX = lobbyCleanupZone.Size.X / 2
	local halfZ = lobbyCleanupZone.Size.Z / 2
	local center = lobbyCleanupZone.Position
	return x >= center.X - halfX and x <= center.X + halfX
		and z >= center.Z - halfZ and z <= center.Z + halfZ
end

-- Lobby counterpart of randomRestPosition -- same shape, but sampled from LobbyGround's own
-- footprint/height, and avoiding the Lobby's own cleanup zone plus a fixed clear circle around the
-- SpawnPlatform (dead center of LobbyGround) so leaves don't spawn on top of where players land.
local function randomLobbyRestPosition()
	local center = lobbyGround.Position
	local size = lobbyGround.Size
	local y = lobbyGroundTop + LeafConfig.LeafSize.Y / 2
	local spawnClearRadius = 10

	for _ = 1, 10 do
		local x = center.X + (math.random() - 0.5) * size.X
		local z = center.Z + (math.random() - 0.5) * size.Z
		local distFromCenter = math.sqrt((x - center.X) ^ 2 + (z - center.Z) ^ 2)
		if distFromCenter > spawnClearRadius and not isInLobbyCleanupZone(x, z) then
			return Vector3.new(x, y, z)
		end
	end

	return Vector3.new(center.X + spawnClearRadius + 5, y, center.Z)
end

-- `zone` ("Yard" or "Lobby") gates the Golden Leaf roll below -- Yard-only, since the Lobby isn't
-- part of the Coins economy at all (see consumeLobbyLeaf) and a golden Lobby leaf would promise a
-- bonus that can never actually pay out.
local function createLeaf(restPosition, zone)
	local leaf = Instance.new("Part")
	leaf.Name = "Leaf"
	leaf.Anchored = true
	leaf.CanCollide = false
	leaf.CastShadow = false
	leaf.Size = LeafConfig.LeafSize
	leaf.TopSurface = Enum.SurfaceType.Smooth
	leaf.BottomSurface = Enum.SurfaceType.Smooth
	leaf.CFrame = CFrame.new(restPosition)

	-- A REAL leaf variant, not a client-side illusion -- Color/Material are genuine Instance
	-- properties, so this replicates to every connected player automatically, the exact same way an
	-- ordinary leaf's color already does, with zero extra work in LeafRenderer.luau. IsGolden
	-- (Attribute, also free replication) is what consumeLeaf reads at delivery time to award the
	-- bonus -- see LeafConfig.luau's own comment for why hand-collecting one into a Sack doesn't
	-- (SackSystem's storage is a plain leaf COUNT, no per-leaf identity survives that).
	local goldenChance = goldenLeafChanceOverride or LeafConfig.GoldenLeafChance
	if zone == "Yard" and math.random() < goldenChance then
		leaf.Color = LeafConfig.GoldenLeafColor
		leaf.Material = Enum.Material.Neon
		leaf:SetAttribute("IsGolden", true)
	else
		leaf.Color = LeafConfig.Colors[math.random(1, #LeafConfig.Colors)]
		leaf.Material = Enum.Material.Grass
	end

	return leaf
end

-- Tracks a leaf as "at rest" so the wind-disturbance scan can find and nudge it. `zone` ("Yard" or
-- "Lobby") is preserved through every later mutation of this same table (glides just update
-- baseX/baseZ/yaw/disturbing in place, never replace it) -- StopYardRound reads it back to know
-- which resting leaves are the yard's to clear without touching the Lobby's.
local function markResting(leaf, restPosition, yaw, zone)
	restingLeaves[leaf] = {
		baseX = restPosition.X,
		baseZ = restPosition.Z,
		restY = restPosition.Y,
		yaw = yaw,
		disturbing = false,
		zone = zone,
	}
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

-- Drives the progress bar: climbs 0 -> 100% across this round's map's own Goal (MapConfig.luau,
-- set fresh each round by StartYardRound below), resetting each time a new round starts -- this
-- used to be a one-time goal against the map's whole leaf budget; now it's per-round, matching
-- RoundSystem's goal-or-timer end condition. Accepts a count > 1 (the sack system can deliver up
-- to SackConfig.MaxCapacity leaves in one go), clamped so a big delivery landing right at/past the
-- goal can't overshoot 100%.
local function registerZoneProgress(count)
	zoneCycleCount = math.min(zoneCycleCount + count, yardGoal)
	Workspace:SetAttribute("CleanupZoneCount", zoneCycleCount)
	Workspace:SetAttribute("CleanupZoneProgress", zoneCycleCount / yardGoal)
end

-- A leaf "arriving" in the cleanup zone: untracked, VFX'd, and destroyed in one shot so it can
-- never be double-counted (no lingering state anywhere still references it afterward). Increments
-- the shared LeavesCleaned count -- exposed as a Workspace attribute for later steps (UI, rewards)
-- to read without this module needing to know about players/coins yet.
local function consumeLeaf(leaf, x, y, z, player)
	local isGolden = leaf:GetAttribute("IsGolden") == true
	restingLeaves[leaf] = nil
	playConsumeVFX(Vector3.new(x, y, z))
	leavesCleanedCount += 1
	Workspace:SetAttribute("LeavesCleaned", leavesCleanedCount)
	registerZoneProgress(1)
	-- No notification/toast for a Golden Leaf -- deliberately silent, per explicit feedback that a
	-- popup for this felt like overkill. The glow itself (see createLeaf) is the only "you found
	-- one" signal; the bonus Coins just land in the balance the same way any other delivery's do.
	notifyDelivery(player, 1, isGolden and LeafConfig.GoldenLeafBonusCoins or 0)
	leaf:Destroy()
end

-- Lobby's cleanup zone equivalent -- same VFX/despawn, but deliberately skips leavesCleanedCount,
-- registerZoneProgress, and notifyDelivery entirely: the Lobby is just an intro space, not part of
-- the yard's coin/progress economy, so a leaf landing here earns nothing and moves no stat.
local function consumeLobbyLeaf(leaf, x, y, z)
	restingLeaves[leaf] = nil
	playConsumeVFX(Vector3.new(x, y, z))
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

-- Lobby counterpart of DeliverToZone, for a physical sack dropped/carried into LobbyCleanupZone --
-- same VFX burst, but deliberately no LeavesCleaned/registerZoneProgress/notifyDelivery, same as
-- consumeLobbyLeaf for loose leaves. Count isn't used for anything here (no stat to add it to) but
-- kept in the signature to mirror DeliverToZone's shape at the SackSystem call site.
function LeafSpawner.DeliverToLobbyZone(count, position)
	if count <= 0 then
		return
	end
	if position then
		playConsumeVFX(position)
	end
end

-- A leaf picked directly off the ground into a player's sack (as opposed to blown into the
-- cleanup zone) -- only resting leaves are collectible this way, and only ones not already
-- mid-glide, matching the same guard ApplyBlow uses. Returns false (does nothing) if the leaf
-- wasn't a valid, currently-resting leaf, so callers can't be tricked into double-counting one.
-- Second return value is the leaf's own zone ("Yard" or "Lobby") -- callers that need to
-- distinguish a real round-map collection from a purely decorative Lobby one (e.g.
-- SackSystem.onCollectLeaf gating the CollectViaSack daily quest) can check it without this module
-- needing to know anything about quests.
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

	return true, rest.zone
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
	-- Picks the yard's or the Lobby's own bounds based on which one the leaf is actually in right
	-- now (fromX/fromZ, its pre-push position) -- the two areas sit far enough apart that this is
	-- unambiguous, and it means a Lobby leaf never gets clamped against the yard's bounds (or
	-- vice versa) just because this function only used to know about one area. spawnArea is nil
	-- whenever no round is active (Map1 hidden -- see StartYardRound/StopYardRound), which is the
	-- common case now, so this can't assume it's set the way it safely could before rounds existed.
	local areaCenter, areaSize
	if lobbyGround and spawnArea then
		local yardDist = (fromX - spawnArea.Position.X) ^ 2 + (fromZ - spawnArea.Position.Z) ^ 2
		local lobbyDist = (fromX - lobbyGround.Position.X) ^ 2 + (fromZ - lobbyGround.Position.Z) ^ 2
		if lobbyDist < yardDist then
			areaCenter, areaSize = lobbyGround.Position, lobbyGround.Size
		else
			areaCenter, areaSize = spawnArea.Position, spawnArea.Size
		end
	elseif lobbyGround then
		areaCenter, areaSize = lobbyGround.Position, lobbyGround.Size
	elseif spawnArea then
		areaCenter, areaSize = spawnArea.Position, spawnArea.Size
	else
		-- Neither area known yet (e.g. called before LeafSpawner.Start()'s Lobby lookup finishes) --
		-- an unbounded "clamp" that doesn't actually restrict anything is the safe default here.
		areaCenter, areaSize = Vector3.new(fromX, 0, fromZ), Vector3.new(1e6, 4, 1e6)
	end

	local halfX = areaSize.X / 2 - 2
	local halfZ = areaSize.Z / 2 - 2
	targetX = math.clamp(targetX, areaCenter.X - halfX, areaCenter.X + halfX)
	targetZ = math.clamp(targetZ, areaCenter.Z - halfZ, areaCenter.Z + halfZ)

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
local function beginFall(leaf, restPosition, zone)
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
		zone = zone,
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
		markResting(leaf, Vector3.new(finalCFrame.Position.X, groundY, finalCFrame.Position.Z), landedYaw, state.zone)
	end)
end

-- Core "glide to a new resting spot" mechanic shared by the small footstep wind-disturbance nudge
-- and the blower's much bigger push -- only the distance/duration/lift/spin differ between them.
-- `player` (optional -- nil is still valid for any future caller with no attributable player) is
-- who gets credited with the coin reward if this glide happens to land the leaf in the cleanup
-- zone. Footstep nudges now pass the nearby player through here too (see triggerDisturbance).
--
-- Same replicate-parameters-once approach as beginFall -- see the top-of-file note.
local function startGlide(leaf, rest, targetX, targetZ, duration, liftHeight, spinDegrees, player)
	targetX, targetZ = clampTargetForObstacles(rest.baseX, rest.baseZ, rest.restY, targetX, targetZ)

	-- Don't drag a leaf into the cleanup zone fence or house footprint.
	if isInAvoidRegion(targetX, targetZ, rest.zone) then
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
		-- A round ending mid-glide (StopYardRound) destroys this leaf and drops its restingLeaves
		-- entry immediately -- bail out rather than register a delivery/VFX for an already-destroyed
		-- leaf, or resurrect a detached `rest` table nothing references anymore.
		if not leaf.Parent then
			return
		end

		if isInCleanupZone(targetX, targetZ) then
			consumeLeaf(leaf, targetX, rest.restY, targetZ, player)
		elseif isInLobbyCleanupZone(targetX, targetZ) then
			consumeLobbyLeaf(leaf, targetX, rest.restY, targetZ)
		else
			-- landingRestY (baked into params.restY above) already carries this landing's pile
			-- bump, so the leaf converges on it exactly -- matches what every client already
			-- rendered on its own last frame, no extra write needed.
			leaf.CFrame = LeafMotion.ComputeGlide(params, duration)
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
-- `player` (the one whose footsteps caused this) gets credited with coins if the nudge happens to
-- land the leaf in the cleanup zone -- same as any other delivery method, just previously missing
-- here, which is exactly why a movement-nudged leaf landing in the zone still counted toward zone
-- progress/LeavesCleaned (that part never depended on player) but paid out nothing.
local function triggerDisturbance(leaf, fromPosition, player)
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

	startGlide(leaf, rest, targetX, targetZ, duration, liftHeight, spinDegrees, player)
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

-- The Rake's core move: drags a resting leaf toward `origin` (the player's own position) instead
-- of away from it, in one big jump -- the whole point is recovering leaves stuck in a map
-- corner/edge that the Blower can only ever push further away. Clamped so a leaf never gets
-- pulled all the way onto the player, just close (RakeStopBuffer).
local function pullRestingLeaf(leaf, rest, origin, rakeConfig, player)
	local toPlayerX = origin.X - rest.baseX
	local toPlayerZ = origin.Z - rest.baseZ
	local distanceToPlayer = math.sqrt(toPlayerX * toPlayerX + toPlayerZ * toPlayerZ)
	if distanceToPlayer <= rakeConfig.RakeStopBuffer then
		return
	end
	local dirX, dirZ = toPlayerX / distanceToPlayer, toPlayerZ / distanceToPlayer

	local jitterRad = math.rad((math.random() - 0.5) * 2 * rakeConfig.RakeDirectionJitterDegrees)
	local cos, sin = math.cos(jitterRad), math.sin(jitterRad)
	local jitteredX = dirX * cos - dirZ * sin
	local jitteredZ = dirX * sin + dirZ * cos

	local desiredPull = rakeConfig.RakePullDistanceMin + math.random() * (rakeConfig.RakePullDistanceMax - rakeConfig.RakePullDistanceMin)
	local pullDistance = math.min(desiredPull, math.max(distanceToPlayer - rakeConfig.RakeStopBuffer, 0))
	if pullDistance <= 0.05 then
		return
	end

	local targetX = rest.baseX + jitteredX * pullDistance
	local targetZ = rest.baseZ + jitteredZ * pullDistance
	local liftHeight = rakeConfig.RakeLiftMin + math.random() * (rakeConfig.RakeLiftMax - rakeConfig.RakeLiftMin)
	local duration = rakeConfig.RakeDurationMin + math.random() * (rakeConfig.RakeDurationMax - rakeConfig.RakeDurationMin)
	local spinDegrees = rakeConfig.RakeSpinDegreesMin + math.random() * (rakeConfig.RakeSpinDegreesMax - rakeConfig.RakeSpinDegreesMin)

	startGlide(leaf, rest, targetX, targetZ, duration, liftHeight, spinDegrees, player)
end

-- Per-ROUND budget now, not lifetime: spawns up to this map's own FallingLeafCount (MapConfig.luau,
-- captured into yardFallingTarget by StartYardRound) for this round and stops -- gated on
-- yardRoundActive so StopYardRound can interrupt it mid-spawn when a round ends early (goal met,
-- timer, or an admin's :finishround), not just when it naturally runs out. Restarting a round calls
-- this fresh via StartYardRound, so totalSpawned resets to 0 each time.
-- FallingMaxConcurrent still throttles how many are actively mid-fall at once, purely so the sky
-- doesn't dump the whole budget in one visual burst.
local function runFallingSpawnLoop()
	local totalSpawned = 0
	while yardRoundActive and totalSpawned < yardFallingTarget do
		local fallingCount = 0
		for _ in pairs(fallingLeaves) do
			fallingCount += 1
		end

		if fallingCount < LeafConfig.FallingMaxConcurrent then
			local toSpawn = math.min(
				LeafConfig.FallingSpawnBatchSize,
				yardFallingTarget - totalSpawned,
				LeafConfig.FallingMaxConcurrent - fallingCount
			)
			for _ = 1, math.max(toSpawn, 0) do
				local restPosition = randomRestPosition()
				local leaf = createLeaf(restPosition, "Yard")
				leaf.Parent = fallingFolder
				beginFall(leaf, restPosition, "Yard")
				totalSpawned += 1
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

		local leaf = createLeaf(restPosition, "Yard")
		local yaw = math.rad(math.random(0, 360))
		leaf.CFrame = CFrame.new(restPosition) * CFrame.Angles(0, yaw, 0)
		leaf.Parent = groundFolder
		markResting(leaf, restPosition, yaw, "Yard")
	end
end

-- ONE-TIME lifetime budget, not hysteresis: spawns up to this map's own GroundLeafCount
-- (MapConfig.luau, captured into yardGroundTarget by StartYardRound) total (tracked here, not
-- re-derived from the current on-map count) and then the loop simply ends -- no refilling. Leaves
-- never despawn on their own either (no lifetime timer), so the map's leaf population only ever
-- goes down via a player actually delivering/collecting them.
local function runGroundSpawnLoop()
	local totalSpawned = 0
	while yardRoundActive and totalSpawned < yardGroundTarget do
		local remaining = yardGroundTarget - totalSpawned
		local clustersToSpawn = math.min(LeafConfig.GroundSpawnBatchSize, math.ceil(remaining / LeafConfig.GroundClusterSize))
		for _ = 1, math.max(clustersToSpawn, 0) do
			spawnGroundCluster()
			totalSpawned += LeafConfig.GroundClusterSize
		end
		task.wait(LeafConfig.GroundSpawnInterval)
	end
end

-- Lobby counterparts of the three functions above -- same exact mechanics/budget numbers
-- (LeafConfig.FallingTargetCount + GroundMaxLeaves, same 700/10,300 = 11,000 total the yard uses),
-- just sampled from randomLobbyRestPosition and parented into the SAME shared fallingFolder/
-- groundFolder as the yard's leaves. Sharing those folders (rather than separate Lobby-only ones)
-- is what lets ApplyBlow/ApplyRake/runWindDisturbanceLoop -- none of which know or care about
-- "zones," only the shared restingLeaves/fallingLeaves tables and these two folders -- affect
-- Lobby leaves for free, with zero changes to any of them.
local function runLobbyFallingSpawnLoop()
	local totalSpawned = 0
	while totalSpawned < LeafConfig.FallingTargetCount do
		local fallingCount = 0
		for _ in pairs(fallingLeaves) do
			fallingCount += 1
		end

		if fallingCount < LeafConfig.FallingMaxConcurrent then
			local toSpawn = math.min(
				LeafConfig.FallingSpawnBatchSize,
				LeafConfig.FallingTargetCount - totalSpawned,
				LeafConfig.FallingMaxConcurrent - fallingCount
			)
			for _ = 1, math.max(toSpawn, 0) do
				local restPosition = randomLobbyRestPosition()
				local leaf = createLeaf(restPosition, "Lobby")
				leaf.Parent = fallingFolder
				beginFall(leaf, restPosition, "Lobby")
				totalSpawned += 1
			end
		end

		task.wait(LeafConfig.FallingSpawnInterval)
	end
end

local function spawnLobbyGroundCluster()
	local center = randomLobbyRestPosition()
	local stackHeight = 0

	for _ = 1, LeafConfig.GroundClusterSize do
		local angle = math.random() * math.pi * 2
		local radius = math.random() * LeafConfig.GroundClusterRadius
		local x = center.X + math.cos(angle) * radius
		local z = center.Z + math.sin(angle) * radius
		stackHeight += LeafConfig.GroundStackHeightMin + math.random() * (LeafConfig.GroundStackHeightMax - LeafConfig.GroundStackHeightMin)
		local restPosition = Vector3.new(x, center.Y + stackHeight, z)

		local leaf = createLeaf(restPosition, "Lobby")
		local yaw = math.rad(math.random(0, 360))
		leaf.CFrame = CFrame.new(restPosition) * CFrame.Angles(0, yaw, 0)
		leaf.Parent = groundFolder
		markResting(leaf, restPosition, yaw, "Lobby")
	end
end

local function runLobbyGroundSpawnLoop()
	local totalSpawned = 0
	while totalSpawned < LeafConfig.GroundMaxLeaves do
		local remaining = LeafConfig.GroundMaxLeaves - totalSpawned
		local clustersToSpawn = math.min(LeafConfig.GroundSpawnBatchSize, math.ceil(remaining / LeafConfig.GroundClusterSize))
		for _ = 1, math.max(clustersToSpawn, 0) do
			spawnLobbyGroundCluster()
			totalSpawned += LeafConfig.GroundClusterSize
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
					-- Same cap as ApplyBlow/ApplyRake (see LeafConfig.MaxDisturbedPerCall) -- WindDisturbRadius
					-- is small (footstep-range) so this rarely matters in practice, but an extremely
					-- dense pile underfoot shouldn't be able to bypass the cap just because it's the
					-- passive footstep path instead of an active tool.
					for i = 1, math.min(#nearbyParts, LeafConfig.MaxDisturbedPerCall) do
						triggerDisturbance(nearbyParts[i], position, player)
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

	-- Collect qualifying leaves first, trigger second -- lets a huge dense pile caught in a
	-- wide/close cone be capped to LeafConfig.MaxDisturbedPerCall (closest first) instead of
	-- firing blowRestingLeaf/startGlide for every single one in this same server tick (see
	-- MaxDisturbedPerCall's own comment for why that matters). Sort is skipped entirely when under
	-- the cap -- the common case (a handful of leaves in the cone), not the big-pile one.
	local candidates = {}
	for leaf, rest in pairs(restingLeaves) do
		if not rest.disturbing then
			local toLeafX = rest.baseX - origin.X
			local toLeafZ = rest.baseZ - origin.Z
			local distance = math.sqrt(toLeafX * toLeafX + toLeafZ * toLeafZ)
			if distance > 0.05 and distance <= range then
				local dot = (toLeafX * direction.X + toLeafZ * direction.Z) / distance
				if distance <= blowConfig.BlowCloseRadius or dot >= cosHalfAngle then
					table.insert(candidates, { Leaf = leaf, Rest = rest, Distance = distance })
				end
			end
		end
	end
	if #candidates > LeafConfig.MaxDisturbedPerCall then
		table.sort(candidates, function(a, b)
			return a.Distance < b.Distance
		end)
	end
	for i = 1, math.min(#candidates, LeafConfig.MaxDisturbedPerCall) do
		local candidate = candidates[i]
		blowRestingLeaf(candidate.Leaf, candidate.Rest, direction, blowConfig, player)
	end

	for leaf, state in pairs(fallingLeaves) do
		local toLeafX = state.baseX - origin.X
		local toLeafZ = state.baseZ - origin.Z
		local distance = math.sqrt(toLeafX * toLeafX + toLeafZ * toLeafZ)
		if distance <= range then
			local dot = distance > 0.05 and (toLeafX * direction.X + toLeafZ * direction.Z) / distance or 1
			if distance <= blowConfig.BlowCloseRadius or dot >= cosHalfAngle then
				local wantedX = state.baseX + direction.X * blowConfig.FallingRedirectPerTick
				local wantedZ = state.baseZ + direction.Z * blowConfig.FallingRedirectPerTick
				-- Same obstacle clamp as resting leaves -- this path was missing it before, which
				-- is why leaves being blown mid-air could still sail through walls/boundary edges.
				local newX, newZ = clampTargetForObstacles(state.baseX, state.baseZ, state.restY, wantedX, wantedZ)
				if not isInAvoidRegion(newX, newZ, state.zone) then
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

-- Called by RakeTool on a timer while a player's rake is equipped: drags every resting leaf within
-- the cone toward `origin` (the player's own position, not a fixed aim point -- see RakeTool's
-- getAimOriginDirection) instead of away from it, and nudges the landing target of any still-falling
-- leaf caught in the cone the same way. Exists specifically to recover leaves stuck in a map
-- corner/edge, since the Blower can only ever push them further away. `rakeConfig` is RakeConfig
-- itself, mirroring how ApplyBlow takes blowConfig -- this module stays agnostic to either tool.
function LeafSpawner.ApplyRake(player, origin, direction, rakeConfig)
	local cosHalfAngle = math.cos(math.rad(rakeConfig.RakeConeAngleDegrees / 2))
	local range = rakeConfig.RakeRange

	-- Same collect-then-cap approach as ApplyBlow, same reason (see LeafConfig.MaxDisturbedPerCall).
	local candidates = {}
	for leaf, rest in pairs(restingLeaves) do
		if not rest.disturbing then
			local toLeafX = rest.baseX - origin.X
			local toLeafZ = rest.baseZ - origin.Z
			local distance = math.sqrt(toLeafX * toLeafX + toLeafZ * toLeafZ)
			if distance > 0.05 and distance <= range then
				local dot = (toLeafX * direction.X + toLeafZ * direction.Z) / distance
				if distance <= rakeConfig.RakeCloseRadius or dot >= cosHalfAngle then
					table.insert(candidates, { Leaf = leaf, Rest = rest, Distance = distance })
				end
			end
		end
	end
	if #candidates > LeafConfig.MaxDisturbedPerCall then
		table.sort(candidates, function(a, b)
			return a.Distance < b.Distance
		end)
	end
	for i = 1, math.min(#candidates, LeafConfig.MaxDisturbedPerCall) do
		local candidate = candidates[i]
		pullRestingLeaf(candidate.Leaf, candidate.Rest, origin, rakeConfig, player)
	end

	for leaf, state in pairs(fallingLeaves) do
		local toLeafX = state.baseX - origin.X
		local toLeafZ = state.baseZ - origin.Z
		local distance = math.sqrt(toLeafX * toLeafX + toLeafZ * toLeafZ)
		if distance <= range then
			local dot = distance > 0.05 and (toLeafX * direction.X + toLeafZ * direction.Z) / distance or 1
			if distance <= rakeConfig.RakeCloseRadius or dot >= cosHalfAngle then
				local toPlayerX = origin.X - state.baseX
				local toPlayerZ = origin.Z - state.baseZ
				local distanceToPlayer = math.sqrt(toPlayerX * toPlayerX + toPlayerZ * toPlayerZ)
				if distanceToPlayer > rakeConfig.RakeStopBuffer then
					local pullX, pullZ = toPlayerX / distanceToPlayer, toPlayerZ / distanceToPlayer
					local step = math.min(rakeConfig.RakeFallingRedirectPerTick, distanceToPlayer - rakeConfig.RakeStopBuffer)
					local wantedX = state.baseX + pullX * step
					local wantedZ = state.baseZ + pullZ * step
					local newX, newZ = clampTargetForObstacles(state.baseX, state.baseZ, state.restY, wantedX, wantedZ)
					if not isInAvoidRegion(newX, newZ, state.zone) then
						state.baseX = newX
						state.baseZ = newZ
						leaf:SetAttribute("FallTargetX", newX)
						leaf:SetAttribute("FallTargetZ", newZ)
					end
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

	-- init.server.luau calls every system's Start() sequentially on one thread -- LeafSpawner runs
	-- 2nd, so anything blocking here used to stall the other ~15 systems after it (SaveSystem's
	-- GetDataStore call was exactly this bug earlier this session). StartingLobby is static content
	-- baked into leaf.rbxlx, so it should always be there -- but a stale Studio session (place
	-- edited on disk, not reopened) or a bad file would otherwise hang this forever. Deferred to its
	-- own thread with a real timeout so that failure mode can only ever disable Lobby leaves for
	-- this session, never anything else. Map1/the yard is NOT looked up here at all anymore --
	-- RoundSystem reveals it and calls StartYardRound() directly once it's confirmed present, so
	-- there's nothing to wait/time out on for the yard side (see that function below).
	task.spawn(function()
		local startingLobby = Workspace:WaitForChild("StartingLobby", 15)
		if not startingLobby then
			warn("[LeafSpawner] Workspace.StartingLobby not found after 15s -- Lobby leaves disabled this session. If you just edited leaf.rbxlx, close Studio's session for it (without saving) and reopen the file fresh.")
			return
		end
		lobbyGround = startingLobby:WaitForChild("LobbyGround")
		lobbyGroundTop = lobbyGround.Position.Y + lobbyGround.Size.Y / 2
		lobbyCleanupZone = startingLobby:WaitForChild("LobbyCleanupZone")

		startLeafSpawning()
	end)
end

-- Everything past the StartingLobby lookup above -- split out so LeafSpawner.Start() itself can
-- return immediately regardless of how long (or whether) that lookup succeeds.
function startLeafSpawning()
	-- Single reused VFX source for every leaf consumed by either cleanup zone -- see
	-- playConsumeVFX. Positioned at the Lobby's zone for now since that's the only one guaranteed
	-- to exist at this point; playConsumeVFX repositions it before every actual use anyway, so its
	-- position here is never seen.
	consumeVFXPart = Instance.new("Part")
	consumeVFXPart.Name = "LeafConsumeVFX"
	consumeVFXPart.Anchored = true
	consumeVFXPart.CanCollide = false
	consumeVFXPart.CanQuery = false
	consumeVFXPart.CastShadow = false
	consumeVFXPart.Transparency = 1
	consumeVFXPart.Size = Vector3.new(0.2, 0.2, 0.2)
	consumeVFXPart.CFrame = CFrame.new(lobbyCleanupZone.Position)
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

	task.spawn(runLobbyFallingSpawnLoop)
	task.spawn(runLobbyGroundSpawnLoop)
	task.spawn(runWindDisturbanceLoop)
end

-- Called by RoundSystem right after it reparents the round's map into Workspace, passing that map
-- folder AND its MapConfig entry directly (MapConfig-driven -- see RoundSystem.luau -- rather than
-- this module hardcoding "Map1" or a global leaf budget itself, so a second/harder map in the pool
-- needs no changes here, just its own MapConfig entry). The folder is guaranteed present by the
-- time this runs, so the WaitForChild calls below resolve instantly; this never blocks. Resets the
-- round-scoped CleanupZoneProgress/Count to 0 and (re)starts the yard's two spawn loops, which run
-- until either they hit their per-round budget (mapEntry.FallingLeafCount/GroundLeafCount) or
-- StopYardRound interrupts them.
function LeafSpawner.StartYardRound(map1, mapEntry)
	if yardRoundActive then
		return
	end

	if not map1 or not mapEntry then
		warn("[LeafSpawner] StartYardRound called without a map folder/MapConfig entry -- RoundSystem should pass both in.")
		return
	end

	spawnArea = map1:WaitForChild("LeafSpawnArea")
	cleanupZone = map1:WaitForChild("CleanupZone")
	local ground = map1:WaitForChild("Ground")
	groundTop = ground.Position.Y + ground.Size.Y / 2

	yardFallingTarget = mapEntry.FallingLeafCount
	yardGroundTarget = mapEntry.GroundLeafCount
	yardGoal = mapEntry.Goal
	yardAvoidRegions = mapEntry.AvoidRegions or {}

	yardRoundActive = true
	zoneCycleCount = 0
	Workspace:SetAttribute("CleanupZoneCount", 0)
	Workspace:SetAttribute("CleanupZoneProgress", 0)

	task.spawn(runFallingSpawnLoop)
	task.spawn(runGroundSpawnLoop)
end

-- Called by RoundSystem when a round ends (goal met or timer expired), before it hides Map1 again.
-- Stops the yard's spawn loops (they check yardRoundActive each iteration) and destroys every
-- currently-tracked yard-zone leaf, resting or mid-flight, so the next round starts from a clean
-- map instead of accumulating leaves across rounds. Lobby leaves are untouched (different zone tag).
function LeafSpawner.StopYardRound()
	if not yardRoundActive then
		return
	end
	yardRoundActive = false

	for leaf, rest in pairs(restingLeaves) do
		if rest.zone == "Yard" then
			restingLeaves[leaf] = nil
			leaf:Destroy()
		end
	end
	for leaf, state in pairs(fallingLeaves) do
		if state.zone == "Yard" then
			fallingLeaves[leaf] = nil
			leaf:Destroy()
		end
	end
end

return LeafSpawner
