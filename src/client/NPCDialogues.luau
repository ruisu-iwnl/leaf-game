local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCConfig = require(ReplicatedStorage.Shared.NPCConfig)
local NPCDialogueUI = require(script.Parent.NPCDialogueUI)
local QuestConfig = require(ReplicatedStorage.Shared.QuestConfig)
local StorePanelUI = require(script.Parent.StorePanelUI)
local TutorialPanelUI = require(script.Parent.TutorialPanelUI)

-- Every NPC's dialogue CONTENT lives here, in one module -- the box/portrait/typewriter/animation
-- system is fully shared (NPCDialogueUI.luau, see its own top comment); this file only registers
-- what each NPC's conversation says and does. Attaching a conversation to a rig is just an
-- NPCConfig.luau entry (RigName/DisplayName/Id) plus one more NPCDialogueUI.Register block below --
-- nothing else needs to change, here or anywhere else, to add NPC #3. Previously split across one
-- file per NPC (StoreDialogueUI.luau, GuideDialogueUI.luau) -- merged into one module since the
-- split bought nothing (each was a near-identical `Register` call, not a meaningfully independent
-- system) and having every conversation in one place makes it easier to read/compare/extend them
-- together.
local NPCDialogues = {}

function NPCDialogues.Start()
	-- Store (the shop counter): "Yes" closes the dialogue and opens the real store panel --
	-- browsing/prices/ownership are all real.
	local storeNPC = NPCConfig.Store
	NPCDialogueUI.Register(storeNPC.Id, {
		rigName = storeNPC.RigName,
		displayName = storeNPC.DisplayName,
		question = "Want to buy something?",
		choices = {
			{ text = "No" },
			{
				text = "Yes",
				accent = true,
				onClick = function()
					NPCDialogueUI.Close()
					StorePanelUI.Open()
				end,
			},
		},
	})

	-- Guide (Ruisu-the-guide): "Show me!" opens the real tutorial content (TutorialPanelUI.luau)
	-- and marks the Tutorial quest complete server-side -- the one thing that stops QuestPathUI's
	-- guiding path from showing again. The question works equally well for a first-time player
	-- (QuestPathUI's guiding beam led them here) and a returning one who just wants another look,
	-- so there's no need for two different registrations/branching text based on completion state.
	local guideNPC = NPCConfig.Guide
	local tutorialQuestId = QuestConfig.Tutorial.Id
	NPCDialogueUI.Register(guideNPC.Id, {
		rigName = guideNPC.RigName,
		displayName = guideNPC.DisplayName,
		question = "Hi! I'm Ruisu -- want a quick tour of how everything works?",
		choices = {
			{ text = "No thanks" },
			{
				text = "Show me!",
				accent = true,
				onClick = function()
					NPCDialogueUI.Close()
					TutorialPanelUI.Open()

					local remotes = ReplicatedStorage.Shared:WaitForChild("Remotes")
					local completeQuestRemote = remotes:WaitForChild("CompleteQuest")
					completeQuestRemote:FireServer(tutorialQuestId)
				end,
			},
		},
	})
end

return NPCDialogues
