-- local BlowerConeIndicator = require(script.BlowerConeIndicator)
local CameraSetup = require(script.CameraSetup)
local CleanupProgressBar = require(script.CleanupProgressBar)
local OverheatUI = require(script.OverheatUI)
local SettingsUI = require(script.SettingsUI)

-- BlowerConeIndicator.Start() -- cone highlight disabled per request; re-enable by uncommenting
CameraSetup.Start()
CleanupProgressBar.Start()
OverheatUI.Start()
SettingsUI.Start()
