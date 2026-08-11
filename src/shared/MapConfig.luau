-- Registry of maps available for rounds. Exactly one entry today (Map1/"The Yard") -- RoundSystem
-- always picks MapConfig[1] until a real map-select/vote UI exists (see CLAUDE.md's "Lobby +
-- intermission/vote loop" section, which already documents that a vote is deferred until a second
-- map exists). Adding a second map later means: build/place its geometry in leaf.rbxlx as its own
-- top-level Workspace folder (same modularized pattern Map1/StartingLobby already use), then add
-- one more entry here -- RoundSystem, LeafSpawner, and SackSystem all already take the map's
-- folder/ground as parameters rather than hardcoding "Map1", so no changes are needed in any of
-- them to support it. Progress display (MapProgressUI.luau, client) needs nothing map-specific at
-- all -- it reads DisplayName straight from this table.
--
-- Each entry's difficulty knobs (FallingLeafCount/GroundLeafCount/Goal) are what actually make a
-- map play differently -- everything that used to be one hardcoded pair of global constants in
-- LeafConfig.luau (only ever used by the yard) now lives per-map here instead, so a future harder
-- map is just a new entry with bigger numbers, not a code change anywhere.
return {
	{
		Id = "Map1",
		DisplayName = "The Yard",
		WorkspaceFolderName = "Map1",
		GroundName = "Ground",

		-- Shown to players before they commit to a round (RoundUI's Start button, and later a real
		-- map-select/vote UI once a second map exists) -- purely informational, never enforced
		-- server-side (nothing stops a lone player from starting a "needs 1-2" round with a crowd).
		Category = "EASY",
		RecommendedPlayers = "1-2",

		-- A smaller total spawn budget isn't actually easier -- it just means fewer leaves scattered
		-- across the same map footprint, so reaching a given Goal takes more searching per leaf, not
		-- less. Kept generous (5,000 -- same 10%/90% falling/ground split as before) precisely so the
		-- ground stays thick with piles and the low Goal below is easy to reach quickly.
		FallingLeafCount = 500,
		GroundLeafCount = 4500,

		-- What actually makes this EASY: a low bar relative to the spawn budget above (20% of it,
		-- versus the old 80%) -- players clean up a fraction of a generously-leafed map, not most of
		-- a sparse one.
		Goal = 1000,
	},

	-- Mock entries, requested explicitly ("include mock maps for now, just for testing") to
	-- exercise the MapPick vote panel with more than one option before a second real map exists.
	-- Trimmed to exactly 2 (3 maps total) per a follow-up ask that all candidates fit on the vote
	-- panel without scrolling. `IsMock = true` makes RoundSystem.Start()'s boot loop skip waiting on
	-- a Workspace folder for these (there isn't one) -- without that flag, nonexistent folders at
	-- 15s WaitForChild each would add real delay to every server's startup before the round loop
	-- could even begin. If a mock entry ever actually wins a vote, `beginRound()` already handles
	-- "folder not found in ServerStorage" gracefully (warns and returns to Intermission) -- these
	-- will never crash a round, just fail to load one, which is expected for a placeholder. Delete
	-- this whole block once a second real map is built, or once vote-panel testing is done.
	{
		Id = "MockSchool",
		DisplayName = "The School",
		WorkspaceFolderName = "MockSchool",
		GroundName = "Ground",
		Category = "MEDIUM",
		RecommendedPlayers = "2-4",
		FallingLeafCount = 700,
		GroundLeafCount = 6300,
		Goal = 3000,
		IsMock = true,
	},
	{
		Id = "MockPark",
		DisplayName = "The Park",
		WorkspaceFolderName = "MockPark",
		GroundName = "Ground",
		Category = "EASY",
		RecommendedPlayers = "1-3",
		FallingLeafCount = 400,
		GroundLeafCount = 3600,
		Goal = 800,
		IsMock = true,
	},
}
