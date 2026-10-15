-- Exact saved input, in-memory guarded installer fixtures only.
-- No place write/reserialization, engine rendering or runtime blink claim.
local adapter = require("./scene-adapter")
local fs, r, I = adapter.fs, adapter.r, adapter.I
local path = "place/Children_of_corn.before-rustle-20261014.rbxl"
local bytes = fs.readFile(path)
local source = fs.readFile("scripts/install-exit-beacon.luau")
local function setup()
	local place = r.deserializePlace(bytes)
	place:GetService("RunService")
	place:GetService("ChangeHistoryService")
	return place
end
local function sign(place)
	return place:GetService("Workspace").CornMap.Props.VillageRoad.ExitSign
end
local function run(place, code, running, studio)
	local gameProxy = {
		GetService = function(_, name)
			if name == "RunService" then
				return {
					IsRunning = function()
						return running == true
					end,
					IsStudio = function()
						return studio ~= false
					end,
				}
			end
			return place:GetService(name)
		end,
	}
	local fn = assert(loadstring(code or source))
	setfenv(
		fn,
		setmetatable({
			game = gameProxy,
			workspace = place:GetService("Workspace"),
			CFrame = r.CFrame,
			Vector3 = r.Vector3,
			Enum = r.Enum,
		}, { __index = getfenv() })
	)
	return pcall(fn)
end
local TRACKED = {
	"CFrame",
	"Size",
	"Material",
	"Color",
	"Anchored",
	"Transparency",
	"CanCollide",
	"CanTouch",
	"CanQuery",
	"CastShadow",
}
local function snapshot(place)
	local result = {}
	for _, item in place:GetDescendants() do
		local state = {
			parent = item.Parent,
			name = item.Name,
			class = item.ClassName,
			attributes = item:GetAttributes(),
			tags = item:GetTags(),
			properties = {},
		}
		if item:IsA("BasePart") then
			for _, key in TRACKED do
				state.properties[key] = item[key]
			end
		end
		if item:IsA("LuaSourceContainer") then
			state.properties.Source = item.Source
		end
		if item:IsA("SurfaceGui") then
			state.properties.Enabled = item.Enabled
			state.properties.AlwaysOnTop = item.AlwaysOnTop
			state.properties.PixelsPerStud = item.PixelsPerStud
		end
		if item:IsA("TextLabel") then
			state.properties.Text = item.Text
		end
		if item:IsA("Lighting") then
			for _, key in
				{ "Brightness", "Ambient", "OutdoorAmbient", "FogStart", "FogEnd", "FogColor" }
			do
				state.properties[key] = item[key]
			end
		end
		result[item] = state
	end
	return result
end
local function sameTable(a, b)
	for key, value in a do
		assert(b[key] == value, "Table value changed: " .. tostring(key))
	end
	for key, value in b do
		assert(a[key] == value, "Table value added: " .. tostring(key))
	end
end
local function unchanged(place, before, approved, rollbackFrame, approvedSurface)
	local count, expected = 0, 0
	for _, item in place:GetDescendants() do
		count += 1
		assert(before[item], "An instance was added")
	end
	for item, state in before do
		expected += 1
		assert(
			item.Parent == state.parent
				and item.Name == state.name
				and item.ClassName == state.class
		)
		sameTable(state.attributes, item:GetAttributes())
		sameTable(state.tags, item:GetTags())
		for key, value in state.properties do
			if item == approved and key == "Size" then
				assert((item.Size - value * 3).Magnitude < 0.00001)
			elseif item == approved and key == "CFrame" then
				local delta = item.CFrame.Position - value.Position
				assert((delta - r.Vector3.new(0, 3.2, 0)).Magnitude < 0.00001)
				assert(item.CFrame.Rotation == value.Rotation, "Exit rotation changed")
			elseif item == rollbackFrame and key == "CFrame" then
				-- Lune's f32 CFrame assignment at saved Y~36 can round by one
				-- ULP (3.814697265625e-6). Permit that measured adapter effect
				-- only on the deliberately written-and-restored sign position.
				assert(item.CFrame.Rotation == value.Rotation, "Rollback rotation changed")
				assert(
					(item.CFrame.Position - value.Position).Magnitude <= 0.000004,
					"Rollback moved sign beyond one f32 ULP"
				)
			elseif item == rollbackFrame and key == "Size" then
				-- The same Lune bounds reconstruction rounds restored Size by
				-- a few f32 units. Only this deliberately written property gets
				-- the explicit <1e-5 adapter allowance; all others remain exact.
				assert(
					(item.Size - value).Magnitude < 0.00001,
					"Rollback size drift exceeds f32 adapter bound"
				)
			elseif item == approvedSurface and key == "PixelsPerStud" then
				assert(value == 48 and item.PixelsPerStud == 16, "Unknown exit text density change")
			elseif item == approvedSurface and key == "AlwaysOnTop" and value == true then
				assert(item.AlwaysOnTop == false, "Known intermediate overlay was not removed")
			else
				assert(
					item[key] == value,
					"Unapproved change: "
						.. item:GetFullName()
						.. "/"
						.. key
						.. " before="
						.. tostring(value)
						.. " after="
						.. tostring(item[key])
				)
			end
		end
	end
	assert(count == expected, "An instance was removed")
