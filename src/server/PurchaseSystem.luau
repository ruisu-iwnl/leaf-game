local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MoneySystem = require(script.Parent.MoneySystem)
local PerkConfig = require(ReplicatedStorage.Shared.PerkConfig)
local PlayerUpgrades = require(script.Parent.PlayerUpgrades)
local UpgradeConfig = require(ReplicatedStorage.Shared.UpgradeConfig)

-- Server-authoritative purchase validation for the store (StorePanelUI.luau) -- the one place an
-- upgrade/perk purchase actually happens, so a client can never grant itself something for free or
-- double-spend by firing the request twice. Generic across both catalogs (and easy to extend to
-- Cosmetics once those have real prices) rather than one handler per item type.
local PurchaseSystem = {}

local CATALOGS = {
	Upgrade = UpgradeConfig,
	Perk = PerkConfig,
}

-- Returns { success = bool, reason = string? } -- reason is only set on failure, meant to be
-- shown directly to the player (e.g. via Ruisu's dialogue), so keep these short and player-facing.
local function purchaseItem(player, itemType, itemId)
	local catalog = CATALOGS[itemType]
	if not catalog or typeof(itemId) ~= "string" then
		return { success = false, reason = "That's not something Ruisu sells." }
	end

	local item = catalog[itemId]
	if not item then
		return { success = false, reason = "That's not something Ruisu sells." }
	end

	local alreadyOwned = (itemType == "Upgrade" and PlayerUpgrades.HasUpgrade(player, itemId))
		or (itemType == "Perk" and PlayerUpgrades.HasPerk(player, itemId))
	if alreadyOwned then
		return { success = false, reason = "You already own that." }
	end

	if not MoneySystem.SpendCoins(player, item.Price) then
		return { success = false, reason = "You don't have enough Coins for that." }
	end

	if itemType == "Upgrade" then
		PlayerUpgrades.GrantUpgrade(player, itemId)
	else
		PlayerUpgrades.GrantPerk(player, itemId)
	end

	return { success = true }
end

function PurchaseSystem.Start()
	local remotes = ReplicatedStorage.Shared:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage.Shared
	end

	local purchaseItemFunction = remotes:FindFirstChild("PurchaseItem") or Instance.new("RemoteFunction")
	purchaseItemFunction.Name = "PurchaseItem"
	purchaseItemFunction.Parent = remotes

	purchaseItemFunction.OnServerInvoke = function(player, itemType, itemId)
		local ok, result = pcall(purchaseItem, player, itemType, itemId)
		if not ok then
			warn(string.format("[PurchaseSystem] error handling a purchase for %s: %s", player.Name, tostring(result)))
			return { success = false, reason = "Something went wrong -- try again." }
		end
		return result
	end
end

return PurchaseSystem
