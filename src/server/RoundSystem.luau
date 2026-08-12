local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig)
local PlayerConfig = require(ReplicatedStorage.Shared.PlayerConfig)
local QuestConfig = require(ReplicatedStorage.Shared.QuestConfig)
local RoundConfig = require(ReplicatedStorage.Shared.RoundConfig)
local DailyQuestSystem = require(script.Parent.DailyQuestSystem)
local LeafSpawner = require(script.Parent.LeafSpawner)
local MoneySystem = require(script.Parent.MoneySystem)
local PlayerUpgrades = require(script.Parent.PlayerUpgrades)
local QuestObjectives = require(script.Parent.QuestObjectives)
local SackSystem = require(script.Parent.SackSystem)

-- Orchestrates the Lobby <-> map loop: Intermission (every map hidden in ServerStorage, everyone
-- in the Lobby, a live "Starting in Ns..." card counting down) -> MapPick (a card announcing which
-- map was picked -- always MapConfig[1] today, since there's only one, but the phase already
-- exists for when a real vote replaces the auto-pick) -> Loading (the picked map revealed + fully
-- built) -> Countdown (map title flash, then a numeric countdown + "GO!" hold, movement frozen
-- throughout) -> Active (the real round: goal-or-timer) -> Results (an end-of-round banner, then
-- the leaderboard/MVP panel, a cooldown beat) -> back to Intermission.
--
-- The whole loop runs on its own (RoundSystem.Start() spawns runRoundLoop) -- there is no longer a
-- manual "Start Round" button/remote; Intermission and MapPick are both just timed pauses
-- (RoundConfig.IntermissionSeconds/MapPickSeconds) with their own Workspace attributes for RoundUI
-- to render a countdown/card off of.
--
-- This is the single orchestrator for anything that depends on a map existing -- LeafSpawner's
-- round spawning and SackSystem's yard references are only ever started/stopped from here, once
-- the map's presence is already guaranteed, rather than each of them independently
-- polling/waiting for it (see their own comments for why that used to be a real hang risk).
-- Progress itself has no server-built UI anymore -- MapProgressUI.luau (client) renders it
-- entirely from Workspace attributes, no per-map instance lookup needed at all.
--
-- Map picking is modularized through MapConfig.luau: every lookup below goes through
-- `currentMap.WorkspaceFolderName`/`currentMap.GroundName`/`currentMap.DisplayName` instead of a
-- hardcoded "Map1" string, and LeafSpawner/SackSystem both take the map's folder as a parameter
-- instead of looking it up themselves -- adding a second map to the pool later is a MapConfig
-- entry plus a real pick, not a rewrite of any of this.
--
-- Every map is authored close to the Lobby in leaf.rbxlx (easiest for hand-placing/nudging in
-- Studio), so `beginRound`/`endRound` physically translate the whole map folder by
-- RoundConfig.MapAwayOffset (and back) via translateMapParts below -- purely a runtime CFrame
-- shift, never written back to the file -- so a player standing on an active map can't see the
-- Lobby (or a future second map) off in the distance.
local RoundSystem = {}

