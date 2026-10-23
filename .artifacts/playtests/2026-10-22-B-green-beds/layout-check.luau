-- Read-only offline check of production GreenBedLayout with real Lune vectors.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local started = os.clock()
local fn = assert(loadstring(fs.readFile("variants/B/shared/Game/GreenBedLayout.luau"), "GreenBedLayout"))
local fakeGame = { GetService = function(_, name)
    assert(name == "HttpService")
    return { JSONDecode = function(_, text) return serde.decode("json", text) end }
end }
setfenv(fn, setmetatable({ game = fakeGame, Vector3 = roblox.Vector3, CFrame = roblox.CFrame }, { __index = getfenv() }))
local layout = fn()
local checks, plants, far, minimum, maximum = 0, 0, 0, math.huge, -math.huge
local spacing = 3 / math.sqrt(2.6)
local ground = 14.399986267089844
local function check(value, message) assert(value, message); checks += 1 end
check(#layout.SoilTiles == 1406 and layout.PlotCount == 143, "Frozen plot/tile counts differ")
local seen = {}
for _, tile in layout.SoilTiles do
    check(tile.Key == "Center" or tile.Key == "End" or tile.Key == "Skirt", "Unknown soil key")
    check(tile.Size.X > 0 and tile.Size.Y > 0 and tile.Size.Z > 0, "Invalid tile size")
    local key = tile.Key .. "/" .. tostring(tile.Frame)
    check(not seen[key], "Duplicate soil placement")
    seen[key] = true
end
for column = -169, 169 do
    for row = -169, 169 do
        local point = roblox.Vector3.new(column * spacing, ground, row * spacing)
        local inside = layout.Contains(point)
        local height = layout.GetHeight(point)
        check(inside == (height ~= nil), "Coverage and height disagree")
        if inside then
            plants += 1
            if column % 2 == 0 and row % 2 == 0 then far += 1 end
            local positioned = layout.Position(point)
            check(positioned.X == point.X and positioned.Z == point.Z, "Position moved a root XZ")
            check(positioned.Y == height or math.abs(positioned.Y - height) < .000002, "Position height differs")
            check(height >= ground and height <= ground + 1, "Plant surface outside source soil bounds")
            minimum = math.min(minimum, height)
            maximum = math.max(maximum, height)
        end
    end
end
for _, point in { roblox.Vector3.new(1000,0,0), roblox.Vector3.new(0,0,1000), roblox.Vector3.new(-1000,0,0) } do
    check(not layout.Contains(point), "Foreign point is planted")
    check(layout.Position(point) == point, "Outside point mutated")
end
local firstSeconds = os.clock() - started
local cacheStarted = os.clock()
for column = -169, 169 do
    for row = -169, 169 do
        layout.Contains(roblox.Vector3.new(column * spacing, ground, row * spacing))
    end
end
print(serde.encode("json", { pass = true, checks = checks, denseEligible = plants, farEligible = far,
    minimumRootY = minimum, maximumRootY = maximum, firstPassSeconds = firstSeconds,
    cachedPassSeconds = os.clock() - cacheStarted, soilParts = #layout.SoilTiles, plotCount = layout.PlotCount,
    nativeMutation = false, renderingAcceptance = false }))
