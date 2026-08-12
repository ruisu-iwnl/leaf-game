local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MoneySystem = require(script.Parent.MoneySystem)
local NPCConfig = require(ReplicatedStorage.Shared.NPCConfig)
local NPCInteraction = require(script.Parent.NPCInteraction)
local PlayerQuests = require(script.Parent.PlayerQuests)
local QuestConfig = require(ReplicatedStorage.Shared.QuestConfig)
local QuestObjectives = require(script.Parent.QuestObjectives)

-- Wires up every quest-giver NPC's Talk prompt (same shared NPCInteraction.luau wiring
-- StoreSystem.luau uses for Store/Ruisu), owns the quest remotes, and is the one place a quest
-- actually starting/completing turns into a reward grant + a client-side notification -- PlayerQuests
-- itself stays pure state (see that file's own comment on why).
--
-- Generic over however many quests/givers exist -- registers a prompt for every distinct NPCConfig
-- key referenced by a QuestConfig entry's GiverNPC, rather than hardcoding "Guide" specifically, so
-- a future quest with a new giver only needs an NPCConfig entry for that rig plus a QuestConfig
-- entry (see QuestConfig.luau) -- nothing here changes.
local QuestSystem = {}

local questStartedRemote = nil
local questCompletedRemote = nil

-- Applies the quest's reward (if any) and fires the QuestCompleted notification -- the one place a
-- quest is actually, freshly completed by something other than SaveSystem restoring prior progress.
-- Returns false (no-op) if the quest was already completed, so re-firing CompleteQuest (e.g. talking
-- to the same NPC twice, or QuestObjectives noticing an already-complete quest again) can never
-- double-grant a reward or double-toast. Also the trigger for chain-quest progression: re-running
-- StartEligibleQuests right after a fresh completion means a RequiresQuest follow-up (e.g.
-- GettingStarted2 after Tutorial) starts LIVE the instant its prerequisite finishes, not just on the
-- player's next rejoin.
function QuestSystem.CompleteQuest(player, id)
	local quest = QuestConfig[id]
	if not quest then
		return false
	end
	if not PlayerQuests.CompleteQuest(player, id) then
		return false
	end

	local rewardCoins = quest.Reward and quest.Reward.Coins
	if rewardCoins and rewardCoins > 0 then
		MoneySystem.AddCoins(player, rewardCoins)
	end
	if questCompletedRemote then
		questCompletedRemote:FireClient(player, id, rewardCoins or 0)
	end
	QuestSystem.StartEligibleQuests(player)
	return true
end

-- Starts every quest the player is eligible for -- not already completed, AutoStartOnJoin isn't
-- explicitly false, and its RequiresQuest prerequisite (if any) is already completed -- and hasn't
-- started yet, firing the QuestStarted notification for each one UNLESS its AnnounceStart is
-- explicitly false. Called once by SaveSystem.luau right after a player's completed-quest state has
-- been restored (or confirmed empty, for a brand-new player), and again by CompleteQuest right after
-- every fresh completion (see above) -- so a chain's next link picks up immediately either way. Safe
-- to call repeatedly: PlayerQuests.StartQuest is itself idempotent (returns false, does nothing, for
-- anything already started or completed).
function QuestSystem.StartEligibleQuests(player)
	for id, quest in pairs(QuestConfig) do
		local prerequisiteMet = not quest.RequiresQuest or PlayerQuests.HasCompleted(player, quest.RequiresQuest)
		if quest.AutoStartOnJoin ~= false and prerequisiteMet and PlayerQuests.StartQuest(player, id) then
			if quest.AnnounceStart ~= false and questStartedRemote then
				questStartedRemote:FireClient(player, id)
			end
		end
	end
end

-- Clears completion+started+objective-progress state and, if its prerequisite (if any) is already
-- satisfied, immediately restarts it (firing the Started notification again if applicable) -- used
-- by :resetquest (AdminCommands.luau) so testing sees the same live flow a real fresh quest-start
-- would give, instead of a silently-cleared flag with no client feedback until the next rejoin. A
-- chain quest whose prerequisite ISN'T satisfied is just left cleared (not force-started out of
-- order) -- StartEligibleQuests will pick it up the normal way once that prerequisite is actually
-- completed.
function QuestSystem.ResetQuest(player, id)
	local quest = QuestConfig[id]
	if not quest then
		return false
	end
	PlayerQuests.ResetQuest(player, id)
	QuestObjectives.ResetProgress(player, id)

	local prerequisiteMet = not quest.RequiresQuest or PlayerQuests.HasCompleted(player, quest.RequiresQuest)
	if quest.AutoStartOnJoin ~= false and prerequisiteMet and PlayerQuests.StartQuest(player, id) then
		if quest.AnnounceStart ~= false and questStartedRemote then
			questStartedRemote:FireClient(player, id)
		end
	end
	return true
