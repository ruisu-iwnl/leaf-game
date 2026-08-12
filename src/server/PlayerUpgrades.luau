local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlowerConfig = require(ReplicatedStorage.Shared.BlowerConfig)
local CosmeticConfig = require(ReplicatedStorage.Shared.CosmeticConfig)
local PerkConfig = require(ReplicatedStorage.Shared.PerkConfig)
local RakeConfig = require(ReplicatedStorage.Shared.RakeConfig)
local SackConfig = require(ReplicatedStorage.Shared.SackConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.UpgradeConfig)

-- The single place that owns "what does this player own, and what does that mean numerically."
-- Everything is backed by plain player Attributes -- same pattern as SackStorage/ActiveSackCount --
-- one boolean per catalog entry, plus one string per tool for the currently-equipped cosmetic.
-- BlowerTool/RakeTool/SackSystem/the coin-payout callback all read through this instead of touching
-- BlowerConfig/RakeConfig/SackConfig/MoneyConfig directly for anything upgrade/perk-affected, so
-- adding a new upgrade or perk later never means touching the tools themselves -- just UpgradeConfig
-- or PerkConfig (pure data) and, if it's genuinely a new kind of effect, one new branch here.
local PlayerUpgrades = {}

local BASE_CONFIGS = {
	LeafBlower = BlowerConfig,
	LeafRake = RakeConfig,
	LeafSack = SackConfig,
}

local DEFAULT_COSMETIC = "Default"

local function upgradeAttribute(id)
	return "Upgrade_" .. id
end

local function perkAttribute(id)
	return "Perk_" .. id
end

local function cosmeticAttribute(toolName)
	return "Cosmetic_" .. toolName
end

local function cosmeticOwnedAttribute(id)
	return "CosmeticOwned_" .. id
end

function PlayerUpgrades.HasUpgrade(player, id)
	return player:GetAttribute(upgradeAttribute(id)) == true
end

-- Sack capacity is the one effective-config value a client actually needs to know on its own --
-- SackUI.luau (the sack count/cap display and its click-to-spawn button) is a LocalScript and can't
-- reach this server-only module, so the resolved number gets replicated as a plain player Attribute
-- instead. Nothing else currently needs this treatment (RakeCooldownDuration/OverheatMax are only
-- ever read server-side, inside RakeTool/BlowerTool).
local function syncSackCapacityAttribute(player)
	player:SetAttribute("SackMaxActiveSacks", PlayerUpgrades.GetEffectiveConfig(player, "LeafSack").MaxActiveSacks)
end

function PlayerUpgrades.GrantUpgrade(player, id)
	local upgrade = UpgradeConfig[id]
	if not upgrade then
		return
	end
	player:SetAttribute(upgradeAttribute(id), true)
	if upgrade.Tool == "LeafSack" then
		syncSackCapacityAttribute(player)
	end
end

-- Setting an Attribute to nil removes it -- GetAttribute then reads nil, which HasUpgrade treats
-- the same as never having owned it.
function PlayerUpgrades.RemoveUpgrade(player, id)
	local upgrade = UpgradeConfig[id]
	player:SetAttribute(upgradeAttribute(id), nil)
	if upgrade and upgrade.Tool == "LeafSack" then
		syncSackCapacityAttribute(player)
	end
end

function PlayerUpgrades.HasPerk(player, id)
	return player:GetAttribute(perkAttribute(id)) == true
end

-- Cosmetics that come bundled free with a perk (e.g. Leaf Patron's 3 exclusive tool skins --
-- CosmeticConfig.luau, `RequiresPerk` field) instead of being individually purchasable. Scanned
-- fresh rather than hardcoded so a future perk can bundle its own exclusive cosmetics just by
-- setting RequiresPerk on a CosmeticConfig entry -- no changes needed here.
local function bundledCosmeticIdsForPerk(perkId)
	local ids = {}
	for id, cosmetic in pairs(CosmeticConfig) do
		if cosmetic.RequiresPerk == perkId then
			table.insert(ids, id)
		end
	end
	return ids
