-- Registry of NPC-driven, one-time quests -- currently just the Tutorial. Rotating daily quests
-- (no quest giver, always "available," reset every real day) are a deliberately SEPARATE catalog --
-- see DailyQuestConfig.luau/DailyQuestSystem.luau -- since they need a genuinely different shape
-- (an Objective + Target instead of a GiverNPC, no AutoStartOnJoin/AnnounceStart concept) and
-- different lifecycle logic (per-day reset vs. once-ever). Both kinds fire through the same
-- QuestStarted/QuestCompleted remotes and the same QuestNotificationUI.luau toast, so from the
-- player's perspective they still read as "one quest system," just two catalogs behind it.
--
-- GiverNPC keys into NPCConfig.luau -- QuestSystem automatically registers a Talk prompt for every
-- NPC referenced this way, so adding a quest with a new giver only needs an NPCConfig entry for
-- that rig plus a QuestConfig entry here, nothing else.
--
-- Field reference:
--   Id                 internal identifier (matches the table key) -- used as the Attribute suffix
--                      (Quest_<id>/QuestStarted_<id>) and the notification remotes' payload.
--   Name/Description   player-facing text -- shown in QuestNotificationUI's toasts and
--                       QuestLogUI's panel. For an Objectives quest, Description is just the short
--                       framing line -- each objective carries its own line (see below).
--   GiverNPC           optional key into NPCConfig.luau -- who hands out/represents this quest. Omit
--                       entirely for a quest nothing narratively hands out (e.g. a long-term/lifetime
--                       goal) -- QuestLogUI then shows "Quest Giver: None (always available)," same as
--                       a daily.
--   RequiresQuest       optional prerequisite quest id -- QuestSystem.StartEligibleQuests won't
--                       start this quest until PlayerQuests.HasCompleted(player, RequiresQuest) is
--                       true, and it's re-checked (live, no rejoin needed) the instant the
--                       prerequisite actually completes (QuestSystem.CompleteQuest re-runs
--                       StartEligibleQuests right after granting a reward). QuestLogUI.luau also
--                       hides a quest entirely -- not even a "locked" row -- while its prerequisite
--                       isn't done, so a follow-up in a chain stays a surprise until it unlocks, per
--                       the explicit ask not to reveal follow-up quests early.
--   AutoStartOnJoin     defaults to true -- QuestSystem.StartEligibleQuests (called once by
--                       SaveSystem after a player's completed-quest state is restored, and again
--                       after any quest completes) starts every quest this isn't explicitly false
--                       for, as long as it isn't already completed AND its RequiresQuest (if any) is
--                       satisfied. Set false for a quest that should only start some other way (none
--                       do yet).
--   AnnounceStart       defaults to true -- whether starting this quest fires a "Quest Started" toast
--                       (QuestNotificationUI.luau). Tutorial sets this false: it's the player's very
--                       first-ever interaction with the quest system, so a toast before they've even
--                       seen one before would read as noise, not information -- the guiding path
--                       (QuestPathUI.luau) already signals it started. Completion still always
--                       announces, for every quest, no exception.
--   Objectives          optional array of { Id, Description, Type, Target } -- turns this quest into
--                       a multi-step one tracked by QuestObjectives.luau instead of the single
--                       "Show me!"-button CompleteQuest remote Tutorial uses. `Type` keys into the
--                       SAME objective-type strings DailyQuestSystem.luau's dailies use wherever the
--                       underlying event is identical (e.g. "DeliverLeaves", "CollectViaSack") --
--                       both systems get fed by the same call sites, just tracked into two separate
--                       catalogs -- plus any NEW type a chain quest introduces (e.g. "UseRake",
--                       "BuyUpgrade") needs exactly one new QuestObjectives.RecordProgress call at
--                       wherever that event happens, same extension shape as a new daily objective
--                       type. A quest is auto-completed (no client remote involved at all) the
--                       instant every one of its objectives reaches its Target -- see
--                       QuestObjectives.luau's onAllComplete callback. A quest with NO Objectives
--                       field (e.g. Tutorial) is untouched by any of this, still completed only by a
--                       client firing the CompleteQuest remote.
--   Reward.Coins        optional flat Coins payout granted exactly once, the moment this quest is
--                       actually, freshly completed (never re-granted on a save restore replaying
--                       old progress -- see QuestSystem.CompleteQuest vs PlayerQuests.CompleteQuest).
return {
	Tutorial = {
		Id = "Tutorial",
		Name = "Getting Started",
		Description = "Learn how to blow, rake, and sell leaves.",
		GiverNPC = "Guide",
		AnnounceStart = false,
		Reward = { Coins = 200 }, -- a small welcome bonus -- also the one thing that actually
			-- exercises the reward system today, since this is the only quest that exists yet
	},

	-- First link of the "Getting Started" chain: unlocks the moment Tutorial completes (RequiresQuest),
	-- stays entirely hidden from QuestLogUI until then. Three objectives spanning three different
	-- mechanics on purpose -- delivering leaves (the core loop, already tracked for dailies), the
	-- Rake specifically (a NEW objective type, "UseRake" -- see RakeTool.luau's performRake for the
	-- one call site), and the Sack specifically (reuses "CollectViaSack", same as the daily).
	GettingStarted2 = {
		Id = "GettingStarted2",
		Name = "Getting Started II",
		Description = "Put everything you've learned to work.",
		GiverNPC = "Guide",
		RequiresQuest = "Tutorial",
		Objectives = {
			{ Id = "BlowLeaves", Description = "Blow 100 leaves into the Cleanup Zone.", Type = "DeliverLeaves", Target = 100 },
			{ Id = "UseRake", Description = "Use the Rake 5 times.", Type = "UseRake", Target = 5 },
			{ Id = "HandpickLeaves", Description = "Handpick 50 leaves into a sack.", Type = "CollectViaSack", Target = 50 },
		},
		Reward = { Coins = 300 },
	},

	-- Second link: unlocks only once GettingStarted2 completes. A single objective ("BuyUpgrade",
	-- another new type -- see PurchaseSystem.luau's purchaseItem) nudges a player toward the Store
	-- for the first time now that they have Coins worth spending.
	GettingStarted3 = {
		Id = "GettingStarted3",
		Name = "Getting Started III",
		Description = "Visit Ruisu's shop and gear up.",
		GiverNPC = "Guide",
		RequiresQuest = "GettingStarted2",
		Objectives = {
			{ Id = "BuyUpgrade", Description = "Buy any upgrade from the shop.", Type = "BuyUpgrade", Target = 1 },
		},
		Reward = { Coins = 500 },
	},

	-- Long-term goals: unlike the Getting Started chain above, these are NOT gated behind a
	-- RequiresQuest (no prerequisite -- QuestSystem.StartEligibleQuests starts both for every player
	-- immediately, alongside Tutorial) and deliberately have no GiverNPC -- nothing narratively
	-- "hands out" a lifetime grind goal, so QuestLogUI shows them the same "Quest Giver: None (always
	-- available)" way it shows dailies. Both reuse EXISTING objective types (no new
	-- QuestObjectives.RecordProgress call sites needed for LeafLegend -- "DeliverLeaves" is already
	-- fed by init.server.luau's LeafSpawner.OnLeafDelivered hook), so a returning/veteran player who
	-- already has thousands of leaves delivered from BEFORE this quest existed still starts these at
	-- 0 progress -- QuestObjectives has no retroactive credit mechanism, a known simplification (same
	-- kind BadgeSystem.CheckAll's retroactive-award pass deliberately avoids needing here, since these
	-- track from a fresh Attribute, not a derived stat like LeavesCleaned).
	LeafLegend = {
		Id = "LeafLegend",
		Name = "Leaf Legend",
		Description = "A long-term goal for the truly dedicated -- keep blowing, raking, and delivering.",
		-- Same reasoning as Tutorial's own AnnounceStart = false: this has no GiverNPC and no
		-- RequiresQuest, so StartEligibleQuests auto-starts it for every player the instant they
		-- join, unconditionally -- there's no player action or narrative moment behind "starting"
		-- it, so a toast for that reads as noise, not information. Also the practical fix for it
		-- re-announcing every single Studio Play/Stop session: Started state only survives a
		-- rejoin via a real DataStore round-trip (see PlayerQuests.luau), which needs the place
		-- published at least once -- an unpublished Studio test server has nothing to persist
		-- across separate Play sessions, so a quest that restarts unconditionally on every join
		-- would otherwise re-toast every single time regardless. Completion still always announces.
		AnnounceStart = false,
		Objectives = {
			{ Id = "DeliverLeaves", Description = "Deliver 10,000 leaves to any Cleanup Zone.", Type = "DeliverLeaves", Target = 10000 },
		},
		Reward = { Coins = 10000 },
	},

	-- Reuses "CompleteRounds" -- until now only ever fed to DailyQuestSystem (RoundSystem.luau's
	-- beginRound). Needed one new QuestObjectives.RecordProgress call right next to that existing
	-- DailyQuestSystem one, same "both systems fed by the same call site" pattern GettingStarted2's
	-- DeliverLeaves/CollectViaSack objectives already established.
	RoundVeteran = {
		Id = "RoundVeteran",
		Name = "Round Veteran",
		Description = "A long-term goal for the truly dedicated -- keep showing up, round after round.",
		-- Same AnnounceStart = false reasoning as LeafLegend right above -- no giver, unconditional
		-- auto-start on every join, so silencing the start toast is both the right call narratively
		-- and what stops it re-announcing on every Studio Play/Stop session.
		AnnounceStart = false,
		Objectives = {
			{ Id = "CompleteRounds", Description = "Finish 25 rounds, any outcome.", Type = "CompleteRounds", Target = 25 },
		},
		Reward = { Coins = 8000 },
	},
}
