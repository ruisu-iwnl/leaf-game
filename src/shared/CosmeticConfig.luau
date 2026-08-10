-- Catalog of one-time-purchase cosmetic skins, same shape/reasoning as UpgradeConfig.luau/
-- PerkConfig.luau -- purely data, `Tool` says which tool it applies to. The actual color values a
-- skin applies live in that tool's OWN Cosmetics table (BlowerConfig.Cosmetics.BlowerCrimson etc,
-- keyed by this same Id) -- this catalog is just the store-facing name/description/price, kept
-- separate from the tool configs so BlowerTool/RakeTool/SackSystem never need to know what's
-- actually for sale, only how to resolve whatever cosmetic id a player currently has equipped.
--
-- "Default" is NOT in here -- it's free and every player already has it, so there's nothing to
-- sell. PlayerUpgrades.HasCosmetic/PurchaseSystem's EquipCosmetic handler both special-case that id
-- directly rather than needing a zero-price catalog entry for it.
return {
	-- Prices span the requested 5,000-10,000 range rather than all sitting at one value -- one
	-- "budget" and one "premium" skin per tool, alternating which one costs more so it doesn't
	-- always land on the same tool.
	BlowerCrimson = {
		Id = "BlowerCrimson",
		Name = "Crimson Blower",
		Description = "A deep autumn-red repaint for the leaf blower.",
		Price = 5000,
		Tool = "LeafBlower",
	},
	BlowerEvergreen = {
		Id = "BlowerEvergreen",
		Name = "Evergreen Blower",
		Description = "A forest-green repaint for the leaf blower.",
		Price = 10000,
		Tool = "LeafBlower",
	},

	RakeGolden = {
		Id = "RakeGolden",
		Name = "Golden Rake",
		Description = "A gilded head and tines for the rake.",
		Price = 10000,
		Tool = "LeafRake",
	},
	RakeCharcoal = {
		Id = "RakeCharcoal",
		Name = "Charcoal Rake",
		Description = "A sleek blackened-steel rake head.",
		Price = 5000,
		Tool = "LeafRake",
	},

	SackHarvest = {
		Id = "SackHarvest",
		Name = "Harvest Sack",
		Description = "A pumpkin-orange burlap sack.",
		Price = 5000,
		Tool = "LeafSack",
	},
	SackFrost = {
		Id = "SackFrost",
		Name = "Frost Sack",
		Description = "A pale, frosty-blue burlap sack.",
		Price = 10000,
		Tool = "LeafSack",
	},
}
