"""Root and face-height leaf proximity along accepted B maze, no scene writes."""
import json,struct,math,statistics
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
data=json.loads((HERE/'edge-analysis-data.json').read_text())
geometries={}
for shape in 'ABCD':
    p=(ROOT/f'assets/harvest-warden/exports/corn/Corn_{shape}_Near/Corn_{shape}_Near.glb').read_bytes()
    n=struct.unpack_from('<I',p,12)[0];j=json.loads(p[20:20+n])
    a=j['accessors'][0];v=j['bufferViews'][a['bufferView']]
    off=20+n+8+v.get('byteOffset',0)+a.get('byteOffset',0)
    geometries['ABCD'.index(shape)+1]=list(struct.iter_unpack('<fff',p[off:off+12*a['count']]))
def quantiles(values):
    values=sorted(values)
    return {'min':values[0],'p10':values[int(.1*len(values))],'median':statistics.median(values),
            'p90':values[int(.9*len(values))],'max':values[-1]}
def overlaps(roots):
    bins={};close_pairs=0;duplicates=0;minimum=math.inf
    for r in roots:
        x,z=r[2],r[3];key=math.floor(x),math.floor(z)
        for cx in range(key[0]-1,key[0]+2):
          for cz in range(key[1]-1,key[1]+2):
            for px,pz in bins.get((cx,cz),[]):
                distance=math.hypot(x-px,z-pz);minimum=min(minimum,distance)
                close_pairs+=distance<.75;duplicates+=distance<1e-5
        bins.setdefault(key,[]).append((x,z))
    return {'distinct_cells':len(roots),'exact_duplicate_roots':duplicates,'pairs_with_root_distance_under_.75stud':close_pairs,'min_pair_distance_in_neighbor_bins':minimum}
def measure(roots):
    grid={}
    for record in roots:
        col,row,x,z,yaw,h=record
        shape=((col*73856093+row*19349663+817)%104729)%4+1
        grid.setdefault((math.floor(x/8),math.floor(z/8)),[]).append((record,shape,math.cos(yaw),math.sin(yaw)))
    rootgaps=[];leafgaps=[];both=[]
    for sample in data['samples']:
        x,z,h=sample['x'],sample['z'],sample['horizontal']
        closest=[math.inf,math.inf];leaves=[math.inf,math.inf]
        for cx in range(math.floor((x-8)/8),math.floor((x+8)/8)+1):
          for cz in range(math.floor((z-8)/8),math.floor((z+8)/8)+1):
            for record,shape,c,s in grid.get((cx,cz),[]):
                rx,rz=record[2],record[3]
                across,along=(rz-z,rx-x) if h else (rx-x,rz-z)
                if abs(across)>8 or abs(along)>3:continue
                side=int(across>=0)
                if abs(along)<1.5:closest[side]=min(closest[side],abs(across))
                for px,py,pz in geometries[shape]:
                    if not 4<=py*1.25*record[5]<=6.6: continue
                    vx,vz=rx+c*px+s*pz,rz-s*px+c*pz
                    va,vl=(vz-z,vx-x) if h else (vx-x,vz-z)
                    if abs(vl)<=1.0 and ((va>=0)==(side==1)):
                        leaves[side]=min(leaves[side],abs(va))
        rootgaps.extend(v for v in closest if v<math.inf)
        leafgaps.extend(v for v in leaves if v<math.inf)
        both.append(max(leaves))
    return {'root_side_distance_from_center':quantiles(rootgaps),
            'face_leaf_side_distance_from_center':quantiles(leafgaps),
            'side_samples_with_leaf_within_1stud_percent':100*sum(v<=1 for v in leafgaps)/len(leafgaps),
            'side_samples_with_leaf_within_2stud_percent':100*sum(v<=2 for v in leafgaps)/len(leafgaps),
            'sample_both_sides_with_leaf_within_2stud_percent':100*sum(v<=2 for v in both)/len(both)}
report={'baseline_sha256':data['baseline_sha256'],'spacing':data['spacing'],'eligible_trail_samples':len(data['samples']),
        'current_1_5padding':measure(data['normal_roots']),'zero_owned_trail_padding':measure(data['edge_roots']),
        'owned_border_projection':measure(data['projected_roots']),
        'projected_count':data['projected_count'],'max_root_shift':data['max_shift'],
        'projected_overlap':overlaps(data['projected_roots']),
        'note':'Read-only exact production grid and exclusions. Face-band leaf distances approximate Near mesh vertices at world height4..6.6 and longitudinal window2stud; they are not GPU/physics proof. Excluded samples cover hard props/spawn/key/gate/barn clearances.'}
(HERE/'edge-summary.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
