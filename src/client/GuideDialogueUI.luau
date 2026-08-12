local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCConfig = require(ReplicatedStorage.Shared.NPCConfig)
local NPCDialogueUI = require(script.Parent.NPCDialogueUI)
local QuestConfig = require(ReplicatedStorage.Shared.QuestConfig)
local TutorialPanelUI = require(script.Parent.TutorialPanelUI)

-- Ruisu-the-guide's dialogue CONTENT -- same shared box/portrait/typewriter system as
-- StoreDialogueUI.luau (see NPCDialogueUI.luau's own top comment); this module only registers what
-- the guide's conversation says and does. The question works equally well for a first-time player
-- (QuestPathUI's guiding beam led them here) and a returning one who just wants another look, so
-- there's no need for two different registrations/branching text based on quest-completion state.
--
-- "Show me!" opens the real tutorial content (TutorialPanelUI.luau) and marks the Tutorial quest
-- complete server-side -- the one thing that stops QuestPathUI's guiding path from showing again.
local GuideDialogueUI = {}

local GUIDE_NPC = NPCConfig.Guide
local TUTORIAL_QUEST_ID = QuestConfig.Tutorial.Id

local function openTutorial()
	NPCDialogueUI.Close()
	TutorialPanelUI.Open()

	local remotes = ReplicatedStorage.Shared:WaitForChild("Remotes")
	local completeQuestRemote = remotes:WaitForChild("CompleteQuest")
	completeQuestRemote:FireServer(TUTORIAL_QUEST_ID)
end

function GuideDialogueUI.Start()
	NPCDialogueUI.Register(GUIDE_NPC.Id, {
		rigName = GUIDE_NPC.RigName,
		displayName = GUIDE_NPC.DisplayName,
		question = "Hi! I'm Ruisu -- want a quick tour of how everything works?",
		choices = {
			{ text = "No thanks" },
			{
				text = "Show me!",
				accent = true,
				onClick = openTutorial,
			},
		},
	})
end

return GuideDialogueUI
