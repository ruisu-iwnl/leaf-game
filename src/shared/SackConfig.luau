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
	SackColor = Color3.fromRGB(120, 72, 38),
	SackTieColor = Color3.fromRGB(80, 46, 22),
	PickupPromptDistance = 8,
}
