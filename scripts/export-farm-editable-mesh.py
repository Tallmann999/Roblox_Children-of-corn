"""Read-only FBX static geometry extraction for EditableMesh, no uploads or scene writes."""
from pathlib import Path
import importlib.util,json,math,hashlib,collections
ROOT=Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('farmfbx',ROOT/'scripts/prepare-farm-assets.py')
fbx=importlib.util.module_from_spec(spec);spec.loader.exec_module(fbx)

def properties(node):
 p=node.child('Properties70');return {c.props[0]:c.props[4:] for c in p.children} if p else {}
def identity():return [[1.0 if i==j else 0.0 for j in range(4)] for i in range(4)]
def mul(a,b):return [[sum(a[i][k]*b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]
def translation(v):
 m=identity()
 for i in range(3):m[i][3]=v[i]
 return m
def scaling(v):
 m=identity()
 for i in range(3):m[i][i]=v[i]
 return m
def rotation(v,order=0):
 axes=['XYZ','XZY','YZX','YXZ','ZXY','ZYX'];assert order in range(6),'Unsupported spherical rotation'
 m=identity()
 for axis in axes[order]:
  a=math.radians(v['XYZ'.index(axis)]);c,s=math.cos(a),math.sin(a);r=identity()
  if axis=='X':r[1][1]=r[2][2]=c;r[1][2]=-s;r[2][1]=s
  elif axis=='Y':r[0][0]=r[2][2]=c;r[0][2]=s;r[2][0]=-s
  else:r[0][0]=r[1][1]=c;r[0][1]=-s;r[1][0]=s
  m=mul(r,m)
 return m
def inverse_rotation(m):
 n=identity()
 for i in range(3):
  for j in range(3):n[i][j]=m[j][i]
 return n
def transform(m,p):return [sum(m[i][j]*p[j] for j in range(3))+m[i][3] for i in range(3)]
def inverse3(m):
 a,b,c=m[0][:3];d,e,f=m[1][:3];g,h,i=m[2][:3]
 det=a*(e*i-f*h)-b*(d*i-f*g)+c*(d*h-e*g);assert abs(det)>1e-12,'Singular transform'
 return [[(e*i-f*h)/det,(c*h-b*i)/det,(b*f-c*e)/det],[(f*g-d*i)/det,(a*i-c*g)/det,(c*d-a*f)/det],[(d*h-e*g)/det,(b*g-a*h)/det,(a*e-b*d)/det]]
def normalize(v):
 length=math.sqrt(sum(n*n for n in v));return [n/length for n in v] if length>1e-12 else [0.0,1.0,0.0]
def normal_transform(m,v):
 inv=inverse3(m);return normalize([sum(inv[j][i]*v[j] for j in range(3)) for i in range(3)])
def sub(a,b):return [x-y for x,y in zip(a,b)]
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def bounds(points):
 low=[min(p[i] for p in points) for i in range(3)];high=[max(p[i] for p in points) for i in range(3)]
 return {'min':low,'max':high,'size':sub(high,low),'center':[(a+b)/2 for a,b in zip(low,high)]}
def triangulate(corners,points):
 if len(corners)==3:return [tuple(corners)]
 xyz=[points[c[0]] for c in corners]
 newell=[0.0,0.0,0.0]
 for p,q in zip(xyz,xyz[1:]+xyz[:1]):
  newell[0]+=(p[1]-q[1])*(p[2]+q[2]);newell[1]+=(p[2]-q[2])*(p[0]+q[0]);newell[2]+=(p[0]-q[0])*(p[1]+q[1])
 drop=max(range(3),key=lambda i:abs(newell[i]));keep=[i for i in range(3) if i!=drop];uv=[[p[i] for i in keep] for p in xyz]
 def area(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
 signed=sum(p[0]*q[1]-q[0]*p[1] for p,q in zip(uv,uv[1:]+uv[:1]));sign=1 if signed>0 else -1
 span=max(max(p[i] for p in uv)-min(p[i] for p in uv) for i in (0,1));eps=max(span*span*1e-12,1e-12)
 remaining=list(range(len(corners)));out=[]
 while len(remaining)>3:
  found=False
  for at,current in enumerate(remaining):
   prev,next_=remaining[at-1],remaining[(at+1)%len(remaining)]
   a,b,c=uv[prev],uv[current],uv[next_]
   if sign*area(a,b,c)<=eps:continue
   blocked=False
   for index in remaining:
    if index in (prev,current,next_):continue
    point=uv[index]
    if min(sign*area(a,b,point),sign*area(b,c,point),sign*area(c,a,point))>=-eps:blocked=True;break
   if blocked:continue
   out.append((corners[prev],corners[current],corners[next_]));remaining.pop(at);found=True;break
  if not found:raise ValueError('Non-simple/degenerate polygon cannot be triangulated: '+str(xyz))
 out.append(tuple(corners[i] for i in remaining));assert len(out)==len(corners)-2
 return out

def static_matrix(prop):
 get=lambda key,default:prop.get(key,default)
 order=int(get('RotationOrder',[0])[0])
 t=get('Lcl Translation',[0,0,0]);r=get('Lcl Rotation',[0,0,0]);s=get('Lcl Scaling',[1,1,1]);rp=get('RotationPivot',[0,0,0]);sp=get('ScalingPivot',[0,0,0])
 matrix=identity()
 factors=[translation(t),translation(get('RotationOffset',[0,0,0])),translation(rp),rotation(get('PreRotation',[0,0,0])),rotation(r,order),inverse_rotation(rotation(get('PostRotation',[0,0,0]))),translation([-v for v in rp]),translation(get('ScalingOffset',[0,0,0])),translation(sp),scaling(s),translation([-v for v in sp])]
 for factor in factors:matrix=mul(matrix,factor)
 geo=mul(mul(translation(get('GeometricTranslation',[0,0,0])),rotation(get('GeometricRotation',[0,0,0]))),scaling(get('GeometricScaling',[1,1,1])))
 return matrix,geo

def extract(path):
 parsed=fbx.read_fbx(path);obj=next(n for n in parsed['nodes'] if n.name=='Objects')
 model={n.props[0]:n for n in obj.children if n.name=='Model'};geos={n.props[0]:n for n in obj.children if n.name=='Geometry'}
 conn=[n.props for n in next(n for n in parsed['nodes'] if n.name=='Connections').children]
 parent={a[1]:a[2] for a in conn if a[0]=='OO' and a[1] in model and a[2] in model}
 owners={a[1]:a[2] for a in conn if a[0]=='OO' and a[1] in geos and a[2] in model}
 assert set(owners)==set(geos)
 materials={n.props[0]:n for n in obj.children if n.name=='Material'}
 assigned={a[2]:a[1] for a in conn if a[0]=='OO' and a[1] in materials and a[2] in model}
 prop={id:properties(n) for id,n in model.items()};matrices={};geo_matrices={}
 def world(id):
  if id in matrices:return matrices[id]
  local,geo=static_matrix(prop[id]);ancestor=parent.get(id)
  inheritance=int(prop[id].get('InheritType',[0])[0])
  if ancestor and inheritance!=1:
   # Actual delivered assets have identity parents; reject unsupported inheritance under transformed parents.
   assert world(ancestor)==identity(),'Nontrivial parent scale inheritance unsupported'
  matrices[id]=mul(world(ancestor),local) if ancestor else local;geo_matrices[id]=geo
  return matrices[id]
 for id in model:world(id)
 settings=properties(next(n for n in parsed['nodes'] if n.name=='GlobalSettings'))
 assert settings.get('UpAxis')==[1] and settings.get('UpAxisSign')==[1] and settings.get('CoordAxis')==[0] and settings.get('CoordAxisSign')==[1] and settings.get('FrontAxis')==[2] and settings.get('FrontAxisSign')==[1],'Unknown axis basis'
 meshes=[]
 for id,node in geos.items():
  owner=owners[id];matrix=mul(matrices[owner],geo_matrices[owner]);flat=node.child('Vertices').props[0];raw_points=list(zip(flat[::3],flat[1::3],flat[2::3]));points=[transform(matrix,p) for p in raw_points]
  indices=node.child('PolygonVertexIndex').props[0];polygons=[];current=[]
  for corner,index in enumerate(indices):
   vertex=-index-1 if index<0 else index;assert 0<=vertex<len(points);current.append((vertex,corner))
   if index<0:polygons.append(current);current=[]
  assert not current
  uv_node=node.child('LayerElementUV');norm_node=node.child('LayerElementNormal') or node.child('LayerElementNormals');color_node=node.child('LayerElementColor')
  def channel(layer,data_name,width,index_names):
   if layer is None:return [],[],None
   values=layer.child(data_name).props[0];direct=[values[i:i+width] for i in range(0,len(values),width)]
   mapping=layer.child('MappingInformationType').props[0];ref=layer.child('ReferenceInformationType').props[0]
   index_node=next((layer.child(k) for k in index_names if layer.child(k)),None)
   indices2=index_node.props[0] if index_node else None
   result=[];polygon_index=0
   for vertex,corner in [pair for polygon in polygons for pair in polygon]:
    # Recover polygon index for ByPolygon without relying on control point reuse.
    while polygon_index+1<len(polygons) and corner>=polygons[polygon_index+1][0][1]:polygon_index+=1
    mapped=corner if mapping=='ByPolygonVertex' else vertex if mapping in {'ByVertice','ByVertex'} else polygon_index if mapping=='ByPolygon' else 0 if mapping=='AllSame' else None
    assert mapped is not None,'Unknown mapping: '+mapping
    actual=indices2[mapped] if ref in {'IndexToDirect','Index'} else mapped
    assert ref in {'Direct','IndexToDirect','Index'} and 0<=actual<len(direct)
    result.append(actual)
   return direct,result,{'mapping':mapping,'reference':ref,'direct_count':len(direct)}
  uvs,uv_index,uv_meta=channel(uv_node,'UV',2,('UVIndex',));normals,norm_index,norm_meta=channel(norm_node,'Normals',3,('NormalsIndex','NormalIndex'));colors,color_index,color_meta=channel(color_node,'Colors',4,('ColorIndex','ColorsIndex'))
  assert len(uv_index)==len(indices),'UV missing'
  normals=[normal_transform(matrix,n) for n in normals]
  # Dedupe exact channel values while retaining separate per-corner assignments.
  def dedupe(values,indices2):
   unique=[];lookup={};remap=[]
   for value in values:
    key=tuple(value)
    if key not in lookup:lookup[key]=len(unique);unique.append(value)
    remap.append(lookup[key])
   return unique,[remap[i] for i in indices2]
  uvs,uv_index=dedupe(uvs,uv_index);normals,norm_index=dedupe(normals,norm_index);colors,color_index=dedupe(colors,color_index)
  triangles=[];corner_uvs=[];corner_normals=[];corner_colors=[];polygon_counts=[]
  for polygon in polygons:
   made=triangulate(polygon,points);polygon_counts.append(len(made))
   for triangle in made:
    triangles.append([corner[0]+1 for corner in triangle]);corner_uvs.append([uv_index[corner[1]]+1 for corner in triangle])
    corner_normals.append([norm_index[corner[1]]+1 for corner in triangle] if normals else [])
    corner_colors.append([color_index[corner[1]]+1 for corner in triangle] if colors else [])
  material_id=assigned.get(owner)
  ancestor=owner
  while material_id is None and ancestor in parent:ancestor=parent[ancestor];material_id=assigned.get(ancestor)
  if material_id is None and len(materials)==1:material_id=next(iter(materials))
  mesh={'model_id':owner,'geometry_id':id,'name':model[owner].props[1].split('\x00\x01')[0],'parent_model_id':parent.get(owner),'model_properties':prop[owner],'model_world_matrix':matrices[owner],'geometric_matrix':geo_matrices[owner],'baked_world_matrix':matrix,'source_local_bounds':bounds(raw_points),'world_bounds':bounds(points),'positions':points,'triangles':triangles,'uvs_fbx':uvs,'uvs_roblox_flip_v':[[u,1-v] for u,v in uvs],'triangle_uvs':corner_uvs,'normals':normals,'triangle_normals':corner_normals,'colors':colors,'triangle_colors':corner_colors,'channel_metadata':{'uv':uv_meta,'normal':norm_meta,'color':color_meta},'material':{'id':material_id,'name':materials[material_id].props[1].split('\x00\x01')[0],'properties':properties(materials[material_id])},'polygon_count':len(polygons),'polygon_sizes':dict(collections.Counter(len(p) for p in polygons)),'triangulation':'orientation-preserving projected ear clipping, including concave n-gons','triangle_count':len(triangles),'triangulation_n_minus_2_verified':all(n==len(p)-2 for n,p in zip(polygon_counts,polygons))}
  meshes.append(mesh)
 return {'file':Path(path).name,'source_sha256':hashlib.sha256(Path(path).read_bytes()).hexdigest(),'fbx_version':parsed['version'],'source_settings':settings,'index_base':1,'positions_units':'FBX source centimetres; transforms baked, no human-scale assumption applied','coordinate_basis':'Source XYZ retained (X right, Y up, source Z); winding retained','uv_policy':'Both original FBX and candidate Roblox 1-v arrays retained. Root must validate texture orientation once before upload/placement.','world_bounds':bounds([p for m in meshes for p in m['positions']]),'meshes':meshes}

def main():
 output=ROOT/'assets/farm/neutral';output.mkdir(parents=True,exist_ok=True)
 manifest=[]
 for path in sorted((ROOT/'assets/farm').glob('*.fbx')):
  if path.stem.endswith('_textured'):continue
  asset=extract(path);out=output/(path.stem+'.json');out.write_text(json.dumps(asset,separators=(',',':'),ensure_ascii=False),encoding='utf-8')
  row={'file':out.name,'bytes':out.stat().st_size,'sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'mesh_count':len(asset['meshes']),'world_bounds':asset['world_bounds'],'meshes':[{'name':m['name'],'vertices':len(m['positions']),'triangles':m['triangle_count'],'unique_uvs':len(m['uvs_fbx']),'unique_normals':len(m['normals']),'world_bounds':m['world_bounds'],'world_matrix_identity':m['baked_world_matrix']==identity()} for m in asset['meshes']]}
  manifest.append(row);print(json.dumps(row,ensure_ascii=False))
 (output/'manifest.json').write_text(json.dumps({'date':'2026-10-12','index_base':1,'assets':manifest,'no_studio_or_upload':True},ensure_ascii=False,indent=2),encoding='utf-8')
if __name__=='__main__':main()
