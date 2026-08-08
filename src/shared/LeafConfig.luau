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
	WindDurationMin = 0.2,
	WindDurationMax = 0.35,

	Colors = {
		Color3.fromRGB(196, 120, 40),
		Color3.fromRGB(168, 88, 32),
		Color3.fromRGB(204, 156, 38),
		Color3.fromRGB(150, 60, 30),
		Color3.fromRGB(120, 84, 40),
	},

	AvoidRegions = {
		{ Center = Vector3.new(-32, 0, 20), Size = Vector3.new(18, 0, 16) },
		-- Cleanup zone fence spans roughly X/Z = +-8.4; a couple studs of buffer beyond that.
		{ Center = Vector3.new(0, 0, 0), Size = Vector3.new(20, 0, 20) },
	},
}
