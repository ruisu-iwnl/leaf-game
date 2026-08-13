local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RoundConfig = require(ReplicatedStorage.Shared.RoundConfig)

-- CharacterAutoLoads is a property of the Players SERVICE (not StarterPlayer, despite the name
-- similarity -- confirmed the hard way: "CharacterAutoLoads is not a valid member of StarterPlayer"
-- at runtime). Set here, first thing in MainMenuSystem.Start() (itself the very first Start() call
-- in init.server.luau), so it's flipped off before any player has a chance to connect. This is
-- what makes a player sit on the client-only Main Menu (MainMenuUI.luau) with no character at all
-- until they press Play -- no spawn, no WalkSpeed, nothing for RoundSystem to ever consider "here"
-- by accident. This module owns exactly the one moment that changes: the PlayerReadyToPlay remote,
-- fired once per player when they click Play, which is the only place LoadCharacter() is ever
-- called in this game.
local MainMenuSystem = {}

-- Workspace.StreamingEnabled culls client replication around the player's CHARACTER -- with
-- CharacterAutoLoads off, a menu-bound player has no character at all, so nothing streams in near
-- the Lobby for them until Play is clicked. That silently broke HallOfFameUI's board lookup and
-- QuestPathUI's guide-rig lookup the moment Main Menu shipped (both are real Workspace instances
-- sitting in StartingLobby, replicated fine before this since a character used to spawn there
-- immediately). Same fix RoundSystem.luau already uses for map teleports (see its own
-- streamPlayersIn/RequestStreamAroundAsync) -- just aimed at the Lobby instead of a map, and fired
-- once per player on join rather than per teleport.
local function requestLobbyStream(player)
	task.spawn(function()
		local lobby = Workspace:WaitForChild("StartingLobby", 15)
		if not lobby then
			return
		end
		local spawnPlatform = lobby:WaitForChild("SpawnPlatform", 15)
		if not spawnPlatform or not player.Parent then
			return
		end
		pcall(function()
			player:RequestStreamAroundAsync(spawnPlatform.Position, RoundConfig.StreamAroundTimeoutSeconds)
		end)
	end)
end

function MainMenuSystem.Start()
	Players.CharacterAutoLoads = false

	local remotes = ReplicatedStorage.Shared:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage.Shared
	end

	local readyRemote = remotes:FindFirstChild("PlayerReadyToPlay") or Instance.new("RemoteEvent")
	readyRemote.Name = "PlayerReadyToPlay"
	readyRemote.Parent = remotes

	-- OnMainMenu: true from the instant a player connects (before any character exists) until
	-- their LoadCharacter() actually finishes below. RoundSystem's isSittingOutThisRound checks
	-- this so a player still on the menu is never counted for Intermission, the map vote, or a
	-- round's participants snapshot -- same shape as IsAFK/the Tutorial-quest gate it already has.
	local function initPlayer(player)
		player:SetAttribute("OnMainMenu", true)
		requestLobbyStream(player)
	end
	Players.PlayerAdded:Connect(initPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		initPlayer(player)
	end

	-- HasEnteredGame guards against a duplicate/replayed remote fire (e.g. a stale client retry)
	-- ever calling LoadCharacter() a second time or re-running this flow.
	readyRemote.OnServerEvent:Connect(function(player)
		if player:GetAttribute("HasEnteredGame") then
			return
		end
		player:SetAttribute("HasEnteredGame", true)

		player:LoadCharacter()
		if not player.Character then
			player.CharacterAdded:Wait()
		end

		player:SetAttribute("OnMainMenu", false)
	end)
end

return MainMenuSystem
