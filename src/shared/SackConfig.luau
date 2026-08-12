return {
	MaxCapacity = 100,

	-- How many physical sacks a single player can have out at once (spawned but not yet delivered
	-- to the cleanup zone), whether carried, dropped, or sitting in their Backpack -- without a cap
	-- a player could spawn an unlimited number of them scattered around the map.
	MaxActiveSacks = 3,

	-- How close a player has to actually be (server-checked) to collect a leaf they clicked/tapped.
	-- Generous enough that you don't have to stand right on top of a leaf, but short enough that you
	-- can't stand still and click leaves clear across the yard -- you still have to walk over to a
	-- pile to actually pick it up.
	CollectMaxDistance = 16,

	-- Physical sack prop.
	SackBodySize = Vector3.new(1.6, 1.8, 1.3),
	SackTieSize = Vector3.new(0.7, 0.35, 0.9),
	PickupPromptDistance = 8,

	-- Cosmetic color scheme -- SackSystem.newSackTool takes a color resolved from here
	-- (PlayerUpgrades.GetCosmetic) at spawn time, falling back to Default for everyone until real
	-- skins exist to buy. Adding a skin later is just one more entry in this table.
	Cosmetics = {
		Default = {
			SackColor = Color3.fromRGB(120, 72, 38),
			SackTieColor = Color3.fromRGB(80, 46, 22),
		},
		SackHarvest = {
			SackColor = Color3.fromRGB(210, 110, 30),
			SackTieColor = Color3.fromRGB(120, 60, 20),
		},
		SackFrost = {
			SackColor = Color3.fromRGB(165, 190, 205),
			SackTieColor = Color3.fromRGB(95, 120, 135),
		},
		SackPatron = {
			SackColor = Color3.fromRGB(90, 40, 135),
			SackTieColor = Color3.fromRGB(212, 175, 55),
		},
	},

	-- The pickup gesture, published as a real Animation asset via Studio's Clip Editor (the
	-- KeyframeSequenceProvider auto-bake only ever produces a session-local id, not something a
	-- live server can use -- see SackSystem.luau's setupPickupAnimation). Works everywhere now,
	-- Studio and the published game both, since this is a real permanent asset id.
	PickupAnimationId = "rbxassetid://93781977036631",

	-- Played on the player when they tie off/spawn a physical sack (SackSystem.onSpawnSack).
	-- Same deal as PickupAnimationId -- a real published asset, works everywhere.
	TieSackAnimationId = "rbxassetid://97341456512958",
}
