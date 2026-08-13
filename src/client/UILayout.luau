-- Shared geometry for the top-right UI stack (gear, Coins, Sack, Player list) so they line up
-- consistently and stay non-overlapping as things get added -- one source of truth instead of
-- hardcoded numbers duplicated (and drifting) across separate UI modules.
--
-- DisplayOrder tiers (below) are the SAME idea applied to cross-ScreenGui stacking: almost every
-- ScreenGui in this game used to just leave DisplayOrder at its default (0), which made stacking
-- order among them effectively incidental (whichever happened to get built/parented in first) --
-- e.g. SackUI covering QuestLogUI, or RoundUI/PlayerListUI/MapProgressUI covering InventoryUI,
-- depending on nothing more meaningful than script execution order. Every ScreenGui in the game
-- should set `screenGui.DisplayOrder = UILayout.DisplayOrder.<Tier>` from this table rather than a
-- bare number, so the whole stack stays deliberate as more panels get added:
--   HUD          : always-on ambient elements never meant to layer above a real panel -- Hotbar,
--                  Overheat/RakeCooldown bars, TopBar (Coins/gear/AFK/player-list toggle), the
--                  round timer + map vote/countdown cards (RoundUI), the custom player list
--                  (PlayerListUI), MapProgressUI's pill, SackUI's grab-count HUD.
--   Banner       : RoundResultsUI's automatic end-of-round leaderboard.
--   Panel        : ordinary click-to-open panels with their own backdrop -- SettingsUI,
--                  StorePanelUI, NPCDialogueUI, TutorialPanelUI.
--   PanelOverlay : a popover that must render above the ONE specific Panel it's opened from --
--                  VIPColorPickerUI (above SettingsUI), ItemPreviewUI (above StorePanelUI).
--   Toast        : floating transient notifications that should float above whatever panel
--                  happens to be open -- ToastNotificationUI (quest/badge toasts), AFKUI's own
--                  "You're AFK"/"Welcome back" confirmation toast.
--   TopPanel     : QuestLogUI and InventoryUI specifically -- explicitly the highest-priority
--                  panels in the game (above every other Panel/PanelOverlay/Toast/HUD element).
--   Admin        : AdminCommandBar only -- a dev tool, deliberately above literally everything
--                  else so it's usable no matter what other UI happens to be open.
--   MainMenu     : MainMenuUI only -- the pre-game title/Play screen, above even Admin, since it
--                  must fully cover the screen before any other system (gameplay or dev tool) has
--                  anything worth seeing underneath it.
return {
	DisplayOrder = {
		HUD = 0,
		Banner = 10,
		Panel = 20,
		PanelOverlay = 30,
		Toast = 40,
		TopPanel = 50,
		Admin = 100,
		MainMenu = 200,
	},


	EdgeMargin = 20, -- gap from the screen's right edge
	WidgetWidth = 150, -- shared width for the right-aligned rows, so their edges all line up

	CoinsY = 20,
	CoinsHeight = 36,

	SackY = 64, -- CoinsY + CoinsHeight + 8
	SackHeight = 36,

	PlayerToggleY = 108, -- SackY + SackHeight + 8
	PlayerToggleHeight = 32,

	PlayerListY = 144, -- PlayerToggleY + PlayerToggleHeight + 4

	-- The settings gear sits to the LEFT of the Coins pill, on the same row (built together by
	-- TopBar.luau so they reflow as one unit and can never overlap), rather than in the vertical
	-- stack -- saves a whole row for something that's just a single icon button.
	GearSize = 36,

	-- Bottom-right hotbar, shared with the inventory button that sits just above it.
	HotbarEdgeMargin = 20,
	HotbarCardSize = 64,

	-- Bottom-CENTER HUD bars (overheat/rake cooldown). Roblox's own default hotbar used to live here
	-- (hence a much bigger margin previously), but it's disabled now that HotbarUI replaces it
	-- bottom-right instead -- just enough gap to clear the screen edge/mobile safe-area.
	HudBottomMargin = 24,
}
