-- Focused B provider fixture over deterministic native-mesh API mocks.
-- No Studio, scene writes, geometry conversion, GPU or performance claims.
local fs = require("@lune/fs")
local r = require("@lune/roblox")
local CF, V3, C3 = r.CFrame, r.Vector3, r.Color3
local source = fs.readFile("variants/B/shared/Game/CornAppearance.luau")
local assertions = 0
local function check(value, message)
	assertions += 1
	assert(value, message)
end
local meshId, textureId = "rbxassetid://104111861186519", "rbxassetid://137803536172445"
local size = V3.new(3.0026558642674086, 8, 3.1309012101883917)
local Enum = setmetatable(
	{ ContentSourceType = { Uri = "Uri", Object = "Object" } },
	{ __index = r.Enum }
)
local function together(...)
	local results, threads = {}, {}
	for index, callback in { ... } do
		threads[index] = coroutine.create(function()
			results[index] = table.pack(callback())
		end)
	end
	for _ = 1, 100 do
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
	error("B green provider deadlocked")
end
local function fixture()
	local state = { calls = 0, clones = 0, created = {}, fail = nil, yields = 0 }
	local methods = {}
	local function failure(kind, call)
		if state.fail and state.fail.kind == kind and state.fail.call == call then
			state.fail = nil
			return true
		end
		return false
	end
	local function newPart()
		local part = setmetatable({
			_values = {
				Name = "MeshPart",
				MeshId = meshId,
				MeshContent = { SourceType = "Uri", Uri = meshId },
				MeshSize = size * 100,
				CFrame = CF.identity,
				PivotOffset = CF.identity,
				Size = V3.one,
				Archivable = true,
				Anchored = false,
				CanCollide = true,
				CanTouch = true,
				CanQuery = true,
				CastShadow = true,
				DoubleSided = false,
				Material = r.Enum.Material.Plastic,
				MaterialVariant = "",
				Color = C3.new(1, 1, 1),
				Transparency = 0,
				Reflectance = 0,
				Massless = false,
				CollisionGroup = "Default",
				CollisionFidelity = r.Enum.CollisionFidelity.Box,
				RenderFidelity = r.Enum.RenderFidelity.Precise,
			},
			_attrs = {},
			_children = {},
			_tags = {},
		}, {
			__index = function(self, key)
				return methods[key] or self._values[key]
			end,
			__newindex = function(self, key, value)
				self._values[key] = value
			end,
		})
		table.insert(state.created, part)
		return part
	end
	function methods:IsA(class)
		return class == "MeshPart" or class == "BasePart"
	end
	function methods:GetAttribute(key)
		return self._attrs[key]
	end
	function methods:GetAttributes()
		return table.clone(self._attrs)
	end
	function methods:SetAttribute(key, value)
		if key == "CornGreenTemplateVersion" and failure("decorate", #state.created) then
			error("Injected decoration failure")
		end
		self._attrs[key] = value
	end
	function methods:GetChildren()
		return table.clone(self._children)
	end
	function methods:GetTags()
		return table.clone(self._tags)
	end
	function methods:Destroy()
		self.Destroyed = true
		self.Parent = nil
	end
	function methods:Clone()
		state.clones += 1
		if failure("cloneNil", state.clones) then
			return nil
		elseif failure("cloneError", state.clones) then
			error("Injected clone failure")
		end
		local part = newPart()
		part._values = table.clone(self._values)
		part._attrs = table.clone(self._attrs)
		return part
	end
	local assetService = {}
	function assetService:CreateMeshPartAsync(content, options)
		state.calls += 1
		check(
			content.SourceType == "Uri" and content.Uri == meshId,
			"Provider did not load original URI"
		)
		check(
			options.CollisionFidelity == r.Enum.CollisionFidelity.Box,
			"Collision fidelity changed"
		)
		check(
			options.RenderFidelity == r.Enum.RenderFidelity.Precise,
			"Render fidelity differs from C"
		)
		state.yields += 1
		coroutine.yield()
		if failure("createError", state.calls) then
			error("Injected URI loading failure")
		elseif failure("createNil", state.calls) then
			return nil
		end
		local part = newPart()
		if failure("meshId", state.calls) then
			part.MeshId = "rbxassetid://1"
		elseif failure("content", state.calls) then
			part.MeshContent = { SourceType = "Object" }
		elseif failure("bounds", state.calls) then
			part.MeshSize = V3.new(100, 100, 100)
		elseif failure("attribute", state.calls) then
			part:SetAttribute("Foreign", true)
		elseif failure("child", state.calls) then
			part._children = { {} }
		elseif failure("tag", state.calls) then
			part._tags = { "Foreign" }
		end
		return part
	end
	local fn = assert(loadstring(source, "B CornAppearance"))
	setfenv(
		fn,
		setmetatable({
			game = {
				GetService = function(_, name)
					check(name == "AssetService", "Unexpected service: " .. name)
					return assetService
				end,
			},
			CFrame = CF,
			Vector3 = V3,
			Color3 = C3,
			Enum = Enum,
			Content = {
				fromUri = function(uri)
					return { SourceType = "Uri", Uri = uri }
				end,
			},
			task = {
				wait = function()
					coroutine.yield()
				end,
			},
		}, { __index = getfenv() })
	)
	return fn(), state
end
local appearance, state = fixture()
check(
	appearance.MeshId == meshId and appearance.GreenTextureId == textureId,
	"Wrong original asset"
)
check(appearance.DryTextureId == textureId, "Shared CornField would reintroduce dry texture")
check(appearance.DetailedHeight == 8, "Height differs from accepted C")
for _, mode in { "easy", "medium", "hard", "unknown" } do
	check(not appearance.IsDry(mode), "B became yellow in mode " .. mode)
end
check(not appearance.IsDry(nil), "Menu became yellow")
check(
	appearance.IsValidMode(nil)
		and appearance.IsValidMode("hard")
		and not appearance.IsValidMode("other"),
	"Mode validation changed"
)
check(state.calls == 0, "Provider eagerly loaded art")
local result = together(appearance.DetailedTemplates, appearance.DetailedTemplates)
local bank = result[1][1]
check(
	result[2][1] == bank and state.calls == 1 and state.clones == 11,
	"Concurrent build duplicated bank"
)
check(appearance.DetailedTemplates() == bank and state.calls == 1, "Cached bank reloaded URI")
check(table.isfrozen(bank), "Caller can replace LOD table")
local seen = {}
for lod, list in bank do
	check(#list == 4 and table.isfrozen(list), "Invalid mutable variety table")
	for variety, part in list do
		check(not seen[part], "Duplicate template reference")
		seen[part] = true
		check(
			appearance.IsDetailedPlant(part, variety, lod),
			"Renderer contract rejected normal mesh"
		)
		check(
			part.MeshContent.SourceType == "Uri" and part.MeshId == meshId,
			"Corn remained editable/session content"
		)
		check(
			part.TextureID == textureId and part.Color == C3.new(1, 1, 1),
			"Original green atlas/tint differs from C"
		)
		check(
			(part.Size - size).Magnitude < 0.00001 and part.Parent == nil,
			"Original proportions/private binding changed"
		)
		check(
			part.Anchored
				and not part.CanCollide
				and not part.CanTouch
				and not part.CanQuery
				and part.CastShadow
				and part.DoubleSided,
			"Plant physics or shadow flags changed"
		)
		check(
			part:GetAttribute("CornGreenOriginal") == true
				and part:GetAttribute("CornPlantTemplateOwned") == true,
			"Layout/wind marker missing"
		)
		for _, yaw in { 0, 0.7, -1.2 } do
			local root = V3.new(14, 14.4, -11)
			local placed = appearance.DetailedPivot(part, root, yaw)
			check(
				(placed.Position - root - V3.new(0, 4, 0)).Magnitude < 0.00001,
				"Yaw detached plant root"
			)
		end
	end
end
for _, kind in
	{ "createError", "createNil", "meshId", "content", "bounds", "attribute", "child", "tag" }
do
	local subject, failed = fixture()
	failed.fail = { kind = kind, call = 1 }
	local attempt = together(function()
		return pcall(subject.DetailedTemplates)
	end)[1]
	check(not attempt[1], "Unsafe asset accepted: " .. kind)
	for _, part in failed.created do
		check(part.Destroyed, "Failed URI asset leaked: " .. kind)
	end
	local recovered = together(subject.DetailedTemplates)[1][1]
	check(
		recovered.Near[1] and subject.DetailedTemplates() == recovered,
		"URI failure poisoned retry"
	)
end
for _, kind in { "cloneNil", "cloneError", "decorate" } do
	for _, call in { 1, 6, 11 } do
		local subject, failed = fixture()
		failed.fail = { kind = kind, call = call }
		local attempt = together(function()
			return pcall(subject.DetailedTemplates)
		end)[1]
		check(not attempt[1], "Partial bank accepted: " .. kind)
		for _, part in failed.created do
			check(part.Destroyed, "Partial bank leaked: " .. kind)
		end
		check(
			together(subject.DetailedTemplates)[1][1].Far[4] ~= nil,
			"Clone failure poisoned retry"
		)
	end
end
local mutations = {
	{
		"parent",
		function(p)
			p.Parent = {}
		end,
	},
	{
		"name",
		function(p)
			p.Name = "Manual"
		end,
	},
	{
		"frame",
		function(p)
			p.CFrame = CF.new(1, 0, 0)
		end,
	},
	{
		"pivot",
		function(p)
			p.PivotOffset = CF.new(0, 1, 0)
		end,
	},
	{
		"size",
		function(p)
			p.Size = V3.one
		end,
	},
	{
		"mesh",
		function(p)
			p.MeshId = "rbxassetid://1"
		end,
	},
	{
		"content",
		function(p)
			p.MeshContent = { SourceType = "Object" }
		end,
	},
	{
		"texture",
		function(p)
			p.TextureID = "rbxassetid://1"
		end,
	},
	{
		"color",
		function(p)
			p.Color = C3.new(0, 0, 0)
		end,
	},
	{
		"collision",
		function(p)
			p.CanCollide = true
		end,
	},
	{
		"touch",
		function(p)
			p.CanTouch = true
		end,
	},
	{
		"query",
		function(p)
			p.CanQuery = true
		end,
	},
	{
		"anchor",
		function(p)
			p.Anchored = false
		end,
	},
	{
		"shadow",
		function(p)
			p.CastShadow = false
		end,
	},
	{
		"double",
		function(p)
			p.DoubleSided = false
		end,
	},
	{
		"alpha",
		function(p)
			p.Transparency = 0.5
		end,
	},
	{
		"reflectance",
		function(p)
			p.Reflectance = 0.5
		end,
	},
	{
		"material",
		function(p)
			p.Material = r.Enum.Material.Neon
		end,
	},
	{
		"variant",
		function(p)
			p.MaterialVariant = "Manual"
		end,
	},
	{
		"mass",
		function(p)
			p.Massless = false
		end,
	},
	{
		"group",
		function(p)
			p.CollisionGroup = "Manual"
		end,
	},
	{
		"physical",
		function(p)
			p.CustomPhysicalProperties = {}
		end,
	},
	{
		"fidelity",
		function(p)
			p.RenderFidelity = r.Enum.RenderFidelity.Automatic
		end,
	},
	{
		"owner",
		function(p)
			p:SetAttribute("CornGreenTemplateOwned", nil)
		end,
	},
	{
		"source",
		function(p)
			p:SetAttribute("CornGreenSourceSHA256", "other")
		end,
	},
	{
		"root",
		function(p)
			p:SetAttribute("HarvestRootOffset", V3.zero)
		end,
	},
	{
		"attribute",
		function(p)
			p:SetAttribute("Manual", true)
		end,
	},
	{
		"child",
		function(p)
			p._children = { {} }
		end,
	},
	{
		"tag",
		function(p)
			p._tags = { "Manual" }
		end,
	},
}
for _, mutation in mutations do
	local subject, changed = fixture()
	local templates = together(subject.DetailedTemplates)[1][1]
	local part = templates.Mid[2]
	mutation[2](part)
	local ok = pcall(subject.DetailedTemplates)
	check(not ok, "Changed cache accepted: " .. mutation[1])
	check(not part.Destroyed and changed.calls == 1, "Manual cache change deleted or rebuilt")
end
local subject, concurrent = fixture()
concurrent.fail = { kind = "cloneError", call = 6 }
local recovered = together(function()
	return pcall(subject.DetailedTemplates)
end, subject.DetailedTemplates)
check(
	not recovered[1][1] and recovered[2][1].Far[4] ~= nil and concurrent.calls == 2,
	"Concurrent waiter failed to recover"
)
for index = 1, 6 do
	check(concurrent.created[index].Destroyed, "Concurrent failed bank leaked")
end
check(subject.DetailedTemplates() == recovered[2][1], "Concurrent retry not cached")
print(
	"PASS: "
		.. assertions
		.. " B green provider assertions; original URI/proportions/12 private templates, green modes, root placement, concurrent cache/retry, 17 failure injections, 29 changed-cache refusals; no GPU claim"
)
