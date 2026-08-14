-- Delivery Streak: consecutive deliveries made without a long gap ramp up a personal Coins
-- multiplier -- rewards sustained, continuous work over start-stop trickling, and gives the
-- delivery popup (DeliveryPopupEffects.luau, client) something to visually escalate against
-- besides a flat 1-leaf-1-coin number. Applied on top of every other Coins multiplier (upgrades,
-- DoubleGrab, Lucky Leaf, golden bonus) in init.server.luau's OnLeafDelivered listener -- the one
-- place all of those already stack.
local DeliveryStreakConfig = {}

-- Max gap (seconds) between two deliveries that still counts as "the same streak" -- generous
-- enough to walk a few steps to the next pile, punishing enough that idling/wandering resets it.
DeliveryStreakConfig.WindowSeconds = 2.5

-- Flat multiplier growth per qualifying delivery EVENT (not per leaf) -- a sack/pile bonus is one
-- event same as a single blown leaf, since the streak rewards cadence/sustained activity, not raw
-- volume (a big batch already pays more Coins on its own merit).
DeliveryStreakConfig.StepPerDelivery = 0.04

DeliveryStreakConfig.MaxMultiplier = 3

-- Ordered low -> high, first entry always Multiplier = 1 (the resting/no-streak state).
-- `Milestone` (optional) is the flair text popped the FIRST time a streak climbs INTO that tier
-- (not on every delivery while sustained there). `Color` tints the "+N" Coins popup itself at
-- that tier. All five numbers/colors here are easy to retune after playtesting.
DeliveryStreakConfig.Tiers = {
	{ Multiplier = 1, Color = Color3.fromRGB(255, 214, 89) },
	{ Multiplier = 1.5, Color = Color3.fromRGB(255, 165, 60), Milestone = "Nice!" },
	{ Multiplier = 2, Color = Color3.fromRGB(255, 105, 70), Milestone = "On Fire!" },
	{ Multiplier = 2.5, Color = Color3.fromRGB(255, 70, 130), Milestone = "Amazing!" },
	{ Multiplier = 3, Color = Color3.fromRGB(200, 90, 255), Milestone = "UNSTOPPABLE!" },
}

return DeliveryStreakConfig
