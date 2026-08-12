local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyQuestConfig = require(ReplicatedStorage.Shared.DailyQuestConfig)
local QuestConfig = require(ReplicatedStorage.Shared.QuestConfig)
local ToastNotificationUI = require(script.Parent.ToastNotificationUI)

-- Quests' own thin content on top of the shared ToastNotificationUI shell -- same "generic system,
-- thin per-feature wrapper" shape as BadgeNotificationUI.luau sitting on top of the same toast.
-- Fired by the server whenever a quest actually starts or completes for this player --
-- QuestSystem.StartEligibleQuests/CompleteQuest and DailyQuestSystem.RecordProgress are the only
-- places either remote fires, all already deduped there (a quest already started/completed never
-- re-fires), so this file doesn't need any de-duplication of its own.
--
-- Both QuestConfig (NPC-driven, e.g. Tutorial) and DailyQuestConfig (rotating, no giver) quests fire
-- through the exact same two remotes -- findQuest checks both catalogs, so this one shared toast
-- handles both kinds; only DailyQuestSystem never fires QuestStarted at all (dailies have no
-- "started" moment worth announcing, see that file's own comment), not something this file needs to
-- special-case.
--
-- A quest can suppress its own "Quest Started" toast (QuestConfig's AnnounceStart = false) -- the
-- Tutorial does, since it's the player's very first-ever interaction with the quest system, and a
-- toast before they've even seen one before would read as noise, not information; the guiding path
-- (QuestPathUI.luau) already signals it started for that one. Completion always announces, for
-- every quest, no exception -- the server only ever fires QuestCompleted at all when AnnounceStart
-- wouldn't apply to it anyway (that field only gates the Started remote).
local QuestNotificationUI = {}

local ACCENT_COLOR = Color3.fromRGB(255, 205, 60)
local STARTED_GLYPH = "!"
local COMPLETED_GLYPH = "\226\156\147" -- "✓"

local function findQuest(id)
	if typeof(id) ~= "string" then
		return nil
	end
	return QuestConfig[id] or DailyQuestConfig.Quests[id]
end

function QuestNotificationUI.Start()
	local remotes = ReplicatedStorage.Shared:WaitForChild("Remotes")
	local questStartedRemote = remotes:WaitForChild("QuestStarted")
	local questCompletedRemote = remotes:WaitForChild("QuestCompleted")

	questStartedRemote.OnClientEvent:Connect(function(questId)
		local quest = findQuest(questId)
		if not quest then
			return
		end
		ToastNotificationUI.Show({
			tierColor = ACCENT_COLOR,
			glyph = STARTED_GLYPH,
			eyebrow = "QUEST STARTED",
			title = quest.Name,
			description = quest.Description,
		})
	end)

	questCompletedRemote.OnClientEvent:Connect(function(questId, rewardCoins)
		local quest = findQuest(questId)
		if not quest then
			return
		end
		local description = (typeof(rewardCoins) == "number" and rewardCoins > 0)
			and string.format("+%d Coins", rewardCoins)
			or quest.Description
		ToastNotificationUI.Show({
			tierColor = ACCENT_COLOR,
			glyph = COMPLETED_GLYPH,
			eyebrow = "QUEST COMPLETED",
			title = quest.Name,
			description = description,
		})
	end)
end

return QuestNotificationUI
