-- Shared geometry for the top-right UI stack (gear, Coins, Sack, Player list) so they line up
-- consistently and stay non-overlapping as things get added -- one source of truth instead of
-- hardcoded numbers duplicated (and drifting) across separate UI modules.
return {
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
}