end

function PlayerUpgrades.GrantPerk(player, id)
	if not PerkConfig[id] then
		return
	end
	player:SetAttribute(perkAttribute(id), true)
	for _, cosmeticId in ipairs(bundledCosmeticIdsForPerk(id)) do
		PlayerUpgrades.GrantCosmetic(player, cosmeticId)
	end
end

-- Doesn't unequip/refresh a currently-worn bundled cosmetic if the perk is revoked while it's
-- equipped -- same known simplification as :removecosmetic's own admin-only edge case (see that
-- command), not worth the extra plumbing for something that only happens via an admin command or a
-- Game Pass ownership desync.
function PlayerUpgrades.RemovePerk(player, id)
	player:SetAttribute(perkAttribute(id), nil)
	for _, cosmeticId in ipairs(bundledCosmeticIdsForPerk(id)) do
		PlayerUpgrades.RemoveCosmetic(player, cosmeticId)
	end
end

-- Leaf Patron's two client-facing preferences (SettingsUI.luau) -- whether the perk's visible
-- effects (nameplate + trail) render at all, and what color the footstep trail uses ("Rainbow", the
-- default animated cycle, or a "#RRGGBB" hex string picked via VIPColorPickerUI.luau). Plain player
-- Attributes, same as everything else in this file -- they replicate automatically, which is exactly
-- what VIPEffects.luau needs since every OTHER client also has to see them, not just the owner's own.
function PlayerUpgrades.IsVIPEffectsEnabled(player)
	return player:GetAttribute("VIPEffectsEnabled") ~= false
end

function PlayerUpgrades.SetVIPEffectsEnabled(player, enabled)
	player:SetAttribute("VIPEffectsEnabled", enabled)
end

function PlayerUpgrades.GetVIPTrailColor(player)
	return player:GetAttribute("VIPTrailColor") or "Rainbow"
end

function PlayerUpgrades.SetVIPTrailColor(player, colorValue)
	player:SetAttribute("VIPTrailColor", colorValue)
end

function PlayerUpgrades.GetCosmetic(player, toolName)
	return player:GetAttribute(cosmeticAttribute(toolName)) or DEFAULT_COSMETIC
end

function PlayerUpgrades.SetCosmetic(player, toolName, cosmeticId)
	player:SetAttribute(cosmeticAttribute(toolName), cosmeticId)
end

-- "Default" is free and every player already has it -- it's deliberately not a CosmeticConfig
-- entry (see that file), so it's special-cased here rather than needing a zero-price catalog row.
function PlayerUpgrades.HasCosmetic(player, id)
	if id == DEFAULT_COSMETIC then
		return true
	end
	return player:GetAttribute(cosmeticOwnedAttribute(id)) == true
end

function PlayerUpgrades.GrantCosmetic(player, id)
	if id == DEFAULT_COSMETIC or not CosmeticConfig[id] then
		return
	end
	player:SetAttribute(cosmeticOwnedAttribute(id), true)
end

function PlayerUpgrades.RemoveCosmetic(player, id)
	if id == DEFAULT_COSMETIC then
		return
	end
	player:SetAttribute(cosmeticOwnedAttribute(id), nil)
end

-- Returns the tool's base config (BlowerConfig/RakeConfig/SackConfig) with any owned upgrade's
-- Overrides merged on top -- a shallow copy, the base config table itself is never mutated. With
-- nothing owned for this tool, returns the base config completely unchanged (same table, no copy)
-- so the common zero-upgrades case costs nothing extra.
function PlayerUpgrades.GetEffectiveConfig(player, toolName)
	local baseConfig = BASE_CONFIGS[toolName]
	if not baseConfig then
		return nil
	end

	local overridesToApply
	for _, upgrade in pairs(UpgradeConfig) do
		if upgrade.Tool == toolName and PlayerUpgrades.HasUpgrade(player, upgrade.Id) then
			overridesToApply = overridesToApply or {}
			for field, value in pairs(upgrade.Overrides) do
				overridesToApply[field] = value
			end
		end
	end

	if not overridesToApply then
		return baseConfig
	end

	local effective = table.clone(baseConfig)
	for field, value in pairs(overridesToApply) do
		effective[field] = value
	end
	return effective
