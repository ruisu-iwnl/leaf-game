local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BadgeConfig = require(ReplicatedStorage.Shared.BadgeConfig)
local ToastNotificationUI = require(script.Parent.ToastNotificationUI)

-- Badges' own thin content on top of the shared ToastNotificationUI shell -- fired by the server
-- (BadgeSystem.luau) whenever a real Roblox Badge actually gets awarded. Same "generic system, thin
-- per-feature wrapper" shape as StoreDialogueUI.luau sitting on top of NPCDialogueUI.luau -- this
-- file owns nothing about the toast's look/animation, only what a badge notification specifically
-- says (tier color, glyph, text).
local BadgeNotificationUI = {}

local TIER_COLORS = {
	Bronze = Color3.fromRGB(196, 128, 74),
	Silver = Color3.fromRGB(176, 184, 192),
	Gold = Color3.fromRGB(232, 180, 74),
	Platinum = Color3.fromRGB(140, 205, 225),
}

local STAR_GLYPH = "\226\152\133" -- "★"

function BadgeNotificationUI.Start()
	local remotes = ReplicatedStorage.Shared:WaitForChild("Remotes")
	local badgeAwardedRemote = remotes:WaitForChild("BadgeAwarded")

	badgeAwardedRemote.OnClientEvent:Connect(function(badgeKey)
		local badge = typeof(badgeKey) == "string" and BadgeConfig[badgeKey]
		if not badge then
			return
		end

		ToastNotificationUI.Show({
			tierColor = TIER_COLORS[badge.Tier],
			glyph = STAR_GLYPH,
			eyebrow = "BADGE UNLOCKED!",
			title = badge.Name,
			description = badge.Description,
		})
	end)
end

return BadgeNotificationUI
