-- In-memory file-backed authoring/refusal/rollback fixture. Never writes scene bytes.
local adapter = require("./scene-adapter")
local fs, r, I, CF, V3 = adapter.fs, adapter.r, adapter.I, adapter.CF, adapter.V3
local bytes = fs.readFile("place/Children_of_corn.before-autumn-20261012.rbxl")
local source = fs.readFile("scripts/install-road-and-exit.luau")
local MESH = "rbxassetid://104111861186519"
local function setup(withPreview)
	local place = r.deserializePlace(bytes)
	for _, name in { "RunService", "ChangeHistoryService" } do
		place:GetService(name)
	end
	-- The binary uses MeshContent Uri; Lune lacks the legacy MeshId getter default.
	-- Set that equivalent legacy read on in-memory fixture objects only.
	local xml = r.serializePlace(place, true)
	assert(xml:find(MESH, 1, true), "Saved original corn URI missing")
	for _, item in place:GetDescendants() do
		if item:IsA("MeshPart") then
			item.MeshId = MESH
		end
	end
	if withPreview then
		local preview = place:GetService("Workspace").CornMap.EditorPreview
		local clone = preview:GetChildren()[1]:Clone()
		clone.Name = "Corn"
		clone.CFrame = CF.new(0, 18.9, 120) * clone.CFrame.Rotation
		clone.Parent = preview
	end
	return place
