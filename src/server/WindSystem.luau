local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local Workspace = game:GetService("Workspace")

local WindConfig = require(ReplicatedStorage.Shared.WindConfig)

local WindSystem = {}

local nextChangeTime = 0
local started = false

-- Replicated via a Workspace attribute (auto-syncs to all clients) rather than a RemoteEvent,
-- since this is just a value clients read, not a one-off action.
local function setDirection(direction)
	Workspace:SetAttribute("WindDirection", direction)
	nextChangeTime = os.clock() + WindConfig.HoldDurationMin + math.random() * (WindConfig.HoldDurationMax - WindConfig.HoldDurationMin)
end

local function randomDirection()
	local directions = WindConfig.Directions
	return directions[math.random(1, #directions)]
end

-- Polls once a second rather than scheduling a task.delay per change, so a chat-command override
-- can simply push nextChangeTime forward without needing to cancel a pending timer.
local function runWindCycleLoop()
	setDirection(randomDirection())
	while true do
		task.wait(1)
		if os.clock() >= nextChangeTime then
			setDirection(randomDirection())
		end
	end
end

local directionAliases = {
	north = "NORTH",
	south = "SOUTH",
	east = "EAST",
	west = "WEST",
}

-- Dev testing commands: "/wind north", "/wind south", "/wind east", "/wind west", "/wind random".
local function handleChatCommand(message)
	local arg = message:lower():match("^/wind%s+(%a+)$")
	if not arg then
		return
	end

	if arg == "random" then
		setDirection(randomDirection())
	elseif directionAliases[arg] then
		setDirection(directionAliases[arg])
	end
end

-- Legacy chat (if the place has it enabled).
local function onPlayerAdded(player)
	player.Chatted:Connect(handleChatCommand)
end

-- Default modern chat: Player.Chatted does NOT fire for TextChatService messages, so commands
-- have to be picked up from each TextChannel directly instead.
local function hookChannel(channel)
	if not channel:IsA("TextChannel") then
		return
	end
	channel.MessageReceived:Connect(function(message)
		handleChatCommand(message.Text)
	end)
end

local function hookTextChatService()
	local textChannels = TextChatService:WaitForChild("TextChannels", 10)
	if not textChannels then
		return
	end
	for _, channel in ipairs(textChannels:GetChildren()) do
		hookChannel(channel)
	end
	textChannels.ChildAdded:Connect(hookChannel)
end

function WindSystem.Start()
	if started then
		return
	end
	started = true

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	task.spawn(hookTextChatService)

	task.spawn(runWindCycleLoop)
end

return WindSystem
