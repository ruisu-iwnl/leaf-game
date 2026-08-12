-- Catalog of daily quests -- unlike QuestConfig.luau's NPC-driven quests (Tutorial), these need no
-- quest giver at all: they're always "available" in the sense that ordinary gameplay automatically
-- tracks progress toward whichever 3 are active today (see DailyRotation.luau), no dialogue/accept
-- step required. Rewarded once per quest per real day; see DailyQuestSystem.luau for the actual
-- progress-tracking/reward/reset logic -- this file is pure data.
--
-- 12 entries: 3 objective "concepts," 4 difficulty tiers each --
--   DeliverLeaves  -- deliver N leaves to any Cleanup Zone (the core gameplay loop, directly).
--   CollectViaSack -- click/tap-collect N leaves into the sack specifically (a different, distinct
--                     interaction from just blowing/raking leaves into a zone -- nudges players
--                     toward trying the Sack mechanic, not just a reskin of DeliverLeaves).
--   CompleteRounds -- finish N rounds, regardless of goal/timer outcome (rewards showing up and
--                     playing multiple sessions, not performance).
-- All 3 concepts are intentionally simple/low-friction ("easy to complete daily," per the ask) --
-- the 4 tiers just scale the target (and reward) up for players who want to do more in a sitting.
--
-- Field reference:
--   ObjectiveType   keys into DailyQuestSystem.luau's tracking -- reusing an EXISTING type (as
--                   every entry below does) needs zero code changes anywhere, just this entry. A
--                   genuinely NEW objective type needs one new DailyQuestSystem.RecordProgress call
--                   at wherever that event actually happens (see that file's own top comment for the
--                   3 existing call sites) -- an unavoidable, expected extension point.
--   Target          the count RecordProgress accumulates toward, per quest per day.
--   Reward.Coins    flat payout granted exactly once, the moment a quest is completed for a given
--                   day (never re-granted if it's later re-completed on a DIFFERENT day it rotates
--                   back into -- that's a fresh completion, not a duplicate of the old one).
--
-- `Order` is the deterministic sequence DailyRotation.luau cycles through 3-at-a-time, day by day --
-- deliberately interleaved (one of each objective concept every 3 entries) so a normal day's active
-- set is naturally one DeliverLeaves + one CollectViaSack + one CompleteRounds, not 3 of the same
-- concept back to back. Adding quest #13: append its Quests entry below, then append its Id to
-- Order (anywhere -- doesn't need to preserve the interleaving to keep working, that's just a nice
-- default) -- nothing else in this project needs to change.
local DailyQuestConfig = {}

DailyQuestConfig.Order = {
	"DeliverLeaves50", "CollectSack20", "CompleteRounds1",
	"DeliverLeaves100", "CollectSack50", "CompleteRounds2",
	"DeliverLeaves250", "CollectSack100", "CompleteRounds3",
	"DeliverLeaves500", "CollectSack200", "CompleteRounds5",
}

DailyQuestConfig.Quests = {
	DeliverLeaves50 = {
		Id = "DeliverLeaves50",
		Name = "Leaf Delivery I",
		Description = "Deliver 50 leaves to any Cleanup Zone.",
		ObjectiveType = "DeliverLeaves",
		Target = 50,
		Reward = { Coins = 100 },
	},
	DeliverLeaves100 = {
		Id = "DeliverLeaves100",
		Name = "Leaf Delivery II",
		Description = "Deliver 100 leaves to any Cleanup Zone.",
		ObjectiveType = "DeliverLeaves",
		Target = 100,
		Reward = { Coins = 150 },
	},
	DeliverLeaves250 = {
		Id = "DeliverLeaves250",
		Name = "Leaf Delivery III",
		Description = "Deliver 250 leaves to any Cleanup Zone.",
		ObjectiveType = "DeliverLeaves",
		Target = 250,
		Reward = { Coins = 275 },
	},
	DeliverLeaves500 = {
		Id = "DeliverLeaves500",
		Name = "Leaf Delivery IV",
		Description = "Deliver 500 leaves to any Cleanup Zone.",
		ObjectiveType = "DeliverLeaves",
		Target = 500,
		Reward = { Coins = 450 },
	},

	CollectSack20 = {
		Id = "CollectSack20",
		Name = "Sack Collector I",
		Description = "Collect 20 leaves by clicking or tapping them.",
		ObjectiveType = "CollectViaSack",
		Target = 20,
		Reward = { Coins = 75 },
	},
	CollectSack50 = {
		Id = "CollectSack50",
		Name = "Sack Collector II",
		Description = "Collect 50 leaves by clicking or tapping them.",
		ObjectiveType = "CollectViaSack",
		Target = 50,
		Reward = { Coins = 125 },
	},
	CollectSack100 = {
		Id = "CollectSack100",
		Name = "Sack Collector III",
		Description = "Collect 100 leaves by clicking or tapping them.",
		ObjectiveType = "CollectViaSack",
		Target = 100,
		Reward = { Coins = 225 },
	},
	CollectSack200 = {
		Id = "CollectSack200",
		Name = "Sack Collector IV",
		Description = "Collect 200 leaves by clicking or tapping them.",
		ObjectiveType = "CollectViaSack",
		Target = 200,
		Reward = { Coins = 375 },
	},

	CompleteRounds1 = {
		Id = "CompleteRounds1",
		Name = "Round Regular I",
		Description = "Finish 1 round.",
		ObjectiveType = "CompleteRounds",
		Target = 1,
		Reward = { Coins = 100 },
	},
	CompleteRounds2 = {
		Id = "CompleteRounds2",
		Name = "Round Regular II",
		Description = "Finish 2 rounds.",
		ObjectiveType = "CompleteRounds",
		Target = 2,
		Reward = { Coins = 175 },
	},
	CompleteRounds3 = {
		Id = "CompleteRounds3",
		Name = "Round Regular III",
		Description = "Finish 3 rounds.",
		ObjectiveType = "CompleteRounds",
		Target = 3,
		Reward = { Coins = 250 },
	},
	CompleteRounds5 = {
		Id = "CompleteRounds5",
		Name = "Round Regular IV",
		Description = "Finish 5 rounds.",
		ObjectiveType = "CompleteRounds",
		Target = 5,
		Reward = { Coins = 400 },
	},
}

return DailyQuestConfig
