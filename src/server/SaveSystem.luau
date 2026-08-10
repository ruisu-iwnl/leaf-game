local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlowerTool = require(script.Parent.BlowerTool)
local LeavesCleanedStat = require(script.Parent.LeavesCleanedStat)
local MoneySystem = require(script.Parent.MoneySystem)
local PlayerUpgrades = require(script.Parent.PlayerUpgrades)
local RakeTool = require(script.Parent.RakeTool)
local SackConfig = require(ReplicatedStorage.Shared.SackConfig)
local SackSystem = require(script.Parent.SackSystem)

-- Persists Coins, the per-player lifetime LeavesCleaned count, SackStorage (leaves currently held
-- in the sack UI, not yet turned into a physical sack), every physical sack currently in the
-- player's Backpack/equipped (as a leaf-count list -- see SackSystem.GetPlayerSackLeafCounts/
-- RestoreSacks), and owned upgrades/perks/cosmetics (see PlayerUpgrades.luau) across sessions.
-- Areas and season progress will get added here once those systems exist to have something to
-- save -- nothing to persist for them yet.
--
-- ActiveSackCount itself is still NOT stored as a raw number -- it's derived by RestoreSacks
-- incrementing it once per sack it actually rebuilds, so it can never drift from the real physical
-- sacks a player has (which is exactly what would soft-lock them if the count were persisted on
-- its own, unattached to real sacks).
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

local function loadPlayerData(player)
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

	if not result then
		return -- brand new player, nothing saved yet
	end

	-- GetAsync above already yielded on a real network call, so MoneySystem's/LeavesCleanedStat's
	-- own PlayerAdded handlers (connected before this one) have almost certainly already built
	-- leaderstats by now -- WaitForChild is just a defensive backstop against that ordering
	-- assumption.
	if player:WaitForChild("leaderstats", 5) then
		if typeof(result.Coins) == "number" then
			MoneySystem.SetCoins(player, result.Coins)
		end
		if typeof(result.LeavesCleaned) == "number" then
			LeavesCleanedStat.Set(player, result.LeavesCleaned)
		end
	end

	-- A plain player Attribute (same as SackSystem/SackUI already read/write it directly, no
	-- dedicated accessor module) -- unlike leaderstats, doesn't need anything else to exist first.
	if typeof(result.SackStorage) == "number" then
		player:SetAttribute("SackStorage", math.clamp(math.floor(result.SackStorage), 0, SackConfig.MaxCapacity))
	end

	if typeof(result.SackLeafCounts) == "table" then
		SackSystem.RestoreSacks(player, result.SackLeafCounts)
	end

	if typeof(result.UpgradeIds) == "table" then
		for _, id in ipairs(result.UpgradeIds) do
			PlayerUpgrades.GrantUpgrade(player, id)
		end
	end
	if typeof(result.PerkIds) == "table" then
		for _, id in ipairs(result.PerkIds) do
			PlayerUpgrades.GrantPerk(player, id)
		end
	end
	if typeof(result.CosmeticIds) == "table" then
		for _, id in ipairs(result.CosmeticIds) do
			PlayerUpgrades.GrantCosmetic(player, id)
		end
	end
	if typeof(result.Cosmetics) == "table" then
		for toolName, cosmeticId in pairs(result.Cosmetics) do
			if typeof(toolName) == "string" and typeof(cosmeticId) == "string" then
				PlayerUpgrades.SetCosmetic(player, toolName, cosmeticId)
			end
		end
	end

	-- Re-applies the now-restored cosmetics to whatever's already in the world for this player.
	-- Without this, a rejoining player's ALWAYS-WORN Blower backpack prop could permanently end up
	-- on the wrong skin: BlowerTool's attachBackpack resolves + bakes in colors once, the very first
	-- time the backpack is built after a character spawns, and never revisits it again -- if that
	-- happens to run (character spawns) before this GetAsync call above finishes yielding, it reads
	-- the not-yet-restored default cosmetic and is stuck there until the player re-equips a skin in
	-- the store. RefreshCosmetic is the exact same fix PurchaseSystem's EquipCosmetic already uses
	-- for a live skin change; calling it again here just closes this one race at load time. A no-op
	-- if the character hasn't spawned yet -- in that case attachBackpack hasn't run either, and will
	-- correctly pick up the now-restored cosmetic on its own once it does.
	BlowerTool.RefreshCosmetic(player)
	RakeTool.RefreshCosmetic(player)
end

local function savePlayerData(player)
	local data = {
		Coins = MoneySystem.GetCoins(player),
		LeavesCleaned = LeavesCleanedStat.Get(player),
		SackStorage = player:GetAttribute("SackStorage") or 0,
		SackLeafCounts = SackSystem.GetPlayerSackLeafCounts(player),
		UpgradeIds = PlayerUpgrades.GetOwnedUpgradeIds(player),
		PerkIds = PlayerUpgrades.GetOwnedPerkIds(player),
		CosmeticIds = PlayerUpgrades.GetOwnedCosmeticIds(player),
		Cosmetics = PlayerUpgrades.GetCosmetics(player),
	}
	local ok, err = pcall(function()
		playerData:SetAsync(keyFor(player), data)
	end)
	if not ok then
		warn(string.format("[Save] failed to save data for %s: %s", player.Name, tostring(err)))
	end
end

local function onPlayerAdded(player)
	loadPlayerData(player)
end

function SaveSystem.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(savePlayerData)

	-- Covers real server shutdowns (Roblox recycling live servers) -- without this, a player who's
	-- still connected when the server closes never gets their last few seconds of progress saved.
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			savePlayerData(player)
		end
	end)
end

return SaveSystem
