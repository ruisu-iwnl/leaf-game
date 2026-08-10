local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCInteraction = require(script.Parent.NPCInteraction)

-- Ruisu-specific half of the store interaction -- the shared "find the rig, attach a Talk prompt"
-- wiring lives in NPCInteraction.luau; this just registers Ruisu (a rig the user places manually
-- in Studio -- see CLAUDE.md's Store System entry, the one part of this feature that genuinely
-- can't be automated away) and tells the client which dialogue to open via the shared
-- OpenNPCDialogue remote. What that dialogue actually says/does lives client-side, in
-- StoreDialogueUI.luau -- this module never needs to know or change if that content does.
local StoreSystem = {}

local RUISU_NAME = "Ruisu"

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

	NPCInteraction.RegisterTalkPrompt(RUISU_NAME, "Talk", function(player)
		openNPCDialogueRemote:FireClient(player, RUISU_NAME)
	end)
end

return StoreSystem
