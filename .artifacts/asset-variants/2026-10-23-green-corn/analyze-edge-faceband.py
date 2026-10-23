"""Exact static triangle clipping in shoulder/face height bands for moved roots.
Run with Blender's bundled NumPy. This reads frozen JSON and writes only analysis.
No Blender scene operations, native Studio writes, collision or human acceptance.
"""
import json,hashlib,math,time
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/".artifacts/playtests/2026-10-23-B-green-variants"
ASSETS=ROOT/".artifacts/asset-variants/2026-10-23-green-corn"
edge_path=OUT/"edge-cells.json"
edge=json.loads(edge_path.read_text(encoding="utf-8"))
rows=np.asarray([row[:19]for row in edge["cells"]],dtype=np.float64)
names=["Original","Var01","Var02","Var03"]
datasets=[json.loads((ASSETS/(key+"-runtime.json")).read_text(encoding="utf-8"))for key in names]
points=np.stack([np.array(data["positions"])+np.array(data["bbox_center_from_root_studs"])for data in datasets])
triangles=np.asarray(datasets[0]["triangles"],dtype=np.int64)-1
assert all(np.array_equal(np.array(data["triangles"])-1,triangles)for data in datasets)
assert len(rows)==5249
GROUND=14.399986267089844
BANDS={"face_4_25_to_5_75":(4.25,5.75),"shoulder_3_5_to_5":(3.5,5.0)}
reference_checks=0
reference_max_error=0.0

def scalar_reference(along,y,across,half_length,low,high):
    """Independent general polygon clipping, avoiding candidate enumeration."""
    smallest=math.inf
    for aa,yy,nn in zip(along,y,across):
        polygon=[(float(a),float(b),float(c))for a,b,c in zip(aa,yy,nn)]
        for axis,bound,sign in [(0,-half_length,1),(0,half_length,-1),(1,low,1),(1,high,-1)]:
            if not polygon:break
            output=[]
            previous=polygon[-1]
            was_inside=(previous[axis]-bound)*sign>=0
            for current in polygon:
                inside=(current[axis]-bound)*sign>=0
                if inside!=was_inside:
                    t=(bound-previous[axis])/(current[axis]-previous[axis])
                    output.append(tuple(a+t*(b-a)for a,b in zip(previous,current)))
                if inside:output.append(current)
                previous,was_inside=current,inside
            polygon=output
        if polygon:smallest=min(smallest,min(point[2]for point in polygon))
    return smallest

def clipped_min(along,y,across,half_length,low,high):
    """Minimise plane-normal coordinate over each triangle clipped to rectangle."""
    count=len(along)
    minima=np.full((count,len(triangles)),np.inf)
    h=half_length[:,None]
    for k in range(3):
        valid=(along[:,:,k]>=-h)&(along[:,:,k]<=h)&(y[:,:,k]>=low)&(y[:,:,k]<=high)
        minima=np.minimum(minima,np.where(valid,across[:,:,k],np.inf))
    for first,second in [(0,1),(1,2),(2,0)]:
        a0,a1=along[:,:,first],along[:,:,second]
        y0,y1=y[:,:,first],y[:,:,second]
        n0,n1=across[:,:,first],across[:,:,second]
        for bound in (low,high):
            t=np.divide(bound-y0,y1-y0,out=np.full_like(y0,np.nan),where=np.abs(y1-y0)>1e-12)
            a=a0+t*(a1-a0)
            valid=(t>=0)&(t<=1)&(a>=-h-1e-9)&(a<=h+1e-9)
            minima=np.minimum(minima,np.where(valid,n0+t*(n1-n0),np.inf))
        for bound in (-h,h):
            t=np.divide(bound-a0,a1-a0,out=np.full_like(a0,np.nan),where=np.abs(a1-a0)>1e-12)
            yy=y0+t*(y1-y0)
            valid=(t>=0)&(t<=1)&(yy>=low-1e-9)&(yy<=high+1e-9)
            minima=np.minimum(minima,np.where(valid,n0+t*(n1-n0),np.inf))
    # A rectangle corner can lie inside a projected triangle with no original
    # triangle vertex or edge intersection on that corner.
    a0,a1,a2=along[:,:,0],along[:,:,1],along[:,:,2]
    y0,y1,y2=y[:,:,0],y[:,:,1],y[:,:,2]
    n0,n1,n2=across[:,:,0],across[:,:,1],across[:,:,2]
    determinant=(a1-a0)*(y2-y0)-(a2-a0)*(y1-y0)
    for bound_a in (-h,h):
        for bound_y in (low,high):
            u=np.divide((bound_a-a0)*(y2-y0)-(bound_y-y0)*(a2-a0),determinant,
                out=np.full_like(a0,np.nan),where=np.abs(determinant)>1e-12)
            v=np.divide((a1-a0)*(bound_y-y0)-(y1-y0)*(bound_a-a0),determinant,
                out=np.full_like(a0,np.nan),where=np.abs(determinant)>1e-12)
            valid=(u>=-1e-9)&(v>=-1e-9)&(u+v<=1+1e-9)
            minima=np.minimum(minima,np.where(valid,n0+u*(n1-n0)+v*(n2-n0),np.inf))
    return np.min(minima,axis=1)

