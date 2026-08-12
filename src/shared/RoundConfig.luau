return {
	-- How long the Lobby sits idle in Intermission before the next round automatically begins
	-- picking a map -- replaces the old manual "Start Round" button entirely; the loop just runs on
	-- its own now (RoundSystem.Start()'s runRoundLoop). RoundUI shows a live "Starting in Ns..."
	-- card during this window (RoundIntermissionEndsAt). This timer doesn't even start counting
	-- down until at least one loaded-in player is present -- see RoundSystem.runIntermission.
	IntermissionSeconds = 30,

	-- Map vote pacing -- was one flat 6s window that felt instant (especially solo, where voting
	-- could end the very moment you clicked). Now three separate beats:
	--   MapVoteMinSeconds : voting stays open at LEAST this long even if every connected player has
	--                       already voted -- stops a solo/fast vote from feeling like a skip.
	--   MapPickSeconds    : the outer timeout -- voting closes here regardless, if not everyone's
	--                       voted by then.
	--   MapTallySeconds   : "Tallying votes..." pause after voting closes, before the winner is
	--                       revealed -- its own RoundState ("MapTally") so RoundUI can show a
	--                       dedicated beat for it instead of an instant cut to the result. Was 1.5s,
	--                       still read as instant -- bumped up so it's actually legible.
	--   MapResultSeconds  : how long the "NEXT MAP" reveal (winning map's name + difficulty +
	--                       recommended players) stays up before Loading begins. Was 2.5s, same
	--                       "too fast to read" issue, worse once the reveal grew a second/third line
	--                       of text -- bumped up to give it enough time to actually be read.
	MapVoteMinSeconds = 5,
	MapPickSeconds = 12,
	MapTallySeconds = 3,
	MapResultSeconds = 4.5,

	-- How many maps get shown on the vote panel each round -- RoundSystem randomly samples this
	-- many entries out of MapConfig every MapPick phase (shuffled order too), instead of always
	-- showing every map. With exactly this many real maps today it just randomizes row order; the
	-- point is that adding a 4th/5th map later doesn't require reworking the panel's fixed 3-row
	-- mobile-friendly layout (see RoundUI.luau) -- it's still always exactly this many rows, just a
	-- random subset of a bigger pool.
	MapPickBallotSize = 3,

	-- Brief pause after Map1 is revealed and players are teleported in, before the countdown
	-- starts -- purely a pacing beat so "Loading" reads as a real step, not an instant flicker.
	LoadingDelaySeconds = 2,

	-- "8...7...6...5...4...3...2...1...GO" -- was 5, which barely gave each number a beat once you
	-- factor in reaction time; this gives the whole thing a slower, more deliberate feel.
	CountdownSeconds = 8,

	-- How long "GO!" itself stays on screen after the numeric countdown hits zero, before the round
	-- actually goes Active -- without this the countdown label swaps state (and disappears) the same
	-- instant it would've shown "GO!", so it read as barely a flicker. Players are unfrozen the
	-- moment this hold starts (see RoundSystem.luau), not when it ends.
	GoHoldSeconds = 1.2,

	-- How long an Active round can run before it ends on the timer instead of the goal. Leaves keep
	-- spawning up to the map's own budget throughout (MapConfig.luau's FallingLeafCount/
	-- GroundLeafCount) -- this is just how long players get to work on that map's Goal, also in
	-- MapConfig now (not here -- it's a per-map difficulty knob, not a global).
	RoundDurationSeconds = 600, -- 10:00

	-- How long the client's full-screen fade holds solid black for a Lobby<->map transition (one
	-- way -- the same duration is used again for the fade back in). Covers both the Loading->
	-- Countdown teleport onto the map and the Results->Intermission teleport back to the Lobby, so
	-- neither ever reads as an instant jump-cut.
	FadeSeconds = 0.4,

	-- Max time RoundSystem.streamPlayersIn waits (per player, in parallel) for
	-- Player:RequestStreamAroundAsync to finish loading the destination region in before fading the
	-- screen back in -- see leaf.rbxlx's Workspace.StreamingEnabled. A generous-but-bounded window:
	-- long enough for a normal streamed-in region on a laggy connection, short enough that one
	-- stuck/slow client can't hang everyone else's transition indefinitely.
	StreamAroundTimeoutSeconds = 2,

	-- How long the map's name flashes big and centered before the numeric countdown starts, once
	-- players have already faded in on the map.
	MapTitleFlashSeconds = 2.2,

	-- How long the round-results panel (leaderboard + MVP tag) stays up before everyone gets faded
	-- back to the Lobby -- a cooldown beat so players can actually read who won, not an instant cut
	-- straight from the goal/timer ending.
	ResultsDurationSeconds = 10,

	-- How long the "GOAL REACHED!"/"TIME'S UP!" banner holds on its own before the Results panel
	-- pops up underneath it -- the two used to fire in the same instant and visually collide; this
	-- is the beat that separates "announcing the round ended" from "showing who won". Read by both
	-- RoundSystem (delays firing the results remote by this long) and RoundUI (how long it holds the
	-- banner) so the two can never drift out of sync with each other.
	ResultsBannerHoldSeconds = 2.2,

	-- Risk/reward for how the round actually ended -- read by both RoundSystem
	-- (RoundSystem.applyResultsRewards, the actual Coins math) and RoundResultsUI (which
	-- compliment/scold message to show, using the exact same threshold so the message and the
	-- Coins change can never disagree about how the round went):
	--   ResultsGoalBonusPercent      : fraction of a player's OWN round-earned Coins added as a
	--                                  bonus when the goal is reached before the timer.
	--   ResultsGoodProgressThreshold : cleanup-progress fraction (0-1) at/above which a Timer-ended
	--                                  round (goal NOT reached) still gets complimented with no
	--                                  penalty, instead of scolded with a deduction. Below this,
	--                                  the deduction is (1 - progress) of round-earned Coins -- the
	--                                  worse the shortfall, the bigger the cut.
	ResultsGoalBonusPercent = 0.2,
	ResultsGoodProgressThreshold = 0.8,

	-- Every BasePart under the active round's map folder gets pushed by this vector when the map is
	-- revealed (and pulled back by the negated vector right before it's hidden again) -- with every
	-- map authored close together in leaf.rbxlx for convenience while building, the Lobby (and any
	-- other map) would otherwise be visible in the distance during a round. 10,000 studs on X alone
	-- is far past normal render/fog distance (and past StreamingEnabled's radius, so it streams out
	-- entirely), while staying well within Roblox's safe float-precision range.
	MapAwayOffset = Vector3.new(10000, 0, 0),
}
