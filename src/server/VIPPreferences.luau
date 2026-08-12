local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerUpgrades = require(script.Parent.PlayerUpgrades)

-- Server-authoritative save point for the two Leaf Patron cosmetic preferences SettingsUI.luau
-- exposes once a player owns the perk: the effects on/off toggle and the footstep trail's color (a
-- custom RGB pick via VIPColorPickerUI.luau, or "Rainbow" for the default animated cycle). Both are
-- plain player Attributes (see PlayerUpgrades.luau) -- going through the server (rather than a client
-- setting its own Attribute directly) matters here because every OTHER client's VIPEffects.luau also
-- reads them to render your nameplate/trail, so they need to be something every viewer can trust.
local VIPPreferences = {}

local function isValidHexColor(value)
	return typeof(value) == "string" and value:match("^#%x%x%x%x%x%x$") ~= nil
end

local function setEffectsEnabled(player, enabled)
	if not PlayerUpgrades.HasPerk(player, "LeafPatron") then
		return { success = false, reason = "You need the Leaf Patron perk for this." }
	end
	if typeof(enabled) ~= "boolean" then
		return { success = false, reason = "Something went wrong -- try again." }
	end
	PlayerUpgrades.SetVIPEffectsEnabled(player, enabled)
	return { success = true }
end

local function setTrailColor(player, colorValue)
	if not PlayerUpgrades.HasPerk(player, "LeafPatron") then
		return { success = false, reason = "You need the Leaf Patron perk for this." }
	end
	if colorValue ~= "Rainbow" and not isValidHexColor(colorValue) then
		return { success = false, reason = "Something went wrong -- try again." }
	end
	PlayerUpgrades.SetVIPTrailColor(player, colorValue)
	return { success = true }
end

function VIPPreferences.Start()
	local remotes = ReplicatedStorage.Shared:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage.Shared
	end

	local setEffectsEnabledFunction = remotes:FindFirstChild("SetVIPEffectsEnabled") or Instance.new("RemoteFunction")
	setEffectsEnabledFunction.Name = "SetVIPEffectsEnabled"
	setEffectsEnabledFunction.Parent = remotes

	setEffectsEnabledFunction.OnServerInvoke = function(player, enabled)
		local ok, result = pcall(setEffectsEnabled, player, enabled)
		if not ok then
			warn(string.format("[VIPPreferences] error toggling effects for %s: %s", player.Name, tostring(result)))
			return { success = false, reason = "Something went wrong -- try again." }
		end
		return result
	end

	local setTrailColorFunction = remotes:FindFirstChild("SetVIPTrailColor") or Instance.new("RemoteFunction")
	setTrailColorFunction.Name = "SetVIPTrailColor"
	setTrailColorFunction.Parent = remotes

	setTrailColorFunction.OnServerInvoke = function(player, colorValue)
		local ok, result = pcall(setTrailColor, player, colorValue)
		if not ok then
			warn(string.format("[VIPPreferences] error setting trail color for %s: %s", player.Name, tostring(result)))
			return { success = false, reason = "Something went wrong -- try again." }
		end
		return result
	end
end

return VIPPreferences