def evaluate(pose,band):
    global reference_checks,reference_max_error
    output=[]
    for first in range(0,len(rows),128):
        part=rows[first:first+128]
        source=points[part[:,18].astype(np.int64)-1].copy()
        source[:,:,1]*=part[:,16,None]/8
        c,s=np.cos(part[:,17,None]),np.sin(part[:,17,None])
        offset=2 if pose=="before_projection"else 5
        x=part[:,offset,None]+c*source[:,:,0]+s*source[:,:,2]
        y=part[:,offset+1,None]+source[:,:,1]
        z=part[:,offset+2,None]-s*source[:,:,0]+c*source[:,:,2]
        along=np.where(part[:,10,None]>0.5,x-part[:,8,None],z-part[:,9,None])[:,triangles]
        across=(part[:,13,None]*(x-part[:,8,None])+part[:,14,None]*(z-part[:,9,None])-part[:,11,None])[:,triangles]
        yy=y[:,triangles]
        values=clipped_min(along,yy,across,part[:,12],GROUND+band[0],GROUND+band[1])
        if first<8*128:
            for index in (0,len(part)-1):
                reference=scalar_reference(along[index],yy[index],across[index],part[index,12],GROUND+band[0],GROUND+band[1])
                error=abs(reference-values[index])
                assert error<1e-8,(pose,index,reference,values[index])
                reference_checks+=1;reference_max_error=max(reference_max_error,error)
        output.extend(values.tolist())
    assert all(math.isfinite(value)for value in output)
    return np.asarray(output)
def stats(values):
    return {"count":len(values),"minimum":float(np.min(values)),"median":float(np.median(values)),
        "p10":float(np.quantile(values,.1)),"p90":float(np.quantile(values,.9)),"maximum":float(np.max(values)),
        "overhang_roots":int(np.count_nonzero(values<0)),
        "overhang_percent":float(np.mean(values<0)*100),
        "overhang_at_least_0_25_stud_roots":int(np.count_nonzero(values<=-.25)),
        "overhang_at_least_0_5_stud_roots":int(np.count_nonzero(values<=-.5)),
        "within_0_5_of_trail_center_roots":int(np.count_nonzero(values+rows[:,11]<=.5))}
began=time.perf_counter()
result={"pass":True,"scope":"exact static rendered mesh triangles clipped to height band and corresponding finite trail segment",
    "source_edge_cells_sha256":hashlib.sha256(edge_path.read_bytes()).hexdigest(),
    "root_count":len(rows),"shape_mix":{key:int(np.count_nonzero(rows[:,18]==i+1))for i,key in enumerate(names)},
    "ground_y":GROUND,"metric":"signed minimum outside-path gap; negative means leaf geometry visually enters trail; halfWidth+gap measures distance from trail centre",
    "comparison":"same new 4-shape mix/height/yaw before vs after 23-Oct root edge projection, not historical scene appearance",
    "algorithm":"Sutherland-Hodgman-equivalent linear minimisation: inside vertices, 12 edge/clip-plane intersections, 4 rectangle corners with barycentric membership",
    "bands":{},"nativeMutation":False,"humanAcceptance":False,"physicalCollisionAcceptance":False,"GPUAcceptance":False}
cellResults={}
for key,band in BANDS.items():
    before=evaluate("before_projection",band)
    after=evaluate("after_projection",band)
    result["bands"][key]={"height_above_ground":list(band),"before":stats(before),"after":stats(after),
        "median_improvement_studs":float(np.median(before-after)),
        "all_roots_nonworse":bool(np.all(after<=before+1e-7))}
    cellResults[key]={"before":[round(float(v),6)for v in before],"after":[round(float(v),6)for v in after]}
result["elapsed_seconds"]=time.perf_counter()-began
result["independent_scalar_polygon_reference"]={"full_plants_checked":reference_checks,"triangles_each":510,"max_minimum_gap_error_studs":reference_max_error,"tolerance_studs":1e-8,"pass":True}
(OUT/"edge-leaf-faceband-analysis.json").write_text(json.dumps(result,indent=2),encoding="utf-8")
(OUT/"edge-leaf-faceband-values.json").write_text(json.dumps({"fields":"same cell order as edge-cells.json","data":cellResults},separators=(",",":")),encoding="utf-8")
print("@@JSON@@"+json.dumps(result))
