local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MoneySystem = require(script.Parent.MoneySystem)
local NPCConfig = require(ReplicatedStorage.Shared.NPCConfig)
local NPCInteraction = require(script.Parent.NPCInteraction)
local PlayerQuests = require(script.Parent.PlayerQuests)
local QuestConfig = require(ReplicatedStorage.Shared.QuestConfig)

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
-- Returns false (no-op) if the quest was already completed, so a client re-firing CompleteQuest
-- (e.g. talking to the same NPC twice) can never double-grant a reward or double-toast.
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
	return true
end

-- Starts every quest the player is eligible for (not already completed, AutoStartOnJoin isn't
-- explicitly false) and hasn't started yet, firing the QuestStarted notification for each one
-- UNLESS its AnnounceStart is explicitly false. Called once by SaveSystem.luau right after a
-- player's completed-quest state has been restored (or confirmed empty, for a brand-new player) --
-- so this never fires "Quest Started" for something they actually already finished in a prior
-- session.
function QuestSystem.StartEligibleQuests(player)
	for id, quest in pairs(QuestConfig) do
		if quest.AutoStartOnJoin ~= false and PlayerQuests.StartQuest(player, id) then
			if quest.AnnounceStart ~= false and questStartedRemote then
				questStartedRemote:FireClient(player, id)
			end
		end
	end
end

-- Clears completion+started state and immediately restarts it (firing the Started notification
-- again if applicable) -- used by :resetquest (AdminCommands.luau) so testing sees the same live
-- flow a real fresh quest-start would give, instead of a silently-cleared flag with no client
-- feedback until the next rejoin.
function QuestSystem.ResetQuest(player, id)
	local quest = QuestConfig[id]
	if not quest then
		return false
	end
	PlayerQuests.ResetQuest(player, id)
	if quest.AutoStartOnJoin ~= false and PlayerQuests.StartQuest(player, id) then
		if quest.AnnounceStart ~= false and questStartedRemote then
			questStartedRemote:FireClient(player, id)
		end
	end
	return true
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
		QuestSystem.CompleteQuest(player, questId)
	end)

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
