-- init.client: owns client bootstrap: building Hud/Fx and mirroring server state, storm, alert, and prompt events.
-- Server gameplay is authoritative; the client only renders and sends intents.
--!strict

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

stateEvent.OnClientEvent:Connect(function(payload: any)
	if typeof(payload) == "table" then
		Hud.update(payload)
		if typeof(payload.gain) == "number" and payload.gain > 0 then
			Fx.money(payload.gain, Hud.basePosition())
		end
	end
end)

stormEvent.OnClientEvent:Connect(function(payload: any)
	if typeof(payload) == "table" then
		Hud.setStorm(payload)
		Fx.event(payload)
	end
end)

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

ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
	local action = prompt.ActionText
	local target = prompt.ObjectText
	if action and action ~= "" then
		Hud.setHint("[" .. tostring(prompt.KeyboardKeyCode.Name) .. "] " .. action .. " " .. tostring(target))
	end
end)

ProximityPromptService.PromptHidden:Connect(function()
	Hud.setHint(nil)
end)
