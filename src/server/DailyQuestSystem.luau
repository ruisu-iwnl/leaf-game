local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyQuestConfig = require(ReplicatedStorage.Shared.DailyQuestConfig)
local DailyRotation = require(ReplicatedStorage.Shared.DailyRotation)
local MoneySystem = require(script.Parent.MoneySystem)

-- Daily quests: unlike QuestSystem's NPC-driven ones (Tutorial), these need no quest giver at all --
-- they're always "available," just automatically tracked from ordinary gameplay (delivering leaves,
-- collecting via the sack, finishing rounds), and reset/rotate once a real day passes (see
-- DailyRotation.luau, a pure day-number function shared with the client so QuestLogUI.luau can show
-- today's active 3 without a remote round-trip).
--
-- Progress and completion are both scoped to the CURRENT day -- a quest completed today is a fresh
-- completion the next time it rotates back in, not a permanent one-time flag like PlayerQuests'
-- NPC-driven quests. Three plain Attributes per quest id do this (same "replicates to every client
-- for free" reasoning as PlayerQuests.luau):
--   DailyProgress_<id>      the accumulated count, only meaningful for the day named below
--   DailyProgressDay_<id>   which day number that count belongs to (stale/ignored otherwise)
--   DailyCompletedDay_<id>  which day number this quest was last completed on
--
-- Only 3 call sites feed this today (see RecordProgress's own comment): init.server.luau's
-- LeafSpawner.OnLeafDelivered ("DeliverLeaves"), SackSystem.luau's onCollectLeaf ("CollectViaSack"),
-- and RoundSystem.luau's beginRound, once per participant when a round concludes
-- ("CompleteRounds"). Adding a quest that reuses one of these three needs ONLY a DailyQuestConfig
-- entry -- this file, and all 3 call sites, stay untouched.
local DailyQuestSystem = {}

local questCompletedRemote = nil

local function progressAttribute(id)
	return "DailyProgress_" .. id
end

local function progressDayAttribute(id)
	return "DailyProgressDay_" .. id
end

local function completedDayAttribute(id)
	return "DailyCompletedDay_" .. id
end

function DailyQuestSystem.HasCompletedToday(player, id, dayNumber)
	dayNumber = dayNumber or DailyRotation.GetCurrentDayNumber()
	return player:GetAttribute(completedDayAttribute(id)) == dayNumber
end

-- Today's progress, discarding anything stored from a previous day this quest happened to be active
-- on -- a daily's progress only ever counts toward the day it was actually earned (see this file's
-- top comment).
function DailyQuestSystem.GetTodayProgress(player, id, dayNumber)
	dayNumber = dayNumber or DailyRotation.GetCurrentDayNumber()
	if player:GetAttribute(progressDayAttribute(id)) ~= dayNumber then
		return 0
	end
	return player:GetAttribute(progressAttribute(id)) or 0
end

-- The one entry point every gameplay hook calls into, e.g.
-- DailyQuestSystem.RecordProgress(player, "DeliverLeaves", count). Only actually moves anything for
-- a quest that's (a) part of TODAY's rotating 3, (b) matches this objectiveType, and (c) not already
-- completed today -- safe and cheap to call unconditionally from a hot path like every leaf
-- delivery, since most calls will find nothing eligible to update most days.
function DailyQuestSystem.RecordProgress(player, objectiveType, amount)
	if not amount or amount <= 0 then
		return
	end

	local dayNumber = DailyRotation.GetCurrentDayNumber()
	for _, id in ipairs(DailyRotation.GetTodaysDailyIds(dayNumber)) do
		local quest = DailyQuestConfig.Quests[id]
		if quest and quest.ObjectiveType == objectiveType and not DailyQuestSystem.HasCompletedToday(player, id, dayNumber) then
			local progress = math.min(DailyQuestSystem.GetTodayProgress(player, id, dayNumber) + amount, quest.Target)
			player:SetAttribute(progressAttribute(id), progress)
			player:SetAttribute(progressDayAttribute(id), dayNumber)

			if progress >= quest.Target then
				player:SetAttribute(completedDayAttribute(id), dayNumber)
				local rewardCoins = quest.Reward and quest.Reward.Coins
				if rewardCoins and rewardCoins > 0 then
					MoneySystem.AddCoins(player, rewardCoins)
				end
				if questCompletedRemote then
					-- Same remote QuestSystem.luau's NPC-driven quests fire -- QuestNotificationUI.luau
					-- (client) already looks the id up in both QuestConfig and DailyQuestConfig, so one
					-- shared toast handles both kinds with no daily-specific UI needed.
					questCompletedRemote:FireClient(player, id, rewardCoins or 0)
				end
			end
		end
	end
end

-- For SaveSystem -- without this, a player could rejoin mid-day and re-earn an already-completed
-- daily's reward a second time (or a third, ...), since Attributes alone don't survive a rejoin.
-- Only ever returns entries that are still relevant to TODAY (see RestoreSaveData) -- no point
-- persisting/restoring a stale prior day's progress that GetTodayProgress would discard anyway.
function DailyQuestSystem.GetSaveData(player)
	local data = {}
	for id in pairs(DailyQuestConfig.Quests) do
		local progressDay = player:GetAttribute(progressDayAttribute(id))
		local completedDay = player:GetAttribute(completedDayAttribute(id))
		if progressDay or completedDay then
			data[id] = {
				Progress = player:GetAttribute(progressAttribute(id)) or 0,
				ProgressDay = progressDay,
				CompletedDay = completedDay,
			}
		end
	end
	return data
end

function DailyQuestSystem.RestoreSaveData(player, data)
	if typeof(data) ~= "table" then
		return
	end
	local currentDay = DailyRotation.GetCurrentDayNumber()
	for id, entry in pairs(data) do
		if DailyQuestConfig.Quests[id] and typeof(entry) == "table" then
			if entry.ProgressDay == currentDay and typeof(entry.Progress) == "number" then
				player:SetAttribute(progressAttribute(id), entry.Progress)
				player:SetAttribute(progressDayAttribute(id), entry.ProgressDay)
			end
			if entry.CompletedDay == currentDay then
				player:SetAttribute(completedDayAttribute(id), entry.CompletedDay)
			end
		end
	end
end

function DailyQuestSystem.Start()
	local remotes = ReplicatedStorage.Shared:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage.Shared
	end

	-- Find-or-create, same as QuestSystem.luau's own setup for this remote -- whichever of the two
	-- Start()s runs first actually creates it, the other just finds it. Both need it, and neither
	-- needs to know about the other to get it.
	questCompletedRemote = remotes:FindFirstChild("QuestCompleted") or Instance.new("RemoteEvent")
	questCompletedRemote.Name = "QuestCompleted"
	questCompletedRemote.Parent = remotes
end

return DailyQuestSystem
