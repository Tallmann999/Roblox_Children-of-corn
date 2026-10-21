-- Real CornAppearance over a deterministic mesh API adapter. This exercises
-- caching, destructive ApplyMesh side effects and failure cleanup, not GPU output.
local fs = require("@lune/fs")
local r = require("@lune/roblox")
local CF, V3 = r.CFrame, r.Vector3
local source = fs.readFile("src/shared/Game/CornAppearance.luau")
local assertions = 0
local function check(condition, message)
	assertions += 1
	assert(condition, message)
end
local PROPERTIES = {
	"CFrame",
	"Size",
	"PivotOffset",
	"TextureID",
	"TextureContent",
	"Color",
	"Material",
	"MaterialVariant",
	"Transparency",
	"Reflectance",
	"Anchored",
	"CanCollide",
	"CanTouch",
	"CanQuery",
	"CastShadow",
	"DoubleSided",
	"CollisionGroup",
	"Massless",
	"CustomPhysicalProperties",
}
local Enum = setmetatable({
	ContentSourceType = { None = "None", Object = "Object", Opaque = "Opaque", Uri = "Uri" },
	CreateContentResult = { Success = "Success", StorageLimitExceeded = "StorageLimitExceeded" },
}, { __index = r.Enum })
local function content(kind, value)
	return {
		SourceType = kind,
		Object = if kind == "Object" then value else nil,
		Uri = if kind == "Uri" then value else "",
		Data = value,
	}
end
local function runTogether(...)
	local threads, results = {}, {}
	for index, callback in { ... } do
		threads[index] = coroutine.create(function()
			results[index] = table.pack(callback())
		end)
	end
	for _ = 1, 10000 do
		local running = false
		for _, thread in threads do
			if coroutine.status(thread) ~= "dead" then
				running = true
				local ok, problem = coroutine.resume(thread)
				assert(ok, problem)
			end
		end
		if not running then
			return results
		end
	end
	error("Private corn bake deadlocked")
