local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LeavesCleanedStat = require(script.Parent.LeavesCleanedStat)

-- A persistent, ACROSS-EVERY-SERVER-EVER top-players leaderboard (TOP_N below) by lifetime leaves
-- cleaned -- unlike RoundResultsUI's leaderboard (this round's participants only, reset every
-- round) or PlayerListUI (this SERVER's currently-connected players only), this one is backed by a
-- real OrderedDataStore, so it survives server restarts and spans every player who's ever played,
-- online or not. Shown by HallOfFameUI.luau (client) on a real physical board in the Lobby.
--
-- Same DataStore-availability caveat as SaveSystem.luau -- requires Studio Access to API Services
-- ON and this place to have been PUBLISHED at least once; neither can be verified from here, so
-- (same as SaveSystem) this falls back to "disabled this session, with a warning" rather than
-- erroring, and has not been exercised against a real published place yet.
local HallOfFameSystem = {}

local TOP_N = 15 -- matches HallOfFameUI.luau's own MAX_ROWS -- keep the two in sync
-- How often the cached top list is re-fetched from the DataStore and pushed to every client. Not on
-- every delivery/round -- this is a leaderboard of LIFETIME totals, it doesn't need to feel
-- perfectly live, and OrderedDataStore reads/writes are rate-limited per DataStore, not something
-- to spend on a hot path.
local REFRESH_INTERVAL_SECONDS = 180
-- How often each currently-connected player's own best score gets (re-)submitted, independent of
-- the read/refresh cadence above.
local SUBMIT_INTERVAL_SECONDS = 90

local hallOfFameOk, hallOfFameStore = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, "LeafBlowerHallOfFame_v1")
if not hallOfFameOk then
	warn("[HallOfFame] DataStore unavailable this session (unpublished place / API access off) -- leaderboard disabled: " .. tostring(hallOfFameStore))
	hallOfFameStore = nil
end

-- { { Name = string, Value = number }, ... }, refreshed by refreshCache below. Every newly-joining
-- player gets this immediately (see PlayerAdded below) rather than waiting for the next periodic
-- refresh, so the board is never empty for a player's first few minutes on a fresh server.
local cachedTopEntries = {}
local hallOfFameUpdatedRemote

local function keyFor(player)
	return "Player_" .. player.UserId
end

-- Only ever writes a HIGHER score than whatever's already stored -- an OrderedDataStore key has no
-- "add" semantics, and lifetime LeavesCleaned only ever goes up anyway (see
-- LeavesCleanedStat.Add), so there's never a legitimate reason for this to decrease. UpdateAsync
-- (not SetAsync) so a real network write only happens when it would actually change the stored
-- value, not every single time this gets called.
local function submitScore(player)
	if not hallOfFameStore then
		return
	end
	local amount = LeavesCleanedStat.Get(player)
	if amount <= 0 then
		return
	end
	local ok, err = pcall(function()
		hallOfFameStore:UpdateAsync(keyFor(player), function(oldValue)
			if oldValue and oldValue >= amount then
				return nil -- no-op: skips the write entirely
			end
			return amount
		end)
	end)
	if not ok then
		warn(string.format("[HallOfFame] failed to submit %s's score: %s", player.Name, tostring(err)))
	end
end

-- Resolves a Hall of Fame key ("Player_<userId>") back to a display name -- works for a player
-- who ISN'T currently online too (GetNameFromUserIdAsync doesn't require them connected), so a
-- top-list entry from someone offline right now still shows their real name, not a raw id.
local function resolveDisplayName(key)
	local userId = tonumber(string.match(key, "^Player_(%d+)$"))
	if not userId then
		return key
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	return (ok and name) or ("Player_" .. userId)
end

local function refreshCache()
	if not hallOfFameStore then
		return
	end
	local ok, pages = pcall(function()
		return hallOfFameStore:GetSortedAsync(false, TOP_N)
	end)
	if not ok then
		warn("[HallOfFame] failed to fetch the leaderboard: " .. tostring(pages))
		return
	end

	local entries = {}
	for _, entry in ipairs(pages:GetCurrentPage()) do
		table.insert(entries, { Name = resolveDisplayName(entry.key), Value = entry.value })
	end
	cachedTopEntries = entries

	if hallOfFameUpdatedRemote then
		hallOfFameUpdatedRemote:FireAllClients(cachedTopEntries)
	end
end

function HallOfFameSystem.Start()
	local remotes = ReplicatedStorage.Shared:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage.Shared
	end
	hallOfFameUpdatedRemote = remotes:FindFirstChild("HallOfFameUpdated") or Instance.new("RemoteEvent")
	hallOfFameUpdatedRemote.Name = "HallOfFameUpdated"
	hallOfFameUpdatedRemote.Parent = remotes

	Players.PlayerAdded:Connect(function(player)
		-- Immediately from cache -- no DataStore round-trip on join, so this never blocks/delays
		-- anything else. A brand-new server (cache still empty) just shows nothing until the first
		-- refreshCache below completes.
		hallOfFameUpdatedRemote:FireClient(player, cachedTopEntries)
	end)

	task.spawn(function()
		while true do
			refreshCache()
			task.wait(REFRESH_INTERVAL_SECONDS)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(SUBMIT_INTERVAL_SECONDS)
			for _, player in ipairs(Players:GetPlayers()) do
				submitScore(player)
			end
		end
	end)

	-- Same two save points SaveSystem.luau uses for Coins/etc. -- a player's best score is never
	-- lost to a disconnect or a server shutdown between periodic submissions.
	Players.PlayerRemoving:Connect(submitScore)
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			submitScore(player)
		end
	end)
end

return HallOfFameSystem
