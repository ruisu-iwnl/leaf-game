local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCDialogueUI = require(script.Parent.NPCDialogueUI)
local StorePanelUI = require(script.Parent.StorePanelUI)
local NPCConfig = require(ReplicatedStorage.Shared.NPCConfig)

-- Ruisu-specific dialogue CONTENT -- the box/portrait/typewriter/animation system is fully shared
-- (NPCDialogueUI.luau, see its own top comment); this module only registers what Ruisu's
-- conversation says and does. A future NPC adds its own equally-small registration module instead
-- of touching the shared system at all.
--
-- "Yes" closes the dialogue and opens the real store panel (StorePanelUI.luau) -- browsing/prices/
-- ownership are all real, buying isn't wired up yet (a later build stage).
local StoreDialogueUI = {}

local STORE_NPC = NPCConfig.Store

function StoreDialogueUI.Start()
	NPCDialogueUI.Register(STORE_NPC.Id, {
		rigName = STORE_NPC.RigName,
		displayName = STORE_NPC.DisplayName,
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
end

return StoreDialogueUI
