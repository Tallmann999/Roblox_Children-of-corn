-- Read-only private DOM analysis. No scene serialization or native mutations.
local adapter = require("../../../tests/scene-adapter")
local fs, r = adapter.fs, adapter.r
local serde = require("@lune/serde")
local OUT = ".artifacts/playtests/2026-10-22-B-double-density/"
local bytes = fs.readFile("place/Children_of_corn_B.rbxl")
assert(serde.hash("sha256", bytes) == "94c55e17bed0dc2f4b2e7c6020f60c031d80bc636be16166fe0effb6df146d5f")
local place = r.deserializePlace(bytes)
local map = place:GetService("Workspace").CornMap
local field = map.FieldZone
assert(map:GetAttribute("HarvestArtVariant") == "B")
local saved = place:GetService("ReplicatedStorage").GameShared.Game.CornLayout.Source:gsub("\r\n", "\n")
local replacement, n = saved:gsub("1 / math%.sqrt%(1%.3%)", "1 / math.sqrt(2.6)")
assert(n == 1)
local function layout(source)
    source = source:gsub("item%.Position", "item.CFrame.Position")
    local fn = assert(loadstring(source, "CornLayout private density analysis"))
    setfenv(fn, setmetatable({CFrame=r.CFrame, Vector3=r.Vector3, Vector2=r.Vector2}, {__index=getfenv()}))
    return fn()
end
local function measure(module)
    local exclusions = module.ReadExclusions(map, field)
    local spacing = module.SpacingFor(field)
    local lowC, highC, lowR, highR = module.GetCellBounds(field)
    local chunks = {}
    local eligible, far, shifted = 0, 0, 0
    local sectors = {}
    for c = lowC, highC do
        for row = lowR, highR do
            local chunkC, chunkR = math.floor(c / module.ChunkCells), math.floor(row / module.ChunkCells)
            local key = chunkC .. ":" .. chunkR
            local chunk = chunks[key]
            if not chunk then
                chunk = {c=chunkC,r=chunkR,full=0,mid=0,sparse=0,minC=math.max(lowC,chunkC*12),maxC=math.min(highC,(chunkC+1)*12-1),minR=math.max(lowR,chunkR*12),maxR=math.min(highR,(chunkR+1)*12-1)}
                chunk.x=(chunk.minC+chunk.maxC)*spacing/2
                chunk.z=(chunk.minR+chunk.maxR)*spacing/2
                chunks[key]=chunk
            end
            local p=module.CellPosition(field,c,row)
            if not module.IsExcluded(p, exclusions) then
                local q=module.TrailEdgePosition(p,exclusions)
                if (q-p).Magnitude>0.00001 then shifted+=1 end
                eligible+=1
                chunk.full+=1
                if c%2==0 and row%2==0 then far+=1; chunk.mid+=1 end
                if c%3==0 and row%3==0 then chunk.sparse+=1 end
                local sx=math.min(3,math.floor((p.X+315)/157.5))
                local sz=math.min(3,math.floor((p.Z+315)/157.5))
                local skey=sx..":"..sz
                sectors[skey]=(sectors[skey] or 0)+1
            end
        end
    end
    local candidates=(math.floor(highC/2)-math.ceil(lowC/2)+1)*(math.floor(highR/2)-math.ceil(lowR/2)+1)
    local maxObserved={normal={chunks=0,plants=0,upper=0},elevated={chunks=0,plants=0,upper=0},retained={chunks=0,plants=0,upper=0}}
    local maxCurrent={normal=0,elevated=0,retained=0}
    local samples={}
    local function sample(x,z,kind,detailRadius,denseRadius)
        local desired={}
        for key,ch in chunks do
            local d=(ch.x-x)^2+(ch.z-z)^2
            if d<=detailRadius^2 then
                local lod=if d<=denseRadius^2 then 1 else 2
                table.insert(desired,{distance=d,key=key,plants=if lod==1 then ch.full else ch.mid,upper=if lod==1 then 144 else 36})
            end
        end
        table.sort(desired,function(a,b) return if a.distance==b.distance then a.key<b.key else a.distance<b.distance end)
        local plants,upper,current=0,0,0
        for i,v in desired do plants+=v.plants;upper+=v.upper;if i<=100 then current+=v.plants end end
        current=math.min(current,4032)
        maxCurrent[kind]=math.max(maxCurrent[kind],current)
        local m=maxObserved[kind]
        m.chunks=math.max(m.chunks,#desired)
        if plants>m.plants then m.plants=plants;m.at={x,z} end
        m.upper=math.max(m.upper,upper)
        table.insert(samples,{position={x,z},kind=kind,desired_chunks=#desired,desired_plants=plants,empty_field_upper=upper,current_limits_plants=current})
    end
    -- 21x21 uniform positions plus starts and center; fine enough to expose caps.
    for x=-300,300,30 do for z=-300,300,30 do
        sample(x,z,"normal",130,60)
        sample(x,z,"elevated",144,60)
        -- Conservative steady retained case: both detail and dense hysteresis maxima.
        sample(x,z,"retained",156,72)
    end end
    return {
        spacing=spacing,chunk_width=spacing*12,nominal_density=1/(spacing*spacing),
        dense_candidate_cells=(highC-lowC+1)*(highR-lowR+1),eligible_dense_cells=eligible,
        far_candidate_cells=candidates,far_eligible=far,projected_edge_cells=shifted,
        sector_dense_counts=sectors,max_sampled_desired=maxObserved,max_sampled_with_current_limits=maxCurrent,
        sample_positions=441,sample_note="Retained bound intentionally combines maximum dense and elevated medium hysteresis. All map positions sampled, not only paths. Native rendering/performance is separate.",
        samples=samples,
    }
end
local started=os.clock()
local old,new=measure(layout(saved)),measure(layout(replacement))
local report={baseline_sha256=serde.hash("sha256",bytes),before=old,after=new,spacing_ratio=new.spacing/old.spacing,nominal_density_ratio=new.nominal_density/old.nominal_density,far_count_ratio=new.far_eligible/old.far_eligible,eligible_dense_ratio=new.eligible_dense_cells/old.eligible_dense_cells,elapsed_analysis_seconds=os.clock()-started,native_or_save_mutation=false}
fs.writeFile(OUT.."density-analysis.json",serde.encode("json",report,true))
old.samples=nil;new.samples=nil
print(serde.encode("json",report,true))
