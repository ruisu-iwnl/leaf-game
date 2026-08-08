return {
	LeafSize = Vector3.new(1, 0.08, 1),
	DespawnFadeDuration = 0.5,

	-- Leaves that drift down from the sky, refilled with hysteresis: once the total on-map count
	-- (falling + landed) reaches FallingTargetCount, spawning pauses; it only resumes once natural
	-- despawns (or, later, players cleaning them up) bring the count back down to FallingResumeBelow.
	FallingTargetCount = 700,
	FallingResumeBelow = 250,
	FallingMaxConcurrent = 300,
	FallingMaxLanded = 1200,
	FallingSpawnInterval = 0.2,
	FallingSpawnBatchSize = 25,
	FallingLifetimeMin = 300,
	FallingLifetimeMax = 600,

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

	-- Leaves placed directly on the ground (no fall animation) to keep the yard looking
	-- lived-in from the start. Long-lived compared to the falling ones.
	GroundMaxLeaves = 200,
	GroundSpawnInterval = 0.3,
	GroundSpawnBatchSize = 10,
	GroundLifetimeMin = 300,
	GroundLifetimeMax = 600,

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
