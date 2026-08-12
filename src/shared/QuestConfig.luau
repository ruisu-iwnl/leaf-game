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
--                       QuestLogUI's panel.
--   GiverNPC           key into NPCConfig.luau -- who hands out/represents this quest.
--   AutoStartOnJoin     defaults to true -- QuestSystem.StartEligibleQuests (called once by
--                       SaveSystem after a player's completed-quest state is restored) starts every
--                       quest this isn't explicitly false for, as long as it isn't already completed.
--                       Set false for a quest that should only start some other way (none do yet).
--   AnnounceStart       defaults to true -- whether starting this quest fires a "Quest Started" toast
--                       (QuestNotificationUI.luau). Tutorial sets this false: it's the player's very
--                       first-ever interaction with the quest system, so a toast before they've even
--                       seen one before would read as noise, not information -- the guiding path
--                       (QuestPathUI.luau) already signals it started. Completion still always
--                       announces, for every quest, no exception.
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
}
