-- init.client: owns client bootstrap: building Hud/Fx and mirroring server state, storm, alert, and prompt events.
-- Server gameplay is authoritative; the client only renders and sends intents.
--!strict
-- Module contract (derived from the code below)
--
-- Owns:
--   - Bootstrapping the client UI: Hud.build(), Hud.start(), Fx.build(), in that order.
--   - The client-side listeners on the Net.State, Net.Storm and Net.Alert RemoteEvents.
--   - The ProximityPromptService PromptShown/PromptHidden hooks that drive the Hud key hint.
--
-- Refuses:
--   - To start at all if ReplicatedStorage.Net does not arrive within 30 seconds
--     (warns "[Client] Net folder never arrived" and returns early).
--   - Any remote payload that is not a table (silently ignored).
--   - Money Fx for a gain that is not a positive number.
--   - Showing a hint for a prompt whose ActionText is nil or empty.
--   - Any gameplay authority: it never fires remotes or mutates server state.
--
-- Returns:
--   - Nothing. This is a LocalScript entrypoint, not a ModuleScript; its only
--     effects are the UI it builds and the event connections it makes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Hud = require(script:WaitForChild("Hud"))
local Fx = require(script:WaitForChild("Fx"))

local net = ReplicatedStorage:WaitForChild("Net", 30)
if not net then
	warn("[Client] Net folder never arrived")
	return
end

local stateEvent = net:WaitForChild("State", 30) :: RemoteEvent
local stormEvent = net:WaitForChild("Storm", 30) :: RemoteEvent
local alertEvent = net:WaitForChild("Alert", 30) :: RemoteEvent

Hud.build()
Hud.start()
Fx.build()

-- State handler: pushes a table payload into Hud.update and plays money Fx at the base for a positive gain.
-- Returns nothing; non-table payloads are ignored.
stateEvent.OnClientEvent:Connect(function(payload: any)
	if typeof(payload) == "table" then
		Hud.update(payload)
		if typeof(payload.gain) == "number" and payload.gain > 0 then
			Fx.money(payload.gain, Hud.basePosition())
		end
	end
end)

-- Storm handler: forwards a table payload to Hud.setStorm and to Fx.event for the visual effect.
-- Returns nothing; non-table payloads are ignored.
stormEvent.OnClientEvent:Connect(function(payload: any)
	if typeof(payload) == "table" then
		Hud.setStorm(payload)
		Fx.event(payload)
	end
end)

-- Alert handler: routes kind == "lock" payloads to Hud.setLock, all others to Hud.alert plus Fx.event.
-- Returns nothing; non-table payloads are ignored.
alertEvent.OnClientEvent:Connect(function(payload: any)
	if typeof(payload) == "table" then
		if payload.kind == "lock" then
			Hud.setLock(payload)
		else
			Hud.alert(payload)
			Fx.event(payload)
		end
	end
end)

-- PromptShown handler: sets the Hud hint to "[Key] Action Object" for prompts with non-empty ActionText.
-- Returns nothing; prompts without action text leave the hint untouched.
ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
	local action = prompt.ActionText
	local target = prompt.ObjectText
	if action and action ~= "" then
		Hud.setHint("[" .. tostring(prompt.KeyboardKeyCode.Name) .. "] " .. action .. " " .. tostring(target))
	end
end)

-- PromptHidden handler: clears the Hud hint by calling Hud.setHint(nil).
-- Returns nothing.
ProximityPromptService.PromptHidden:Connect(function()
	Hud.setHint(nil)
end)
