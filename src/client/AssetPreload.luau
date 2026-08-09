local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SackConfig = require(ReplicatedStorage.Shared.SackConfig)

-- Roblox streams animation content in from its CDN on first use -- without this, the very first
-- time a client is asked to render the pickup/tie-off gesture, the content hasn't finished
-- downloading yet and it silently misses that one play; every play after is instant since it's
-- then cached locally. Preloading here, at startup rather than on-demand, avoids that cold-start
-- miss. task.spawn so this never blocks the rest of client startup while it downloads.
local AssetPreload = {}

function AssetPreload.Start()
	task.spawn(function()
		ContentProvider:PreloadAsync({
			SackConfig.PickupAnimationId,
			SackConfig.TieSackAnimationId,
		})
	end)
end

return AssetPreload
