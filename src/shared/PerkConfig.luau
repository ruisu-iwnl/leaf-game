-- Catalog of one-time-purchase perks -- unlike upgrades, these aren't scoped to one tool, they
-- modify some game-wide rule (currently just the Coins-per-leaf rate). Purely data, same reasoning
-- as UpgradeConfig.luau.
--
-- Currency defaults to "Coins" (bought through PurchaseSystem.luau, same as Upgrades/Cosmetics) --
-- set it to "Robux" to sell a perk as a real Roblox Game Pass instead (see GamePassPerks.luau,
-- server-side). Robux perks don't set Price here at all -- once a Game Pass is created on Roblox's
-- website, ITS price is entirely controlled there, not by this file. They do need a real GamePassId
-- (see docs/GAMEPASS_SETUP.md for how to create one and fill this in).
return {
	DoubleGrab = {
		Id = "DoubleGrab",
		Name = "2X Grab",
		-- Compact badge text for the Active Perks row in InventoryUI.luau -- those slots are only
		-- 44px, too small to fit a full Name legibly.
		ShortLabel = "2X",
		Description = "Every leaf delivered is worth double Coins.",
		Currency = "Robux",
		GamePassId = 1941205385,
		CoinsMultiplier = 2,
	},
}
