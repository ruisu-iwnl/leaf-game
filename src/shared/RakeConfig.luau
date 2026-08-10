return {
	-- Cosmetic color scheme -- RakeTool.luau resolves the owning player's chosen skin
	-- (PlayerUpgrades.GetCosmetic) and looks it up here, falling back to Default for everyone
	-- until real skins exist to buy. Adding a skin later is just one more entry in this table.
	Cosmetics = {
		Default = {
			HandleColor = Color3.fromRGB(120, 80, 45),
			GripColor = Color3.fromRGB(60, 50, 45),
			HeadColor = Color3.fromRGB(80, 80, 85),
		},
	},

	-- Long pole (like a standard real-world rake) and a wider head/tine spread than the first pass.
	-- Held vertically for now -- see RakeTool.luau's Tool.Grip -- since a proper two-handed grip is
	-- coming later via animation; a handle this long pointed forward one-handed would've looked odd.
	HandleSize = Vector3.new(0.22, 0.22, 5),
	GripSize = Vector3.new(0.32, 0.32, 0.9),
	HeadSize = Vector3.new(2.4, 0.16, 0.22),
	TineSize = Vector3.new(0.07, 0.07, 0.55),
	TineCount = 7,

	-- One-shot dust puff fired via ParticleEmitter:Emit() each time the rake is used (not a
	-- continuous stream while equipped) -- see RakeTool.luau.
	ConeAngleDegrees = 30,
	ParticleBurstCount = 14,
	ParticleSpeedMin = 4,
	ParticleSpeedMax = 8,
	ParticleLifetimeMin = 0.2,
	ParticleLifetimeMax = 0.4,

	-- Actually drags leaves (both resting and still-falling) toward the PLAYER on use -- the
	-- opposite of the Blower's push, specifically so leaves stuck in a map corner/edge (which the
	-- Blower can only ever push further away, never recover) can be pulled back into play. One
	-- click = one pull of everything currently in the cone, then RakeCooldownDuration before it can
	-- fire again (see RakeTool.luau) -- deliberately a shorter-range, more precise tool than the
	-- Blower rather than a continuous hold-to-use stream.
	RakeConeAngleDegrees = 46,
	RakeRange = 12,
	-- Same reasoning as BlowerConfig.BlowCloseRadius -- a cone is a single point at its own apex, so
	-- leaves sitting right next to the player but slightly off-axis can fail the angle test even
	-- though they're well within reach. This is a small unconditional bubble around the player where
	-- leaves get pulled regardless of angle, layered on top of the angled cone for everything further out.
	RakeCloseRadius = 4,
	RakeCooldownDuration = 2,
	RakePullDistanceMin = 12,
	RakePullDistanceMax = 20,
	-- Kept low so leaves drag along the ground toward the player rather than visibly hopping/
	-- flying through the air.
	RakeLiftMin = 0.1,
	RakeLiftMax = 0.35,
	RakeSpinDegreesMin = 8,
	RakeSpinDegreesMax = 20,
	RakeDurationMin = 0.9,
	RakeDurationMax = 1.4,
	-- A still-falling leaf caught in the cone gets its landing target redirected toward the player
	-- by this much, applied once per use (not per-tick -- there's no loop anymore).
	RakeFallingRedirectPerTick = 6,
	-- Same scatter idea as the Blower's BlowDirectionJitterDegrees, just smaller -- a rake gathers
	-- leaves toward one point rather than firing them all in a parallel line, so less randomness
	-- reads better here.
	RakeDirectionJitterDegrees = 10,
	-- A leaf never gets pulled all the way onto the player -- it always stops at least this many
	-- studs short, so it settles at their feet instead of inside them.
	RakeStopBuffer = 2.5,

	-- Sweep gesture played on use (RakeTool.performRake) -- a real published Animation asset, same
	-- deal as SackConfig.PickupAnimationId/TieSackAnimationId, works everywhere (Studio and the
	-- published game both) since it's a permanent asset id, no Studio-only baking step needed.
	RakeSweepAnimationId = "rbxassetid://135190147392302",
}
