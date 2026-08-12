-- Registry of maps available for rounds. Five real maps today (Map1/"The Yard", School/"The
-- School", Forest/"The Forest", Neighborhood/"The Neighborhood", Plaza/"Downtown Plaza") -- no
-- mock placeholders needed, and the pool is no longer capped at the vote panel's 3-row layout
-- either: RoundSystem randomly samples RoundConfig.MapPickBallotSize (3) maps out of however many
-- are here each round (see
-- RoundSystem.pickRandomBallot), so this table can keep growing without the panel ever needing
-- rework again. Adding a real map means: build/place its geometry in leaf.rbxlx as its own
-- top-level Workspace folder (same modularized pattern Map1/StartingLobby/School already use),
-- then add one more entry here -- RoundSystem, LeafSpawner, and SackSystem all already take the
-- map's folder/ground as parameters rather than hardcoding a specific map, so no changes are
-- needed in any of them to support it. Progress display (MapProgressUI.luau, client) needs
-- nothing map-specific at all -- it reads DisplayName straight from this table. Players actually
-- vote among these via RoundSystem's MapPick phase (see CLAUDE.md's "Lobby + intermission/vote
-- loop" section).
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

		-- Obstacle footprints leaves must never spawn/rest/glide into, relative to this map's own
		-- LeafSpawnArea position (see LeafSpawner.isInAvoidRegion) -- moved here from the old
		-- game-wide LeafConfig.AvoidRegions once a second real map existed, since this is genuinely
		-- per-map data (the yard's House footprint), not something every map shares.
		AvoidRegions = {
			{ Center = Vector3.new(-32, 0, 20), Size = Vector3.new(18, 0, 16) },
		},
	},

	-- The School -- built directly in leaf.rbxlx (same rbxlx-surgery approach as the
	-- Lobby/StartingLobby work), replacing the old MockSchool placeholder now that real geometry
	-- exists: Workspace.School (Boundary hedges/walls + Ground + LeafSpawnArea reused from Map1's
	-- pattern, 8 cloned Trees, and a from-scratch schoolyard theme -- a brick SchoolBuilding facade
	-- with a name plaque, and a redesigned CleanupZone with its own single-post CleanupSign
	-- (SurfaceGui+TextLabel reading "LEAF DROP-OFF ZONE", not a BillboardGui) instead of Map1's
	-- two-post arch. Sits 220 studs north of Map1 in world space -- clear of both Map1 (z <= ~52)
	-- and StartingLobby (x 110-230) -- purely so it doesn't overlap anything when Studio is opened
	-- in Edit mode; RoundSystem's MapAwayOffset still pushes whichever map is actually active
	-- another 10,000 studs away during a round.
	{
		Id = "School",
		DisplayName = "The School",
		WorkspaceFolderName = "School",
		GroundName = "Ground",
		Category = "MEDIUM",
		RecommendedPlayers = "2-4",
		FallingLeafCount = 1000,
		GroundLeafCount = 9000,
		Goal = 5000,

		-- The school building's own footprint (so leaves don't spawn/rest inside it), plus a small
		-- region around the CleanupSign's post so leaves don't pile up on top of it.
		AvoidRegions = {
			{ Center = Vector3.new(-30, 0, 23), Size = Vector3.new(32, 0, 32) },
			{ Center = Vector3.new(0, 0, -38), Size = Vector3.new(10, 0, 6) },
		},
	},
	-- The Forest -- third real map, built directly in leaf.rbxlx (same rbxlx-surgery approach as
	-- Lobby/School). Workspace.Forest sits 450 studs north of Map1 (x [-67,67] / z [383,517]),
	-- clear of Map1/StartingLobby/School's own footprints for the same Studio-Edit-mode reason
	-- those are staggered along Z -- RoundSystem's MapAwayOffset still pushes whichever map is
	-- actually active another 10,000 studs away during a round, unrelated to this.
	-- Rebuilt once already (see CLAUDE.md's Ninth/Tenth follow-ups) after the first pass read as
	-- "practically the same as the Yard" despite the different Boardwalk/CleanupZone -- Ground
	-- was still Map1's exact pale olive-tan and the building was still a low recolored copy of
	-- Map1's House/School's SchoolBuilding shape, so the silhouette never actually changed. Current
	-- version: `Boundary` (grass Hedge*/invisible Wall*) still reused verbatim per the user's
	-- explicit request, but `Ground` is now a deep pine green distinct from every other map, the
	-- old RangerCabin was replaced with a `FireLookoutTower` (four thin stilts + an elevated
	-- platform + a small cabin on top -- a genuinely different silhouette, not just a recolor), and
	-- tree count went from 22 to 34 (cloned from Map1's Tree1-Tree10, cycled) with randomized
	-- ScaleFactor 1.0-1.6 per tree for canopy height variance, plus 4 `GroundDetail` leaf-litter
	-- patches for forest-floor texture Map1/School don't have.
	{
		Id = "Forest",
		DisplayName = "The Forest",
		WorkspaceFolderName = "Forest",
		GroundName = "Ground",
		Category = "HARD",
		RecommendedPlayers = "3-5",
		FallingLeafCount = 1300,
		GroundLeafCount = 11700,
		Goal = 8000,

		-- The FireLookoutTower's own footprint, plus a small region around the TrailMarker's post.
		AvoidRegions = {
			{ Center = Vector3.new(0, 0, 58), Size = Vector3.new(18, 0, 20) },
			{ Center = Vector3.new(0, 0, -43), Size = Vector3.new(10, 0, 6) },
		},
	},

	-- The Neighborhood -- fourth real map, built directly in leaf.rbxlx the same rbxlx-surgery way
	-- as School/Forest. Workspace.Neighborhood sits 700 studs north of Map1 (x [-52,52] /
	-- z [628,772]), clear of every other map's footprint, same Z-staggering reason as the others.
	-- Per the Forest-rework lesson ("ensure everything is different"), this one is differentiated
	-- by LAYOUT SHAPE, not just theme dressing: a long narrow 100x140 rectangle (every other map is
	-- roughly square) built around a paved `Street` + `Turnaround` cul-de-sac flanked by concrete
	-- sidewalks -- nowhere else in the game has a road at all. `Boundary` (grass Hedge*/invisible
	-- Wall*) and `Ground`'s grass material are reused per the established convention, but Ground's
	-- own color (bright suburban lawn green) is distinct from Map1/School/Forest's. 3 `Houses`
	-- (HouseA/B/C), each a different siding color with its own Driveway, face the street from
	-- alternating sides -- not 3 clones of the same building. `CleanupZone` (orange-brown, matching
	-- LeafConfig's own leaf-pile palette) sits at the cul-de-sac end, paired with a short curb-height
	-- `CurbSign` (a stubby 2-stud post, not a tall signpost) reusing the SurfaceGui+TextLabel "LEAF
	-- DROP-OFF ZONE" pattern. Trees are sparse (10, cloned from Map1's Tree1-Tree10) -- a suburban
	-- street has occasional yard trees, not Forest's thicket. 3 `Mailboxes` cloned from Map1's own
	-- Decor/Mailbox model sit curbside near each driveway.
	{
		Id = "Neighborhood",
		DisplayName = "The Neighborhood",
		WorkspaceFolderName = "Neighborhood",
		GroundName = "Ground",
		Category = "MEDIUM",
		RecommendedPlayers = "2-4",
		FallingLeafCount = 1000,
		GroundLeafCount = 9000,
		Goal = 5000,

		-- The 3 house footprints (body+roof+driveway each), plus a small region around the curb
		-- sign's post.
		AvoidRegions = {
			{ Center = Vector3.new(-24, 0, -40), Size = Vector3.new(30, 0, 16) },
			{ Center = Vector3.new(24, 0, -5), Size = Vector3.new(30, 0, 16) },
			{ Center = Vector3.new(-24, 0, 30), Size = Vector3.new(30, 0, 16) },
			{ Center = Vector3.new(0, 0, 50), Size = Vector3.new(8, 0, 6) },
		},
	},

	-- Downtown Plaza -- fifth real map, same rbxlx-surgery build as the others. Workspace.Plaza
	-- sits 950 studs north of Map1 (x [-67,67] / z [898,1002]), clear of every other map. A wide
	-- 130x100 footprint (opposite proportions from the Neighborhood's tall-narrow street) built
	-- around a dead-center `Fountain` centerpiece and a continuous 4-unit `Shops` terrace
	-- (ShopCafe/ShopBooks/ShopFlowers/ShopBakery, each its own awning color) along the south edge
	-- -- neither a single building nor freestanding houses, a connected storefront row instead.
	-- `Boundary` is re-skinned to a low ornamental brick `StoneWall*` (still paired with the usual
	-- invisible `Wall*` collision) instead of every other map's grass hedge, since a garden hedge
	-- around a stone plaza would look inconsistent -- nothing in code cares what the visible
	-- boundary looks like. `Ground` is warm brick-tan pavement (Concrete, reused from School's
	-- proven-working blacktop, different color). `CleanupZone` (fresh green) sits in the northeast
	-- corner, paired with `PlazaSign` (a medium-height post + a decorative `WasteBin`) -- its own
	-- distinct scale from every other map's sign. `Decor` is deliberately the most elaborate of any
	-- map so far, per an explicit "make sure it's decorated properly" ask: 2 cafe tables with
	-- umbrellas outside ShopCafe, 5 lamp posts each with a real PointLight, 3 benches, and 7 planter
	-- boxes. 8 trees (cloned from Map1's Tree1-Tree10) are placed in a deliberate ORDERLY row along
	-- the north edge plus 2 corner accents -- a placement PATTERN distinct from Forest's wild
	-- scatter and the Neighborhood's individual-yard placement, matching real planted street trees.
	{
		Id = "Plaza",
		DisplayName = "Downtown Plaza",
		WorkspaceFolderName = "Plaza",
		GroundName = "Ground",
		Category = "MEDIUM",
		RecommendedPlayers = "2-4",
		FallingLeafCount = 1000,
		GroundLeafCount = 9000,
		Goal = 5000,

		-- The fountain's own footprint, the shop terrace, and a small region around the PlazaSign.
		AvoidRegions = {
			{ Center = Vector3.new(0, 0, 0), Size = Vector3.new(16, 0, 16) },
			{ Center = Vector3.new(0, 0, -38), Size = Vector3.new(84, 0, 12) },
			{ Center = Vector3.new(40, 0, 35), Size = Vector3.new(10, 0, 8) },
		},
	},
}
