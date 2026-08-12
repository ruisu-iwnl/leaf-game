local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerQuests = require(script.Parent.PlayerQuests)
local QuestConfig = require(ReplicatedStorage.Shared.QuestConfig)

-- Tracks per-objective progress for multi-step, NPC-driven quests (QuestConfig entries with an
-- `Objectives` array, e.g. Getting Started II/III) -- the chain-quest counterpart to
-- DailyQuestSystem.luau's RecordProgress pattern, just scoped to one quest's own objective list
-- instead of "today's rotating 3." A quest with no Objectives field (e.g. Tutorial) never touches
-- this module -- it still completes the old way, via the CompleteQuest remote fired by
-- TutorialPanelUI's "Show me!" button.
--
-- Progress lives in one Attribute per objective: QuestObjProgress_<questId>_<objectiveId>. No
-- separate "completed" Attribute of its own is needed -- PlayerQuests' own Quest_<id> already is
-- that, set the instant RecordProgress notices every objective has hit its Target, via the
-- onAllComplete callback QuestSystem.Start() passes in (kept as a plain callback rather than a
-- require of QuestSystem, to avoid a circular require -- QuestSystem already requires THIS module,
-- to reset objective progress on :resetquest).
local QuestObjectives = {}

local onAllComplete = nil -- (player, questId) -> (), set by QuestObjectives.Start

local function progressAttribute(questId, objectiveId)
	return string.format("QuestObjProgress_%s_%s", questId, objectiveId)
end

function QuestObjectives.GetProgress(player, questId, objectiveId)
	return player:GetAttribute(progressAttribute(questId, objectiveId)) or 0
end

function QuestObjectives.IsObjectiveComplete(player, questId, objective)
	return QuestObjectives.GetProgress(player, questId, objective.Id) >= objective.Target
end

local function areAllObjectivesComplete(player, quest, questId)
	for _, objective in ipairs(quest.Objectives) do
		if not QuestObjectives.IsObjectiveComplete(player, questId, objective) then
			return false
		end
	end
	return true
end

-- The one entry point every gameplay hook calls into for chain-quest objectives, mirroring
-- DailyQuestSystem.RecordProgress's shape -- most call sites feed BOTH systems the same event, e.g.
-- SackSystem.luau's onCollectLeaf calls DailyQuestSystem.RecordProgress(player, "CollectViaSack", 1)
-- and QuestObjectives.RecordProgress(player, "CollectViaSack", 1) right next to each other, just
-- tracked into two separate catalogs. Safe/cheap to call unconditionally: only actually updates
-- anything for a quest the player has STARTED but not yet completed, with a matching-type objective
-- that isn't already at its Target.
function QuestObjectives.RecordProgress(player, objectiveType, amount)
	if not amount or amount <= 0 then
		return
	end

	for questId, quest in pairs(QuestConfig) do
		if quest.Objectives and PlayerQuests.HasStarted(player, questId) and not PlayerQuests.HasCompleted(player, questId) then
			local touchedAny = false
			for _, objective in ipairs(quest.Objectives) do
				if objective.Type == objectiveType and not QuestObjectives.IsObjectiveComplete(player, questId, objective) then
					local progress = math.min(QuestObjectives.GetProgress(player, questId, objective.Id) + amount, objective.Target)
					player:SetAttribute(progressAttribute(questId, objective.Id), progress)
					touchedAny = true
				end
			end
			if touchedAny and areAllObjectivesComplete(player, quest, questId) and onAllComplete then
				onAllComplete(player, questId)
			end
		end
	end
end

-- Clears every objective's progress for one quest -- used by QuestSystem.ResetQuest (:resetquest)
-- alongside PlayerQuests.ResetQuest, so re-testing a chain quest starts every objective back at 0,
-- not just the Started/Completed flags.
function QuestObjectives.ResetProgress(player, questId)
	local quest = QuestConfig[questId]
	if not quest or not quest.Objectives then
		return
	end
	for _, objective in ipairs(quest.Objectives) do
		player:SetAttribute(progressAttribute(questId, objective.Id), nil)
	end
end

-- For SaveSystem -- without this, objective progress toward e.g. "use the Rake 5 times" would reset
-- to 0 on every rejoin, the same rejoin-loses-progress problem DailyQuestSystem.GetSaveData/
-- RestoreSaveData exists to solve for dailies. This one's permanent (not day-scoped), same lifetime
-- as PlayerQuests' own CompletedQuestIds. Never needs to persist a quest that's already fully
-- complete -- Quest_<id> being true (via PlayerQuests.GetCompletedQuestIds) already covers that, and
-- a quest can only reach full objective completion by also being marked Completed in the same
-- server tick (see onAllComplete).
function QuestObjectives.GetSaveData(player)
	local data = {}
	for questId, quest in pairs(QuestConfig) do
		if quest.Objectives then
			for _, objective in ipairs(quest.Objectives) do
				local progress = QuestObjectives.GetProgress(player, questId, objective.Id)
				if progress > 0 then
					data[questId] = data[questId] or {}
					data[questId][objective.Id] = progress
				end
			end
		end
	end
	return data
end

function QuestObjectives.RestoreSaveData(player, data)
	if typeof(data) ~= "table" then
		return
	end
	for questId, objectiveProgress in pairs(data) do
		local quest = QuestConfig[questId]
		if quest and quest.Objectives and typeof(objectiveProgress) == "table" then
			for _, objective in ipairs(quest.Objectives) do
				local progress = objectiveProgress[objective.Id]
				if typeof(progress) == "number" then
					player:SetAttribute(progressAttribute(questId, objective.Id), math.clamp(progress, 0, objective.Target))
				end
			end
		end
	end
end

-- callback: (player, questId) -> (), invoked the instant every objective in a quest reaches its
-- Target. QuestSystem.Start() passes QuestSystem.CompleteQuest here.
function QuestObjectives.Start(callback)
	onAllComplete = callback
end

return QuestObjectives