end
local place = setup()
local before, target = snapshot(place), sign(place)
local oldBottom = target.CFrame.Position.Y - target.Size.Y / 2
local surface = target.ExitTextSurface
assert(surface.AlwaysOnTop == false)
assert(surface.PixelsPerStud == 48)
local ok, result = run(place)
assert(ok, result)
assert(result.changed == 3 and result.lower_edge_preserved and result.physical_letters_scale == 3)
assert(result.pixels_per_stud == 16 and result.always_on_top == false)
unchanged(place, before, target, nil, surface)
assert(math.abs(target.CFrame.Position.Y - target.Size.Y / 2 - oldBottom) < 0.00001)
local installed = snapshot(place)
ok, result = run(place)
assert(ok and result.changed == 0 and result.repeated)
unchanged(place, installed)

-- Migrate the exact already-installed geometry without touching it again.
local partial = setup()
local partialSign = sign(partial)
partialSign.Size *= 3
partialSign.CFrame += r.Vector3.new(0, 3.2, 0)
local partialSurface = partialSign.ExitTextSurface
local partialBefore = snapshot(partial)
ok, result = run(partial)
assert(
	ok and result.changed == 1 and result.pixels_per_stud == 16 and result.always_on_top == false
)
unchanged(partial, partialBefore, nil, nil, partialSurface)
local completedPartial = snapshot(partial)
ok, result = run(partial)
assert(ok and result.changed == 0 and result.repeated)
unchanged(partial, completedPartial)

-- The explicitly installed intermediate overlay is undone without moving or
-- resizing the known enlarged geometry.
local intermediate = setup()
local intermediateSign = sign(intermediate)
intermediateSign.Size *= 3
intermediateSign.CFrame += r.Vector3.new(0, 3.2, 0)
intermediateSign.ExitTextSurface.AlwaysOnTop = true
local intermediateBefore = snapshot(intermediate)
ok, result = run(intermediate)
assert(
	ok and result.changed == 2 and result.pixels_per_stud == 16 and result.always_on_top == false
)
unchanged(intermediate, intermediateBefore, nil, nil, intermediateSign.ExitTextSurface)
local intermediateFinal = snapshot(intermediate)
ok, result = run(intermediate)
assert(ok and result.changed == 0 and result.repeated)
unchanged(intermediate, intermediateFinal)

local rejected = 0
for _, kind in
	{
		"wrong-project",
		"wrong-scene",
		"manual-size",
		"manual-frame",
		"partial-size",
		"partial-frame",
		"ownership",
		"topology",
		"label",
		"premature-overlay",
		"unknown-density",
		"premature-density",
		"enlarged-unknown-density",
		"final-density-with-overlay",
		"running",
		"not-studio",
	}
