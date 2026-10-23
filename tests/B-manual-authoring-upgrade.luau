-- Synthetic current-171 upgrade test. No scene I/O or native Studio execution.
local fs, serde = require("@lune/fs"), require("@lune/serde")
local first = fs.readFile("tests/B-manual-authoring-installer.luau")
local cut =
	assert(first:find("local good = setup()", 1, true), "First fixture setup boundary changed")
local setup = assert(loadstring(first:sub(1, cut - 1) .. "\nreturn setup"))()
local code = fs.readFile("scripts/upgrade-B-manual-authoring-sources.luau")
assert(loadstring(code))
local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end
local function clone(value)
	return serde.decode("json", serde.encode("json", value))
end
local function nextPayload(f)
	local payload = clone(f.state.sourcesPayload)
	for _, rows in { payload.sourceChanges, payload.newSources } do
		for _, row in rows do
			row.source ..= "-- reviewed editor-pool upgrade\n"
			row.sha256 = serde.hash("sha256", row.source)
		end
	end
	return payload
end
local function call(f, payload, text)
	local wrapped = "return function(_) local nextPayload=require('@lune/serde').decode('json',[==["
		.. serde.encode("json", payload)
		.. "]==]);return (function()\n"
		.. (text or code)
		.. "\nend)()(nextPayload) end"
	return f.execute(wrapped)
end
local function installed()
	local f = setup()
	local ok, result = f.execute()
	assert(ok, tostring(result))
	return f
end
local good = installed()
local upgradePayload = nextPayload(good)
local identities = good.snapshot()
local added = #good.state.added
local ok, result = call(good, upgradePayload)
check(ok, tostring(result))
check(
	result.upgraded and result.changedSources == 11 and result.newNodes == 0,
	"Exact Source-only upgrade"
)
check(#good.state.added == added and #good.state.journal == 19, "Prior8+upgrade11 Source journal")
for item, before in identities do
	check(
		item.Parent == before.parent and item.Name == before.name,
		"Code/world identity/parent moved"
	)
end
check(good.state.verifySources().totalSources == 171, "Updated acceptance closure")
local final = good.snapshot()
ok, result = call(good, upgradePayload)
check(ok and result.repeated and result.changedSources == 0, "Idempotent upgrade")
check(good.same(final), "Repeated upgrade changed persistent state")
local refusals, rollbacks = {}, {}
local function reject(name, change, injected)
	local f = installed()
	local payload = nextPayload(f)
	if change then
		change(f, payload)
	end
	local before = f.snapshot()
	local oldPayload, oldVerify = f.state.sourcesPayload, f.state.verifySources
	local oldSignature, oldJournal, oldAdded =
		f.state.sourcesPayloadSignature, #f.state.journal, #f.state.added
	local accepted, problem = call(f, payload, injected)
	check(not accepted, "Unsafe upgrade accepted: " .. name)
	check(
		f.same(before),
		"Upgrade rejection changed prior171/world: " .. name .. ": " .. tostring(problem)
	)
	check(
		f.state.sourcesPayload == oldPayload
			and f.state.verifySources == oldVerify
			and f.state.sourcesPayloadSignature == oldSignature,
		"Previous accepted payload/closure changed"
	)
	check(
		#f.state.journal == oldJournal
			and #f.state.added == oldAdded
			and f.state.phase == "sources-installed",
		"Failed upgrade altered journal/phase"
	)
	table.insert(refusals, name)
end
reject("Play", function(f)
	f.run.running = true
end)
reject("prior editor buffer", function(f)
	local path = next(f.payload.sourceChanges)
	f.editor.dirty[f.resolve(path)] = "return 'author'"
end)
reject("prior Source edit", function(f)
	f.resolve("Workspace/CornfieldFog/RuntimeServer").Source ..= "-- author"
end)
reject("changed before pin", function(_, p)
	local _, row = next(p.sourceChanges)
	row.beforeSha256 = string.rep("0", 64)
end)
reject("new Source topology", function(_, p)
	local path, row = next(p.newSources)
	p.newSources[path] = nil
	p.newSources[path .. "Injected"] = row
end)
reject("changed canonical file", function(_, p)
	local _, row = next(p.newSources)
	row.file = "variants/B/shared/Game/Other.luau"
end)
reject("new syntax", function(_, p)
	local _, row = next(p.newSources)
	row.source = "return ("
	row.sha256 = serde.hash("sha256", row.source)
end)
for point = 1, 11 do
	local injected = "local fixtureWrites=0;local function upgradeFault() fixtureWrites+=1;if fixtureWrites=="
		.. point
		.. " then error('injected upgrade failure') end end\n"
		.. code
	local count
	injected, count =
		injected:gsub("row.item.Source = row.after", "row.item.Source = row.after\nupgradeFault()")
	check(count == 1, "Upgrade fault hook changed")
	reject("rollback:" .. point, nil, injected)
	table.insert(rollbacks, point)
end
local report = {
	passed = true,
	checks = checks,
	refusals = refusals,
	rollbackPoints = rollbacks,
	upgradedSources = 11,
	retainedCodeIdentities = 171,
	newNodes = 0,
	sceneIO = false,
}
fs.writeFile(
	".artifacts/playtests/2026-10-23-B-manual-authoring/source-upgrade-fixture.json",
	serde.encode("json", report)
)
print(serde.encode("json", report))
