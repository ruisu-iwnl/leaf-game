local Workspace = game:GetService("Workspace")

-- Shared "walk up to an NPC and get a Talk prompt" wiring, reused by every NPC-specific server
-- module (e.g. StoreSystem.luau for Ruisu) instead of each one re-finding its rig and building its
-- own ProximityPrompt from scratch. Doesn't know or care what happens after the prompt fires --
-- that's entirely up to the caller's onTriggered callback (usually firing that NPC's own
-- dialogue via the shared OpenNPCDialogue remote -- see NPCDialogueUI.luau).
local NPCInteraction = {}

local PROMPT_ACTIVATION_DISTANCE = 10

-- Checked in the order most rig-building workflows actually produce a usable anchor part: a plain
-- Humanoid rig's HumanoidRootPart, a Model's PrimaryPart if it was set some other way, or as a
-- last resort just the first BasePart found anywhere inside it -- so this doesn't care exactly how
-- the rig was assembled.
local function findRootPart(rig)
	return rig:FindFirstChild("HumanoidRootPart")
		or rig.PrimaryPart
		or rig:FindFirstChildWhichIsA("BasePart", true)
end

-- Instance:WaitForChild only ever checks DIRECT children, never descendants -- and now that map
-- content is grouped into folders (Map1, StartingLobby -- see CLAUDE.md), an NPC rig ending up
-- nested inside one of those instead of straight under Workspace is a real possibility, not just a
-- hypothetical. Polls FindFirstChild(name, true) (which IS recursive) instead, on the same overall
-- timeout budget WaitForChild used to give this -- works the same regardless of nesting depth.
local function waitForRig(rigName, timeout)
	local deadline = os.clock() + timeout
	repeat
		local rig = Workspace:FindFirstChild(rigName, true)
		if rig then
			return rig
		end
		task.wait(0.1)
	until os.clock() >= deadline
	return Workspace:FindFirstChild(rigName, true)
end

-- Finds `rigName` anywhere under Workspace (waits up to 10s in case it's still streaming in) and
-- attaches a ProximityPrompt to its root part. `onTriggered(player)` fires on interaction.
function NPCInteraction.RegisterTalkPrompt(rigName, promptText, onTriggered)
	local rig = waitForRig(rigName, 10)
	if not rig then
		warn(string.format(
			"[NPCInteraction] no '%s' found in Workspace -- place the rig, named exactly this, for its interaction to work",
			rigName
		))
		return
	end

	local rootPart = findRootPart(rig)
	if not rootPart then
		warn(string.format("[NPCInteraction] couldn't find a part on %s to attach the interaction prompt to", rig:GetFullName()))
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TalkPrompt"
	prompt.ActionText = promptText or "Talk"
	prompt.ObjectText = rigName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_ACTIVATION_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = rootPart

	prompt.Triggered:Connect(onTriggered)
end

return NPCInteraction
