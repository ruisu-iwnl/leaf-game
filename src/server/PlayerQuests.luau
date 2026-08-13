local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestConfig = require(ReplicatedStorage.Shared.QuestConfig)

-- The single place that owns a player's quest state -- Started and Completed, each a plain
-- Attribute (same pattern as PlayerUpgrades' Upgrade_id/Perk_id, see that file), so both replicate
-- to every client for free. QuestPathUI.luau (client) reads Quest_<id> directly to decide whether to
-- show the guide path, and QuestLogUI.luau reads both Quest_<id>/QuestStarted_<id> to render a
-- quest's status -- the same way RoundSystem's IsAFK/InActiveRound Attributes already drive client
-- UI elsewhere in this codebase, no remote round-trip needed just to ask "where am I on this quest."
--
-- Pure state only -- rewards and notifications are NOT this module's job. QuestSystem.luau wraps
-- StartQuest/CompleteQuest with that (reward grants, QuestStarted/QuestCompleted remote firing);
-- SaveSystem.luau calls the plain functions here directly when REPLAYING a save (a returning
-- player's already-earned reward/already-seen toast must never re-fire).
--
-- Nothing here needs a PlayerAdded hook -- an unset Attribute already reads as "not started/not
-- completed," which is exactly the right default for both a brand-new player and (in an unpublished
-- Studio session with no DataStore access) a player whose save never loads -- see SaveSystem.luau's
-- own comment on that. Both Completed (CompletedQuestIds) AND Started (StartedQuestIds) are
-- persisted -- SaveSystem restores Started directly via PlayerQuests.StartQuest (the same "call the
-- plain function directly, never QuestSystem's wrapper" pattern already used for Completed) BEFORE
-- QuestSystem.StartEligibleQuests runs, so an in-progress quest's Started Attribute is already true
-- by the time that function checks it -- StartQuest is a no-op for anything already started, so no
-- "Quest Started" toast re-fires on a rejoin, only on a quest's genuine first-ever start. (Started
-- used to NOT be persisted at all, which is why that toast used to re-fire every single login for
-- any not-yet-completed quest with AnnounceStart ~= false -- e.g. the long-term LeafLegend/
-- RoundVeteran quests, which realistically stay "in progress" for a very long time.)
local PlayerQuests = {}

local function questAttribute(id)
	return "Quest_" .. id
end

local function startedAttribute(id)
	return "QuestStarted_" .. id
end

function PlayerQuests.HasStarted(player, id)
	return player:GetAttribute(startedAttribute(id)) == true
end

function PlayerQuests.HasCompleted(player, id)
	return player:GetAttribute(questAttribute(id)) == true
end

-- Returns true only if this call actually started it (not already started or already completed) --
-- QuestSystem.StartEligibleQuests uses that to decide whether to fire a "Quest Started" toast.
function PlayerQuests.StartQuest(player, id)
	if not QuestConfig[id] then
		return false
	end
	if PlayerQuests.HasStarted(player, id) or PlayerQuests.HasCompleted(player, id) then
		return false
	end
	player:SetAttribute(startedAttribute(id), true)
	return true
end

-- Validated against QuestConfig so a client can never mark an arbitrary/unknown id "complete" via
-- the CompleteQuest remote (see QuestSystem.luau). Returns true only if this call actually completed
-- it (not already completed) -- QuestSystem.CompleteQuest uses that to decide whether to grant the
-- reward/fire the "Quest Completed" toast, so talking to the same NPC a second time is a safe no-op
-- rather than a double payout.
function PlayerQuests.CompleteQuest(player, id)
	if not QuestConfig[id] then
		return false
	end
	if PlayerQuests.HasCompleted(player, id) then
		return false
	end
	player:SetAttribute(startedAttribute(id), true) -- completing implies started; keeps state consistent
	player:SetAttribute(questAttribute(id), true)
	return true
end

-- Clears both Started and Completed so the quest's content can be re-tested (e.g. the Tutorial's
-- guiding path/dialogue/reward) without needing a fresh account -- see AdminCommands.luau's
-- :resetquest. Setting an Attribute to nil removes it, same as PlayerUpgrades.RemoveUpgrade --
-- HasStarted/HasCompleted then read nil, identical to never having touched the quest at all.
function PlayerQuests.ResetQuest(player, id)
	if not QuestConfig[id] then
		return false
	end
	player:SetAttribute(questAttribute(id), nil)
	player:SetAttribute(startedAttribute(id), nil)
	return true
end

-- For SaveSystem -- enumerating what to persist without it needing to know Attributes are the
-- storage mechanism (same shape as PlayerUpgrades.GetOwnedUpgradeIds).
function PlayerQuests.GetCompletedQuestIds(player)
	local ids = {}
	for id in pairs(QuestConfig) do
		if PlayerQuests.HasCompleted(player, id) then
			table.insert(ids, id)
		end
	end
	return ids
end

-- Same shape as GetCompletedQuestIds, but deliberately excludes anything already completed --
-- CompletedQuestIds already covers those (and PlayerQuests.CompleteQuest sets Started true as a
-- side effect of restoring one, see that function), so this only needs to carry genuinely
-- in-progress quests.
function PlayerQuests.GetStartedQuestIds(player)
	local ids = {}
	for id in pairs(QuestConfig) do
		if PlayerQuests.HasStarted(player, id) and not PlayerQuests.HasCompleted(player, id) then
			table.insert(ids, id)
		end
	end
	return ids
end

return PlayerQuests
