local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local TopBar = require(script.Parent.TopBar)

-- Coins readout logic -- the actual row (icon + gear) is built once by TopBar.luau, shared with
-- SettingsUI, so the two can never end up overlapping. This module just owns keeping the number
-- itself in sync with the server, and hiding Roblox's default player list (which otherwise sits
-- in the same corner and would cover this up). It's also the one existing place in this codebase
-- that already pokes at StarterGui's CoreGui config at startup, so the reset-button disable below
-- lives here too rather than in a new one-line module -- not actually Coins-related, just sharing
-- the same "one-time client core UI setup" spot.
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

	-- Strictly disables the "Reset Character" option from the pause/escape menu -- resetting
	-- mid-round would otherwise let a player instantly respawn (e.g. to escape a bad position or
	-- desync round state) outside anything RoundSystem controls. false removes the button/callback
	-- entirely rather than just hiding a CoreGui panel (SetCoreGuiEnabled has no effect on it).
	--
	-- SetCore("ResetButtonCallback", ...) throws until Roblox's own CoreScripts finish registering
	-- that event -- which can happen AFTER this runs, since CoinsUI.Start() fires from the very top
	-- of init.client.luau. A single pcall attempt could silently lose that race and leave the reset
	-- button live for the whole session (the exact game-breaking gap being fixed), so retry on a
	-- short interval until it actually succeeds instead of trying once.
	task.spawn(function()
		local attempts = 0
		local disabledReset = false
		while not disabledReset and attempts < 20 do
			disabledReset = pcall(function()
				StarterGui:SetCore("ResetButtonCallback", false)
			end)
			attempts += 1
			if not disabledReset then
				task.wait(0.5)
			end
		end
		if not disabledReset then
			warn("[CoinsUI] couldn't disable the character reset button after retrying")
		end
	end)

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
