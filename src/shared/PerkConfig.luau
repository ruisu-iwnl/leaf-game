-- Catalog of one-time-purchase perks -- unlike upgrades, these aren't scoped to one tool, they
-- modify some game-wide rule (currently just the Coins-per-leaf rate). Purely data, same reasoning
-- as UpgradeConfig.luau.
return {
	DoubleGrab = {
		Id = "DoubleGrab",
		Name = "2X Grab",
		Description = "Every leaf delivered is worth double Coins.",
		Price = 500,
		CoinsMultiplier = 2,
	},
}
