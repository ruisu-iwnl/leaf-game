local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdminCommands = require(script.AdminCommands)
local BlowerTool = require(script.BlowerTool)
local CleanupZoneUI = require(script.CleanupZoneUI)
local DayNightCycle = require(script.DayNightCycle)
local LeafSpawner = require(script.LeafSpawner)
local MoneyConfig = require(ReplicatedStorage.Shared.MoneyConfig)
local MoneySystem = require(script.MoneySystem)
local PlayerSetup = require(script.PlayerSetup)
local SackSystem = require(script.SackSystem)
local SaveSystem = require(script.SaveSystem)
local WindSystem = require(script.WindSystem)

-- WindSystem first so the WindDirection attribute is already set before the first leaves spawn.
WindSystem.Start()
LeafSpawner.Start()
CleanupZoneUI.Start()
SackSystem.Start()
PlayerSetup.Start()
MoneySystem.Start()
SaveSystem.Start()
DayNightCycle.Start()
BlowerTool.Start()
AdminCommands.Start()

-- The one place LeafSpawner's leaf-delivery events get turned into Coins -- keeps LeafSpawner
-- itself decoupled from Coins/MoneySystem as a concept (see LeafSpawner.OnLeafDelivered).
LeafSpawner.OnLeafDelivered(function(player, count)
	MoneySystem.AddCoins(player, count * MoneyConfig.CoinsPerLeaf)
end)
