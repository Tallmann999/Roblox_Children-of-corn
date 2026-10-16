-- Actual generated HTTP wrapper: temporary setting restoration before installer entry.
local fs = require("@lune/fs")
local source = fs.readFile("scripts/install-harvest.luau")
for _, original in { false, true } do
	local calls = 0
	local http = {
		HttpEnabled = original,
		GetAsync = function(self, url)
			assert(self.HttpEnabled == true and url == "http://127.0.0.1:8768/payload.json")
			calls += 1
			error("Controlled transport failure")
		end,
	}
	local fn = assert(loadstring(source))
	setfenv(
		fn,
		setmetatable(
			{
				game = {
					GetService = function(_, name)
						assert(
							name == "HttpService",
							"Installer entered before failed HTTP restoration"
						)
						return http
					end,
				},
			},
			{ __index = getfenv() }
		)
	)
	local ok, message = pcall(fn)
	assert(not ok and message:find("payload fetch failed", 1, true))
	assert(http.HttpEnabled == original and calls == 1)
end
local writes = 0
local denied = setmetatable({
	GetAsync = function()
		error("HTTP called after enable denial")
	end,
}, {
	__index = function(_, name)
		if name == "HttpEnabled" then
			return false
		end
	end,
	__newindex = function(_, name)
		assert(name == "HttpEnabled")
		writes += 1
		error("Controlled enable denial")
	end,
})
local fn = assert(loadstring(source))
setfenv(
	fn,
	setmetatable(
		{ game = {
			GetService = function(_, name)
				assert(name == "HttpService")
				return denied
			end,
		} },
		{ __index = getfenv() }
	)
)
assert(not pcall(fn) and denied.HttpEnabled == false and writes == 1)
print(
	"PASS: actual HTTP wrapper restores initial true/false after fetch failure; enable denial leaves false and never enters project installer"
)
