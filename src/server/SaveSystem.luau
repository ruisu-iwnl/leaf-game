local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local MoneySystem = require(script.Parent.MoneySystem)

-- Persists Coins across sessions. Scoped to just Coins for now, matching where the build order
-- actually is (Step 6, Money) -- Step 8 (Saving) will expand this to LeavesCleaned, upgrades,
-- areas, cosmetics, and season progress once those systems exist to have something to save.
--
-- Two things have to be true for this to actually work, neither of which a script can flip on
-- its own:
--   1. Game Settings > Security > "Enable Studio Access to API Services" must be ON, or every
--      DataStore call below fails (pcall-wrapped, so it just warns instead of erroring).
--   2. The place needs to have been published to Roblox at least once (Publish, even privately)
--      -- DataStores belong to the published universe, so an entirely local/unpublished place has
--      no real store to save into. (This is the same root cause as game.CreatorId reading 0
--      earlier for AdminCommands -- this place has never been published.)
local SaveSystem = {}

local playerData = DataStoreService:GetDataStore("LeafBlowerPlayerData_v1")

local function keyFor(player)
	return "Player_" .. player.UserId
end

local function loadCoins(player)
	local ok, result = pcall(function()
		return playerData:GetAsync(keyFor(player))
	end)

	if not ok then
		warn(string.format(
			"[Save] failed to load data for %s: %s (check Studio Access to API Services, and that this place has been published)",
			player.Name, tostring(result)
		))
		return
	end

	if not result or typeof(result.Coins) ~= "number" then
		return -- brand new player, nothing saved yet
	end

	-- GetAsync above already yielded on a real network call, so MoneySystem's own PlayerAdded
	-- handler (connected before this one) has almost certainly already built leaderstats by now --
	-- WaitForChild is just a defensive backstop against that ordering assumption.
	if player:WaitForChild("leaderstats", 5) then
		MoneySystem.SetCoins(player, result.Coins)
	end
end

local function saveCoins(player)
	local coins = MoneySystem.GetCoins(player)
	local ok, err = pcall(function()
		playerData:SetAsync(keyFor(player), { Coins = coins })
	end)
	if not ok then
		warn(string.format("[Save] failed to save data for %s: %s", player.Name, tostring(err)))
	end
end

local function onPlayerAdded(player)
	loadCoins(player)
end

function SaveSystem.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(saveCoins)

	-- Covers real server shutdowns (Roblox recycling live servers) -- without this, a player who's
	-- still connected when the server closes never gets their last few seconds of progress saved.
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			saveCoins(player)
		end
	end)
end

return SaveSystem
