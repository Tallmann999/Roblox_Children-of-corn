-- Execute each current production session-gate expression verbatim. This is a
-- focused policy regression check; client-startup.luau separately executes the
-- complete real Bootstrap in both local modes with readiness/lifecycle adapters.
local fs = require("@lune/fs")

local gates = {
	{ path = "src/client/Bootstrap.client.luau", kind = "reject" },
	{ path = "src/client/Controllers/FarmGeometryController.luau", kind = "enable" },
	{ path = "src/client/Controllers/MonsterAnimationController.luau", kind = "enable" },
	{ path = "src/client/Controllers/CornWindController.luau", kind = "enable" },
	{ path = "src/client/Controllers/CornController.luau", kind = "enable" },
	{ path = "src/client/Controllers/CornBackdropController.luau", kind = "enable" },
	{ path = "src/client/Controllers/CornAppearanceController.luau", kind = "reject" },
	{ path = "src/server/Services/FarmGeometryService.luau", kind = "reject" },
	{ path = "src/server/Game/CornField.luau", kind = "reject" },
}

local function gateExpression(source, kind)
	source = source:gsub("\r\n", "\n")
	if kind == "reject" then
		for expression in source:gmatch("%f[%w]if%s+(.-)%s+then") do
			if expression:find("SessionMode", 1, true) then
				return expression
			end
		end
	else
		local tail = assert(source:match("self%._enabled%s*=%s*(.*)"), "Missing enabled assignment")
		local lines, depth = {}, 0
		for line in (tail .. "\n"):gmatch("(.-)\n") do
			if
				#lines > 0
				and depth == 0
				and not line:match("^%s+and%s")
				and not line:match("^%s+or%s")
			then
				break
			end
			table.insert(lines, line)
			local _, opened = line:gsub("%(", "")
			local _, closed = line:gsub("%)", "")
			depth += opened - closed
		end
		return table.concat(lines, "\n")
	end
	error("Missing production session guard")
end

local checked = 0
for _, gate in gates do
	local source = fs.readFile(gate.path)
	local expression = gateExpression(source, gate.kind)
	assert(
		expression:find("IsStudio", 1, true)
			and expression:find('"DEV"', 1, true)
			and expression:find('"solo_local"', 1, true)
			and expression:find('"team_local"', 1, true),
		"Production guard lost a local mode, Studio or DEV constraint: " .. gate.path
	)
	local code = "return " .. (if gate.kind == "reject" then "not (" else "(") .. expression .. ")"
	for _, mode in { "solo_local", "team_local", "external", "team_public", "solo", "", 123, false } do
		for _, studio in { true, false } do
			for _, environment in { "DEV", "PROD", "TEST" } do
				local config = { Environment = environment, Game = { SessionMode = mode } }
				local run = {
					IsStudio = function()
						return studio
					end,
				}
				local chunk = assert(loadstring(code, gate.path .. " session guard"))
				setfenv(
					chunk,
					{ RunService = run, run = run, Config = config, context = { Config = config } }
				)
				local expected = studio
					and environment == "DEV"
					and (mode == "solo_local" or mode == "team_local")
				assert(
					chunk() == expected,
					"Wrong production session policy: " .. gate.path .. " / " .. tostring(mode)
				)
				checked += 1
			end
		end
	end
end

-- Actual RoundService module lifecycle: only the explicit team_local server
-- coordinator starts. Legacy solo fixtures do not authorize a live solo service.
local serviceSource = fs.readFile("src/server/Services/RoundService.luau")
local serviceCases = 0
for _, mode in { "team_local", "solo_local", "external", "team_public", "", 123, false } do
	for _, studio in { true, false } do
		for _, environment in { "DEV", "PROD", "TEST" } do
			local newCalls, startCalls, warnings = 0, 0, 0
			local context = {
				Config = { Environment = environment, Game = { SessionMode = mode } },
				Log = {
					Warn = function()
						warnings += 1
					end,
				},
			}
			local team = {
				new = function(value)
					assert(value == context)
					newCalls += 1
					return {
						Start = function()
							startCalls += 1
						end,
					}
				end,
			}
			local node = {}
			function node:WaitForChild()
				return self
			end
			node.Parent = { Parent = node }
			local chunk = assert(loadstring(serviceSource, "RoundService session lifecycle"))
			setfenv(
				chunk,
				setmetatable({
					game = {
						GetService = function(_, name)
							assert(name == "RunService")
							return {
								IsStudio = function()
									return studio
								end,
							}
						end,
					},
					script = node,
					require = function()
						return team
					end,
				}, { __index = getfenv() })
			)
			local service = chunk()
			service:Init(context)
			service:Start()
			local expected = studio and environment == "DEV" and mode == "team_local"
			assert(
				newCalls == (if expected then 1 else 0)
					and startCalls == (if expected then 1 else 0),
				"RoundService started outside the explicit Studio DEV team mode"
			)
			assert(warnings == (if expected then 0 else 1))
			serviceCases += 1
		end
	end
end

print(
	"PASS all 9 production client/farm/corn session guards: "
		.. tostring(checked)
		.. " verbatim guard executions accept solo_local/team_local only in Studio DEV; actual RoundService Init/Start: "
		.. tostring(serviceCases)
		.. " cases require team_local. External/unknown modes, non-Studio and non-DEV stay inactive. Complete Bootstrap readiness is covered separately; no native-client acceptance claim."
)
