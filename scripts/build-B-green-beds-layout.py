"""Build B-only deterministic soil-bed coverage from a frozen native mask read.

No Studio connection, scene serialization, source FBX edits, or asset publication.
The three C geometry modules supply unchanged height triangles and template sizes.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".artifacts/playtests/2026-10-22-B-green-beds"
INPUT = OUT / "native-inputs.json"
MODULE = ROOT / "variants/B/shared/Game/GreenBedLayout.luau"
CLEARANCE = 0.08
BUCKET_SIZE = 24
MIN_SCALE = 0.55
MAX_SCALE = 1.35
CORE_X = 18.296041720615904
CORE_Z = 18.296041720615904
SKIRT_X = 21.65385258547726
SKIRT_Z = 21.318965503815413
OFFSET_X = 0.135925124246959
OFFSET_Z = 0.172515646050567
GROUND = 14.399986267089844
SOURCE_CENTERS = {"Center": 0.3558834467478431,
                  "End": 0.35588344674784517, "Skirt": -0.16705228626471172}


def compact(value):
    return json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":"))


def rounded(value):
    return round(value, 8)


def mesh_data(key):
    source = (ROOT / f"scene-c/data/{key}.luau").read_text(encoding="utf-8")
    match = re.search(r"\[==\[(.*?)\]==\]", source, re.S)
    assert match, key
    data = json.loads(match.group(1))
    return {"positions": data["positions"], "triangles": data["triangles"],
            "size": data["bounds"]["size"], "centerY": SOURCE_CENTERS[key]}


def obstacles(native):
    result = []
    for box in native["boxes"]:
        f = box["frame"]
        hx, hz = box["half"]
        x, z = f[0], f[2]
        # ReadExclusions already flattened these oriented footprints.
        dx = abs(f[3]) * hx + abs(f[5]) * hz + CLEARANCE
        dz = abs(f[9]) * hx + abs(f[11]) * hz + CLEARANCE
        result.append([x - dx, x + dx, z - dz, z + dz])
    for circle in native["circles"]:
        x, _, z = circle["center"]
        radius = circle["radius"] + CLEARANCE
        result.append([x - radius, x + radius, z - radius, z + radius])
    low, high = -315 + CLEARANCE, 315 - CLEARANCE
    return [[max(low, a), min(high, b), max(low, c), min(high, d)]
            for a, b, c, d in result
            if a < high and b > low and c < high and d > low]


def free_rectangles(blockers):
    low, high = -315 + CLEARANCE, 315 - CLEARANCE
    bands = sorted({low, high} | {v for r in blockers for v in (r[2], r[3])})
    active = {}
    result = []
    for za, zb in zip(bands, bands[1:]):
        mid = (za + zb) / 2
        intervals = sorted((a, b) for a, b, c, d in blockers if c < mid < d)
        merged = []
        for a, b in intervals:
            if merged and a <= merged[-1][1]:
                merged[-1][1] = max(merged[-1][1], b)
            else:
                merged.append([a, b])
        cursor = low
        free = []
        for a, b in merged:
            if a > cursor:
                free.append((cursor, a))
            cursor = max(cursor, b)
        if cursor < high:
            free.append((cursor, high))
        current = {}
        for a, b in free:
            key = (a, b)
            rectangle = active.pop(key, [a, b, za, zb])
            rectangle[3] = zb
            current[key] = rectangle
        result.extend(active.values())
        active = current
    result.extend(active.values())
    return sorted(result, key=lambda r: (r[2], r[0], r[3], r[1]))


def axis_fit(length, core, skirt, offset):
    extra = skirt + 2 * abs(offset) - core
    count = max(1, round((length - extra) / core))
    scale = length / (count * core + extra)
    while scale > MAX_SCALE:
        count += 1
        scale = length / (count * core + extra)
    return count, scale


def tile_rows(plots, meshes):
    result = []
    for plot_id, plot in enumerate(plots, 1):
        a, b, c, d, nx, nz, sx, sz = plot
        first_x = a + (SKIRT_X / 2 + abs(OFFSET_X)) * sx
        first_z = c + (SKIRT_Z / 2 + abs(OFFSET_Z)) * sz
        for ix in range(nx):
            for iz in range(nz):
                key = "Center" if nz == 1 or 0 < iz < nz - 1 else "End"
                yaw = math.pi if nz > 1 and iz == nz - 1 else 0
                sign = -1 if yaw else 1
                x, z = first_x + ix * CORE_X * sx, first_z + iz * CORE_Z * sz
                for asset in (key, "Skirt"):
                    size = meshes[asset]["size"]
                    px = x + (sign * OFFSET_X * sx if asset == "Skirt" else 0)
                    pz = z + (sign * OFFSET_Z * sz if asset == "Skirt" else 0)
                    width, depth = size[0] * sx, size[2] * sz
                    box = [px - width / 2, px + width / 2, pz - depth / 2, pz + depth / 2]
                    assert a - 1e-6 <= box[0] <= box[1] <= b + 1e-6
                    assert c - 1e-6 <= box[2] <= box[3] <= d + 1e-6
                    result.append({"key": asset, "plot": plot_id, "position": [px, GROUND + .06 + SOURCE_CENTERS[asset], pz],
                                   "yaw": yaw, "size": [width, size[1], depth], "bounds": box})
    return result


LUA = '''--!strict
-- Generated by scripts/build-B-green-beds-layout.py. B only; no world writes.
local raw = game:GetService("HttpService"):JSONDecode([==[__DATA__]==])
local GreenBedLayout = {
    Version = 1,
    Signature = raw.signature,
    InputSHA256 = raw.inputSha256,
    GroundY = raw.ground,
    SoilTiles = {},
    PlotCount = #raw.plots,
}
local plots = raw.plots
local buckets = {}
local sourceMeshes = {}
local heightCache = {}
local heightCacheCount = 0
local BUCKET = 24
local CORE = 18.296041720615904
local SKIRT_X, SKIRT_Z = 21.65385258547726, 21.318965503815413
local OFFSET_X, OFFSET_Z = .135925124246959, .172515646050567

local function token(x, z)
    return x .. ":" .. z
end

local expectedBoxBuckets, expectedCircleBuckets = {}, {}
local function indexExpected(target, values, center)
    for id, value in values do
        local x, z = center(value)
        local key = token(math.floor(x / BUCKET), math.floor(z / BUCKET))
        if not target[key] then target[key] = {} end
        table.insert(target[key], id)
    end
end
indexExpected(expectedBoxBuckets, raw.expected.boxes, function(box) return box.frame[1], box.frame[3] end)
indexExpected(expectedCircleBuckets, raw.expected.circles, function(circle) return circle.center[1], circle.center[3] end)

local function closeNumber(actual, expected, tolerance)
    return actual == actual and math.abs(actual) < math.huge and math.abs(actual - expected) <= tolerance
end

local function frameMatches(actual, expected)
    for i, value in { actual:GetComponents() } do
        if not closeNumber(value, expected[i], if i <= 3 then .0001 else .00025) then return false end
    end
    return true
end

local function findExpected(point, bucketsToSearch, values, used, predicate)
    local bx, bz = math.floor(point.X / BUCKET), math.floor(point.Z / BUCKET)
    for x = bx - 1, bx + 1 do
        for z = bz - 1, bz + 1 do
            local bucket = bucketsToSearch[token(x, z)]
            if bucket then
                for _, index in bucket do
                    if not used[index] and predicate(values[index]) then
                        used[index] = true
                        return true
                    end
                end
            end
        end
    end
    return false
end

function GreenBedLayout.MatchesExclusions(exclusions, field): boolean
    -- Only a CLIENT caller may use this narrow replication tolerance. Edit and
    -- server authoring retain the independent exact signature preflight.
    if #exclusions.Boxes ~= #raw.expected.boxes or #exclusions.Circles ~= #raw.expected.circles then return false end
    if field.Size ~= Vector3.new(table.unpack(raw.expected.fieldSize))
        or not frameMatches(field.CFrame, raw.expected.fieldFrame) then return false end
    local used = {}
    for _, box in exclusions.Boxes do
        if not findExpected(box.Frame.Position, expectedBoxBuckets, raw.expected.boxes, used, function(expected)
            return closeNumber(box.HalfSize.X, expected.half[1], .0001)
                and closeNumber(box.HalfSize.Y, expected.half[2], .0001)
                and frameMatches(box.Frame, expected.frame)
        end) then return false end
    end
    used = {}
    for _, circle in exclusions.Circles do
        if not findExpected(circle.Center, expectedCircleBuckets, raw.expected.circles, used, function(expected)
            return closeNumber(circle.Radius, expected.radius, .0001)
                and closeNumber(circle.Center.X, expected.center[1], .0001)
                and closeNumber(circle.Center.Y, expected.center[2], .0001)
                and closeNumber(circle.Center.Z, expected.center[3], .0001)
        end) then return false end
    end
    return true
end

for id, plot in plots do
    for bx = math.floor(plot[1] / BUCKET), math.floor(plot[2] / BUCKET) do
        for bz = math.floor(plot[3] / BUCKET), math.floor(plot[4] / BUCKET) do
            local key = token(bx, bz)
            local bucket = buckets[key]
            if not bucket then
                bucket = {}
                buckets[key] = bucket
            end
            table.insert(bucket, id)
        end
    end
end

for key, data in raw.meshes do
    local grid = {}
    for index, triangle in data.triangles do
        local a, b, c = data.positions[triangle[1]], data.positions[triangle[2]], data.positions[triangle[3]]
        for bx = math.floor(math.min(a[1], b[1], c[1]) / 2), math.floor(math.max(a[1], b[1], c[1]) / 2) do
            for bz = math.floor(math.min(a[3], b[3], c[3]) / 2), math.floor(math.max(a[3], b[3], c[3]) / 2) do
                local code = token(bx, bz)
                if not grid[code] then grid[code] = {} end
                table.insert(grid[code], index)
            end
        end
    end
    sourceMeshes[key] = { Data = data, Grid = grid }
end

local function sourceHeight(key, x, z)
    local source = sourceMeshes[key]
    local data = source.Data
    local candidates = source.Grid[token(math.floor(x / 2), math.floor(z / 2))]
    if not candidates then return nil end
    local height = nil
    for _, index in candidates do
        local triangle = data.triangles[index]
        local a, b, c = data.positions[triangle[1]], data.positions[triangle[2]], data.positions[triangle[3]]
        local determinant = (b[3] - c[3]) * (a[1] - c[1]) + (c[1] - b[1]) * (a[3] - c[3])
        if math.abs(determinant) > 1e-12 then
            local u = ((b[3] - c[3]) * (x - c[1]) + (c[1] - b[1]) * (z - c[3])) / determinant
            local v = ((c[3] - a[3]) * (x - c[1]) + (a[1] - c[1]) * (z - c[3])) / determinant
            local w = 1 - u - v
            if u >= -1e-7 and v >= -1e-7 and w >= -1e-7 then
                local y = u * a[2] + v * b[2] + w * c[2] + data.centerY
                height = if height then math.max(height, y) else y
            end
        end
    end
    return height
end

local function findPlot(point)
    local bucket = buckets[token(math.floor(point.X / BUCKET), math.floor(point.Z / BUCKET))]
    if bucket then
        for _, id in bucket do
            local plot = plots[id]
            if point.X >= plot[1] and point.X <= plot[2] and point.Z >= plot[3] and point.Z <= plot[4] then
                return plot
            end
        end
    end
    return nil
end

local function rawHeight(point)
    local plot = findPlot(point)
    if not plot then return nil end
    local nx, nz, sx, sz = plot[5], plot[6], plot[7], plot[8]
    local firstX = plot[1] + (SKIRT_X / 2 + math.abs(OFFSET_X)) * sx
    local firstZ = plot[3] + (SKIRT_Z / 2 + math.abs(OFFSET_Z)) * sz
    local ix = math.clamp(math.floor((point.X - firstX) / (CORE * sx) + .5), 0, nx - 1)
    local iz = math.clamp(math.floor((point.Z - firstZ) / (CORE * sz) + .5), 0, nz - 1)
    local best = nil
    for column = math.max(0, ix - 1), math.min(nx - 1, ix + 1) do
        for row = math.max(0, iz - 1), math.min(nz - 1, iz + 1) do
            local sign = if nz > 1 and row == nz - 1 then -1 else 1
            local key = if nz == 1 or (row > 0 and row < nz - 1) then "Center" else "End"
            local x, z = firstX + column * CORE * sx, firstZ + row * CORE * sz
            local localX, localZ = (point.X - x) / sx * sign, (point.Z - z) / sz * sign
            local coreY = sourceHeight(key, localX, localZ)
            local skirtY = sourceHeight("Skirt", localX - OFFSET_X, localZ - OFFSET_Z)
            if coreY then best = if best then math.max(best, coreY) else coreY end
            if skirtY then best = if best then math.max(best, skirtY) else skirtY end
        end
    end
    return if best then math.max(raw.ground, raw.ground + .06 + best) + .01 else nil
end

function GreenBedLayout.GetHeight(point: Vector3): number?
    -- Calls on the same stable corn cell share one exact triangle query.
    local key = string.format("%.7f:%.7f", point.X, point.Z)
    local cached = heightCache[key]
    if cached ~= nil then return if cached == false then nil else cached end
    local height = rawHeight(point)
    if heightCacheCount < 150000 then
        heightCache[key] = if height then height else false
        heightCacheCount += 1
    end
    return height
end

function GreenBedLayout.Contains(point: Vector3): boolean
    return GreenBedLayout.GetHeight(point) ~= nil
end

function GreenBedLayout.Position(point: Vector3): Vector3
    local height = GreenBedLayout.GetHeight(point)
    return if height then Vector3.new(point.X, height, point.Z) else point
end

function GreenBedLayout.ClearHeightCache()
    table.clear(heightCache)
    heightCacheCount = 0
end

for plotId, plot in plots do
    local nx, nz, sx, sz = plot[5], plot[6], plot[7], plot[8]
    local firstX = plot[1] + (SKIRT_X / 2 + math.abs(OFFSET_X)) * sx
    local firstZ = plot[3] + (SKIRT_Z / 2 + math.abs(OFFSET_Z)) * sz
    for ix = 0, nx - 1 do
        for iz = 0, nz - 1 do
            local key = if nz == 1 or (iz > 0 and iz < nz - 1) then "Center" else "End"
            local sign = if nz > 1 and iz == nz - 1 then -1 else 1
            local yaw = if sign == -1 then math.pi else 0
            local x, z = firstX + ix * CORE * sx, firstZ + iz * CORE * sz
            for _, asset in { key, "Skirt" } do
                local data = raw.meshes[asset]
                local px = x + (if asset == "Skirt" then sign * OFFSET_X * sx else 0)
                local pz = z + (if asset == "Skirt" then sign * OFFSET_Z * sz else 0)
                local size = Vector3.new(data.size[1] * sx, data.size[2], data.size[3] * sz)
                table.insert(GreenBedLayout.SoilTiles, table.freeze({
                    Key = asset, Plot = plotId,
                    Frame = CFrame.new(px, raw.ground + .06 + data.centerY, pz) * CFrame.Angles(0, yaw, 0),
                    Size = size,
                    Bounds = table.freeze({ px - size.X / 2, px + size.X / 2, pz - size.Z / 2, pz + size.Z / 2 }),
                }))
            end
        end
    end
end
table.freeze(GreenBedLayout.SoilTiles)
return table.freeze(GreenBedLayout)
'''


def main():
    inputs = INPUT.read_bytes()
    native = json.loads(inputs)
    assert len(native["boxes"]) == 188 and len(native["circles"]) == 19
    assert native["fieldSize"] == [630, 10, 630]
    assert native["fieldFrame"][3:] == [1, 0, 0, 0, 1, 0, 0, 0, 1]
    blockers = obstacles(native)
    free = free_rectangles(blockers)
    plots, cleared = [], []
    for rectangle in free:
        a, b, c, d = rectangle
        nx, sx = axis_fit(b - a, CORE_X, SKIRT_X, OFFSET_X)
        nz, sz = axis_fit(d - c, CORE_Z, SKIRT_Z, OFFSET_Z)
        if min(b - a, d - c) < 6 or min(sx, sz) < MIN_SCALE:
            cleared.append(rectangle)
            continue
        assert MIN_SCALE <= sx <= MAX_SCALE and MIN_SCALE <= sz <= MAX_SCALE
        plots.append([*[rounded(n) for n in rectangle], nx, nz, sx, sz])
    meshes = {key: mesh_data(key) for key in ("Center", "End", "Skirt")}
    payload = {"signature": native["signature"], "inputSha256": hashlib.sha256(inputs).hexdigest(),
               "ground": GROUND, "plots": plots, "meshes": meshes,
               "expected": {key: native[key] for key in ("boxes", "circles", "fieldSize", "fieldFrame")}}
    tiles = tile_rows(plots, meshes)
    for tile in tiles:
        a, b, c, d = tile["bounds"]
        assert all(b <= x + 1e-6 or a >= y - 1e-6 or d <= z + 1e-6 or c >= q - 1e-6
                   for x, y, z, q in blockers), "Tile crosses preserved mask"
    source = LUA.replace("__DATA__", compact(payload))
    assert len(source.encode()) < 200000
    MODULE.parent.mkdir(parents=True, exist_ok=True)
    MODULE.write_text(source, encoding="utf-8", newline="\n")
    formatter = ROOT / ".tools/rokit-data/tool-storage/johnnymorganz/stylua/2.5.2/stylua.exe"
    if formatter.is_file():
        subprocess.run([str(formatter), str(MODULE)], check=True)
        source = MODULE.read_text(encoding="utf-8")
    layout = {"version": 1, "project": "children_of_corn", "variant": "B", "ground": GROUND,
              "clearance": CLEARANCE, "bucketSize": BUCKET_SIZE, "inputSha256": payload["inputSha256"],
              "plots": plots, "soilTiles": tiles, "clearedSlivers": cleared}
    (OUT / "layout.json").write_text(json.dumps(layout, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    area = lambda rectangles: sum((r[1] - r[0]) * (r[3] - r[2]) for r in rectangles)
    analysis = {"nativeBoxes": len(native["boxes"]), "nativeCircles": len(native["circles"]),
                "freeRectangles": len(free), "freeArea": area(free), "plots": len(plots),
                "plotOuterArea": area(plots), "clearedSlivers": len(cleared), "clearedSliverArea": area(cleared),
                "soilTiles": len(tiles), "tileKeys": {key: sum(t["key"] == key for t in tiles) for key in meshes},
                "scaleRange": [min(p[i] for p in plots for i in (6, 7)), max(p[i] for p in plots for i in (6, 7))],
                "allTileFootprintsInsidePlots": True, "allTileFootprintsOutsideConservativeMasks": True,
                "rootXZAlignment": "Exact original B spacing; no XZ movement. Caller removes stagger/jitter.",
                "heightSampling": "Exact C Center/End/Skirt triangle barycentrics; maximum overlapping surface +0.01.",
                "sourceBytes": len(source.encode()), "sourceSHA256": hashlib.sha256(source.encode()).hexdigest(),
                "inputSHA256": payload["inputSha256"], "nativeMutation": False}
    (OUT / "layout-analysis.json").write_text(json.dumps(analysis, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(compact(analysis))


if __name__ == "__main__":
    main()