-- Workspace attributes clients read to drive their own UI (RoundUI.luau, RoundResultsUI.luau):
--   RoundState            : "Intermission" | "MapPick" | "MapTally" | "MapResult" | "Loading" |
--                           "Countdown" | "Active" | "Results"
--   RoundIntermissionEndsAt : server timestamp Intermission ends and MapPick begins, set entering
--                           Intermission -- drives RoundUI's "Starting in Ns..." card
--   RoundMapPickEndsAt    : server timestamp voting closes at the latest (MapVoteMinSeconds/
--                           MapPickSeconds -- see RoundConfig.luau) -- voting can also close
--                           earlier once every connected player has voted.
--   RoundMapPickCandidates : comma-separated MapConfig Ids for THIS round's ballot -- a random
--                           subset/order of MapConfig (RoundConfig.MapPickBallotSize entries, see
--                           pickRandomBallot), not necessarily every map in the pool, so RoundUI
--                           can no longer assume "every MapConfig entry is votable" and reads this
--                           instead to know which cards to build. Live tallies still arrive via the
--                           MapVoteUpdate remote, not an attribute.
--   RoundMapPickToken     : bumped every MapPick phase, same reason as RoundMapTitleToken -- two
--                           rounds could randomly land on the identical ballot+order, and
--                           GetAttributeChangedSignal isn't guaranteed to fire on an unchanged
--                           value.
--   RoundMapResultName/RoundMapResultCategory/RoundMapResultPlayers : the winning map's
--                           DisplayName/Category/RecommendedPlayers, set entering MapResult (after
--                           voting closes and MapTallySeconds' pause), for RoundUI's "NEXT MAP"
--                           reveal
--   RoundMapResultToken   : bumped every round for the same reason RoundMapTitleToken is (see
--                           below) -- lets the reveal fire even if the same map wins twice in a row
--   ActiveMapFolderName   : the current map's Workspace folder name, set while Loading/Countdown/
--                           Active/Results, so client scripts never need to hardcode "Map1" either
--   RoundGoal             : this round's map's leaf-delivery goal (MapConfig.luau's Goal field),
--                           set alongside ActiveMapFolderName -- so RoundResultsUI's subtitle can
--                           show "X / Goal" without needing to require MapConfig itself
--   RoundMapTitle         : the current map's display name (for the pre-countdown title flash)
--   RoundMapTitleToken    : bumped every round, even if RoundMapTitle's text is identical to last
--                           round's (same map picked twice in a row) -- GetAttributeChangedSignal
--                           only fires client-side, and firing on a byte-identical SetAttribute
--                           isn't guaranteed, so the flash needs its own always-changing token
--   RoundMapTitleEndsAt   : server timestamp the title flash phase ends and the numeric countdown
--                           begins
--   RoundCountdownEndsAt  : server timestamp, set once the numeric countdown actually starts (nil
--                           during the title-flash phase, so a stale value from last round can't
--                           flash "GO!" for a frame before the title even shows)
--   RoundEndsAt           : server timestamp, set entering Active
--   RoundEndReason        : "Goal" | "Timer", set entering Results (drives the banner text)
--   RoundResultsEndsAt    : server timestamp the Results cooldown ends and everyone gets teleported
--                           back to the Lobby
--
-- Per-player attribute (not on Workspace -- on each Player instance), set in teleportPlayersTo:
--   InActiveRound         : true only for players actually teleported onto the map for the CURRENT
--                           round; false for everyone else, including a player who joined after
--                           this round's teleport already happened. Every client UI that only makes
--                           sense for round participants (the countdown, the round timer pill, the
--                           map-title flash, the results banner + leaderboard, MapProgressUI) reads
--                           their own Players.LocalPlayer:GetAttribute("InActiveRound") before
--                           showing any of that -- a non-participant gets a plain "Round in
--                           Progress"/"Round ending..." pill instead (see RoundUI.luau). MapPick's
--                           vote panel and the Intermission card are NOT gated on this -- those
--                           happen before any teleport for the round even occurs, so they still
--                           apply to everyone connected at the time.
--   IntermissionActive    : false the instant a player connects, true only once their character
--                           has finished loading in for the first time (set in
--                           initPlayerIntermissionState, Start()). runIntermission won't start the
--                           "Starting in Ns..." countdown while zero connected players have this
--                           true -- see countActiveIntermissionPlayers.
--   IsAFK                 : per-player, default false, toggled by the client's AFK icon (TopBar.luau
--                           /AFKUI.luau) via the SetAFK remote. true excludes the player from
--                           countActiveIntermissionPlayers (an all-AFK Lobby never starts counting
--                           down), from this round's map vote (mapVoteRemote's handler rejects a
--                           vote from an AFK player, and going AFK mid-vote drops any vote already
--                           cast), and from beginRound's `participants` snapshot -- an AFK player is
--                           simply never teleported onto the map, never frozen during Countdown, and
--                           never included in the Results leaderboard (see buildResultsList). Can be
--                           toggled any time the player is still physically standing in the Lobby --
--                           Intermission/MapPick/MapTally/MapResult/Loading, all the way up until
--                           `participants` is actually snapshotted right before the teleport onto the
--                           map -- a toggle after that instant is silently dropped (SetAFK's
--                           handler). Loading is included deliberately: the map is being revealed
--                           and leaves are spawning 10,000 studs away during it (see
--                           RoundConfig.MapAwayOffset), but the PLAYER hasn't moved yet, so it reads
--                           to them as still being in the Lobby -- locking the toggle out the instant
--                           RoundState flips to "Loading" (rather than at the actual teleport, ~
--                           RoundConfig.LoadingDelaySeconds later) was the bug a player actually hit:
--                           a toggle made mid-Loading, well before they'd been moved anywhere, was
--                           being silently rejected.
--                           If EVERY connected player is AFK by the time beginRound snapshots
--                           `participants` (nobody actually toggled off in time, or everyone present
--                           is sitting out), beginRound bails out back to Intermission immediately
--                           instead of running a full Loading/Countdown/Active/Results cycle for
--                           zero players -- see the `#participants == 0` check there.
--
-- A player with the Tutorial quest (QuestConfig.luau) STARTED but not yet COMPLETED is treated
-- exactly like an AFK player everywhere IsAFK is checked above (see isSittingOutThisRound) --
-- excluded from countActiveIntermissionPlayers, the map vote, and beginRound's `participants`
-- snapshot. Getting walked into a round mid-tutorial would interrupt it: NPCDialogueUI's
-- AUTO_CLOSE_DISTANCE would close the conversation with the guide the instant they're teleported
-- away, and QuestPathUI's guiding path/arrow would vanish (it's gated on InActiveRound). Unlike
-- IsAFK, this isn't a player-facing toggle -- it's fully automatic, keyed off PlayerQuests'
-- own `QuestStarted_Tutorial`/`Quest_Tutorial` Attributes, so a player doing the tutorial never has
-- to remember to flip anything, and it clears itself the instant they finish (or skip to the end of)
-- the guide's conversation. Deliberately NOT extended to GettingStarted2/GettingStarted3 -- those
-- objectives (deliver leaves, use the Rake, collect via Sack, buy an upgrade) are largely things a
-- player would naturally be doing DURING a round anyway, unlike Tutorial's Lobby-only guide
-- conversation, so sitting them out of rounds while those are active would work against the quest
-- rather than protecting it. Revisit if that turns out wrong in practice.
local state = "Intermission"
local currentMap = MapConfig[1]
local roundContributions = {} -- Player -> leaves delivered this round, for the Results MVP tag
-- Player -> Coins earned via leaf delivery this round (see RoundSystem.RecordCoinsEarned, called
-- from init.server.luau's LeafSpawner.OnLeafDelivered listener -- the one place the coins-per-leaf
-- formula, perks included, actually lives). Reset alongside roundContributions in beginRound().
local roundCoinsEarned = {}
-- Player -> signed Coins actually applied as a Results bonus/penalty this round (positive = bonus,
-- negative = penalty), set once by applyResultsRewards right as an Active round ends. Read by
-- buildResultsList so RoundResultsUI can show it per player.
local roundCoinDeltas = {}
local mapVotes = {} -- Player -> MapConfig Id, reset every MapPick phase
-- The randomly-sampled/shuffled subset of MapConfig actually up for vote this round (see
-- pickRandomBallot below) -- RoundConfig.MapPickBallotSize entries (or all of MapConfig, if it has
-- fewer than that). Votes and the tally are both scoped to this, not the full MapConfig table, so
-- a vote for a map that didn't make this round's ballot can never be cast or counted.
local currentBallot = {}

