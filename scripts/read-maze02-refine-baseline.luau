-- Read exact archived RBXL bytes in memory; never create or serialize a scene.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local ARCHIVE = ".artifacts/playtests/2026-10-21-maze02-refine/before-refine.zip"
local M = {}
function M.Read(): string
	assert(
		serde.hash("sha256", fs.readFile(ARCHIVE))
			== "facdfe7e63fafd1eeb8fce784ec2172378db56c7b48ea306b1ec01e24105106e"
	)
	local result = process.exec("python", {
		"-c",
		"import sys,zipfile;sys.stdout.write(zipfile.ZipFile(sys.argv[1]).read('checkpoint/B-before-refine.rbxl').hex())",
		ARCHIVE,
	})
	assert(result.ok, result.stderr)
	local hex = result.stdout
	assert(#hex == 1497748 * 2 and not hex:find("[^%x]"), "Invalid archived bytes")
	local bytes = hex:gsub("%x%x", function(pair)
		return string.char(tonumber(pair, 16) :: number)
	end)
	assert(
		serde.hash("sha256", bytes)
			== "108066bc0cf2a55f3c90d8db0ba7bef2eccb4a21351d5e9d53983fbcce8c50f3"
	)
	return bytes
end
return M
