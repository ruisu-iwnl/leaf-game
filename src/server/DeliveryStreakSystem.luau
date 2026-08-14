local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DeliveryStreakConfig = require(ReplicatedStorage.Shared.DeliveryStreakConfig)

-- Tracks each player's delivery streak -- see DeliveryStreakConfig.luau for the full design.
-- Deliberately decoupled from Coins itself, same as LeafSpawner: this module just answers "what's
-- this player's current multiplier, what color should the popup be, and did they just cross into
-- a new tier" for init.server.luau's OnLeafDelivered listener to apply and display.
local DeliveryStreakSystem = {}

local lastDeliveryTime = {} -- player -> os.clock() of their last qualifying delivery
local currentTierIndex = {} -- player -> index into DeliveryStreakConfig.Tiers

-- Called once per delivery event (see LeafSpawner.OnLeafDelivered). Returns:
--   multiplier  - apply to this delivery's Coins
--   color       - tint the delivery popup with, for this tier
--   milestone   - nil most of the time; a flair label the FIRST delivery that pushes the streak
--                 into a new, higher tier than it was already sustaining
function DeliveryStreakSystem.RecordDelivery(player)
	local now = os.clock()
	local last = lastDeliveryTime[player]
	local multiplier = player:GetAttribute("DeliveryStreakMultiplier") or 1

	if not last or (now - last) > DeliveryStreakConfig.WindowSeconds then
		multiplier = 1
		currentTierIndex[player] = 1
	end

	multiplier = math.min(multiplier + DeliveryStreakConfig.StepPerDelivery, DeliveryStreakConfig.MaxMultiplier)
	lastDeliveryTime[player] = now
	player:SetAttribute("DeliveryStreakMultiplier", multiplier)

	local tiers = DeliveryStreakConfig.Tiers
	local tierIndex = currentTierIndex[player] or 1
	local milestone = nil
	-- Walk upward from the player's last known tier -- multiplier only grows by one small step per
	-- call, so this crosses at most one boundary in practice, but the loop stays correct even if
	-- StepPerDelivery is later tuned much larger.
	while tierIndex < #tiers and multiplier >= tiers[tierIndex + 1].Multiplier do
		tierIndex += 1
		milestone = tiers[tierIndex].Milestone
	end
	currentTierIndex[player] = tierIndex

	return multiplier, tiers[tierIndex].Color, milestone
end

function DeliveryStreakSystem.Start()
	Players.PlayerRemoving:Connect(function(player)
		lastDeliveryTime[player] = nil
		currentTierIndex[player] = nil
	end)
end

return DeliveryStreakSystem
