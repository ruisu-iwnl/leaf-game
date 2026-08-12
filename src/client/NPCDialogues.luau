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

	-- Guide (Ruisu-the-guide): a genuine multi-step CONVERSATION, not one question -- each topic is
	-- its own node (its own question text + choices), chained via NPCDialogueUI.Show (the same hand-
	-- off mechanism Store's "Yes" uses to jump to StorePanelUI, just jumping to another dialogue node
	-- here instead of closing). Greeting -> Blower -> Rake -> Sack -> Cleanup Zone/Shop -> Closing,
	-- with a "Skip" choice available from every topic straight to Closing, for a player who doesn't
	-- want the full walkthrough. Choice labels are kept SHORT ("Skip"/"Next"/"Ready!") on purpose --
	-- NPCDialogueUI's choice buttons auto-size to their text (see that file's buildChoiceButton), and
	-- a long label next to another long label could still grow the row wide enough to overlap the
	-- portrait on a narrow/mobile dialogue box. The Tutorial quest only completes at Closing's
	-- "Thanks, Ruisu!" -- reaching ANY path through the conversation, full or skipped -- which also
	-- opens TutorialPanelUI.luau as a reference the player can revisit later. The question at Greeting
	-- still works equally well for a first-time player (QuestPathUI's guiding beam led them here) and
	-- a returning one who just wants another look, so there's no branching based on completion state.
	--
	-- Nodes are forward-declared locals so each one's choices can reference the NEXT node before it's
	-- actually assigned below -- safe, since an onClick closure only reads that upvalue when a player
	-- actually clicks it, long after every node has its final table assigned.
	local guideNPC = NPCConfig.Guide
	local tutorialQuestId = QuestConfig.Tutorial.Id

	local nodeGreeting, nodeBlower, nodeRake, nodeSack, nodeShop, nodeClosing

	local function completeTutorialAndClose()
		NPCDialogueUI.Close()
		TutorialPanelUI.Open()

		local remotes = ReplicatedStorage.Shared:WaitForChild("Remotes")
		local completeQuestRemote = remotes:WaitForChild("CompleteQuest")
		completeQuestRemote:FireServer(tutorialQuestId)
	end

	nodeGreeting = {
		rigName = guideNPC.RigName,
		displayName = guideNPC.DisplayName,
		question = "Hi! I'm Ruisu -- want a quick tour of how everything works?",
		choices = {
			{ text = "No thanks" },
			{ text = "Show me!", accent = true, onClick = function() NPCDialogueUI.Show(nodeBlower) end },
		},
	}

	nodeBlower = {
		rigName = guideNPC.RigName,
		displayName = guideNPC.DisplayName,
		question = "Let's start with the Leaf Blower -- check your hotbar. Click to switch it on, aim it at some leaves, and they'll go flying into a pile. Click again to turn it off.",
		choices = {
			{ text = "Skip", onClick = function() NPCDialogueUI.Show(nodeClosing) end },
			{ text = "Next", accent = true, onClick = function() NPCDialogueUI.Show(nodeRake) end },
		},
	}

	nodeRake = {
		rigName = guideNPC.RigName,
		displayName = guideNPC.DisplayName,
		question = "Next, the Rake -- more precise than the Blower. One click drags nearby leaves back toward you, perfect for corners the Blower can only ever push leaves further into.",
		choices = {
			{ text = "Skip", onClick = function() NPCDialogueUI.Show(nodeClosing) end },
			{ text = "Next", accent = true, onClick = function() NPCDialogueUI.Show(nodeSack) end },
		},
	}

	nodeSack = {
		rigName = guideNPC.RigName,
		displayName = guideNPC.DisplayName,
		question = "You can also hand-collect leaves -- click or tap one directly and it goes straight into your Sack. Walk a full Sack over to a Cleanup Zone to turn it into Coins.",
		choices = {
			{ text = "Skip", onClick = function() NPCDialogueUI.Show(nodeClosing) end },
			{ text = "Next", accent = true, onClick = function() NPCDialogueUI.Show(nodeShop) end },
		},
	}

	nodeShop = {
		rigName = guideNPC.RigName,
		displayName = guideNPC.DisplayName,
		question = "Once you've cashed in some leaves, swing by my other spot at the Shop -- I sell upgrades for your Blower, Rake, and Sack.",
		choices = {
			{ text = "Ready!", accent = true, onClick = function() NPCDialogueUI.Show(nodeClosing) end },
		},
	}

	nodeClosing = {
		rigName = guideNPC.RigName,
		displayName = guideNPC.DisplayName,
		question = "That's the tour! I've popped all of this into a handy panel too, in case you ever want to look back. Good luck out there!",
		choices = {
			{ text = "Thanks, Ruisu!", accent = true, onClick = completeTutorialAndClose },
		},
	}

	NPCDialogueUI.Register(guideNPC.Id, nodeGreeting)
end

return NPCDialogues
