local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local TopBar = require(script.Parent.TopBar)

-- Coins readout logic -- the actual row (icon + gear) is built once by TopBar.luau, shared with
-- SettingsUI, so the two can never end up overlapping. This module just owns keeping the number
-- itself in sync with the server, and hiding Roblox's default player list (which otherwise sits
-- in the same corner and would cover this up).
local CoinsUI = {}

-- "1234567" -> "1,234,567". Coins is a plain integer, not real currency, so no "$" prefix -- the
-- coin icon itself already signals what's being counted.
local function formatAmount(amount)
	local text = tostring(math.floor(amount))
	local sign = ""
	if text:sub(1, 1) == "-" then
		sign = "-"
		text = text:sub(2)
	end
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return sign .. formatted
end

function CoinsUI.Start()
	local hid = pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
	if not hid then
		warn("[CoinsUI] couldn't hide the default player list")
	end

	local player = Players.LocalPlayer
	local amountLabel = TopBar.Build().amountLabel

	local leaderstats = player:WaitForChild("leaderstats")
	local coins = leaderstats:WaitForChild("Coins")

	local function refresh()
		amountLabel.Text = formatAmount(coins.Value)
	end

	refresh()
	coins.Changed:Connect(refresh)
end

return CoinsUI
