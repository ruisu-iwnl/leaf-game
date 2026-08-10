local Players = game:GetService("Players")

-- Roblox automatically swaps the system cursor to a "ready to click" hand icon whenever the mouse
-- hovers a ClickDetector-enabled part. This forces the icon back to the plain default arrow every
-- time that happens, so the cursor never changes shape anywhere in the game.
local CursorLock = {}

function CursorLock.Start()
	local player = Players.LocalPlayer
	local mouse = player:GetMouse()

	mouse.Icon = ""
	mouse.Move:Connect(function()
		if mouse.Icon ~= "" then
			mouse.Icon = ""
		end
	end)
end

return CursorLock
