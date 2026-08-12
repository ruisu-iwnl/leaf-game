return {
	-- Cosmetic color scheme, applied to both the handheld tool and the worn backpack prop --
	-- BlowerTool.luau resolves the owning player's chosen skin (PlayerUpgrades.GetCosmetic) and
	-- looks it up here, falling back to Default for everyone until real skins exist to buy. Adding
	-- a skin later is just one more entry in this table, no code changes in BlowerTool.luau itself.
	Cosmetics = {
		Default = {
			BodyColor = Color3.fromRGB(230, 120, 20),
			GripColor = Color3.fromRGB(40, 40, 40),
			NozzleColor = Color3.fromRGB(60, 60, 60),
		},
		BlowerCrimson = {
			BodyColor = Color3.fromRGB(165, 30, 30),
			GripColor = Color3.fromRGB(35, 30, 30),
			NozzleColor = Color3.fromRGB(50, 45, 45),
		},
		BlowerEvergreen = {
			BodyColor = Color3.fromRGB(35, 110, 55),
			GripColor = Color3.fromRGB(35, 40, 35),
			NozzleColor = Color3.fromRGB(55, 60, 55),
		},
		BlowerPatron = {
			BodyColor = Color3.fromRGB(90, 40, 135),
			GripColor = Color3.fromRGB(20, 20, 26),
			NozzleColor = Color3.fromRGB(212, 175, 55),
		},
	},

	BodySize = Vector3.new(0.9, 0.9, 2.2),
	GripSize = Vector3.new(0.5, 1, 0.5),
	NozzleSize = Vector3.new(0.5, 0.5, 0.6),
	AccentSize = Vector3.new(1, 0.15, 1), -- thin dark band around the barrel for detail

	-- Wind cone particle effect, toggled on/off by clicking while equipped.
	ConeAngleDegrees = 26,
	ParticleRate = 150,
	ParticleSpeedMin = 40,
	ParticleSpeedMax = 55,
	ParticleLifetimeMin = 0.25,
	ParticleLifetimeMax = 0.5,

	-- Actually pushes leaves (both resting and still-falling) while equipped: a focused jet aimed
	-- at the ground in front of the nozzle, not a wide gust, but with real reach and force.
	BlowConeAngleDegrees = 32,
	BlowRange = 20,
	-- A cone is a single point at its own apex -- anything off-axis but very close to the nozzle
	-- (e.g. leaves sitting right at the player's feet) can fail the angle test even though they're
	-- well within arm's reach, since the cone hasn't widened out yet at that distance. This radius
	-- is a small unconditional bubble around the nozzle where leaves are affected regardless of
	-- angle, layered on top of the angled cone for everything further out.
	BlowCloseRadius = 4,
	-- How far below horizontal the cone points, so it aims at the ground instead of dead level.
	BlowPitchDownDegrees = 9,
	BlowInterval = 0.12,
	BlowPushDistanceMin = 5,
	BlowPushDistanceMax = 10,
	BlowLiftMin = 1,
	BlowLiftMax = 2.2,
	BlowSpinDegreesMin = 60,
	BlowSpinDegreesMax = 140,
	BlowDurationMin = 0.9,
	BlowDurationMax = 1.6,
	FallingRedirectPerTick = 2, -- studs the landing target shifts each blow tick while a falling leaf is caught in the cone
	-- Each leaf's push direction is randomly rotated away from the exact aim direction by up to
	-- this many degrees, so a batch of leaves scatters naturally instead of all flying in one
	-- perfectly parallel line.
	BlowDirectionJitterDegrees = 20,

	-- Worn backpack unit + straps, same color scheme as the handheld part. Always worn once the
	-- character spawns (not tied to whether the blower is currently equipped) -- that's intentional,
	-- matching the original "backpack the player will wear" request.
	BackpackTankSize = Vector3.new(1.3, 1.5, 0.7),
	BackpackTrimSize = Vector3.new(1.35, 0.18, 0.75),
	BackpackMotorSize = Vector3.new(1, 0.6, 0.9),
	BackpackExhaustSize = Vector3.new(0.3, 0.3, 0.4),
	BackpackVentSize = Vector3.new(0.08, 0.9, 0.5),
	BackpackLightSize = Vector3.new(0.15, 0.15, 0.05),
	PullHandleSize = Vector3.new(0.15, 0.35, 0.15),
	StrapSize = Vector3.new(0.25, 1.2, 0.15),

	-- Status light on the backpack: red while off, green while actively blowing.
	LightColorOff = Color3.fromRGB(200, 40, 40),
	LightColorOn = Color3.fromRGB(60, 220, 80),

	-- Hose connecting the backpack to the grip, present whenever the tool is equipped (regardless
	-- of whether it's actively blowing -- a real hose stays attached either way). Same-sign
	-- CurveSize0/1 on purpose (opposite signs make an S-curve, not a coil) -- a generous magnitude
	-- so it visibly bulges/coils with slack rather than looking like a taut straight line.
	HoseColor = Color3.fromRGB(35, 35, 35),
	HoseWidth = 0.2,
	HoseCurveSize = 3.5,

	-- Overheating: continuous blowing builds heat; hitting the cap force-stops the tool and locks
	-- it out (Activated does nothing) until it cools back down to OverheatResumeThreshold. Cooling
	-- runs any time it's not actively blowing, whether the player let go or it force-stopped itself.
	OverheatMax = 100,
	HeatGainPerSecond = 11, -- ~9s of continuous blowing to hit the cap
	-- (OverheatMax - OverheatResumeThreshold) / HeatCoolPerSecond = how long the lockout actually
	-- lasts once triggered -- tuned here for ~2.5s (85 / 34).
	HeatCoolPerSecond = 34,
	OverheatResumeThreshold = 15, -- must cool down to this (out of OverheatMax) before it can fire again
}
