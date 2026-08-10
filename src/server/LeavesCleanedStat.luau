local Players = game:GetService("Players")

-- Per-player lifetime leaves-cleaned count, shown the same way Coins is (a leaderstats IntValue,
-- so it's visible/verifiable with no custom UI needed -- see MoneySystem's own comment on why
-- leaderstats). This is deliberately separate from LeafSpawner's "LeavesCleaned" Workspace
-- attribute, which is a single count shared by everyone currently on that server instance and
-- resets every server restart -- this one is scoped to one specific player and persisted via
-- SaveSystem, for future stats/leaderboard use.
local LeavesCleanedStat = {}

local function onPlayerAdded(player)
	local leaderstats = player:WaitForChild("leaderstats")
	if leaderstats:FindFirstChild("LeavesCleaned") then
		return
	end

	local stat = Instance.new("IntValue")
	stat.Name = "LeavesCleaned"
	stat.Value = 0
	stat.Parent = leaderstats
end

-- Routed through LeafSpawner.OnLeafDelivered (see init.server.luau), same event MoneySystem uses
-- for Coins -- so this only ever counts leaves actually attributable to a player, matching Coins'
-- own payout rules exactly.
function LeavesCleanedStat.Add(player, amount)
	if not player or not player.Parent then
		return
	end
	amount = math.floor(amount)
	if amount <= 0 then
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local stat = leaderstats and leaderstats:FindFirstChild("LeavesCleaned")
	if stat then
		stat.Value += amount
	end
end

-- Sets the count to an exact value rather than adding -- used by SaveSystem to restore a saved
-- total, same shape as MoneySystem.SetCoins.
function LeavesCleanedStat.Set(player, amount)
	if not player or not player.Parent then
		return
	end
	amount = math.max(0, math.floor(amount))

	local leaderstats = player:FindFirstChild("leaderstats")
	local stat = leaderstats and leaderstats:FindFirstChild("LeavesCleaned")
	if stat then
		stat.Value = amount
	end
end

-- Reads the current count -- used by SaveSystem so it doesn't need to know leaderstats is how
-- this happens to be stored internally, same shape as MoneySystem.GetCoins.
function LeavesCleanedStat.Get(player)
	local leaderstats = player and player:FindFirstChild("leaderstats")
	local stat = leaderstats and leaderstats:FindFirstChild("LeavesCleaned")
	return stat and stat.Value or 0
end

function LeavesCleanedStat.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
end

return LeavesCleanedStat
