local Players = game:GetService("Players")

-- Server-authoritative Coins. leaderstats is the standard Roblox folder name that automatically
-- shows up in the player list, so this needs no custom UI to be visible/verifiable -- Step 7
-- (Basic UI) will add a nicer HUD readout of the same value later.
local MoneySystem = {}

local function onPlayerAdded(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = 0
	coins.Parent = leaderstats
end

-- The one reusable reward function every coin payout in the game should route through (leaf
-- delivery now, upgrades/gamepasses/offline earnings later), so payouts stay consistent and
-- always server-side. Silently ignores invalid players/amounts rather than erroring, since
-- callers may race a player leaving mid-delivery.
function MoneySystem.AddCoins(player, amount)
	if not player or not player.Parent then
		return
	end
	amount = math.floor(amount)
	if amount <= 0 then
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	if coins then
		coins.Value += amount
	end
end

-- Attempts to deduct `amount` Coins, only if the player can currently afford it -- returns true if
-- the spend actually happened, false otherwise (can't afford it, or an invalid player/amount). The
-- one place every purchase in the game should route through (see PurchaseSystem.luau), so nothing
-- can ever push a balance negative or spend twice off a stale balance check.
function MoneySystem.SpendCoins(player, amount)
	if not player or not player.Parent then
		return false
	end
	amount = math.floor(amount)
	if amount <= 0 then
		return false
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	if not coins or coins.Value < amount then
		return false
	end

	coins.Value -= amount
	return true
end

-- Deducts up to `amount` Coins, clamped so the balance never goes negative -- unlike SpendCoins,
-- this never "fails": a penalty (see RoundSystem.applyResultsRewards) should always apply, just
-- capped at whatever the player actually still has. Returns the amount ACTUALLY deducted, which
-- can be less than requested if the player already spent this round's earnings on something before
-- the penalty was applied.
function MoneySystem.DeductCoins(player, amount)
	if not player or not player.Parent then
		return 0
	end
	amount = math.floor(amount)
	if amount <= 0 then
		return 0
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	if not coins then
		return 0
	end

	local actual = math.min(amount, coins.Value)
	coins.Value -= actual
	return actual
end

-- Sets Coins to an exact value (clamped to non-negative) rather than adding -- used by admin
-- commands (e.g. wiping a player's balance for testing), not by normal gameplay rewards.
function MoneySystem.SetCoins(player, amount)
	if not player or not player.Parent then
		return
	end
	amount = math.max(0, math.floor(amount))

	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	if coins then
		coins.Value = amount
	end
end

-- Reads the current balance -- used by SaveSystem so it doesn't need to know leaderstats/Coins
-- is how balances happen to be stored internally.
function MoneySystem.GetCoins(player)
	local leaderstats = player and player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	return coins and coins.Value or 0
end

function MoneySystem.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
end

return MoneySystem
