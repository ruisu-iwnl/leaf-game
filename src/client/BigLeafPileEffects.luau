local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BigLeafPileConfig = require(ReplicatedStorage.Shared.BigLeafPileConfig)

-- Client-side half of the Big Leaf Pile kill effect (see BigLeafPileSystem.luau, server, for the
-- other half and the full story on why this moved off the server). The fly-apart-and-fade dissolve
-- used to be driven by the SERVER writing Position/Transparency on every leaf part (up to ~300 per
-- pile) every frame for BigLeafPileConfig.KillAnimDuration -- correct-looking, but each of those
-- writes replicates to every connected client, and that volume of per-frame replication is exactly
-- what showed up as real lag in the published game (Studio solo testing never has enough clients/
-- latency to expose it). Now the server fires ONE lightweight event per kill (the model reference +
-- its center) and EVERY client plays this same animation entirely locally -- zero further network
-- cost, since a client mutating a replicated Instance's properties is purely a local visual
-- override that never replicates onward to the server or other clients. The server still destroys
-- the model itself, after the animation window -- this module only ever touches its visuals.
local BigLeafPileEffects = {}

local function playKillAnimation(model, corePosition)
	if not model or not model.Parent then
		return
	end

	local leafInfos = {}
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "Core" then
			local away = Vector3.new(part.Position.X - corePosition.X, 0, part.Position.Z - corePosition.Z)
			if away.Magnitude < 0.05 then
				away = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
			end
			table.insert(leafInfos, {
				Part = part,
				StartPosition = part.Position,
				AwayDirection = away.Unit,
			})
		end
	end

	local duration = BigLeafPileConfig.KillAnimDuration
	local outward = BigLeafPileConfig.KillAnimOutwardStuds
	local rise = BigLeafPileConfig.KillAnimRiseStuds

	local elapsed = 0
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		-- The server destroys the model shortly after this animation's own duration -- if that's
		-- already happened (e.g. this client was running behind), just stop instead of erroring on
		-- now-destroyed parts.
		if not model.Parent then
			connection:Disconnect()
			return
		end
		elapsed += dt
		local t = math.clamp(elapsed / duration, 0, 1)
		local eased = 1 - (1 - t) * (1 - t) -- ease-out, so the burst is fast at first and settles near the end
		for _, info in ipairs(leafInfos) do
			if info.Part.Parent then
				local riseAmount = rise * eased * (1 - eased * 0.5)
				local offset = info.AwayDirection * (outward * eased) + Vector3.new(0, riseAmount, 0)
				info.Part.Position = info.StartPosition + offset
				info.Part.Transparency = eased
			end
		end
		if t >= 1 then
			connection:Disconnect()
		end
	end)
end

function BigLeafPileEffects.Start()
	task.spawn(function()
		local remotes = ReplicatedStorage.Shared:WaitForChild("Remotes", 15)
		if not remotes then
			warn("[BigLeafPileEffects] ReplicatedStorage.Shared.Remotes not found after 15s -- pile kill effect disabled this session.")
			return
		end
		local remote = remotes:WaitForChild("BigLeafPileKilled", 15)
		if not remote then
			warn("[BigLeafPileEffects] BigLeafPileKilled remote not found after 15s -- pile kill effect disabled this session.")
			return
		end
		remote.OnClientEvent:Connect(playKillAnimation)
	end)
end

return BigLeafPileEffects