end

-- 1 normally; combines multiplicatively if the player owns more than one coin-affecting perk (only
-- DoubleGrab exists right now, but written to generalize rather than hardcode "2 or nothing").
function PlayerUpgrades.GetCoinsMultiplier(player)
	local multiplier = 1
	for _, perk in pairs(PerkConfig) do
		if perk.CoinsMultiplier and PlayerUpgrades.HasPerk(player, perk.Id) then
			multiplier *= perk.CoinsMultiplier
		end
	end
	return multiplier
end

-- The Lucky Leaf perk's actual roll -- called once per delivery from init.server.luau's
-- LeafSpawner.OnLeafDelivered listener, right alongside GetCoinsMultiplier (the same one place the
-- whole coins-per-leaf formula lives). Rolls INDEPENDENTLY for each of the `count` leaves in this
-- delivery, not once for the whole batch -- a big sack drop-off (dozens/hundreds of leaves at once)
-- should get proportionally more shots at the bonus than a single blown-in leaf does, not the same
-- flat 5% either way. `perLeafCoins` is what ONE leaf is already worth (MoneyConfig.CoinsPerLeaf *
-- GetCoinsMultiplier) -- the returned bonus is just the EXTRA on top of that, so it stacks with 2X
-- Grab automatically (a lucky leaf's bonus is a multiple of the already-doubled rate, not the base
-- rate) without this function needing to know 2X Grab exists at all.
function PlayerUpgrades.RollLuckyBonus(player, perLeafCoins, count)
	if perLeafCoins <= 0 or count <= 0 or not PlayerUpgrades.HasPerk(player, "LuckyLeaf") then
		return 0
	end
	local perk = PerkConfig.LuckyLeaf
	local bonus = 0
	for _ = 1, count do
		if math.random() < perk.LuckyChance then
			local multiplier = perk.LuckyMultiplierMin + math.random() * (perk.LuckyMultiplierMax - perk.LuckyMultiplierMin)
			bonus += perLeafCoins * (multiplier - 1)
		end
	end
	return bonus
end

-- The next three are for SaveSystem -- enumerating what to persist without it needing to know
-- Attributes are the storage mechanism.
function PlayerUpgrades.GetOwnedUpgradeIds(player)
	local ids = {}
	for id in pairs(UpgradeConfig) do
		if PlayerUpgrades.HasUpgrade(player, id) then
			table.insert(ids, id)
		end
	end
	return ids
end

function PlayerUpgrades.GetOwnedPerkIds(player)
	local ids = {}
	for id in pairs(PerkConfig) do
		if PlayerUpgrades.HasPerk(player, id) then
			table.insert(ids, id)
		end
	end
	return ids
end

function PlayerUpgrades.GetOwnedCosmeticIds(player)
	local ids = {}
	for id in pairs(CosmeticConfig) do
		if PlayerUpgrades.HasCosmetic(player, id) then
			table.insert(ids, id)
		end
	end
	return ids
end

-- Flat {toolName -> cosmeticId} table, only including non-default choices (nothing to persist for
-- a tool still on its default look).
function PlayerUpgrades.GetCosmetics(player)
	local cosmetics = {}
	for toolName in pairs(BASE_CONFIGS) do
		local id = PlayerUpgrades.GetCosmetic(player, toolName)
		if id ~= DEFAULT_COSMETIC then
			cosmetics[toolName] = id
		end
	end
	return cosmetics
end

local function onPlayerAdded(player)
	-- Sets the default (base MaxActiveSacks, nothing owned yet) immediately -- SaveSystem's later
	-- GrantUpgrade calls for anything actually owned will correct it via the sync above.
	syncSackCapacityAttribute(player)
end

function PlayerUpgrades.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
end

return PlayerUpgrades
