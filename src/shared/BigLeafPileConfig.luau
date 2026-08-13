return {
	-- Roughly half an R15 rig's standing height (~5.5 studs) -- built entirely out of individual
	-- flat Leaf-shaped parts (LeafConfig.LeafSize/Colors, the exact same look every other leaf in
	-- the game already uses) densely scattered through a dome-shaped volume, not one smooth solid
	-- shape, so it actually reads as a pile of real leaves up close.
	PileHeight = 2.75,
	PileBaseRadius = 2.6,
	-- How many individual leaf parts make up one pile -- cheap even at 10 piles/round (well under
	-- 3,000 extra thin, Anchored, non-colliding parts total) next to the map's own 5,000-13,000-leaf
	-- budget.
	LeafCount = 260,

	-- A thinning halo of loose leaves scattered on the ground just outside the mound's own base --
	-- reads as leaves that spilled out of the pile rather than the pile having a hard, unnaturally
	-- clean edge. GroundScatterExtraRadius is added ON TOP of PileBaseRadius, and sampling is
	-- weighted toward the inner edge (closer to the mound) so it genuinely thins out with distance
	-- instead of forming a uniform ring.
	GroundScatterCount = 45,
	GroundScatterExtraRadius = 4,

	-- Spawned fresh each round (StartYardRound), same count range regardless of which map -- a
	-- random pick in this range, not a fixed number, so it's not identical every round. Piles never
	-- respawn once killed or once the round ends; this is the round's whole budget.
	MinCountPerRound = 5,
	MaxCountPerRound = 10,
	-- Piles need this much clearance from each other (checked against already-placed piles only, not
	-- retried against ordinary leaves) so a dense cluster never reads as one big blob.
	MinSpacing = 10,

	-- Only the Blower affects these (matches the user's original ask) -- damage is applied once per
	-- BlowerConfig.BlowInterval tick a pile stays inside the cone, same cadence ApplyBlow already
	-- uses for leaves. Fixed regardless of Wide/Long Nozzle upgrades -- those widen/extend the shared
	-- blow cone this rides on (more REACH), same as BlowerConfig.PlayerPushSpeed already stays fixed
	-- for the same reason (see that config's own comment) -- they never make a pile die faster.
	-- HealthMax / DamagePerBlowTick -> ~3.6s of continuous solo blowing to kill one, faster with more
	-- players blowing the same pile at once (each contributes independently, same tick cadence).
	HealthMax = 120,
	DamagePerBlowTick = 4,

	-- Paid out as real leaves delivered (LeafSpawner.DeliverToZone) to every player who landed at
	-- least one damaging hit on a pile before it died -- so a kill also counts toward the round's own
	-- Goal/CleanupZoneProgress, not just a side bonus, and rides the exact same Coins/multipliers/
	-- LeavesCleaned/Badges/Quests pipeline every other delivery already goes through (see
	-- init.server.luau's LeafSpawner.OnLeafDelivered hook). Deliberately no toast/notification --
	-- same "the reward speaks for itself" choice already made for Golden Leaf.
	BonusLeavesPerParticipant = 25,

	-- Health-bar billboard, hidden until a pile takes its first hit (see BigLeafPileSystem.applyDamage)
	-- so an untouched map isn't cluttered with 5-10 floating bars at once -- it appears as a reward
	-- for noticing/engaging with one.
	BarWidth = 90,
	BarHeight = 12,
	BarMaxDistance = 45,
	TrackColor = Color3.fromRGB(224, 218, 206),
	TrackStroke = Color3.fromRGB(40, 35, 30),
	FillColor = Color3.fromRGB(224, 168, 96),
}