-- Set by RoundSystem.ForceEndRound() (wired to the ":finishround" admin command), consumed by the
-- Active-phase poll loop in beginRound() -- lets testing skip straight to Results without waiting
-- out the full RoundDurationSeconds. Counts as a Timer end, not a Goal one.
local forceEndRequested = false

local endRound -- forward-declared, see the note on LeafSpawner's startLeafSpawning for why

local remotes
local screenFadeRemote
local roundResultsRemote
local mapVoteRemote
local mapVoteUpdateRemote

local function setState(newState)
	state = newState
	Workspace:SetAttribute("RoundState", newState)
end

-- Spreads players in a small ring around `part` instead of stacking them all on the exact same
-- point -- `index` just needs to differ per player, doesn't need to be stable across calls.
local function landingCFrame(part, index)
	local top = part.Position.Y + part.Size.Y / 2 + 3
	local angle = index * (math.pi * 2 / 8)
	local radius = 6
	local x = part.Position.X + math.cos(angle) * radius
	local z = part.Position.Z + math.sin(angle) * radius
	return CFrame.new(x, top, z)
end

-- `inRound` stamps every teleported player's InActiveRound attribute (true onto the map, false back
-- to the Lobby) -- the single source of truth every client UI (RoundUI/MapProgressUI/
-- RoundResultsUI) reads to decide whether the countdown/timer/map-title flash/results banner/
-- leaderboard actually apply to *them*, versus a player who joined mid-round and was never part of
-- this particular teleport (see fadeTeleport below -- `players` is captured once and reused for
-- both the fade and the pivot, so the two can never disagree about who's actually being moved).
local function teleportPlayersTo(players, part, inRound)
	for i, player in ipairs(players) do
		local character = player.Character
		if character then
			character:PivotTo(landingCFrame(part, i))
		end
		player:SetAttribute("InActiveRound", inRound)
	end
end

-- With Workspace.StreamingEnabled on (see leaf.rbxlx/default.project.json), an instant long-range
-- teleport -- like the Lobby<->map jump, which lands players either right next to a map that was
-- just pulled out of ServerStorage or right next to the Lobby again -- doesn't guarantee the
-- destination region has actually streamed in yet. Without this, a player could fade back in to an
-- empty void, or fall through not-yet-loaded ground, for a frame or more. RequestStreamAroundAsync
-- forces exactly that region to load; fired per player via task.spawn so N players stream in
-- parallel rather than serially, bounded by RoundConfig.StreamAroundTimeoutSeconds so one
-- slow-loading client can never hang everyone else's fade-in.
local function streamPlayersIn(players, position)
	local remaining = 0
	for _, player in ipairs(players) do
		remaining += 1
		task.spawn(function()
			pcall(function()
				player:RequestStreamAroundAsync(position, RoundConfig.StreamAroundTimeoutSeconds)
			end)
			remaining -= 1
		end)
	end
	local deadline = Workspace:GetServerTimeNow() + RoundConfig.StreamAroundTimeoutSeconds + 0.5
	while remaining > 0 and Workspace:GetServerTimeNow() < deadline do
		task.wait(0.05)
	end
end

-- Pushes every BasePart under a map's folder by a fixed offset -- every map is authored close to
-- the Lobby in leaf.rbxlx (convenient for building), so without this a player standing on an
-- active map could see the Lobby (or, later, another map) off in the distance. Called with
-- RoundConfig.MapAwayOffset right after the map is revealed, and with the negated offset right
-- before it's hidden again, so the folder's baseline position in leaf.rbxlx itself never drifts --
-- reopening the file in Studio always shows the original authored layout, never a translated one.
-- Only BaseParts move -- Attachments etc. are parent-relative already and follow for free (same
-- reasoning as the Booth/Ruisu Lobby-relocation script's own translation, see CLAUDE.md).
local function translateMapParts(map1, offset)
	for _, descendant in ipairs(map1:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CFrame = descendant.CFrame + offset
		end
	end
end

-- Full-screen fade out, teleport while the screen is solid black, fade back in -- used for both
-- the Lobby->map transition and the map->Lobby one, so a teleport never reads as an instant
-- jump-cut. The client owns the actual tween (RoundUI.luau); this just brackets it with waits long
-- enough for that tween to finish before/after the teleport actually happens.
-- `inRound` is threaded straight through to teleportPlayersTo (see its comment) -- fired only to
-- the players actually being moved, not FireAllClients, so a player sitting out this round in the
-- Lobby never sees a pointless screen-fade flash for a teleport that doesn't touch them.
local function fadeTeleport(part, inRound, playersOverride)
	local players = playersOverride or Players:GetPlayers()

	for _, player in ipairs(players) do
		screenFadeRemote:FireClient(player, "Out", RoundConfig.FadeSeconds)
	end
	task.wait(RoundConfig.FadeSeconds)

	teleportPlayersTo(players, part, inRound)
	streamPlayersIn(players, part.Position) -- lets the destination actually stream in before fading back

	for _, player in ipairs(players) do
		screenFadeRemote:FireClient(player, "In", RoundConfig.FadeSeconds)
	end
	task.wait(RoundConfig.FadeSeconds)
end

-- WalkSpeed=0 + Jumping disabled during Countdown so nobody can get a head start positioning
-- themselves before "GO!" -- restored from PlayerConfig (the same source PlayerSetup.luau uses),
-- not a remembered value, so this can never drift from whatever a normal spawn would set.
local function setPlayerFrozen(player, frozen)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if frozen then
		humanoid.WalkSpeed = 0
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	else
		humanoid.WalkSpeed = PlayerConfig.WalkSpeed
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, not PlayerConfig.DisableJump)
	end
end

-- `players` defaults to everyone connected, but beginRound passes its own `participants` snapshot
-- (round participants only) so an AFK player standing in the Lobby during another round's Countdown
-- never gets their own WalkSpeed zeroed for a round they were never part of.
local function freezePlayers(frozen, players)
	for _, player in ipairs(players or Players:GetPlayers()) do
		setPlayerFrozen(player, frozen)
	end
end

-- Called right as Loading begins, before anyone's teleported -- wipes anything a player could
-- otherwise carry INTO a fresh round to cheese an instant delivery: their click-collected leaf
-- counter and any physical sack they're holding (equipped, in Backpack, or dropped loose).
local function resetPlayersForRound()
	for _, player in ipairs(Players:GetPlayers()) do
		SackSystem.ResetPlayerForRound(player)
	end
end

-- Builds the Results leaderboard: every currently-connected player, sorted by leaves delivered
-- this round (ties broken by name for a stable order), with the top scorer flagged as MVP -- but
-- only if someone actually delivered at least one leaf, so an empty/skipped round doesn't crown
-- an MVP with 0. CoinDelta (signed -- positive bonus, negative penalty, 0 if neither applied) comes
-- from applyResultsRewards, which must run before this is called (see beginRound).
local function buildResultsList()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		-- Only players actually teleported into THIS round (see beginRound's `participants`
		-- snapshot) -- excludes AFK players and anyone who joined too late to be part of it, so
		-- they don't show up as a padded "0 leaves" row for round they never played.
		if player:GetAttribute("InActiveRound") == true then
			table.insert(list, {
				Name = player.Name,
				Count = roundContributions[player] or 0,
				CoinDelta = roundCoinDeltas[player] or 0,
				IsVIP = PlayerUpgrades.HasPerk(player, "LeafPatron"),
			})
		end
	end
	table.sort(list, function(a, b)
		if a.Count == b.Count then
			return a.Name < b.Name
		end
		return a.Count > b.Count
	end)
	if #list > 0 and list[1].Count > 0 then
		list[1].IsMVP = true
	end
	return list
end

-- Turns each participant's round-earned Coins into either a completion bonus (goal reached before
-- the timer) or a shortfall penalty (timer ran out with the cleanup still meaningfully unfinished)
-- -- called once, right as an Active round ends, before Results fires. Replaces the "risk/reward
-- distinction" this round loop originally shipped without (see this file's Third tuning pass in
-- CLAUDE.md) -- coins are still paid out immediately per leaf delivered, never held back; this
-- only ever adjusts the balance by a percentage of what was ALREADY earned this round, on top of
-- that.
--   Goal reached (endReason == "Goal")            : +RoundConfig.ResultsGoalBonusPercent of
--                                                     roundCoinsEarned, added.
--   Timer, finalProgress >= ResultsGoodProgressThreshold : no penalty -- a near-finished round
--                                                     (see RoundConfig's own comment on the
--                                                     threshold) still gets complimented in
--                                                     RoundResultsUI, not docked.
--   Timer, finalProgress < ResultsGoodProgressThreshold  : -(1 - finalProgress) of
--                                                     roundCoinsEarned, deducted (clamped to
--                                                     whatever the player actually still has via
--                                                     MoneySystem.DeductCoins -- a penalty always
--                                                     applies, it just never goes negative).
-- Players who earned 0 Coins this round (didn't deliver anything) are skipped entirely -- nothing
-- to bonus or deduct.
local function applyResultsRewards(endReason, finalProgress)
	roundCoinDeltas = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local earned = roundCoinsEarned[player] or 0
		if earned > 0 then
			if endReason == "Goal" then
				local bonus = math.floor(earned * RoundConfig.ResultsGoalBonusPercent)
				if bonus > 0 then
					MoneySystem.AddCoins(player, bonus)
					roundCoinDeltas[player] = bonus
				end
			elseif finalProgress < RoundConfig.ResultsGoodProgressThreshold then
				local penalty = math.floor(earned * (1 - finalProgress))
				if penalty > 0 then
					local deducted = MoneySystem.DeductCoins(player, penalty)
					if deducted > 0 then
						roundCoinDeltas[player] = -deducted
					end
				end
			end
		end
	end
end

local TUTORIAL_QUEST_ID = QuestConfig.Tutorial.Id

-- true for an explicitly-AFK player, OR a player with the Tutorial quest started but not yet
-- completed -- both are excluded from Intermission's player count, the map vote, and beginRound's
-- `participants` snapshot. See this file's own top attribute-doc block for why Tutorial specifically.
local function isSittingOutThisRound(player)
	if player:GetAttribute("IsAFK") then
		return true
	end
	return player:GetAttribute("QuestStarted_" .. TUTORIAL_QUEST_ID) == true
		and player:GetAttribute("Quest_" .. TUTORIAL_QUEST_ID) ~= true
end

-- How many connected players are actually "active" for Intermission purposes -- see the
-- IntermissionActive attribute (set in initPlayerIntermissionState, Start()) for what that means.
local function countActiveIntermissionPlayers()
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("IntermissionActive") and not isSittingOutThisRound(player) then
			count += 1
		end
	end
	return count
end

-- Idle beat in the Lobby before the next round automatically starts picking a map -- replaces the
-- old manual "Start Round" button entirely. Doesn't start the actual "Starting in Ns..." countdown
-- until at least one player is both connected AND actually active (loaded in, see
-- initPlayerIntermissionState) -- an empty server, or one where everyone just joined and hasn't
-- finished loading, shouldn't burn through Intermission into a round nobody's actually there for.
-- RoundIntermissionEndsAt stays nil the whole time no one's active, so RoundUI's Intermission card
-- shows a "Waiting for players..." message instead of a countdown to nothing.
local function runIntermission()
	setState("Intermission")
	Workspace:SetAttribute("RoundIntermissionEndsAt", nil)
	while countActiveIntermissionPlayers() == 0 do
		task.wait(0.5)
	end
	Workspace:SetAttribute("RoundIntermissionEndsAt", Workspace:GetServerTimeNow() + RoundConfig.IntermissionSeconds)
	task.wait(RoundConfig.IntermissionSeconds)
end

-- Tells every client the live per-map vote tally plus how many players are currently connected --
-- RoundUI.luau uses this to show a vote count next to each map card and update it in real time as
-- other players vote, not just the local player's own click.
local function broadcastMapVotes()
	if not mapVoteUpdateRemote then
		return
	end
	local counts = {}
	for _, mapId in pairs(mapVotes) do
		counts[mapId] = (counts[mapId] or 0) + 1
	end
	mapVoteUpdateRemote:FireAllClients(counts, #Players:GetPlayers())
end

-- Picks the map with the most votes, ties broken by ballot order -- defaults to currentBallot[1]
-- if nobody voted at all (bestCount starts below every possible real count, so the first entry
-- always wins by default). Scoped to currentBallot, not all of MapConfig, since only ballot
-- entries could ever have received a vote (see mapVoteRemote's validation in Start()).
local function tallyMapVote()
	local counts = {}
	for _, mapId in pairs(mapVotes) do
		counts[mapId] = (counts[mapId] or 0) + 1
	end
	local winner = currentBallot[1]
	local bestCount = -1
	for _, mapEntry in ipairs(currentBallot) do
		local count = counts[mapEntry.Id] or 0
		if count > bestCount then
			bestCount = count
			winner = mapEntry
		end
	end
	return winner
end

-- Randomly samples RoundConfig.MapPickBallotSize entries out of MapConfig (shuffled order too, via
-- a partial Fisher-Yates), so the vote panel shows a fresh subset/order every round instead of
-- always the same fixed list. Clamped to #MapConfig so this still works fine if the pool ever has
-- fewer maps than the configured ballot size.
local function pickRandomBallot()
	local pool = {}
	for _, mapEntry in ipairs(MapConfig) do
		table.insert(pool, mapEntry)
	end
	for i = #pool, 2, -1 do
		local j = math.random(i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local ballotSize = math.min(RoundConfig.MapPickBallotSize, #pool)
	local ballot = {}
	for i = 1, ballotSize do
		table.insert(ballot, pool[i])
	end
	return ballot
end

-- A real vote, even with only one map/one player on the roster today -- RoundUI.luau shows a
-- Vote button for each map in this round's ballot (a random subset/order of MapConfig, see
-- pickRandomBallot -- announced via RoundMapPickCandidates below, since the client can no longer
-- assume "every MapConfig entry" is what's votable). Three beats, each its own RoundState so
-- RoundUI can render a distinct step instead of an instant cut between them:
--   MapPick  -- voting is open. Waits for everyone connected to vote AND MapVoteMinSeconds to have
--              passed (so a solo/fast vote can't make the whole phase feel skipped), or the outer
--              MapPickSeconds timeout, whichever's first -- same "goal or timer" shape the Active
--              round itself already uses. `mapVoteRemote`'s OnServerEvent handler (see Start()) is
--              what actually fills in `mapVotes` while this loop polls it.
--   MapTally -- a short fixed pause after voting closes, before the winner is revealed.
--   MapResult -- the winning map's name, held up before Loading begins.
local function runMapPick()
	mapVotes = {}
	currentBallot = pickRandomBallot()
	broadcastMapVotes()

	local candidateIds = {}
	for _, mapEntry in ipairs(currentBallot) do
		table.insert(candidateIds, mapEntry.Id)
	end
	-- Data attributes set BEFORE the RoundState flip that triggers reading them -- same
	-- before-the-trigger ordering as RoundMapTitle/RoundEndReason elsewhere in this file.
	-- RoundMapPickToken (not just the candidates string) exists because two different rounds could
	-- randomly land on the identical ballot+order, and GetAttributeChangedSignal isn't guaranteed
	-- to fire on a byte-identical SetAttribute -- same reasoning as RoundMapTitleToken.
	Workspace:SetAttribute("RoundMapPickCandidates", table.concat(candidateIds, ","))
	Workspace:SetAttribute("RoundMapPickToken", (Workspace:GetAttribute("RoundMapPickToken") or 0) + 1)

	local votingEndsAt = Workspace:GetServerTimeNow() + RoundConfig.MapPickSeconds
	local votingMinEndsAt = Workspace:GetServerTimeNow() + RoundConfig.MapVoteMinSeconds
	Workspace:SetAttribute("RoundMapPickEndsAt", votingEndsAt)
	setState("MapPick")

	while state == "MapPick" do
		local now = Workspace:GetServerTimeNow()
		local players = Players:GetPlayers()
		local everyoneVoted = #players > 0
		for _, player in ipairs(players) do
			if not mapVotes[player] then
				everyoneVoted = false
				break
			end
		end
		if (everyoneVoted and now >= votingMinEndsAt) or now >= votingEndsAt then
			break
		end
		task.wait(0.25)
	end

	currentMap = tallyMapVote()

	setState("MapTally")
	task.wait(RoundConfig.MapTallySeconds)

	-- Data attributes set BEFORE the RoundState flip that triggers reading them -- same
	-- before-the-trigger ordering as RoundMapTitle/RoundEndReason elsewhere in this file.
	Workspace:SetAttribute("RoundMapResultName", currentMap.DisplayName)
	Workspace:SetAttribute("RoundMapResultCategory", currentMap.Category)
	Workspace:SetAttribute("RoundMapResultPlayers", currentMap.RecommendedPlayers)
	Workspace:SetAttribute("RoundMapResultToken", (Workspace:GetAttribute("RoundMapResultToken") or 0) + 1)
	setState("MapResult")
	task.wait(RoundConfig.MapResultSeconds)
end

local function beginRound()
	setState("Loading")
	Workspace:SetAttribute("RoundCountdownEndsAt", nil)
	Workspace:SetAttribute("RoundMapTitle", nil)

	local map1 = ServerStorage:FindFirstChild(currentMap.WorkspaceFolderName)
	if not map1 then
		warn(string.format("[RoundSystem] %s not found in ServerStorage -- can't start a round.", currentMap.WorkspaceFolderName))
		setState("Intermission")
		return
	end
	map1.Parent = Workspace
	translateMapParts(map1, RoundConfig.MapAwayOffset)
	Workspace:SetAttribute("ActiveMapFolderName", currentMap.WorkspaceFolderName)
	Workspace:SetAttribute("RoundGoal", currentMap.Goal)

	roundContributions = {}
	roundCoinsEarned = {}
	roundCoinDeltas = {}
	resetPlayersForRound()

	-- Both find the map's children directly (no WaitForChild timeout) since it's guaranteed
	-- present in Workspace as of the line above -- see their own comments. LeafSpawner also gets
	-- currentMap itself (not just the folder) since this map's FallingLeafCount/GroundLeafCount/
	-- Goal live there now, not in a global config.
	LeafSpawner.StartYardRound(map1, currentMap)
	SackSystem.StartYardRound(map1)

	-- The map is now fully built (leaves spawned) -- this pacing wait is the actual "loading" beat.
	-- Players are NOT teleported until it's done, so nobody ever arrives on a map that's still
	-- mid-setup.
	task.wait(RoundConfig.LoadingDelaySeconds)

	local ground = map1:WaitForChild(currentMap.GroundName)

	-- Snapshot of who's actually playing this round -- excludes anyone marked AFK. SetAFK's handler
	-- allows toggling right up until this exact line (see its own comment in Start()), so this is
	-- deliberately taken as late as possible, immediately before the teleport below.
	local participants = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if not isSittingOutThisRound(player) then
			table.insert(participants, player)
		end
	end

	-- Nobody's actually playing this round -- everyone connected is AFK (or nobody's connected at
	-- all, though runIntermission already guards against that case). Undo the reveal/spawn that
	-- already happened above and bail straight back to Intermission instead of running a full
	-- Loading/Countdown/Active/Results cycle -- complete with a translated map and 10,000 leaves --
	-- for a round literally nobody will experience.
	if #participants == 0 then
		LeafSpawner.StopYardRound()
		SackSystem.StopYardRound()
		translateMapParts(map1, -RoundConfig.MapAwayOffset)
		map1.Parent = ServerStorage
		Workspace:SetAttribute("ActiveMapFolderName", nil)
		Workspace:SetAttribute("RoundGoal", nil)
		setState("Intermission")
		return
	end

	fadeTeleport(ground, true, participants)

	setState("Countdown")
	freezePlayers(true, participants)

	-- RoundMapTitle/RoundMapTitleEndsAt are set BEFORE the token bump: the client's trigger for the
	-- title flash is the token changing, and it reads RoundMapTitle synchronously the instant it
	-- sees that change -- if the token were set first, a client could observe the new token before
	-- the new title text, and flash blank/stale text for a frame.
	Workspace:SetAttribute("RoundMapTitle", currentMap.DisplayName)
	Workspace:SetAttribute("RoundMapTitleEndsAt", Workspace:GetServerTimeNow() + RoundConfig.MapTitleFlashSeconds)
	Workspace:SetAttribute("RoundMapTitleToken", (Workspace:GetAttribute("RoundMapTitleToken") or 0) + 1)
	task.wait(RoundConfig.MapTitleFlashSeconds)

	Workspace:SetAttribute("RoundCountdownEndsAt", Workspace:GetServerTimeNow() + RoundConfig.CountdownSeconds)
	task.wait(RoundConfig.CountdownSeconds)

	-- Countdown hits zero here -- players are released immediately ("GO!" means go), but the
	-- RoundState itself (and therefore the countdown label showing "GO!") stays put for a bit
	-- longer so it actually reads as a moment, not a single-frame flicker.
	freezePlayers(false, participants)
	task.wait(RoundConfig.GoHoldSeconds)

	setState("Active")
	local roundEndsAt = Workspace:GetServerTimeNow() + RoundConfig.RoundDurationSeconds
	Workspace:SetAttribute("RoundEndsAt", roundEndsAt)

	-- Goal-or-timer, whichever first (or an admin's :finishround, which counts as the timer --
	-- see forceEndRequested/ForceEndRound below). Polled rather than event-driven since this is the
	-- only place that cares about the combination of all three conditions together.
	--
	-- Also ends early (as a Timer end) once none of THIS round's actual participants are still
	-- connected -- without this, an abandoned round used to just sit there for the full
	-- RoundDurationSeconds (240s default) with leaves still spawning and their movement loops still
	-- ticking, for nobody. Deliberately checks `participants` still in Players:GetPlayers(), NOT
	-- Players:GetPlayers() being empty -- an AFK player can stay connected in the Lobby the entire
	-- time (that's the whole point of the feature), which would otherwise mask a round every real
	-- participant has already left/disconnected from as "still has someone in the server". Checked
	-- every poll (0.5s), so it catches an empty round quickly rather than waiting out the timer.
	local function anyParticipantStillConnected()
		for _, participant in ipairs(participants) do
			if participant.Parent == Players then
				return true
			end
		end
		return false
	end

	local endReason = "Timer"
	while state == "Active" do
		local progress = Workspace:GetAttribute("CleanupZoneProgress") or 0
		if progress >= 0.999 then
			endReason = "Goal"
			break
		end
		if forceEndRequested then
			forceEndRequested = false
			endReason = "Timer"
			break
		end
		if not anyParticipantStillConnected() then
			endReason = "Timer"
			break
		end
		if Workspace:GetServerTimeNow() >= roundEndsAt then
			endReason = "Timer"
			break
		end
		task.wait(0.5)
	end

	-- Read fresh (not the while loop's own local `progress`, out of scope here) -- safe to read
	-- after the loop regardless of which condition broke it, since nothing but a delivery can move
	-- this attribute and StopYardRound below doesn't touch it. Clamped to 1 -- a delivery landing in
	-- the ~0.5s gap between the loop's last poll and here could in principle push it a hair past 1.
	local finalProgress = math.min(Workspace:GetAttribute("CleanupZoneProgress") or 0, 1)
	applyResultsRewards(endReason, finalProgress)

	-- Counts toward the "CompleteRounds" daily quest AND the long-term "Round Veteran" quest
	-- (QuestConfig.luau) -- participation only, regardless of goal/timer outcome (same "showing up
	-- counts" spirit as the rest of this round's rewards not requiring a win). Filtered to
	-- still-connected participants, same check as anyParticipantStillConnected above -- a
	-- participant who disconnected mid-round has no Player instance left to set an Attribute on.
	for _, participant in ipairs(participants) do
		if participant.Parent == Players then
			DailyQuestSystem.RecordProgress(participant, "CompleteRounds", 1)
			QuestObjectives.RecordProgress(participant, "CompleteRounds", 1)
		end
	end

	-- Stop the round's mechanics the instant it's over, not after the whole Results phase -- leaves
	-- stop spawning and existing ones are cleared, and SackSystem drops its cleanup-zone reference,
	-- so nothing delivered/blown in during the banner+leaderboard cooldown can still register as
	-- part of a round that's already finished (no more progress, no more coins).
	LeafSpawner.StopYardRound()
	SackSystem.StopYardRound()

	-- Announce first (RoundUI's big "GOAL REACHED!"/"TIME'S UP!" flash, triggered by RoundState
	-- entering Results), hold that on its own, THEN pop the leaderboard -- these used to fire in
	-- the same instant and visually collide. RoundEndReason is set BEFORE setState("Results") for
	-- the same reason as RoundMapTitle above -- the client reads it synchronously the instant it
	-- sees RoundState become "Results", so it has to already be correct by then, not racing it.
	Workspace:SetAttribute("RoundEndReason", endReason)
	setState("Results")
	task.wait(RoundConfig.ResultsBannerHoldSeconds)

	Workspace:SetAttribute("RoundResultsEndsAt", Workspace:GetServerTimeNow() + RoundConfig.ResultsDurationSeconds)
	roundResultsRemote:FireAllClients(buildResultsList())

	task.wait(RoundConfig.ResultsDurationSeconds)

	endRound(participants)
end

function endRound(participants)
	local map1 = Workspace:FindFirstChild(currentMap.WorkspaceFolderName)

	local startingLobby = Workspace:WaitForChild("StartingLobby", 15)
	local spawnPlatform = startingLobby and startingLobby:WaitForChild("SpawnPlatform", 15)
	if spawnPlatform then
		-- Same `participants` snapshot from beginRound -- an AFK player never left the Lobby in the
		-- first place, so there's nothing to bring back for them.
		fadeTeleport(spawnPlatform, false, participants)
	end

	if map1 then
		translateMapParts(map1, -RoundConfig.MapAwayOffset)
		map1.Parent = ServerStorage
	end
	Workspace:SetAttribute("ActiveMapFolderName", nil)
	Workspace:SetAttribute("RoundGoal", nil)

	setState("Intermission")
end

-- Called from init.server.luau's LeafSpawner.OnLeafDelivered listener, right alongside
-- MoneySystem.AddCoins -- that's the one place the coins-per-leaf formula (perks/multipliers
-- included) actually lives, so this just mirrors whatever was really awarded rather than
-- recomputing the formula a second time here. Purely additive bookkeeping; never touches a
-- player's actual balance itself (see applyResultsRewards for where roundCoinsEarned gets turned
-- into a bonus/penalty).
function RoundSystem.RecordCoinsEarned(player, amount)
	if player and amount and amount > 0 then
		roundCoinsEarned[player] = (roundCoinsEarned[player] or 0) + amount
	end
end

-- Testing-only escape hatch (see AdminCommands.luau's ":finishround") -- skips straight to Results
-- without waiting out the rest of RoundDurationSeconds, as if the timer had just expired. Returns
-- false (does nothing) outside of an Active round, so the admin command can report back cleanly.
function RoundSystem.ForceEndRound()
	if state ~= "Active" then
		return false
	end
	forceEndRequested = true
	return true
end

function RoundSystem.Start()
	Workspace:SetAttribute("RoundState", state)

	remotes = ReplicatedStorage.Shared:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage.Shared
	end

	screenFadeRemote = remotes:FindFirstChild("RoundScreenFade") or Instance.new("RemoteEvent")
	screenFadeRemote.Name = "RoundScreenFade"
	screenFadeRemote.Parent = remotes

	roundResultsRemote = remotes:FindFirstChild("RoundResults") or Instance.new("RemoteEvent")
	roundResultsRemote.Name = "RoundResults"
	roundResultsRemote.Parent = remotes

	mapVoteRemote = remotes:FindFirstChild("SubmitMapVote") or Instance.new("RemoteEvent")
	mapVoteRemote.Name = "SubmitMapVote"
	mapVoteRemote.Parent = remotes

	mapVoteUpdateRemote = remotes:FindFirstChild("MapVoteUpdate") or Instance.new("RemoteEvent")
	mapVoteUpdateRemote.Name = "MapVoteUpdate"
	mapVoteUpdateRemote.Parent = remotes

	local setAFKRemote = remotes:FindFirstChild("SetAFK") or Instance.new("RemoteEvent")
	setAFKRemote.Name = "SetAFK"
	setAFKRemote.Parent = remotes

	-- InActiveRound defaults to false for every player -- explicitly set (not just left nil, though
	-- nil already reads falsy client-side) so it's always present for debugging/introspection, and
	-- so a player who joins mid-round has an unambiguous "not part of this one" signal from the
	-- instant they connect, before teleportPlayersTo ever runs for them.
	local function initPlayerRoundAttribute(player)
		player:SetAttribute("InActiveRound", false)
	end
	Players.PlayerAdded:Connect(initPlayerRoundAttribute)
	for _, player in ipairs(Players:GetPlayers()) do
		initPlayerRoundAttribute(player)
	end

	-- IntermissionActive: false the instant a player connects, true only once their character has
	-- actually finished loading in (CharacterAdded) -- a just-joined player shouldn't count toward
	-- "there's someone here" for Intermission purposes (see countActiveIntermissionPlayers) while
	-- they're still loading, or Intermission could start counting down for someone who isn't
	-- actually ready to be teleported into a round yet. Only listens for the FIRST CharacterAdded --
	-- once a player has genuinely loaded in, later respawns (death, admin teleport, etc.) shouldn't
	-- flip this back to false.
	local function initPlayerIntermissionState(player)
		player:SetAttribute("IntermissionActive", false)
		if player.Character then
			player:SetAttribute("IntermissionActive", true)
			return
		end
		local connection
		connection = player.CharacterAdded:Connect(function()
			if player.Parent then
				player:SetAttribute("IntermissionActive", true)
			end
			connection:Disconnect()
		end)
	end
	Players.PlayerAdded:Connect(initPlayerIntermissionState)
	for _, player in ipairs(Players:GetPlayers()) do
		initPlayerIntermissionState(player)
	end

	-- IsAFK: default false for every player, same explicit-not-just-nil reasoning as
	-- InActiveRound above. See the attribute doc block up top for what true actually does.
	local function initPlayerAFKState(player)
		player:SetAttribute("IsAFK", false)
	end
	Players.PlayerAdded:Connect(initPlayerAFKState)
	for _, player in ipairs(Players:GetPlayers()) do
		initPlayerAFKState(player)
	end

	-- Only honored while the player is still physically standing in the Lobby -- which includes
	-- Loading, not just the states before it: the map is being revealed/built 10,000 studs away
	-- during Loading (RoundConfig.MapAwayOffset), but nobody's actually been teleported there yet,
	-- so the player is still in the Lobby the whole time. Only locked out once beginRound actually
	-- snapshots `participants` right before the real teleport (a few lines before fadeTeleport is
	-- called) -- a toggle after THAT instant wouldn't change anything for the round already
	-- underway. A rejected toggle simply leaves IsAFK unchanged; the client reads the attribute back
	-- rather than assuming its own request succeeded.
	local LOBBY_STATES = { Intermission = true, MapPick = true, MapTally = true, MapResult = true, Loading = true }
	setAFKRemote.OnServerEvent:Connect(function(player, wantsAFK)
		if not LOBBY_STATES[state] then
			return
		end
		wantsAFK = wantsAFK == true
		player:SetAttribute("IsAFK", wantsAFK)
		-- Going AFK mid-vote drops any vote already cast -- sitting this round out means not having
		-- a say in which map everyone else plays it on.
		if wantsAFK and state == "MapPick" and mapVotes[player] then
			mapVotes[player] = nil
			broadcastMapVotes()
		end
	end)

	-- Only counted during MapPick, only for a map actually in this round's ballot, and never for an
	-- AFK player (they're sitting this round out, see IsAFK above) -- any of those, a stale/late
	-- vote fired right as the phase ends, or a map that didn't make this round's randomly-sampled
	-- ballot, is silently dropped rather than corrupting the tally.
	mapVoteRemote.OnServerEvent:Connect(function(player, mapId)
		if state ~= "MapPick" or isSittingOutThisRound(player) then
			return
		end
		local validMap = false
		for _, mapEntry in ipairs(currentBallot) do
			if mapEntry.Id == mapId then
				validMap = true
				break
			end
		end
		if not validMap then
			return
		end
		mapVotes[player] = mapId
		broadcastMapVotes()
	end)

	Players.PlayerRemoving:Connect(function(player)
		if mapVotes[player] then
			mapVotes[player] = nil
			if state == "MapPick" then
				broadcastMapVotes()
			end
		end
	end)

	LeafSpawner.OnLeafDelivered(function(player, count)
		if player then
			roundContributions[player] = (roundContributions[player] or 0) + count
		end
	end)

	-- Every map starts baked into leaf.rbxlx as a normal Workspace child (so it's still
	-- visible/editable in Studio's Edit mode) -- moved to ServerStorage once at boot so
	-- Intermission is the actual default state a fresh server starts in, matching "don't load a
	-- map by default, only when selected." Deferred + timed for the same reason as every other
	-- map lookup this session: a stale Studio session or bad file shouldn't be able to hang this
	-- and block whatever's after it.
	-- Once every map is confirmed moved into ServerStorage (or timed out trying), the round loop
	-- starts on its own -- Intermission -> MapPick -> Loading -> ... -> back to Intermission,
	-- forever, no manual trigger. Chained after the move (not spawned independently) so beginRound
	-- can never look a map up in ServerStorage before this has had a chance to put it there.
	task.spawn(function()
		for _, mapEntry in ipairs(MapConfig) do
			-- Mock entries (MapConfig.luau's `IsMock` -- placeholder maps for testing the vote
			-- panel with more than one option) have no real Workspace folder at all, so waiting
			-- 15s per entry here would add up to a full minute of startup delay for nothing.
			if not mapEntry.IsMock then
				local mapFolder = Workspace:WaitForChild(mapEntry.WorkspaceFolderName, 15)
				if not mapFolder then
					warn(string.format(
						"[RoundSystem] Workspace.%s not found after 15s -- rounds disabled this session. If you just edited leaf.rbxlx, close Studio's session for it (without saving) and reopen the file fresh.",
						mapEntry.WorkspaceFolderName
					))
				else
					mapFolder.Parent = ServerStorage
				end
			end
		end

		while true do
			runIntermission()
			runMapPick()
			beginRound()
		end
	end)
end

return RoundSystem
