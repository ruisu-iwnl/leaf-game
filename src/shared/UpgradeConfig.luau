-- Catalog of one-time-purchase upgrades, each targeting exactly one tool. `Overrides` is a table
-- of just the base config fields this upgrade changes -- PlayerUpgrades.GetEffectiveConfig merges
-- it on top of the tool's base config (BlowerConfig/RakeConfig/SackConfig) for a player who owns
-- it, everyone else just gets the unmodified base config. Purely data: adding a new upgrade later
-- is just a new entry here, no code changes needed in the tools themselves.
return {
	RakeCooldown = {
		Id = "RakeCooldown",
		Name = "Fast Rake",
		Description = "Decreases the rake's cooldown to 1 second.",
		Price = 250,
		Tool = "LeafRake",
		Overrides = {
			RakeCooldownDuration = 1,
		},
	},

	BlowerOverheat = {
		Id = "BlowerOverheat",
		Name = "Bigger Tank",
		Description = "Increases how long the blower can run before overheating.",
		Price = 250,
		Tool = "LeafBlower",
		Overrides = {
			OverheatMax = 150, -- was 100 -- roughly 50% more time before overheating
		},
	},

	SackCapacity = {
		Id = "SackCapacity",
		Name = "Extra Sack",
		Description = "Lets you have one more sack active at once.",
		Price = 250,
		Tool = "LeafSack",
		Overrides = {
			MaxActiveSacks = 4, -- was 3
		},
	},
}
