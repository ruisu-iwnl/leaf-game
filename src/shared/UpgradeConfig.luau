-- Catalog of one-time-purchase upgrades, each targeting exactly one tool. `Overrides` is a table
-- of just the base config fields this upgrade changes -- PlayerUpgrades.GetEffectiveConfig merges
-- it on top of the tool's base config (BlowerConfig/RakeConfig/SackConfig) for a player who owns
-- it, everyone else just gets the unmodified base config. Purely data: adding a new upgrade later
-- is just a new entry here, no code changes needed in the tools themselves.
--
-- Prices are deliberately steep (thousands to tens of thousands of Coins, at MoneyConfig's
-- CoinsPerLeaf = 1 -- see MoneyConfig.luau) -- these are meant to be long-term goals saved up
-- across many rounds, on the same scale as the Coins-balance Badge ladder (BadgeConfig.luau's
-- 25,000/40,000/60,000/80,000/100,000 tiers), not something bought after a single round.
return {
	RakeCooldown = {
		Id = "RakeCooldown",
		Name = "Fast Rake",
		Description = "Rake again after just 1 second instead of 2.",
		Price = 12000,
		Tool = "LeafRake",
		Overrides = {
			RakeCooldownDuration = 1, -- was 2
		},
	},

	BlowerOverheat = {
		Id = "BlowerOverheat",
		Name = "Bigger Tank",
		Description = "Blow for longer before the blower overheats.",
		Price = 10000,
		Tool = "LeafBlower",
		Overrides = {
			OverheatMax = 150, -- was 100 -- roughly 50% more time before overheating
		},
	},

	SackCapacity = {
		Id = "SackCapacity",
		Name = "Extra Sack",
		Description = "Carry one more sack at the same time.",
		Price = 15000,
		Tool = "LeafSack",
		Overrides = {
			MaxActiveSacks = 4, -- was 3
		},
	},

	-- Blower upgrades. Wide Nozzle/Long Hose are throughput upgrades (bigger spread, more reach);
	-- Cool Engine/Quick Vent are two different levers on the SAME overheat system as the existing
	-- Bigger Tank -- that one raises the heat CAP, these change the GAIN rate and the COOL rate
	-- instead, so all three can be owned together without being redundant with each other.

	BlowerWideNozzle = {
		Id = "BlowerWideNozzle",
		Name = "Wide Nozzle",
		Description = "Catches leaves from a wider area with every blow.",
		Price = 15000,
		Tool = "LeafBlower",
		Overrides = {
			BlowConeAngleDegrees = 48, -- was 32
		},
	},

	BlowerLongHose = {
		Id = "BlowerLongHose",
		Name = "Long Hose",
		Description = "Reach leaves that are farther away with the blower.",
		Price = 12000,
		Tool = "LeafBlower",
		Overrides = {
			BlowRange = 30, -- was 20
		},
	},

	BlowerCoolEngine = {
		Id = "BlowerCoolEngine",
		Name = "Cool Engine",
		Description = "The blower heats up slower, so you can blow for longer.",
		Price = 10000,
		Tool = "LeafBlower",
		Overrides = {
			HeatGainPerSecond = 7, -- was 11 -- ~9s of continuous blowing before overheating becomes ~14s
		},
	},

	BlowerQuickVent = {
		Id = "BlowerQuickVent",
		Name = "Quick Vent",
		Description = "The blower cools down faster after it overheats.",
		Price = 8000,
		Tool = "LeafBlower",
		Overrides = {
			HeatCoolPerSecond = 50, -- was 34 -- the overheat lockout itself shrinks from ~2.5s to ~1.7s
		},
	},

	BlowerPrecisionNozzle = {
		Id = "BlowerPrecisionNozzle",
		Name = "Precision Nozzle",
		Description = "Blown leaves fly in a tighter, straighter line instead of scattering.",
		Price = 9000,
		Tool = "LeafBlower",
		Overrides = {
			BlowDirectionJitterDegrees = 8, -- was 20
		},
	},

	-- Rake upgrades. Wide Sweep/Long Reach are the rake's own throughput/reach pair (same shape as
	-- the blower's Wide Nozzle/Long Hose); Magnet Pull is the flashiest/most expensive of the three
	-- since it changes how dramatic every single rake use feels, not just its numbers.

	RakeWideSweep = {
		Id = "RakeWideSweep",
		Name = "Wide Sweep",
		Description = "Gathers leaves from a wider area with every rake.",
		Price = 14000,
		Tool = "LeafRake",
		Overrides = {
			RakeConeAngleDegrees = 64, -- was 46
		},
	},

	RakeLongReach = {
		Id = "RakeLongReach",
		Name = "Long Reach",
		Description = "Reach leaves that are farther away with the rake.",
		Price = 11000,
		Tool = "LeafRake",
		Overrides = {
			RakeRange = 18, -- was 12
		},
	},

	RakeMagnetPull = {
		Id = "RakeMagnetPull",
		Name = "Magnet Pull",
		Description = "Pulls leaves in much farther with every rake.",
		Price = 18000,
		Tool = "LeafRake",
		Overrides = {
			RakePullDistanceMin = 20, -- was 12
			RakePullDistanceMax = 30, -- was 20
		},
	},

	-- Sack upgrades. Mega Sack is a deliberately different tradeoff from the existing Extra Sack
	-- (which adds a 4th sack SLOT) -- this makes each individual sack hold more instead, so owning
	-- both means fewer, bigger sacks rather than just more of the same-sized ones.

	SackMegaCapacity = {
		Id = "SackMegaCapacity",
		Name = "Mega Sack",
		Description = "Each sack now holds 150 leaves instead of 100.",
		Price = 20000,
		Tool = "LeafSack",
		Overrides = {
			MaxCapacity = 150, -- was 100
		},
	},

	SackQuickHands = {
		Id = "SackQuickHands",
		Name = "Quick Hands",
		Description = "Click or tap leaves from farther away to pick them up.",
		Price = 7000,
		Tool = "LeafSack",
		Overrides = {
			CollectMaxDistance = 24, -- was 16
		},
	},
}
