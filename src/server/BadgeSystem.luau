local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BadgeConfig = require(ReplicatedStorage.Shared.BadgeConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.UpgradeConfig)
local LeavesCleanedStat = require(script.Parent.LeavesCleanedStat)
local MoneySystem = require(script.Parent.MoneySystem)
local PlayerUpgrades = require(script.Parent.PlayerUpgrades)

-- Awards real Roblox Badges (BadgeService) based on this game's own stats -- deliberately NOT
-- required by PlayerUpgrades/MoneySystem/LeavesCleanedStat themselves (that would risk a circular
-- require, since this module reads all three) -- instead, every place that can move one of those
-- stats (leaf delivery, a purchase, a granted Game Pass perk, a restored save, an admin command)
-- calls one of the Check* functions below right after. Each check is cheap and safe to call
-- redundantly (award() below no-ops on anything already owned), so there's no harm calling it more
-- often than strictly necessary.
local BadgeSystem = {}

local badgeAwardedRemote

-- Guards against the SAME badge getting awarded (and its popup fired) more than once for a player
-- who crosses a threshold via several near-simultaneous calls -- e.g. a delivery that both finishes
-- loading a save (SaveSystem's CheckAll) and pushes leavesCleaned over a threshold in the same
-- instant, or several leaf deliveries firing close together. UserHasBadgeAsync/AwardBadge below are
-- both real network calls that YIELD, so without this, two overlapping award() calls for the same
-- badge can both pass the "do they already have it?" check before either has actually finished
-- awarding it -- classic check-then-act race. Claiming a plain table entry SYNCHRONOUSLY, before
-- the first yield, closes that window: Luau never runs two calls literally in parallel, so whichever
-- award() call reaches the claim first is guaranteed to be the only one that proceeds. Weak-keyed
-- (by Player) as a defensive backstop against ever leaking entries for a player who leaves without
-- Start()'s explicit PlayerRemoving cleanup running for some reason.
local awardClaims = setmetatable({}, { __mode = "k" })

-- Skips silently (no error, no warning spam) for any badge whose BadgeId is still the 0 placeholder
-- -- see BadgeConfig.luau -- so this whole system is a no-op until docs/BADGES_SETUP.md has been
-- done for a given badge, same "0 means not set up yet" convention as PerkConfig's GamePassId.
local function award(player, badgeKey)
	local badge = BadgeConfig[badgeKey]
	if not badge or not badge.BadgeId or badge.BadgeId == 0 then
		return
	end

	local claims = awardClaims[player]
	if not claims then
		claims = {}
		awardClaims[player] = claims
	end
	if claims[badgeKey] then
		return -- already owned, or another award() call for this exact badge is already in flight
	end
	claims[badgeKey] = true -- claimed BEFORE any yielding call below, so a concurrent caller sees this immediately

	local checkOk, hasBadge = pcall(BadgeService.UserHasBadgeAsync, BadgeService, player.UserId, badge.BadgeId)
	if not checkOk then
		warn(string.format("[BadgeSystem] couldn't check %s's ownership of badge %s: %s", player.Name, badgeKey, tostring(hasBadge)))
		claims[badgeKey] = nil -- unknown real state -- release the claim so a later call can retry
		return
	end
	if hasBadge then
		return -- genuinely already owned (e.g. from a previous session) -- stays claimed, no client fire
	end

	local awardOk, awardErr = pcall(BadgeService.AwardBadge, BadgeService, player.UserId, badge.BadgeId)
	if not awardOk then
		warn(string.format("[BadgeSystem] couldn't award badge %s to %s: %s", badgeKey, player.Name, tostring(awardErr)))
		claims[badgeKey] = nil -- award didn't actually happen -- release the claim so a later call can retry
		return
	end

	if badgeAwardedRemote then
		badgeAwardedRemote:FireClient(player, badgeKey)
	end
end

-- LeavesCleaned/Coins thresholds -- call after anything that can move either stat (leaf delivery,
-- SaveSystem restoring a save).
function BadgeSystem.CheckDeliveryMilestones(player)
	local leavesCleaned = LeavesCleanedStat.Get(player)
	if leavesCleaned >= 1 then
		award(player, "FirstSweep")
	end
	if leavesCleaned >= 100 then
		award(player, "TidyYard")
	end
	if leavesCleaned >= 1000 then
		award(player, "LeafWrangler")
	end
	if leavesCleaned >= 10000 then
		award(player, "AutumnLegend")
	end
	if leavesCleaned >= 40000 then
		award(player, "LeafMaster")
	end
	if leavesCleaned >= 60000 then
		award(player, "LeafTycoon")
	end
	if leavesCleaned >= 80000 then
		award(player, "LeafBaron")
	end
	if leavesCleaned >= 100000 then
		award(player, "LeafMogul")
	end
	if leavesCleaned >= 500000 then
		award(player, "LeafDynasty")
	end
	if leavesCleaned >= 1000000 then
		award(player, "LeafImmortal")
	end

	local coins = MoneySystem.GetCoins(player)
	if coins >= 1000 then
		award(player, "PocketChange")
	end
	if coins >= 25000 then
		award(player, "CoinHoarder")
	end
	if coins >= 40000 then
		award(player, "CoinMagnate")
	end
	if coins >= 60000 then
		award(player, "CoinBaron")
	end
	if coins >= 80000 then
		award(player, "CoinTycoon")
	end
	if coins >= 100000 then
		award(player, "CoinMogul")
	end
	if coins >= 500000 then
		award(player, "CoinDynasty")
	end
	if coins >= 1000000 then
		award(player, "CoinImmortal")
	end
end

-- Upgrade/Perk/Cosmetic ownership -- call after anything that can grant one of those (a Coins
-- purchase, a Game Pass perk grant, SaveSystem restoring a save, an admin command).
function BadgeSystem.CheckOwnershipMilestones(player)
	local ownedUpgradeCount = #PlayerUpgrades.GetOwnedUpgradeIds(player)
	if ownedUpgradeCount >= 1 then
		award(player, "Upgraded")
	end

	local totalUpgradeCount = 0
	for _ in pairs(UpgradeConfig) do
		totalUpgradeCount += 1
	end
	if totalUpgradeCount > 0 and ownedUpgradeCount >= totalUpgradeCount then
		award(player, "FullyLoaded")
	end

	if #PlayerUpgrades.GetOwnedCosmeticIds(player) >= 1 then
		award(player, "Fashionista")
	end

	if PlayerUpgrades.HasPerk(player, "DoubleGrab") then
		award(player, "TwoXGrabber")
	end
	if PlayerUpgrades.HasPerk(player, "LuckyLeaf") then
		award(player, "LuckyLeafOwner")
	end
	if PlayerUpgrades.HasPerk(player, "LeafPatron") then
		award(player, "LeafPatronOwner")
	end
end

-- Both categories at once -- used by SaveSystem right after a full restore (so a player who already
-- had progress before this system existed gets everything they've actually earned retroactively)
-- and by admin commands (so testing one grant doesn't require remembering which Check* it maps to).
function BadgeSystem.CheckAll(player)
	BadgeSystem.CheckDeliveryMilestones(player)
	BadgeSystem.CheckOwnershipMilestones(player)
end

-- Exposed for AdminCommands' :addbadge -- awards a specific badge directly regardless of whether
-- the player actually meets its criteria. Still goes through the real BadgeService (and is still a
-- genuine, permanent award, same as earning it normally) -- for a repeatable way to preview the
-- popup without touching real badge state at all, see FireNotification below.
function BadgeSystem.Award(player, badgeKey)
	award(player, badgeKey)
end

-- Exposed for AdminCommands' :testbadge -- fires just the client-side popup with no BadgeService
-- call at all, so the notification's look/animation can be previewed on demand as many times as
-- needed, independent of real award state (which, once granted, this project has no way to revoke
-- -- see docs/BADGES_SETUP.md).
function BadgeSystem.FireNotification(player, badgeKey)
	if BadgeConfig[badgeKey] and badgeAwardedRemote then
		badgeAwardedRemote:FireClient(player, badgeKey)
	end
end

function BadgeSystem.Start()
	local remotes = ReplicatedStorage.Shared:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage.Shared
	end

	badgeAwardedRemote = remotes:FindFirstChild("BadgeAwarded") or Instance.new("RemoteEvent")
	badgeAwardedRemote.Name = "BadgeAwarded"
	badgeAwardedRemote.Parent = remotes

	-- Explicit + immediate on top of awardClaims' own weak keys -- no reason to keep a left player's
	-- claims around for the rest of the server's lifetime.
	Players.PlayerRemoving:Connect(function(player)
		awardClaims[player] = nil
	end)
end

return BadgeSystem
