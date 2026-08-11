local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local MapConfig = require(ReplicatedStorage.Shared.MapConfig)
local PlayerConfig = require(ReplicatedStorage.Shared.PlayerConfig)
local RoundConfig = require(ReplicatedStorage.Shared.RoundConfig)
local LeafSpawner = require(script.Parent.LeafSpawner)
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
--                           earlier once every connected player has voted. RoundUI builds its vote
--                           cards straight from the shared MapConfig module (no server announcement
--                           needed for *which* maps are votable) and gets live tallies via the
--                           MapVoteUpdate remote instead of an attribute.
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
local state = "Intermission"
local currentMap = MapConfig[1]
local roundContributions = {} -- Player -> leaves delivered this round, for the Results MVP tag
local mapVotes = {} -- Player -> MapConfig Id, reset every MapPick phase

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
local function fadeTeleport(part, inRound)
	local players = Players:GetPlayers()

	for _, player in ipairs(players) do
		screenFadeRemote:FireClient(player, "Out", RoundConfig.FadeSeconds)
	end
	task.wait(RoundConfig.FadeSeconds)

	teleportPlayersTo(players, part, inRound)
	task.wait(0.15) -- lets the teleport's replication actually land before fading back in

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

local function freezePlayers(frozen)
	for _, player in ipairs(Players:GetPlayers()) do
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
-- an MVP with 0.
local function buildResultsList()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(list, { Name = player.Name, Count = roundContributions[player] or 0 })
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

-- Idle beat in the Lobby before the next round automatically starts picking a map -- replaces the
-- old manual "Start Round" button entirely.
local function runIntermission()
	setState("Intermission")
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

-- Picks the map with the most votes, ties broken by MapConfig order -- defaults to MapConfig[1]
-- if nobody voted at all (bestCount starts below every possible real count, so the first entry
-- always wins by default).
local function tallyMapVote()
	local counts = {}
	for _, mapId in pairs(mapVotes) do
		counts[mapId] = (counts[mapId] or 0) + 1
	end
	local winner = MapConfig[1]
	local bestCount = -1
	for _, mapEntry in ipairs(MapConfig) do
		local count = counts[mapEntry.Id] or 0
		if count > bestCount then
			bestCount = count
			winner = mapEntry
		end
	end
	return winner
end

-- A real vote, even with only one map/one player on the roster today -- RoundUI.luau shows every
-- MapConfig entry as a votable card (it already has the shared MapConfig module, so it doesn't
-- need the server to announce candidates first) with a Vote button. Three beats, each its own
-- RoundState so RoundUI can render a distinct step instead of an instant cut between them:
--   MapPick  -- voting is open. Waits for everyone connected to vote AND MapVoteMinSeconds to have
--              passed (so a solo/fast vote can't make the whole phase feel skipped), or the outer
--              MapPickSeconds timeout, whichever's first -- same "goal or timer" shape the Active
--              round itself already uses. `mapVoteRemote`'s OnServerEvent handler (see Start()) is
--              what actually fills in `mapVotes` while this loop polls it.
--   MapTally -- a short fixed pause after voting closes, before the winner is revealed.
--   MapResult -- the winning map's name, held up before Loading begins.
local function runMapPick()
	mapVotes = {}
	broadcastMapVotes()
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
	fadeTeleport(ground, true)

	setState("Countdown")
	freezePlayers(true)

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
	freezePlayers(false)
	task.wait(RoundConfig.GoHoldSeconds)

	setState("Active")
	local roundEndsAt = Workspace:GetServerTimeNow() + RoundConfig.RoundDurationSeconds
	Workspace:SetAttribute("RoundEndsAt", roundEndsAt)

	-- Goal-or-timer, whichever first (or an admin's :finishround, which counts as the timer --
	-- see forceEndRequested/ForceEndRound below). Polled rather than event-driven since this is the
	-- only place that cares about the combination of all three conditions together.
	--
	-- Also ends early (as a Timer end) if everyone disconnects mid-round -- without this, an
	-- abandoned round used to just sit there for the full RoundDurationSeconds (240s default) with
	-- leaves still spawning and their movement loops still ticking, for nobody. Checked every poll
	-- (0.5s), so it catches an empty round quickly rather than waiting out the timer.
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
		if #Players:GetPlayers() == 0 then
			endReason = "Timer"
			break
		end
		if Workspace:GetServerTimeNow() >= roundEndsAt then
			endReason = "Timer"
			break
		end
		task.wait(0.5)
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

	endRound()
end

function endRound()
	local map1 = Workspace:FindFirstChild(currentMap.WorkspaceFolderName)

	local startingLobby = Workspace:WaitForChild("StartingLobby", 15)
	local spawnPlatform = startingLobby and startingLobby:WaitForChild("SpawnPlatform", 15)
	if spawnPlatform then
		fadeTeleport(spawnPlatform, false)
	end

	if map1 then
		translateMapParts(map1, -RoundConfig.MapAwayOffset)
		map1.Parent = ServerStorage
	end
	Workspace:SetAttribute("ActiveMapFolderName", nil)
	Workspace:SetAttribute("RoundGoal", nil)

	setState("Intermission")
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

	-- Only counted during MapPick, and only for a real MapConfig entry -- a stale/late vote fired
	-- right as the phase ends (or a bogus id) is silently dropped rather than corrupting the tally.
	mapVoteRemote.OnServerEvent:Connect(function(player, mapId)
		if state ~= "MapPick" then
			return
		end
		local validMap = false
		for _, mapEntry in ipairs(MapConfig) do
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