end
local function execute(place, patched, running, studio)
	local gameProxy = {
		GetService = function(_, name)
			if name == "RunService" then
				return {
					IsStudio = function()
						return studio ~= false
					end,
					IsRunning = function()
						return running == true
					end,
				}
			end
			return place:GetService(name)
		end,
	}
	local fn = assert(loadstring(patched or source))
	setfenv(
		fn,
		setmetatable({
			game = gameProxy,
			Instance = I,
			CFrame = CF,
			Vector3 = V3,
			Vector2 = r.Vector2,
			UDim2 = r.UDim2,
			Color3 = r.Color3,
			Enum = r.Enum,
			print = function() end,
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
			attrs = item:GetAttributes(),
			tags = item:GetTags(),
			props = {},
		}
		if item:IsA("BasePart") then
			for _, key in TRACKED do
				state.props[key] = item[key]
			end
		end
		if item:IsA("LuaSourceContainer") then
			state.props.Source = item.Source
		end
		result[item] = state
	end
	return result
end
local function equalMap(a, b)
	for key, value in a do
		assert(b[key] == value, "Original attribute changed: " .. key)
	end
	for key in b do
		assert(a[key] ~= nil, "New original attribute")
	end
end
local function preserved(place, before, allowed, newAllowed)
	for item, state in before do
		assert(
			item.Parent == state.parent
				and item.Name == state.name
				and item.ClassName == state.class,
			"Original identity/parent changed"
		)
		equalMap(state.attrs, item:GetAttributes())
		assert(#state.tags == #item:GetTags(), "Original tags changed")
		for _, tag in state.tags do
			assert(item:HasTag(tag))
		end
		for key, value in state.props do
			if allowed and allowed[item] and key == "Transparency" then
				assert(item.Transparency == 1)
			else
				assert(
					item[key] == value,
					"Original property changed: " .. item:GetFullName() .. "/" .. key
				)
			end
		end
	end
	for _, item in place:GetDescendants() do
		if not before[item] then
			assert(
				newAllowed
					and item:GetAttribute("CornRoadExitOwned") == true
					and item:GetAttribute("corn_project_id") == "children_of_corn",
				"Unexpected new instance"
			)
		end
	end
end
local p = setup(true)
local before = snapshot(p)
local m = p:GetService("Workspace").CornMap
local ok, problem = execute(p)
assert(ok, tostring(problem))
local road = m.Props.VillageRoad
assert((road.RoadSurface.Size - V3.new(14, 0.08, 840)).Magnitude < 0.00001)
assert(
	road.RoadClearance.Size == V3.new(18, 10, 840)
		and road.RoadClearance:HasTag("corn_no_corn_zone")
)
local floor = m.Ground.CFrame.Position.Y + m.Ground.Size.Y / 2
assert(
	math.abs(road.RoadSurface.CFrame.Position.Y + road.RoadSurface.Size.Y / 2 - floor - 0.04)
		< 0.0001
)
assert(
	road.RoadSurface.CFrame.Position.X == m.FieldZone.CFrame.Position.X
		and road.RoadSurface.CFrame.Position.Z == m.FieldZone.CFrame.Position.Z
)
assert(#m.TorchMarkers:GetChildren() == 31)
local allowed, overviewCount, previewCount = {}, 0, 0
for _, ref in road.HiddenCornIndex:GetChildren() do
	assert(ref:IsA("ObjectValue") and before[ref.Value] and ref.Value.Transparency == 1)
	assert(
		ref:GetAttribute("OriginalTransparency") == 0
			and (ref:GetAttribute("OriginalFrame").Position - ref.Value.CFrame.Position).Magnitude < 0.0002
			and (ref:GetAttribute("OriginalSize") - ref.Value.Size).Magnitude < 0.00001
	)
	allowed[ref.Value] = true
	if ref.Value.Parent == m.EditorPreview then
		previewCount += 1
	else
		overviewCount += 1
	end
end
assert(overviewCount > 0 and previewCount > 0, "Fixture did not exercise both owned editor layers")
preserved(p, before, allowed, true)
for _, part in road:GetDescendants() do
	if part:IsA("BasePart") then
		assert(part.Anchored and not part.CanCollide and not part.CanTouch and not part.CanQuery)
	end
end
for row = 1, 8 do
	local torch = m.TorchMarkers[string.format("road_exit_row_%02d", row)]
	assert(
		torch:HasTag("corn_torch")
			and torch:GetAttribute("CornTorchOwned") == true
			and torch:GetAttribute("torch_id") == torch.Name
	)
	local base = torch.Pole.CFrame * CF.new(0, -6.5, 0)
	local localBase = m.EscapeGate.Door.CFrame:PointToObjectSpace(base.Position)
	assert(math.abs(localBase.X) == 10 and localBase.Z == -((row - 1) % 4 + 1) * 8)
	assert(math.abs(base.Position.Y - floor) < 0.0001)
end
for _, id in { "left", "right" } do
	local torch = m.TorchMarkers["road_exit_wall_" .. id]
	local angle = math.acos(math.clamp(torch.Pole.CFrame.UpVector:Dot(V3.yAxis), -1, 1))
	assert(math.abs(angle - math.pi / 4) < 0.0001, "Wall torch not45deg")
	for _, part in torch:GetDescendants() do
		if part:IsA("BasePart") then
			assert(not part.CanCollide and not part.CanQuery)
		end
	end
end
assert(
	road.ExitSign.Material == r.Enum.Material.Neon
		and road.ExitSign.ExitTextSurface.ExitText.Text == "ВЫХОД"
)
assert(
	road.ExitSign.CFrame.Position.Y - road.ExitSign.Size.Y / 2
		> m.EscapeGate.Header.CFrame.Position.Y + m.EscapeGate.Header.Size.Y / 2
)
-- Current actual exclusion code must prevent new runtime corn down the whole lane.
local layoutFn = assert(
	loadstring(
		fs.readFile("src/shared/Game/CornLayout.luau")
			:gsub("item%.Position", "item.CFrame.Position")
	)
)
setfenv(
	layoutFn,
	setmetatable({ CFrame = CF, Vector3 = V3, Vector2 = r.Vector2 }, { __index = getfenv() })
)
local layout = layoutFn()
local exclusions = layout.ReadExclusions(m, m.FieldZone)
for _, z in { -419, -200, 0, 200, 419 } do
	assert(
		layout.IsExcluded(V3.new(0, floor, z), exclusions),
		"Road failed existing corn exclusion"
	)
end
local installed = snapshot(p)
assert(execute(p))
preserved(p, installed, nil, false)
print(
	"PASS: road14x840/floor+.04, in-place overview+preview hide only, current exclusions,8row+2wall45 torches/31total, neon sign aboveHeader, original identity/gameplay/code preserved and exact repeat"
)
for _, kind in
	{
		"running",
		"notStudio",
		"wrong",
		"size",
		"tilted",
		"gate",
		"roadCollision",
		"torchForeign",
		"cornForeign",
		"cornMesh",
		"cornManual",
		"runtime",
	}
do
	local fixture = setup()
	local map = fixture:GetService("Workspace").CornMap
	if kind == "wrong" then
		local v = I.new("Folder")
		v.Name = "Asmr_Base"
		v.Parent = fixture:GetService("Workspace")
	end
	if kind == "size" then
		map.FieldZone.Size += V3.new(1, 0, 0)
	end
	if kind == "tilted" then
		map.FieldZone.CFrame *= CF.Angles(0.1, 0, 0)
	end
	if kind == "gate" then
		map.EscapeGate.InteractionAnchor.CFrame *= CF.new(1, 0, 0)
	end
	if kind == "roadCollision" then
		local v = I.new("Folder")
		v.Name = "VillageRoad"
		v.Parent = map.Props
	end
	if kind == "torchForeign" then
		local v = I.new("Model")
		v.Name = "AuthorManual"
		v.Parent = map.TorchMarkers
	end
	if kind == "cornForeign" then
		local v = I.new("Part")
		v.Parent = map.EditorFieldOverview
	end
	if kind == "cornMesh" then
		map.EditorFieldOverview:GetChildren()[1].MeshId = "rbxassetid://999"
	end
	if kind == "cornManual" then
		for _, v in map.EditorFieldOverview:GetChildren() do
			if math.abs(v.CFrame.Position.X) < 2 then
				v.Transparency = 0.3
				break
			end
		end
	end
	if kind == "runtime" then
		local v = I.new("Folder")
		v.Name = "CornRoundRuntime"
		v.Parent = map
	end
	local prior = snapshot(fixture)
	assert(
		not execute(fixture, nil, kind == "running", kind ~= "notStudio"),
		"Guard failed: " .. kind
	)
	preserved(fixture, prior, nil, false)
end
for _, kind in
	{
		"partialTorch",
		"roadGeometry",
		"roadForeign",
		"snapshot",
		"reference",
		"neonText",
		"wallAngle",
		"visibleAgain",
	}
do
	local fixture = setup()
	assert(execute(fixture))
	local map = fixture:GetService("Workspace").CornMap
	local road = map.Props.VillageRoad
	if kind == "partialTorch" then
		map.TorchMarkers.road_exit_row_01:Destroy()
	end
	if kind == "roadGeometry" then
		road.RoadSurface.Size += V3.new(1, 0, 0)
	end
	if kind == "roadForeign" then
		local v = I.new("Folder")
		v.Name = "AuthorManual"
		v.Parent = road
	end
	if kind == "snapshot" then
		road:SetAttribute("SourceDoorFrame", CF.identity)
	end
	if kind == "reference" then
		road.HiddenCornIndex:GetChildren()[1].Value = map.Ground
	end
	if kind == "neonText" then
		road.ExitSign.ExitTextSurface.ExitText.Text = "AUTHOR"
	end
	if kind == "wallAngle" then
		map.TorchMarkers.road_exit_wall_left.Pole.CFrame *= CF.Angles(0, 0, 0.2)
	end
	if kind == "visibleAgain" then
		road.HiddenCornIndex:GetChildren()[1].Value.Transparency = 0
	end
	local prior = snapshot(fixture)
	assert(not execute(fixture), "Repeat guard failed: " .. kind)
	preserved(fixture, prior, nil, false)
end
print("PASS:20 initial/repeat/manual/foreign/partial guards refuse before changing any instance")
for _, kind in { "roadPublished", "torchPublished", "cornHidden" } do
	local fixture = setup()
	local prior = snapshot(fixture)
	local patched, count
	if kind == "roadPublished" then
		patched, count = source:gsub(
			"road.Parent = props",
			'road.Parent = props\nerror("Injected road failure")'
		)
	elseif kind == "torchPublished" then
		patched, count = source:gsub(
			"model.Parent = torches",
			'model.Parent = torches\nerror("Injected torch failure")'
		)
	else
		patched, count = source:gsub(
			"entry.Part.Transparency = 1",
			'entry.Part.Transparency = 1\nerror("Injected visibility failure")'
		)
	end
	assert(count == 1, "Injection anchor changed: " .. kind)
	assert(not execute(fixture, patched))
	preserved(fixture, prior, nil, false)
end
assert(
	fs.readFile("place/Children_of_corn.before-autumn-20261012.rbxl") == bytes,
	"Input rbxl changed"
)
print(
	"PASS: failures after road/torch/visibility publication restore every original and remove only created tree; exact input bytes preserved"
)
