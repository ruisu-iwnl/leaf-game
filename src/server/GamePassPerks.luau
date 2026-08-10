local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BadgeSystem = require(script.Parent.BadgeSystem)
local PerkConfig = require(ReplicatedStorage.Shared.PerkConfig)
local PlayerUpgrades = require(script.Parent.PlayerUpgrades)

-- Grants any perk in PerkConfig whose Currency is "Robux" (see that file) based on real Game Pass
-- ownership, instead of PurchaseSystem's Coins flow. Reuses PlayerUpgrades.GrantPerk/HasPerk
-- unchanged -- once granted, a Robux perk is indistinguishable from a Coins one to every other
-- system (GetCoinsMultiplier, InventoryUI's Active Perks row, SaveSystem's persistence) -- this
-- module's only job is deciding WHEN to call GrantPerk for these specific ids.
--
-- Ownership is re-checked fresh from Roblox on every join (UserOwnsGamePassAsync) rather than
-- trusted from a prior save -- Roblox is the actual source of truth for a Game Pass, so there's
-- nothing for this game's own DataStore to get out of sync with. A successful purchase mid-session
-- is caught immediately via PromptGamePassPurchaseFinished, without needing a rejoin.
local GamePassPerks = {}

-- {gamePassId -> perkId}, built once from every Robux-currency perk with a real (non-zero) id --
-- 0 means "not set up yet" (see PerkConfig.luau's comment), skipped entirely so this stays silent
-- and harmless until you've actually created the Game Pass and filled in its real id.
local function robuxPerksByGamePassId()
	local byId = {}
	for id, perk in pairs(PerkConfig) do
		if perk.Currency == "Robux" and typeof(perk.GamePassId) == "number" and perk.GamePassId ~= 0 then
			byId[perk.GamePassId] = id
		end
	end
	return byId
end

local function grantIfOwned(player, gamePassId, perkId)
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, gamePassId)
	if ok and owns then
		PlayerUpgrades.GrantPerk(player, perkId)
		BadgeSystem.CheckOwnershipMilestones(player)
	elseif not ok then
		warn(string.format("[GamePassPerks] couldn't check %s's ownership of GamePassId %d: %s", player.Name, gamePassId, tostring(owns)))
	end
end

local function onPlayerAdded(player)
	for gamePassId, perkId in pairs(robuxPerksByGamePassId()) do
		task.spawn(grantIfOwned, player, gamePassId, perkId)
	end
end

-- Deliberately re-checks real ownership here instead of trusting `wasPurchased` on its own --
-- Roblox reports wasPurchased = false both when the player actually cancelled AND when they
-- already owned the pass (the "You already own this item" dialog), and there's no way to tell
-- those two apart from this event alone. Re-verifying via UserOwnsGamePassAsync handles both:
-- a genuine cancel finds no ownership and grants nothing, while an "already owned" prompt finds
-- real ownership and finally syncs Perk_<id> to match -- covering things like an admin clearing it
-- with :removeperk (which only clears this game's own attribute, never real Game Pass ownership)
-- without needing the player to rejoin for onPlayerAdded's own check to catch it.
local function onPromptGamePassPurchaseFinished(player, gamePassId, wasPurchased)
	local perkId = robuxPerksByGamePassId()[gamePassId]
	if perkId then
		task.spawn(grantIfOwned, player, gamePassId, perkId)
	end
end

function GamePassPerks.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPromptGamePassPurchaseFinished)
end

return GamePassPerks
