local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BadgeSystem = require(script.Parent.BadgeSystem)
local BlowerTool = require(script.Parent.BlowerTool)
local CosmeticConfig = require(ReplicatedStorage.Shared.CosmeticConfig)
local MoneySystem = require(script.Parent.MoneySystem)
local PerkConfig = require(ReplicatedStorage.Shared.PerkConfig)
local PlayerUpgrades = require(script.Parent.PlayerUpgrades)
local RakeTool = require(script.Parent.RakeTool)
local UpgradeConfig = require(ReplicatedStorage.Shared.UpgradeConfig)

-- Server-authoritative purchase validation for the store (StorePanelUI.luau) -- the one place an
-- upgrade/perk/cosmetic purchase actually happens, so a client can never grant itself something for
-- free or double-spend by firing the request twice. Generic across all three catalogs rather than
-- one handler per item type. Also owns EquipCosmetic (see below) -- picking a skin isn't a purchase,
-- but it's the same "server has to check ownership before anything happens" shape, so it lives here
-- rather than starting a whole separate module for one remote.
local PurchaseSystem = {}

local CATALOGS = {
	Upgrade = UpgradeConfig,
	Perk = PerkConfig,
	Cosmetic = CosmeticConfig,
}

-- toolName -> whatever needs telling "repaint anything of mine already in the world" right after an
-- equip changes -- LeafSack deliberately has no entry: sacks bake their color in at spawn time (see
-- SackSystem.newSackTool), there's no persistent worn instance to repaint the way the Blower/Rake
-- tools have.
local REFRESH_COSMETIC = {
	LeafBlower = BlowerTool.RefreshCosmetic,
	LeafRake = RakeTool.RefreshCosmetic,
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

	-- VIP-exclusive cosmetics (CosmeticConfig.luau, `RequiresPerk`) aren't individually purchasable
	-- at all -- they come free with the perk itself (see PlayerUpgrades.GrantPerk). Defense-in-depth
	-- against a client calling this remote directly; the real client UI never offers a buy button for
	-- one of these (see StorePanelUI.luau's "locked" row state).
	if item.RequiresPerk then
		local perk = PerkConfig[item.RequiresPerk]
		return { success = false, reason = "That comes free with " .. (perk and perk.Name or "a perk") .. "." }
	end

	-- Robux-currency perks (see PerkConfig.luau) are bought through MarketplaceService's own
	-- PromptGamePassPurchase, not this Coins-spending remote at all -- GamePassPerks.luau grants
	-- them once Roblox confirms the purchase. Rejecting here is defense-in-depth against a client
	-- calling this remote directly for one of those ids; the real client UI never does.
	if item.Currency == "Robux" then
		return { success = false, reason = "Buy this one with the Robux prompt, not Coins." }
	end

	local alreadyOwned = (itemType == "Upgrade" and PlayerUpgrades.HasUpgrade(player, itemId))
		or (itemType == "Perk" and PlayerUpgrades.HasPerk(player, itemId))
		or (itemType == "Cosmetic" and PlayerUpgrades.HasCosmetic(player, itemId))
	if alreadyOwned then
		return { success = false, reason = "You already own that." }
	end

	if not MoneySystem.SpendCoins(player, item.Price) then
		return { success = false, reason = "You don't have enough Coins for that." }
	end

	if itemType == "Upgrade" then
		PlayerUpgrades.GrantUpgrade(player, itemId)
	elseif itemType == "Perk" then
		PlayerUpgrades.GrantPerk(player, itemId)
	else
		PlayerUpgrades.GrantCosmetic(player, itemId)
	end
	BadgeSystem.CheckOwnershipMilestones(player)

	return { success = true }
end

-- Returns { success = bool, reason = string? }, same shape as purchaseItem. "Default" is always a
-- valid choice for any tool (see PlayerUpgrades.HasCosmetic); anything else has to be a real
-- catalog entry, for the tool being asked about, that this player actually owns.
local function equipCosmetic(player, toolName, cosmeticId)
	if typeof(toolName) ~= "string" or typeof(cosmeticId) ~= "string" then
		return { success = false, reason = "Something went wrong -- try again." }
	end
	if not REFRESH_COSMETIC[toolName] and toolName ~= "LeafSack" then
		return { success = false, reason = "Something went wrong -- try again." }
	end

	if cosmeticId ~= "Default" then
		local item = CosmeticConfig[cosmeticId]
		if not item or item.Tool ~= toolName then
			return { success = false, reason = "That's not something Ruisu sells." }
		end
		if not PlayerUpgrades.HasCosmetic(player, cosmeticId) then
			return { success = false, reason = "You don't own that yet." }
		end
	end

	PlayerUpgrades.SetCosmetic(player, toolName, cosmeticId)

	local refresh = REFRESH_COSMETIC[toolName]
	if refresh then
		refresh(player)
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

	local equipCosmeticFunction = remotes:FindFirstChild("EquipCosmetic") or Instance.new("RemoteFunction")
	equipCosmeticFunction.Name = "EquipCosmetic"
	equipCosmeticFunction.Parent = remotes

	equipCosmeticFunction.OnServerInvoke = function(player, toolName, cosmeticId)
		local ok, result = pcall(equipCosmetic, player, toolName, cosmeticId)
		if not ok then
			warn(string.format("[PurchaseSystem] error handling an equip for %s: %s", player.Name, tostring(result)))
			return { success = false, reason = "Something went wrong -- try again." }
		end
		return result
	end
end

return PurchaseSystem