end
local function fixture()
	local state = {
		originals = {},
		carriers = {},
		clones = {},
		snapshots = {},
		baked = {},
		bakes = 0,
		creates = 0,
		applies = 0,
		cloneCalls = 0,
		geometryCalls = 0,
		requires = 0,
		serviceCalls = 0,
		yields = 0,
		fail = nil,
	}
	local methods = {}
	local function fail(kind, call)
		local planned = state.fail
		if planned and planned.kind == kind and planned.call == call then
			state.fail = nil
			return true
		end
		return false
	end
	local newPart
	newPart = function(kind)
		local item = {
			_kind = kind,
			_attrs = {},
			_tags = {},
			_writes = 0,
			_values = {
				Name = "MeshPart",
				Archivable = true,
				CFrame = CF.identity,
				Size = V3.one,
				PivotOffset = CF.identity,
				TextureID = "",
				TextureContent = content("None"),
				MeshContent = content("None"),
				Color = r.Color3.new(1, 1, 1),
				Material = r.Enum.Material.Plastic,
				MaterialVariant = "",
				Transparency = 0,
				Reflectance = 0,
				Anchored = false,
				CanCollide = true,
				CanTouch = true,
				CanQuery = true,
				CastShadow = true,
				DoubleSided = false,
				CollisionGroup = "Default",
				Massless = false,
				CustomPhysicalProperties = { default = true },
				CollisionFidelity = r.Enum.CollisionFidelity.Box,
				RenderFidelity = r.Enum.RenderFidelity.Automatic,
			},
		}
		return setmetatable(item, {
			__index = function(self, key)
				return methods[key] or self._values[key]
			end,
			__newindex = function(self, key, value)
				if
					self._kind == "clone"
					and key == "TextureContent"
					and fail("restore", state.applies)
				then
					error("Injected texture restoration failure")
				end
				if key == "TextureID" then
					self._values.TextureContent =
						content(if value == "" then "None" else "Uri", value)
				elseif key == "TextureContent" then
					self._values.TextureID = if value.SourceType == "Uri" then value.Uri else ""
				end
				self._values[key] = value
				self._writes += 1
			end,
		})
	end
	function methods:IsA(class)
		return class == "MeshPart" or class == "BasePart"
	end
	function methods:GetAttribute(name)
		return self._attrs[name]
	end
	function methods:Clone()
		state.cloneCalls += 1
		if fail("clone", state.cloneCalls) then
			return nil
		end
		local result = newPart("clone")
		result._values = table.clone(self._values)
		result._attrs = table.clone(self._attrs)
		result._tags = table.clone(self._tags)
		table.insert(state.clones, result)
		return result
	end
	function methods:ApplyMesh(other)
		state.applies += 1
		self.MeshContent = other.MeshContent
		-- Deliberately destroy every preserved property, not just geometry: this
		-- catches the native-observed texture loss and regressions in copy ordering.
		for _, property in PROPERTIES do
			if property ~= "TextureContent" then
				self[property] = other[property]
			end
		end
		self._values.TextureContent = other.TextureContent
		self.CollisionFidelity = other.CollisionFidelity
		self.RenderFidelity = other.RenderFidelity
		if fail("apply", state.applies) then
			error("Injected partial ApplyMesh failure")
		end
	end
	function methods:Destroy()
		self._values.Destroyed = true
	end
	local function wait()
		state.yields += 1
		coroutine.yield()
	end
	local service = {}
	function service:CreateDataModelContentAsync(input)
		state.bakes += 1
		check(input.SourceType == "Object", "Bake input changed canonical content kind")
		check(not input.Object.Destroyed, "Canonical EditableMesh was destroyed")
		wait()
		if fail("bakeError", state.bakes) then
			error("Injected bake error")
		end
		if fail("bakeResult", state.bakes) then
			return "StorageLimitExceeded", content("None")
		end
		if fail("bakeType", state.bakes) then
			return "Success", input
		end
		local baked = content("Opaque", input.Object.Geometry)
		table.insert(state.baked, baked)
		return "Success", baked
	end
	function service:CreateMeshPartAsync(baked, options)
		state.creates += 1
		check(baked.SourceType == "Opaque", "Carrier received dynamic geometry")
		check(
			options.CollisionFidelity == r.Enum.CollisionFidelity.Box,
			"Original collision fidelity was not supplied"
		)
		check(
			options.RenderFidelity == r.Enum.RenderFidelity.Automatic,
			"Original render fidelity was not supplied"
		)
		wait()
		if fail("createError", state.creates) then
			error("Injected static carrier error")
		end
		if fail("createNil", state.creates) then
			return nil
		end
		local carrier = newPart("carrier")
		carrier._values.MeshContent = if fail("carrierBinding", state.creates)
			then content("None")
			else baked
		carrier._values.CollisionFidelity = if fail("fidelity", state.creates)
			then r.Enum.CollisionFidelity.Hull
			else options.CollisionFidelity
		carrier._values.RenderFidelity = options.RenderFidelity
		table.insert(state.carriers, carrier)
		return carrier
	end
	local geometry = {}
	function geometry.CornTemplate(index, lod)
		state.geometryCalls += 1
		local key = "Corn_" .. string.char(64 + index) .. "_" .. lod
		if state.bad == "duplicate" and state.geometryCalls == 2 then
			return state.originals.Corn_A_Near
		end
		if not state.originals[key] then
			local part = newPart("original")
			local n = state.geometryCalls
			local texture = if n % 3 == 0
				then content("None")
				elseif n % 3 == 1 then content("Uri", "rbxassetid://103653296385119")
				else content("Opaque", { texture = n })
			part._values = {
				Name = key,
				Archivable = true,
				MeshContent = content("Object", { Geometry = { key = key }, Destroyed = false }),
				Size = V3.new(2 + index / 10, 8, 2.1 + index / 10),
				CFrame = CF.new(0.17, 4, -0.09),
				PivotOffset = CF.identity,
				TextureID = if texture.SourceType == "Uri" then texture.Uri else "",
				TextureContent = texture,
				Color = r.Color3.new(0.4, 0.2, 0.1),
				Material = r.Enum.Material.SmoothPlastic,
				MaterialVariant = "Corn",
				Transparency = 0,
				Reflectance = 0.07,
				Anchored = true,
				CanCollide = false,
				CanTouch = false,
				CanQuery = false,
				CastShadow = false,
				DoubleSided = true,
				CollisionGroup = "CornArt",
				Massless = true,
				CustomPhysicalProperties = if n % 2 == 0 then nil else { density = n },
				CollisionFidelity = r.Enum.CollisionFidelity.Box,
				RenderFidelity = r.Enum.RenderFidelity.Automatic,
			}
			part._attrs = {
				HarvestGeometryOwner = "harvest_warden_v1",
				HarvestAssetKey = key,
				corn_project_id = "children_of_corn",
				CornPlantTemplateOwned = true,
				HarvestRootOffset = V3.new(0.17, 4, -0.09),
				HarvestMeshKey = key .. "/leaf",
				unrelatedAuthorValue = "retained",
			}
			part._tags = { "retained-art-tag" }
			state.originals[key] = part
			if state.bad == "owner" then
				part._attrs.HarvestGeometryOwner = "foreign"
			elseif state.bad == "project" then
				part._attrs.corn_project_id = "foreign"
			elseif state.bad == "asset" then
				part._attrs.HarvestAssetKey = "different_shape"
			elseif state.bad == "owned" then
				part._attrs.CornPlantTemplateOwned = nil
			elseif state.bad == "root" then
				part._attrs.HarvestRootOffset = nil
			elseif state.bad == "height" then
				part._values.Size = V3.new(2, 12, 2)
			elseif state.bad == "pivot" then
				part._values.PivotOffset = CF.new(1, 0, 0)
			elseif state.bad == "physics" then
				part._values.CanQuery = true
			elseif state.bad == "archivable" then
				part._values.Archivable = false
			end
			state.snapshots[part] = table.clone(part._values)
		end
		return state.originals[key]
	end
	local fn = assert(loadstring(source, "CornAppearance"))
	setfenv(
		fn,
		setmetatable({
			game = {
				GetService = function(_, name)
					state.serviceCalls += 1
					check(name == "AssetService", "Unexpected service lookup")
					return service
				end,
			},
			script = {
				Parent = {
					WaitForChild = function(_, name)
						check(name == "HarvestArtGeometry", "Unexpected geometry lookup")
						return name
					end,
				},
			},
			require = function()
				state.requires += 1
				return geometry
			end,
			CFrame = CF,
			Vector3 = V3,
			Enum = Enum,
			task = { wait = wait },
		}, { __index = getfenv() })
	)
	return fn(), state