do
	local fixture = setup()
	local item = sign(fixture)
	if kind == "wrong-project" then
		fixture:GetService("Workspace").CornMap:SetAttribute("corn_project_id", "other")
	end
	if kind == "wrong-scene" then
		local foreign = I.new("Folder")
		foreign.Name, foreign.Parent = "Asmr_Base", fixture:GetService("Workspace")
	end
	if kind == "manual-size" then
		item.Size += r.Vector3.xAxis
	end
	if kind == "manual-frame" then
		item.CFrame += r.Vector3.xAxis
	end
	if kind == "partial-size" then
		item.Size *= 3
	end
	if kind == "partial-frame" then
		item.CFrame += r.Vector3.new(0, 3.2, 0)
	end
	if kind == "ownership" then
		item:SetAttribute("CornRoadExitOwned", false)
	end
	if kind == "topology" then
		item.ExitTextSurface:Destroy()
	end
	if kind == "label" then
		item.ExitTextSurface.ExitText.Text = "Авторская надпись"
	end
	if kind == "premature-overlay" then
		item.ExitTextSurface.AlwaysOnTop = true
	end
	if kind == "unknown-density" then
		item.ExitTextSurface.PixelsPerStud = 24
	end
	if kind == "premature-density" then
		item.ExitTextSurface.PixelsPerStud = 16
	end
	if kind == "enlarged-unknown-density" or kind == "final-density-with-overlay" then
		item.Size *= 3
		item.CFrame += r.Vector3.new(0, 3.2, 0)
		item.ExitTextSurface.PixelsPerStud = if kind == "enlarged-unknown-density" then 32 else 16
		if kind == "final-density-with-overlay" then
			item.ExitTextSurface.AlwaysOnTop = true
		end
	end
	local state = snapshot(fixture)
	local accepted = run(fixture, nil, kind == "running", kind ~= "not-studio")
	assert(not accepted, "Unsafe installer fixture accepted: " .. kind)
	unchanged(fixture, state)
	rejected += 1
end
local injected, matches = source:gsub(
	"sign%.Size = afterSize",
	'sign.Size = afterSize\nerror("Injected failure after Size")'
)
assert(matches == 1)
local rollback = setup()
local original = snapshot(rollback)
local accepted, problem = run(rollback, injected)
assert(not accepted and tostring(problem):find("rolled back", 1, true))
local rollbackTarget = sign(rollback)
local rollbackDelta = rollbackTarget.CFrame.Position
	- original[rollbackTarget].properties.CFrame.Position
local rollbackSizeDelta = rollbackTarget.Size - original[rollbackTarget].properties.Size
unchanged(rollback, original, nil, rollbackTarget)
local densityFailure, densityMatches = source:gsub(
	"surface%.PixelsPerStud = 16",
	'surface.PixelsPerStud = 16\nerror("Injected failure after density")'
)
assert(densityMatches == 1)
local rollbackOverlay = setup()
local overlayOriginal = snapshot(rollbackOverlay)
accepted, problem = run(rollbackOverlay, densityFailure)
assert(not accepted and tostring(problem):find("rolled back", 1, true))
unchanged(rollbackOverlay, overlayOriginal, nil, sign(rollbackOverlay))
assert(sign(rollbackOverlay).ExitTextSurface.AlwaysOnTop == false, "Authored overlay flag changed")
assert(sign(rollbackOverlay).ExitTextSurface.PixelsPerStud == 48, "Density rollback failed")

local overlayFailure, overlayMatches = source:gsub(
	"surface%.AlwaysOnTop = false",
	'surface.AlwaysOnTop = false\nerror("Injected failure after removing intermediate overlay")'
)
assert(overlayMatches == 1)
local rollbackIntermediate = setup()
local rollbackIntermediateSign = sign(rollbackIntermediate)
rollbackIntermediateSign.Size *= 3
rollbackIntermediateSign.CFrame += r.Vector3.new(0, 3.2, 0)
rollbackIntermediateSign.ExitTextSurface.AlwaysOnTop = true
local savedIntermediate = snapshot(rollbackIntermediate)
accepted, problem = run(rollbackIntermediate, overlayFailure)
assert(not accepted and tostring(problem):find("rolled back", 1, true))
unchanged(rollbackIntermediate, savedIntermediate)
assert(
	rollbackIntermediateSign.ExitTextSurface.PixelsPerStud == 48
		and rollbackIntermediateSign.ExitTextSurface.AlwaysOnTop == true
)
assert(fs.readFile(path) == bytes, "Immutable baseline bytes changed")
print(
	"PASS: exact before-rustle in-memory sign 3x/Y+3.2/lower edge/PPs48to16/AOTfalse, full repeat + recognized geometry/overlay migrations, "
		.. rejected
		.. " guard refusals, injected-after-Size/density/intermediate-overlay rollback (sign-only f32 delta="
		.. tostring(rollbackDelta.Magnitude)
		.. ",size delta="
		.. tostring(rollbackSizeDelta.Magnitude)
		.. ") and immutable bytes. No Studio/render/blink claim."
)
