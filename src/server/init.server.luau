local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdminCommands = require(script.AdminCommands)
local BadgeSystem = require(script.BadgeSystem)
local BigLeafPileSystem = require(script.BigLeafPileSystem)
local BlowerTool = require(script.BlowerTool)
local DailyQuestSystem = require(script.DailyQuestSystem)
local DayNightCycle = require(script.DayNightCycle)
local GamePassPerks = require(script.GamePassPerks)
local HallOfFameSystem = require(script.HallOfFameSystem)
local LeafSpawner = require(script.LeafSpawner)
local LeavesCleanedStat = require(script.LeavesCleanedStat)
local MainMenuSystem = require(script.MainMenuSystem)
local MoneyConfig = require(ReplicatedStorage.Shared.MoneyConfig)
local MoneySystem = require(script.MoneySystem)
local PlayerSetup = require(script.PlayerSetup)
local PlayerUpgrades = require(script.PlayerUpgrades)
local PurchaseSystem = require(script.PurchaseSystem)
local QuestObjectives = require(script.QuestObjectives)
local QuestSystem = require(script.QuestSystem)
local RakeTool = require(script.RakeTool)
local RoundSystem = require(script.RoundSystem)
local SackSystem = require(script.SackSystem)
local SaveSystem = require(script.SaveSystem)
local StoreSystem = require(script.StoreSystem)
local VIPPreferences = require(script.VIPPreferences)
local WindSystem = require(script.WindSystem)

-- MainMenuSystem first of all -- it sets OnMainMenu on PlayerAdded, which every other
-- player-facing system (RoundSystem especially) needs to already see as true the instant a player
-- connects, since CharacterAutoLoads is off and nobody has a character until it fires LoadCharacter().
MainMenuSystem.Start()
-- WindSystem first so the WindDirection attribute is already set before the first leaves spawn.
WindSystem.Start()
LeafSpawner.Start()
BigLeafPileSystem.Start()
SackSystem.Start()
PlayerSetup.Start()
MoneySystem.Start()
LeavesCleanedStat.Start()
HallOfFameSystem.Start()
PlayerUpgrades.Start()
BadgeSystem.Start()
-- QuestSystem must be started before SaveSystem: SaveSystem.Start() spawns loadPlayerData, which can
-- run fully synchronously (no yield at all) when the DataStore is unavailable -- e.g. an unpublished
-- Studio session, a common case here, not just a theoretical one -- and loadPlayerData calls
-- QuestSystem.StartEligibleQuests. If QuestSystem.Start() hadn't already created its remotes by
-- then, a quest's "Quest Started" toast would silently never fire in exactly that case.
QuestSystem.Start()
DailyQuestSystem.Start()
SaveSystem.Start()
DayNightCycle.Start()
BlowerTool.Start()
GamePassPerks.Start()
PurchaseSystem.Start()
RakeTool.Start()
StoreSystem.Start()
RoundSystem.Start()
VIPPreferences.Start()
AdminCommands.Start()

-- The one place LeafSpawner's leaf-delivery events get turned into Coins -- keeps LeafSpawner
-- itself decoupled from Coins/MoneySystem as a concept (see LeafSpawner.OnLeafDelivered). Coins
-- are scaled by the player's coin-affecting perks (e.g. DoubleGrab) here, in the one place every
-- payout already routes through -- perks never need touching MoneySystem or LeafSpawner directly.
-- RollLuckyBonus (the Lucky Leaf perk) is the one exception that ISN'T a flat multiplier -- it's a
-- per-leaf random roll, so it needs `count` threaded through separately rather than folding into
-- GetCoinsMultiplier's plain numeric product.
-- bonusCoins (new): a flat, pre-multiplier amount on top of the normal count-based payout -- today
-- only ever set by LeafSpawner.consumeLeaf for a Golden Leaf (see LeafConfig.luau). Scaled by the
-- SAME GetCoinsMultiplier every other leaf already gets here, so a Golden Leaf's bonus is just as
-- affected by DoubleGrab etc. as the rest of a delivery -- no separate multiplier logic needed.
LeafSpawner.OnLeafDelivered(function(player, count, bonusCoins)
	local perLeafCoins = MoneyConfig.CoinsPerLeaf * PlayerUpgrades.GetCoinsMultiplier(player)
	local goldenBonus = (bonusCoins or 0) * PlayerUpgrades.GetCoinsMultiplier(player)
	local coins = count * perLeafCoins + PlayerUpgrades.RollLuckyBonus(player, perLeafCoins, count) + goldenBonus
	MoneySystem.AddCoins(player, coins)
	RoundSystem.RecordCoinsEarned(player, coins)
	LeavesCleanedStat.Add(player, count)
	BadgeSystem.CheckDeliveryMilestones(player)
	DailyQuestSystem.RecordProgress(player, "DeliverLeaves", count)
	QuestObjectives.RecordProgress(player, "DeliverLeaves", count)
end)
