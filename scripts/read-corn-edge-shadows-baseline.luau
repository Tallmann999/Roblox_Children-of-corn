-- Read exact archived RBXL bytes in memory; never create or serialize a scene.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local ARCHIVE = ".artifacts/playtests/2026-10-21-corn-edge-shadows/before-corn-edge-shadows.zip"
local M = {}
function M.Read(): string
	assert(
		serde.hash("sha256", fs.readFile(ARCHIVE))
			== "2bf1ac59830101e707d5890875d6a439b8afe26261c89d48b7bde7110708e5cc"
	)
	local result = process.exec("python", {
		"-c",
		"import sys,zipfile;sys.stdout.write(zipfile.ZipFile(sys.argv[1]).read('checkpoint/B-before-corn-edge-shadows.rbxl').hex())",
		ARCHIVE,
	})
	assert(result.ok, result.stderr)
	local hex = result.stdout
	assert(#hex == 1497688 * 2 and not hex:find("[^%x]"), "Invalid archived bytes")
	local bytes = hex:gsub("%x%x", function(pair)
		return string.char(tonumber(pair, 16) :: number)
	end)
	assert(
		serde.hash("sha256", bytes)
			== "b113d584f1a60e16f34ba4ec40ce051b0338cab712467f07d762d9fc8528b1d2"
	)
	return bytes
end
return M
