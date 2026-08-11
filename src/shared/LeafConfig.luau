return {
	LeafSize = Vector3.new(1, 0.08, 1),

	-- Leaves that drift down from the sky. ONE-TIME lifetime budget, not hysteresis: spawns up to
	-- FallingTargetCount total and then stops for good, same as GroundMaxLeaves below -- no
	-- refilling once leaves land or get collected, and no despawning on a timer either. Once
	-- landed, a falling leaf sticks around exactly like a ground leaf until a player actually
	-- delivers/collects it. FallingMaxConcurrent still throttles how many are actively mid-fall at
	-- once, purely so the sky doesn't dump the whole budget in one visual burst.
	-- NOTE: FallingTargetCount/GroundMaxLeaves below are the LOBBY's leaf budget only (always-on,
	-- not round-scoped) -- each map's own round budget is its own FallingLeafCount/GroundLeafCount
	-- in MapConfig.luau instead, so different maps can spawn different amounts.
	FallingTargetCount = 700,
	FallingMaxConcurrent = 300,
	FallingSpawnInterval = 0.2,
	FallingSpawnBatchSize = 25,

	-- Fall speed is studs/second, not a fixed duration, so a higher spawn height
	-- just takes proportionally longer instead of falling unnaturally fast.
	FallHeightMin = 70,
	FallHeightMax = 120,
	FallSpeedMin = 10,
	FallSpeedMax = 16,

	-- Falling leaves get carried sideways in the current WindSystem direction (studs/second of
	-- lateral drift, scaled by how long each individual leaf is in the air, with some per-leaf
	-- variance so they don't all drift by the exact same amount).
	WindFallDriftPerSecond = 7,
	WindFallDriftVarianceMin = 0.7,
	WindFallDriftVarianceMax = 1.3,

	-- Primary side-to-side sway, plus a faster/smaller secondary flutter layered on top
	-- (real leaves don't swing in one clean arc — they flutter unevenly as they catch air).
	SwayAmplitudeMin = 1.5,
	SwayAmplitudeMax = 3.2,
	FlutterAmplitudeRatio = 0.4,
	FlutterFreqMultiplierMin = 2.2,
	FlutterFreqMultiplierMax = 3.6,
	TumbleAmplitudeDegreesMin = 35,
	TumbleAmplitudeDegreesMax = 65,

	-- Leaves placed directly on the ground (no fall animation) to keep the yard looking properly
	-- buried in leaves. Spawned in small clustered PILES (not one flat scatter) with each leaf in
	-- a pile stacked a little higher than the last -- reads as a real pile without any actual
	-- physics/collision (every leaf stays Anchored and non-colliding; see LeafSpawner.luau's
	-- top-of-file note on why real per-leaf collision at this scale isn't worth the performance
	-- risk -- thousands of unanchored parts settling into each other is one of the more reliable
	-- ways to tank a Roblox server). Long-lived compared to the falling ones.
	-- This is a ONE-TIME lifetime total, not a hysteresis refill target: runLobbyGroundSpawnLoop
	-- spawns up to GroundMaxLeaves once, then stops for good. Leaves never despawn on a timer
	-- either -- once placed, one sticks around until a player actually delivers/collects it.
	-- 10,300 here + FallingTargetCount's 700 = 11,000, the Lobby's whole leaf budget (atmosphere
	-- only -- the Lobby has no cleanup goal/reward, see StartingLobby.LobbyCleanupZone).
	GroundMaxLeaves = 10300,
	GroundClusterSize = 8, -- leaves per pile
	GroundClusterRadius = 1.3, -- how tightly a pile's leaves scatter around its center, studs
	GroundStackHeightMin = 0.02, -- per-leaf Y increment within a pile, studs
	GroundStackHeightMax = 0.05,
	GroundSpawnInterval = 0.05,
	GroundSpawnBatchSize = 10, -- PILES (not individual leaves) spawned per loop tick

	-- Resting leaves get shoved a short distance when a player WALKS near, landing at a genuinely
	-- new spot each time (not springing back) so repeated gusts drift them around over time.
	-- Gated on actual movement (WindMinMoveDistance per scan tick) so standing still nearby does nothing.
	WindDisturbRadius = 6,
	WindScanInterval = 0.15,
	WindMinMoveDistance = 0.3,
	WindPushMin = 0.3,
	WindPushMax = 0.8,
	WindLiftMin = 0.08,
	WindLiftMax = 0.18,
	WindSpinDegreesMin = 10,
	WindSpinDegreesMax = 30,
	WindDurationMin = 0.3,
	WindDurationMax = 0.5,

	-- Tumble applied mid-glide (both the footstep nudge and the blower's push), fading to exactly
	-- 0 at the start/end so the leaf still lands flat -- it just doesn't slide perfectly flat
	-- along the ground while in motion, more like it's briefly caught in the air.
	GlideTumbleAmplitudeDegreesMin = 20,
	GlideTumbleAmplitudeDegreesMax = 55,
	GlideTumbleFreqMin = 1.5,
	GlideTumbleFreqMax = 3,

	-- Sideways sway (perpendicular to the direct start->target line) plus a slower secondary
	-- flutter, and a flattened/hover-y lift curve instead of one clean bounce -- so a blown leaf
	-- reads as featherweight and swept around by air, not like it's hopping in a straight line.
	-- Frequencies are in Hz (real seconds), NOT cycles-per-glide -- glides here only last a
	-- fraction of a second, so a "cycles per glide" rate (like the falling-leaf sway uses, where
	-- glides last several seconds) would compress into a jittery blur.
	GlideSwayAmplitudeRatio = 0.22, -- fraction of the glide's travel distance
	GlideSwayFreqMin = 1,
	GlideSwayFreqMax = 1.8,
	GlideVerticalFlutterRatio = 0.25, -- fraction of liftHeight

	-- Vertical motion is asymmetric, not a symmetric bounce: reaches peak height quickly, then
	-- eases down and decelerates as it nears the ground -- like a feather settling under drag,
	-- not a ball falling under gravity. Both vary per-leaf so a batch doesn't move in lockstep.
	GlidePeakTimeMin = 0.2, -- fraction of the glide duration spent rising
	GlidePeakTimeMax = 0.4,
	GlideFallExponentMin = 1.6, -- > 1 drops earlier, then eases off gently right near the ground
	GlideFallExponentMax = 2.4,

	-- Obstacles (walls, fences, trees) clamp how far a glide target can be pushed -- see
	-- clampTargetForObstacles. Leaves stay this far short of whatever they'd hit.
	ObstacleClearance = 1,
	-- Fraction of the leftover push distance a leaf keeps after bouncing off an obstacle
	-- (reflected off the surface normal), so it visibly deflects back instead of just stopping dead.
	BounceEnergyRatio = 0.4,

	Colors = {
		Color3.fromRGB(196, 120, 40),
		Color3.fromRGB(168, 88, 32),
		Color3.fromRGB(204, 156, 38),
		Color3.fromRGB(150, 60, 30),
		Color3.fromRGB(120, 84, 40),
	},

	-- Note: the cleanup zone used to have a blanket avoid-region here too, blocking leaves from
	-- ever being placed/pushed there at all. Removed -- the whole point of the blower is to be
	-- able to blow leaves INTO the cleanup zone. The fence posts themselves are still respected
	-- via clampTargetForObstacles' raycast (real geometry), just not the open platform/gate area.
	AvoidRegions = {
		{ Center = Vector3.new(-32, 0, 20), Size = Vector3.new(18, 0, 16) },
	},
}
