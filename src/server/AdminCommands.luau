local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local AdminConfig = require(ReplicatedStorage.Shared.AdminConfig)
local CosmeticConfig = require(ReplicatedStorage.Shared.CosmeticConfig)
local MoneySystem = require(script.Parent.MoneySystem)
local PerkConfig = require(ReplicatedStorage.Shared.PerkConfig)
local PlayerUpgrades = require(script.Parent.PlayerUpgrades)
local SackSystem = require(script.Parent.SackSystem)
local UpgradeConfig = require(ReplicatedStorage.Shared.UpgradeConfig)

-- Lightweight dev/testing commands, e.g. ":addmoney me 100". Restricted to the game's owner
-- (game.CreatorId) plus any extra usernames listed in AdminConfig.ExtraAdmins, PLUS anyone
-- testing inside Studio (RunService:IsStudio()) -- game.CreatorId is 0 for a place that's never
-- been published, which would otherwise lock the developer themselves out. Only you can open your
-- own Studio file, so the Studio check is safe; it stops applying the moment this runs as a real
-- published server. Feedback goes to the server Output window, not any in-game UI -- this is a
-- dev tool, not a player-facing feature.
--
-- Primary delivery is a RemoteEvent fired by AdminCommandBar.luau (client), not Roblox's chat --
-- this place's chat pipeline (neither legacy Player.Chatted nor TextChatService.MessageReceived)
-- was never actually delivering messages to the server here, even from a guaranteed-fresh build,
-- so commands stopped depending on it. The chat listeners stay wired as a harmless bonus in case
-- that ever starts working, but the RemoteEvent is the path that's actually guaranteed to work,
-- since this project owns both ends of it end-to-end.
local AdminCommands = {}

local adminUserIds = {}

local function resolveAdmins()
	adminUserIds[game.CreatorId] = true
	for _, name in ipairs(AdminConfig.ExtraAdmins) do
		local ok, userId = pcall(Players.GetUserIdFromNameAsync, Players, name)
		if ok and userId then
			adminUserIds[userId] = true
		end
	end
end

local function isAdmin(player)
	if RunService:IsStudio() then
		return true
	end
	return adminUserIds[player.UserId] == true
end

-- Exact match first, then case-insensitive substring as a fallback (so ":addmoney lu 100" still
-- finds "Luis123"). Returns nil (and the caller warns) if nothing matches, or more than one
-- player matches ambiguously -- never silently guesses between two players.
local function findPlayer(query)
	if not query then
		return nil
	end
	local lowered = query:lower()

	for _, player in ipairs(Players:GetPlayers()) do
		if player.Name:lower() == lowered then
			return player
		end
	end

	local match
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Name:lower():find(lowered, 1, true) then
			if match then
				return nil
			end
			match = player
		end
	end
	return match
end

-- "me" always refers to whoever ran the command -- the common case (solo Studio testing, or an
-- admin adjusting their own balance) shouldn't require typing/guessing a username at all.
local function resolveTarget(admin, query)
	if query and query:lower() == "me" then
		return admin
	end
	local target = findPlayer(query)
	if not target then
		local names = {}
		for _, player in ipairs(Players:GetPlayers()) do
			table.insert(names, player.Name)
		end
		warn(string.format(
			"[Admin] no player matched '%s'. Try 'me', or one of: %s",
			tostring(query),
			#names > 0 and table.concat(names, ", ") or "(no players in-game)"
		))
	end
	return target
end

local commands = {}

commands.addmoney = function(admin, args)
	local target = resolveTarget(admin, args[1])
	local amount = tonumber(args[2])
	if not target then
		return
	end
	if not amount or amount <= 0 then
		warn("[Admin] usage: :addmoney <player|me> <amount>")
		return
	end
	MoneySystem.AddCoins(target, amount)
	print(string.format("[Admin] %s gave %d coins to %s", admin.Name, math.floor(amount), target.Name))
end

commands.wipemoney = function(admin, args)
	local target = resolveTarget(admin, args[1])
	if not target then
		return
	end
	MoneySystem.SetCoins(target, 0)
	print(string.format("[Admin] %s wiped %s's coins", admin.Name, target.Name))
end

-- Recalculates ActiveSackCount from the real sack Tools a player currently has (see
-- SackSystem.ResyncActiveSackCount) -- fixes the "counter says 2/3 but nothing's in the hotbar"
-- desync immediately, without needing a rejoin.
commands.fixsacks = function(admin, args)
	local target = resolveTarget(admin, args[1])
	if not target then
		return
	end
	SackSystem.ResyncActiveSackCount(target)
	print(string.format(
		"[Admin] %s resynced %s's ActiveSackCount to match their real sacks (now %d)",
		admin.Name, target.Name, target:GetAttribute("ActiveSackCount") or 0
	))
end

-- Upgrade/perk grant-and-revoke commands for testing the store's effects before the store itself
-- exists (see PlayerUpgrades.luau) -- e.g. ":addupgrade me RakeCooldown", ":addperk me DoubleGrab".
-- Same resolveTarget pattern as the money commands; ids are matched case-insensitively against the
-- UpgradeConfig/PerkConfig catalogs so a typo doesn't silently grant nothing.
local function findCatalogId(catalog, query)
	if not query then
		return nil
	end
	local lowered = query:lower()
	for id in pairs(catalog) do
		if id:lower() == lowered then
			return id
		end
	end
	return nil
