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

	-- A chance-based bonus instead of a flat multiplier -- rolled per LEAF (not once per whole
	-- delivery) in PlayerUpgrades.RollLuckyBonus, called from init.server.luau's
	-- LeafSpawner.OnLeafDelivered listener alongside GetCoinsMultiplier. Stacks fine with 2X Grab:
	-- the lucky roll's bonus is a multiple of that leaf's ALREADY-doubled rate, not the base rate.
	-- Robux-only, same shape as DoubleGrab -- see docs/GAMEPASS_SETUP.md for the real Game Pass this
	-- GamePassId points to (icon: docs/gamepass-lucky-leaf-icon.png).
	LuckyLeaf = {
		Id = "LuckyLeaf",
		Name = "Lucky Leaf",
		ShortLabel = "Luck",
		Description = "Every leaf has a small chance to pay 3-5x Coins.",
		Currency = "Robux",
		GamePassId = 1944114701,
		-- 1 in 20 leaves (5%) hits the bonus -- LuckyMultiplierMin/Max is the RANGE that roll picks
		-- from, applied on top of whatever that leaf was already worth (see RollLuckyBonus).
		LuckyChance = 0.05,
		LuckyMultiplierMin = 3,
		LuckyMultiplierMax = 5,
	},

	-- The premium VIP tier -- bundles four purely-cosmetic perks (no gameplay/economy effect, unlike
	-- DoubleGrab/LuckyLeaf) instead of one. Robux-only, same shape as the other two -- see
	-- docs/GAMEPASS_SETUP.md for the real Game Pass this GamePassId points to (icon:
	-- docs/gamepass-leaf-patron-icon.png). The three exclusive tool skins it unlocks aren't listed
	-- here -- they're CosmeticConfig entries with `RequiresPerk = "LeafPatron"`, auto-granted/revoked
	-- by PlayerUpgrades.GrantPerk/RemovePerk whenever this perk is granted/removed (see that file).
	LeafPatron = {
		Id = "LeafPatron",
		Name = "Leaf Patron",
		ShortLabel = "VIP",
		Description = "Rainbow name, a gold Results banner, a neon footstep trail, and exclusive VIP tool skins.",
		Currency = "Robux",
		GamePassId = 1945372319,
	},
}
