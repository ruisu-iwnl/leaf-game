local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RakeConfig = require(ReplicatedStorage.Shared.RakeConfig)
local SackConfig = require(ReplicatedStorage.Shared.SackConfig)

-- Roblox streams an animation's actual KEYFRAME DATA in from its CDN separately from the
-- AnimationTrack object itself. SackSystem/RakeTool already call LoadAnimation server-side once per
-- character ("warm" the track) -- but that only creates the SERVER's own track handle; it does
-- nothing to make any given CLIENT's machine have that content cached. The first time a client is
-- ever told to render one of these gestures, if it hasn't fetched that data before, playback stalls
-- or visibly delays; every play after that is instant since it's then cached locally. That's the
-- "first use always has a delay, second use is smooth" symptom.
--
-- This used to be "fixed" with ContentProvider:PreloadAsync(animationId), which did NOT actually
-- solve it -- PreloadAsync is well-documented (Roblox DevForum, going back years and still true as
-- of 2024/2025 reports) as unreliable specifically for Animation content, unlike images/sounds/
-- meshes, which it does preload correctly. What DOES reliably force the fetch is calling
-- LoadAnimation on a real Animator: the call itself yields until the underlying clip data is ready,
-- so by the time it returns, this client has it cached -- confirmed against multiple real-world
-- reports of this exact bug. So instead of PreloadAsync, this loads (and only ever loads, never
-- plays) each gesture animation once, client-side, onto the LOCAL player's own Animator, as soon as
-- a character exists. Content caching is per-client per-AnimationId, not per-rig, so warming it here
-- via the local player's own Animator also covers seeing these same gestures play smoothly on any
-- OTHER player later, not just this one.
local AssetPreload = {}

local ANIMATION_IDS = {
	SackConfig.PickupAnimationId,
	SackConfig.TieSackAnimationId,
	RakeConfig.RakeSweepAnimationId,
}

local function preloadAnimations(humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 5)
	if not animator then
		return
	end

	for _, id in ipairs(ANIMATION_IDS) do
		if id ~= "" then
			task.spawn(function()
				local animation = Instance.new("Animation")
				animation.AnimationId = id
				pcall(function()
					-- Never played -- LoadAnimation itself is what forces the content fetch; the
					-- returned track is only kept alive long enough for that yield to finish.
					animator:LoadAnimation(animation)
				end)
			end)
		end
	end
end

function AssetPreload.Start()
	local player = Players.LocalPlayer

	local function onCharacterAdded(character)
		local humanoid = character:WaitForChild("Humanoid", 5)
		if humanoid then
			preloadAnimations(humanoid)
		end
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

return AssetPreload