end

local function catalogIdList(catalog)
	local ids = {}
	for id in pairs(catalog) do
		table.insert(ids, id)
	end
	return table.concat(ids, ", ")
end

commands.addupgrade = function(admin, args)
	local target = resolveTarget(admin, args[1])
	if not target then
		return
	end
	local id = findCatalogId(UpgradeConfig, args[2])
	if not id then
		warn(string.format("[Admin] usage: :addupgrade <player|me> <id>. Known ids: %s", catalogIdList(UpgradeConfig)))
		return
	end
	PlayerUpgrades.GrantUpgrade(target, id)
	print(string.format("[Admin] %s granted %s the %s upgrade", admin.Name, target.Name, id))
end

commands.removeupgrade = function(admin, args)
	local target = resolveTarget(admin, args[1])
	if not target then
		return
	end
	local id = findCatalogId(UpgradeConfig, args[2])
	if not id then
		warn(string.format("[Admin] usage: :removeupgrade <player|me> <id>. Known ids: %s", catalogIdList(UpgradeConfig)))
		return
	end
	PlayerUpgrades.RemoveUpgrade(target, id)
	print(string.format("[Admin] %s removed %s's %s upgrade", admin.Name, target.Name, id))
end

commands.addperk = function(admin, args)
	local target = resolveTarget(admin, args[1])
	if not target then
		return
	end
	local id = findCatalogId(PerkConfig, args[2])
	if not id then
		warn(string.format("[Admin] usage: :addperk <player|me> <id>. Known ids: %s", catalogIdList(PerkConfig)))
		return
	end
	PlayerUpgrades.GrantPerk(target, id)
	print(string.format("[Admin] %s granted %s the %s perk", admin.Name, target.Name, id))
end

commands.removeperk = function(admin, args)
	local target = resolveTarget(admin, args[1])
	if not target then
		return
	end
	local id = findCatalogId(PerkConfig, args[2])
	if not id then
		warn(string.format("[Admin] usage: :removeperk <player|me> <id>. Known ids: %s", catalogIdList(PerkConfig)))
		return
	end
	PlayerUpgrades.RemovePerk(target, id)
	print(string.format("[Admin] %s removed %s's %s perk", admin.Name, target.Name, id))
end

commands.addcosmetic = function(admin, args)
	local target = resolveTarget(admin, args[1])
	if not target then
		return
	end
	local id = findCatalogId(CosmeticConfig, args[2])
	if not id then
		warn(string.format("[Admin] usage: :addcosmetic <player|me> <id>. Known ids: %s", catalogIdList(CosmeticConfig)))
		return
	end
	PlayerUpgrades.GrantCosmetic(target, id)
	print(string.format("[Admin] %s granted %s the %s cosmetic", admin.Name, target.Name, id))
end

commands.removecosmetic = function(admin, args)
	local target = resolveTarget(admin, args[1])
	if not target then
		return
	end
	local id = findCatalogId(CosmeticConfig, args[2])
	if not id then
		warn(string.format("[Admin] usage: :removecosmetic <player|me> <id>. Known ids: %s", catalogIdList(CosmeticConfig)))
		return
	end
	PlayerUpgrades.RemoveCosmetic(target, id)
	print(string.format("[Admin] %s removed %s's %s cosmetic", admin.Name, target.Name, id))
end

-- Shared by both the RemoteEvent path and the (bonus, possibly-inert) chat listeners below.
local function runCommand(player, message)
	if message:sub(1, #AdminConfig.CommandPrefix) ~= AdminConfig.CommandPrefix then
		return
	end
	if not isAdmin(player) then
		warn(string.format("[Admin] %s (UserId %d) is not an admin -- command ignored", player.Name, player.UserId))
		return
	end

	local tokens = {}
	for token in message:sub(#AdminConfig.CommandPrefix + 1):gmatch("[^%s,]+") do
		table.insert(tokens, token)
	end

	local commandName = table.remove(tokens, 1)
	if not commandName then
		return
	end

	local handler = commands[commandName:lower()]
	if handler then
		handler(player, tokens)
	else
		warn(string.format("[Admin] unknown command: %s", commandName))
	end
end

local function onMessageReceived(textChatMessage)
	local textSource = textChatMessage.TextSource
	if not textSource then
		return
	end
	local player = Players:GetPlayerByUserId(textSource.UserId)
	if player then
		runCommand(player, textChatMessage.Text)
	end
end

local function onPlayerAdded(player)
	player.Chatted:Connect(function(message)
		runCommand(player, message)
	end)
end

function AdminCommands.Start()
	resolveAdmins()

	local remotes = ReplicatedStorage.Shared:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage.Shared
	end

	local adminCommandRemote = remotes:FindFirstChild("AdminCommand") or Instance.new("RemoteEvent")
	adminCommandRemote.Name = "AdminCommand"
	adminCommandRemote.Parent = remotes

	adminCommandRemote.OnServerEvent:Connect(function(player, message)
		if typeof(message) == "string" then
			runCommand(player, message)
		end
	end)

	TextChatService.MessageReceived:Connect(onMessageReceived)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	print("[Admin] AdminCommands ready -- press the ` (backtick) key in-game to open the command bar")
end

return AdminCommands
