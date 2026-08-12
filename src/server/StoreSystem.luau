local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCInteraction = require(script.Parent.NPCInteraction)
local NPCConfig = require(ReplicatedStorage.Shared.NPCConfig)

-- Ruisu-specific half of the store interaction -- the shared "find the rig, attach a Talk prompt"
-- wiring lives in NPCInteraction.luau; this just registers Ruisu (a rig the user places manually
-- in Studio -- see CLAUDE.md's Store System entry, the one part of this feature that genuinely
-- can't be automated away) and tells the client which dialogue to open via the shared
-- OpenNPCDialogue remote. What that dialogue actually says/does lives client-side, in
-- StoreDialogueUI.luau -- this module never needs to know or change if that content does.
--
-- All identity (Workspace instance name, dialogue/registry id, display name) comes from
-- NPCConfig.luau -- the one place to touch if the rig ever gets renamed/replaced again.
local StoreSystem = {}

local STORE_NPC = NPCConfig.Store

function StoreSystem.Start()
	local remotes = ReplicatedStorage.Shared:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage.Shared
	end

	local openNPCDialogueRemote = remotes:FindFirstChild("OpenNPCDialogue") or Instance.new("RemoteEvent")
	openNPCDialogueRemote.Name = "OpenNPCDialogue"
	openNPCDialogueRemote.Parent = remotes

	NPCInteraction.RegisterTalkPrompt(STORE_NPC.RigName, "Talk", function(player)
		openNPCDialogueRemote:FireClient(player, STORE_NPC.Id)
	end, STORE_NPC.DisplayName)
end

return StoreSystem