end
local function preserved(state)
	for original, snapshot in state.snapshots do
		check(original._writes == 0, "Canonical template was written")
		check(
			not original.Destroyed and not original.MeshContent.Object.Destroyed,
			"Canonical geometry was destroyed"
		)
		for key, value in snapshot do
			check(original[key] == value, "Canonical property changed: " .. key)
		end
	end
end
local function released(state)
	for _, carrier in state.carriers do
		check(carrier.Destroyed, "Temporary static carrier leaked")
	end
end
local Appearance, state = fixture()
check(
	Appearance.IsDry("hard") and Appearance.IsValidMode("medium"),
	"Simple appearance API changed"
)
check(state.serviceCalls == 0 and state.requires == 0, "A/simple API eagerly builds B geometry")
local results = runTogether(Appearance.DetailedTemplates, Appearance.DetailedTemplates)
local templates = results[1][1]
check(results[2][1] == templates, "Concurrent callers received separate template banks")
check(
	state.bakes == 12 and state.creates == 12 and state.applies == 12,
	"Expected one bake per variety/LOD"
)
check(
	state.geometryCalls == 12 and state.requires == 1 and state.serviceCalls == 1,
	"Duplicate concurrent construction"
)
check(Appearance.DetailedTemplates() == templates and state.bakes == 12, "Cached templates rebaked")
for lod, list in templates do
	check(#list == 4, "Missing corn variety")
	for index, part in list do
		local original = state.originals[Appearance.DetailedKey(index, lod)]
		check(
			part ~= original and not part.Destroyed and part.Parent == nil,
			"Template ownership/parent changed"
		)
		check(part.MeshContent.SourceType == "Opaque", "Private corn remains an EditableMesh")
		check(
			part.MeshContent.Data == original.MeshContent.Object.Geometry,
			"Baked geometry differs from original"
		)
		check(
			part.Size == V3.new(original.Size.X, 10, original.Size.Z),
			"Private height/width changed"
		)
		for _, name in PROPERTIES do
			if name ~= "Size" then
				check(
					part[name] == original[name],
					"ApplyMesh lost exact appearance/physics: " .. name
				)
			end
		end
		for name, value in original._attrs do
			check(part:GetAttribute(name) == value, "Clone lost metadata: " .. name)
		end
		check(part._tags[1] == original._tags[1], "Clone lost source tags")
		check(
			Appearance.IsDetailedPlant(part, index, lod),
			"Static templates rejected by renderer contract"
		)
		local root = V3.new(31, 14.4, -27)
		local frame = Appearance.DetailedPivot(part, root, 0)
		check(
			(frame.Position - (root + V3.new(0.17, 5, -0.09))).Magnitude < 0.00001,
			"Static conversion changed planted root placement"
		)
	end
end
preserved(state)
released(state)
for _, kind in
	{
		"bakeError",
		"bakeResult",
		"bakeType",
		"createError",
		"createNil",
		"clone",
		"apply",
		"restore",
		"carrierBinding",
		"fidelity",
	}
do
	for _, call in { 1, 7, 12 } do
		local subject, failed = fixture()
		failed.fail = { kind = kind, call = call }
		local result = runTogether(function()
			return pcall(subject.DetailedTemplates)
		end)[1]
		check(result[1] == false, "Unsafe partial static bank accepted: " .. kind)
		for _, clone in failed.clones do
			check(clone.Destroyed, "Partial private bank leaked after " .. kind)
		end
		released(failed)
		preserved(failed)
		local retried = runTogether(subject.DetailedTemplates)[1][1]
		check(
			retried and #retried.Near == 4 and #retried.Mid == 4 and #retried.Far == 4,
			"Failed construction poisoned retry: " .. kind
		)
		check(subject.DetailedTemplates() == retried, "Retry was not cached")
		released(failed)
		preserved(failed)
	end
end
for _, kind in
	{
		"owner",
		"project",
		"asset",
		"owned",
		"root",
		"height",
		"pivot",
		"physics",
		"archivable",
		"duplicate",
	}
do
	local subject, failed = fixture()
	failed.bad = kind
	local result = runTogether(function()
		return pcall(subject.DetailedTemplates)
	end)[1]
	check(not result[1], "Unknown canonical template accepted: " .. kind)
	check(
		failed.bakes == (if kind == "duplicate" then 1 else 0),
		"Unknown template reached static bake"
	)
	for _, clone in failed.clones do
		check(clone.Destroyed, "Unknown template retained partial bank")
	end
	released(failed)
	preserved(failed)
end
local failing, concurrent = fixture()
concurrent.fail = { kind = "bakeResult", call = 7 }
local recovered = runTogether(function()
	return pcall(failing.DetailedTemplates)
end, failing.DetailedTemplates)
check(
	not recovered[1][1] and recovered[2][1] ~= nil,
	"Concurrent waiter did not recover after builder failure"
)
check(
	concurrent.bakes == 19 and failing.DetailedTemplates() == recovered[2][1],
	"Concurrent recovery duplicated or poisoned cache"
)
released(concurrent)
preserved(concurrent)
print(
	"PASS: "
		.. assertions
		.. " corn static-content assertions; 12 shapes/LOD, exact appearance, concurrent cache/recovery, 30 failures/cleanup/retry, 10 ownership guards; no GPU claim"
)
