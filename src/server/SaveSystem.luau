local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BadgeSystem = require(script.Parent.BadgeSystem)
local BlowerTool = require(script.Parent.BlowerTool)
local DailyQuestSystem = require(script.Parent.DailyQuestSystem)
local LeavesCleanedStat = require(script.Parent.LeavesCleanedStat)
local MoneySystem = require(script.Parent.MoneySystem)
local PlayerQuests = require(script.Parent.PlayerQuests)
local PlayerUpgrades = require(script.Parent.PlayerUpgrades)
local QuestObjectives = require(script.Parent.QuestObjectives)
local QuestSystem = require(script.Parent.QuestSystem)
local RakeTool = require(script.Parent.RakeTool)
local SackConfig = require(ReplicatedStorage.Shared.SackConfig)
local SackSystem = require(script.Parent.SackSystem)

-- Persists Coins, the per-player lifetime LeavesCleaned count, SackStorage (leaves currently held
-- in the sack UI, not yet turned into a physical sack), every physical sack currently in the
-- player's Backpack/equipped (as a leaf-count list -- see SackSystem.GetPlayerSackLeafCounts/
-- RestoreSacks), owned upgrades/perks/cosmetics, the Leaf Patron perk's own two cosmetic
-- preferences (effects on/off, trail color -- see PlayerUpgrades.luau), completed AND in-progress
-- (started but not yet completed) quest ids (see PlayerQuests.luau), in-progress chain-quest
-- objective counts (see QuestObjectives.luau, e.g.
-- Getting Started II's "3/5 Rake uses"), and today's daily-quest progress/completion (see
-- DailyQuestSystem.luau -- without this, rejoining mid-day would let a player re-earn an
-- already-completed daily's reward) across sessions. Areas and season progress will get added here once those systems exist to have
-- something to save -- nothing to persist for them yet.
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

-- GetDataStore itself (not just GetAsync/SetAsync below) can throw in a local/unpublished test
-- session -- pcall'd so that case disables saving for this session (with a warning) instead of
-- throwing at module load time, which would crash this require() in init.server.luau and take
-- every other system down with it before any of them ever start.
local playerDataOk, playerData = pcall(DataStoreService.GetDataStore, DataStoreService, "LeafBlowerPlayerData_v1")
if not playerDataOk then
	warn("[Save] DataStore unavailable this session (unpublished place / API access off) -- saving disabled: " .. tostring(playerData))
	playerData = nil
end

local function keyFor(player)
	return "Player_" .. player.UserId
end

local function loadPlayerData(player)
	-- Every early-return path below routes through QuestSystem.StartEligibleQuests instead of a
	-- bare `return` -- quest-starting must happen for EVERY player, not just ones with real save
	-- data restored, or the Tutorial would never auto-start at all for a brand-new player, or for
	-- anyone in an unpublished/no-DataStore-access Studio session (see this file's own top comment
	-- on why that's a real, common case here, not just a theoretical one). Return value is unused by
	-- every caller of loadPlayerData, so this is safe.
	if not playerData then
		return QuestSystem.StartEligibleQuests(player)
	end

	local ok, result = pcall(function()
		return playerData:GetAsync(keyFor(player))
	end)

	if not ok then
		warn(string.format(
			"[Save] failed to load data for %s: %s (check Studio Access to API Services, and that this place has been published)",
			player.Name, tostring(result)
		))
		return QuestSystem.StartEligibleQuests(player)
	end

	if not result then
		return QuestSystem.StartEligibleQuests(player) -- brand new player, nothing saved yet
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

	-- Leaf Patron's two cosmetic preferences (see PlayerUpgrades.luau) -- harmless to restore even
	-- for a player who doesn't currently own the perk, same as restoring a Cosmetics entry for a
	-- tool skin they might not own anymore; PlayerUpgrades/VIPEffects.luau only ever act on these
	-- once HasPerk("LeafPatron") is also true.
	if typeof(result.VIPEffectsEnabled) == "boolean" then
		PlayerUpgrades.SetVIPEffectsEnabled(player, result.VIPEffectsEnabled)
	end
	if typeof(result.VIPTrailColor) == "string" then
		PlayerUpgrades.SetVIPTrailColor(player, result.VIPTrailColor)
	end

	if typeof(result.CompletedQuestIds) == "table" then
		for _, id in ipairs(result.CompletedQuestIds) do
			PlayerQuests.CompleteQuest(player, id)
		end
	end
	-- Restored BEFORE StartEligibleQuests below so an in-progress quest's Started Attribute is
	-- already true the moment that function checks it -- PlayerQuests.StartQuest is a no-op for
	-- anything already started, so this is what stops the "Quest Started" toast from re-firing on
	-- every single rejoin for a long-running quest (e.g. LeafLegend/RoundVeteran) that just hasn't
	-- been completed yet. Called directly (not through QuestSystem's wrapper), same "call the plain
	-- function directly when replaying a save" pattern CompletedQuestIds above already uses.
	if typeof(result.StartedQuestIds) == "table" then
		for _, id in ipairs(result.StartedQuestIds) do
			PlayerQuests.StartQuest(player, id)
		end
	end
	-- Chain quests' (e.g. GettingStarted2/3) per-objective progress -- restored before
	-- StartEligibleQuests below so a returning player's partial progress (e.g. 3/5 Rake uses) is
	-- already in place the moment the quest itself starts/resumes. Never needs to restore a quest
	-- that's already fully complete -- CompletedQuestIds above already covers that case.
	QuestObjectives.RestoreSaveData(player, result.QuestObjectives)
	QuestSystem.StartEligibleQuests(player)

	-- Without this, a player could rejoin mid-day and re-earn an already-completed daily's Coins
	-- reward a second time, since DailyQuestSystem's progress/completion otherwise lives only in
	-- per-session Attributes. RestoreSaveData discards anything that isn't still relevant to TODAY.
	DailyQuestSystem.RestoreSaveData(player, result.DailyQuests)

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

	-- Retroactively awards anything this player already qualifies for -- covers both a returning
	-- player whose save predates a given badge existing, and the ordinary "restored progress already
	-- clears a threshold" case.
	BadgeSystem.CheckAll(player)
end

local function savePlayerData(player)
	if not playerData then
		return
	end

	local data = {
		Coins = MoneySystem.GetCoins(player),
		LeavesCleaned = LeavesCleanedStat.Get(player),
		SackStorage = player:GetAttribute("SackStorage") or 0,
		SackLeafCounts = SackSystem.GetPlayerSackLeafCounts(player),
		UpgradeIds = PlayerUpgrades.GetOwnedUpgradeIds(player),
		PerkIds = PlayerUpgrades.GetOwnedPerkIds(player),
		CosmeticIds = PlayerUpgrades.GetOwnedCosmeticIds(player),
		Cosmetics = PlayerUpgrades.GetCosmetics(player),
		VIPEffectsEnabled = PlayerUpgrades.IsVIPEffectsEnabled(player),
		VIPTrailColor = PlayerUpgrades.GetVIPTrailColor(player),
		CompletedQuestIds = PlayerQuests.GetCompletedQuestIds(player),
		StartedQuestIds = PlayerQuests.GetStartedQuestIds(player),
		QuestObjectives = QuestObjectives.GetSaveData(player),
		DailyQuests = DailyQuestSystem.GetSaveData(player),
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
	-- task.spawn, not a direct call: loadPlayerData does a real blocking DataStore GetAsync (often
	-- several real seconds in Studio). init.server.luau calls every system's Start() sequentially on
	-- one thread, so a direct call here would stall every system listed after this one (DayNightCycle,
	-- BlowerTool, GamePassPerks, PurchaseSystem, RakeTool, StoreSystem, AdminCommands) until this
	-- player's data finished loading -- including AdminCommands, which is what creates the
	-- AdminCommand remote. This only affects players already connected when this runs (e.g. Studio
	-- Play Solo's own test player); Players.PlayerAdded above already fires async for anyone joining
	-- after, same as any other event connection.
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
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
