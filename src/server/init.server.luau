local LeafSpawner = require(script.LeafSpawner)
local PlayerSetup = require(script.PlayerSetup)
local WindSystem = require(script.WindSystem)

-- WindSystem first so the WindDirection attribute is already set before the first leaves spawn.
WindSystem.Start()
LeafSpawner.Start()
PlayerSetup.Start()