end

-- Resets EVERY quest at once in two passes -- clear everything first, THEN try to restart -- rather
-- than looping ResetQuest per id (which resets-and-immediately-restarts one at a time). That
-- matters for a chain: pairs() gives no ordering guarantee, so a naive per-id loop could reset
-- GettingStarted2 (restarting it, since its prerequisite Tutorial hadn't been cleared YET) before
-- later clearing Tutorial itself -- leaving a stale QuestStarted flag on a quest QuestLogUI would
-- otherwise keep hidden. Used by :resetquest <player> all (AdminCommands.luau).
function QuestSystem.ResetAllQuests(player)
	for id in pairs(QuestConfig) do
		PlayerQuests.ResetQuest(player, id)
		QuestObjectives.ResetProgress(player, id)
	end
	QuestSystem.StartEligibleQuests(player)
end

function QuestSystem.Start()
	local remotes = ReplicatedStorage.Shared:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage.Shared
	end

	local openNPCDialogueRemote = remotes:FindFirstChild("OpenNPCDialogue") or Instance.new("RemoteEvent")
	openNPCDialogueRemote.Name = "OpenNPCDialogue"
	openNPCDialogueRemote.Parent = remotes

	local completeQuestRemote = remotes:FindFirstChild("CompleteQuest") or Instance.new("RemoteEvent")
	completeQuestRemote.Name = "CompleteQuest"
	completeQuestRemote.Parent = remotes

	questStartedRemote = remotes:FindFirstChild("QuestStarted") or Instance.new("RemoteEvent")
	questStartedRemote.Name = "QuestStarted"
	questStartedRemote.Parent = remotes

	questCompletedRemote = remotes:FindFirstChild("QuestCompleted") or Instance.new("RemoteEvent")
	questCompletedRemote.Name = "QuestCompleted"
	questCompletedRemote.Parent = remotes

	completeQuestRemote.OnServerEvent:Connect(function(player, questId)
		if typeof(questId) ~= "string" then
			return
		end
		local quest = QuestConfig[questId]
		-- Objective-driven quests (QuestConfig entries with an Objectives array, e.g.
		-- GettingStarted2/3) can ONLY be completed by QuestObjectives noticing every objective hit
		-- its Target -- never by this remote directly. Without this guard a client could fire
		-- CompleteQuest with e.g. "GettingStarted2" and skip straight to the reward without doing
		-- any of the actual objectives.
		if not quest or quest.Objectives then
			return
		end
		QuestSystem.CompleteQuest(player, questId)
	end)

	QuestObjectives.Start(QuestSystem.CompleteQuest)

	local registeredGivers = {}
	for _, quest in pairs(QuestConfig) do
		local giverKey = quest.GiverNPC
		if giverKey and not registeredGivers[giverKey] then
			registeredGivers[giverKey] = true
			local npc = NPCConfig[giverKey]
			if npc then
				NPCInteraction.RegisterTalkPrompt(npc.RigName, "Talk", function(player)
					openNPCDialogueRemote:FireClient(player, npc.Id)
				end, npc.DisplayName)
			else
				warn(string.format("[QuestSystem] QuestConfig references unknown NPCConfig key '%s'", giverKey))
			end
		end
	end
end

return QuestSystem
