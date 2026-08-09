local BlowerTool = require(script.BlowerTool)
local CleanupZoneUI = require(script.CleanupZoneUI)
local DayNightCycle = require(script.DayNightCycle)
local LeafSpawner = require(script.LeafSpawner)
local PlayerSetup = require(script.PlayerSetup)
local WindSystem = require(script.WindSystem)

-- WindSystem first so the WindDirection attribute is already set before the first leaves spawn.
WindSystem.Start()
LeafSpawner.Start()
CleanupZoneUI.Start()
PlayerSetup.Start()
DayNightCycle.Start()
BlowerTool.Start()
