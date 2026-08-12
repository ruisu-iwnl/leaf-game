-- Registry of interactable NPCs (Store rig, and any future ones) -- the single place that maps an
-- NPC's identity to the Workspace instance it's actually placed as. Keeping RigName separate from
-- DisplayName/Id means renaming the object in Studio (or reskinning which character plays a given
-- role) never means hunting through NPCInteraction/StoreDialogueUI/StorePanelUI for hardcoded
-- strings again -- change it here once.
--
-- Id: internal identifier used for the OpenNPCDialogue remote + NPCDialogueUI's registry key.
-- RigName: the actual Workspace instance name Claude/the user placed the rig as (may not match the
--   character's name -- e.g. the Store rig is a "Ruisu" character parented as an instance named
--   "Store").
-- DisplayName: what's shown to players (ProximityPrompt subtitle, dialogue box name).
return {
	Store = {
		Id = "Ruisu",
		RigName = "Store",
		DisplayName = "Ruisu",
	},
	-- A second, separate physical rig -- placed by the user in the Lobby specifically to greet new/
	-- returning players and point them at the Tutorial quest (see QuestConfig.luau/QuestSystem.luau).
	-- Its Id is deliberately distinct from Store's ("Guide", not "Ruisu") even though both display
	-- as "Ruisu" -- Id is only ever used as an internal dialogue-registry/remote key, never shown to
	-- players, so the two NPCs never collide despite sharing a display name.
	Guide = {
		Id = "Guide",
		RigName = "Ruisu",
		DisplayName = "Ruisu",
	},
}
