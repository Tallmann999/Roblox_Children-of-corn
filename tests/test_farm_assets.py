"""Actual file-backed FBX/neutral geometry integrity tests; no Studio or upload."""
from pathlib import Path
import importlib.util,json,math,unittest,hashlib,collections
ROOT=Path(__file__).resolve().parent.parent
def load(name,path):
 s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
fbx=load('farm_prepare_test',ROOT/'scripts/prepare-farm-assets.py')
neutral=load('farm_neutral_test',ROOT/'scripts/export-farm-editable-mesh.py')
class FarmAssets(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.report=json.loads((ROOT/'assets/farm/asset-verification.json').read_text(encoding='utf-8'))
  cls.assets={row['original']:json.loads((ROOT/'assets/farm/neutral'/(Path(row['original']).stem+'.json')).read_text(encoding='utf-8')) for row in cls.report['assets']}
 def test_originals_exact(self):
  for row in self.report['assets']:
   source=Path(row['source_path']).read_bytes();copy=(ROOT/'assets/farm'/row['original']).read_bytes()
   self.assertEqual(source,copy);self.assertEqual(hashlib.sha256(copy).hexdigest(),row['original_sha256'])
 def test_derived_preserves_all_source_geometry_models_and_connections(self):
  for row in self.report['assets']:
   before=fbx.read_fbx(ROOT/'assets/farm'/row['original']);after=fbx.read_fbx(ROOT/'assets/farm'/row['derived'])
   self.assertEqual(before['version'],after['version'])
   for node in before['nodes']:
    matching=next(n for n in after['nodes'] if n.name==node.name)
    if node.name!='Objects':self.assertEqual(fbx.structural_hash(node),fbx.structural_hash(matching))
    else:
     old={n.props[0]:n for n in node.children};new={n.props[0]:n for n in matching.children};self.assertEqual(set(old),set(new))
     for id,obj in old.items():
      if obj.name not in {'Texture','Video'}:self.assertEqual(fbx.structural_hash(obj),fbx.structural_hash(new[id]))
 def test_atlas_embedded_exact_and_existing_links_retained(self):
  png=(ROOT/'assets/farm/PolygonFarm_Texture_01_A.png').read_bytes()
  for row in self.report['assets']:
   parsed=fbx.read_fbx(ROOT/'assets/farm'/row['derived']);objects=next(n for n in parsed['nodes'] if n.name=='Objects')
   video=next(n for n in objects.children if n.name=='Video');tex=next(n for n in objects.children if n.name=='Texture')
   self.assertEqual(video.child('Content').props[0],png)
   for obj,key in [(video,'Filename'),(video,'RelativeFilename'),(tex,'FileName'),(tex,'RelativeFilename')]:self.assertEqual(obj.child(key).props[0],'PolygonFarm_Texture_01_A.png')
 def test_all_static_positions_and_pivot_cancellation_preserved(self):
  expected_counts={'SM_Bld_Barn_03.fbx':(7,8160),'SM_Prop_Truck_Rusted_01.fbx':(1,5936),'SM_Prop_Tyre_01.fbx':(1,1522),'SM_Prop_Rubbish_Pile_05.fbx':(1,608)}
  for name,asset in self.assets.items():
   parsed=fbx.read_fbx(ROOT/'assets/farm'/name);objects=next(n for n in parsed['nodes'] if n.name=='Objects');geos={n.props[0]:n for n in objects.children if n.name=='Geometry'}
   self.assertEqual((len(asset['meshes']),sum(m['triangle_count'] for m in asset['meshes'])),expected_counts[name])
   for mesh in asset['meshes']:
    values=geos[mesh['geometry_id']].child('Vertices').props[0];source=[list(values[i:i+3]) for i in range(0,len(values),3)]
    self.assertEqual(mesh['baked_world_matrix'],neutral.identity());self.assertEqual(mesh['positions'],source)
    self.assertEqual(mesh['world_bounds'],neutral.bounds(source));center=mesh['world_bounds']['center']
    for point in source:
     restored=[(p-c)+c for p,c in zip(point,center)]
     for a,b in zip(point,restored):self.assertAlmostEqual(a,b,places=9)
 def test_per_corner_uv_normal_and_concave_area_invariants(self):
  for name,asset in self.assets.items():
   parsed=fbx.read_fbx(ROOT/'assets/farm'/name);geos={n.props[0]:n for n in next(n for n in parsed['nodes'] if n.name=='Objects').children if n.name=='Geometry'}
   for mesh in asset['meshes']:
    geo=geos[mesh['geometry_id']];original=geo.child('PolygonVertexIndex').props[0]
    uv=geo.child('LayerElementUV');raw_uv=uv.child('UV').props[0];uv_index=uv.child('UVIndex').props[0]
    normal_layer=geo.child('LayerElementNormal') or geo.child('LayerElementNormals');raw_norm=normal_layer.child('Normals').props[0]
    self.assertEqual(normal_layer.child('MappingInformationType').props[0],'ByPolygonVertex');self.assertEqual(normal_layer.child('ReferenceInformationType').props[0],'Direct')
    polygons=[];current=[]
    for corner,index in enumerate(original):
     vertex=-index-1 if index<0 else index;current.append((vertex,corner))
     if index<0:polygons.append(current);current=[]
    triangle_at=0
    for polygon in polygons:
     count=len(polygon)-2;tris=mesh['triangles'][triangle_at:triangle_at+count]
     points=[mesh['positions'][p[0]] for p in polygon]
     newell=[0,0,0]
     for a,b in zip(points,points[1:]+points[:1]):
      newell[0]+=(a[1]-b[1])*(a[2]+b[2]);newell[1]+=(a[2]-b[2])*(a[0]+b[0]);newell[2]+=(a[0]-b[0])*(a[1]+b[1])
     drop=max(range(3),key=lambda i:abs(newell[i]));axes=[i for i in range(3) if i!=drop]
     def area(a,b,c):return (b[axes[0]]-a[axes[0]])*(c[axes[1]]-a[axes[1]])-(b[axes[1]]-a[axes[1]])*(c[axes[0]]-a[axes[0]])
     polygon_area=sum(a[axes[0]]*b[axes[1]]-b[axes[0]]*a[axes[1]] for a,b in zip(points,points[1:]+points[:1]))
     triangle_area=sum(area(*(mesh['positions'][id-1] for id in triangle)) for triangle in tris)
     self.assertAlmostEqual(polygon_area,triangle_area,delta=max(abs(polygon_area)*1e-8,1e-8))
     for local_index,triangle in enumerate(tris):
      t=triangle_at+local_index
      self.assertGreaterEqual(area(*(mesh['positions'][id-1] for id in triangle))*polygon_area,-1e-8)
      for corner_in_tri,vertex in enumerate(triangle):
       got_uv=mesh['uvs_fbx'][mesh['triangle_uvs'][t][corner_in_tri]-1];got_n=mesh['normals'][mesh['triangle_normals'][t][corner_in_tri]-1]
       matching=[c for v,c in polygon if v==vertex-1]
       self.assertTrue(any(got_uv==raw_uv[uv_index[c]*2:uv_index[c]*2+2] and all(abs(a-b)<1e-8 for a,b in zip(got_n,neutral.normalize(raw_norm[c*3:c*3+3]))) for c in matching),'Lost per-corner seam attribute')
     triangle_at+=count
    self.assertEqual(triangle_at,len(mesh['triangles']))
    self.assertFalse(mesh['colors']);self.assertFalse(geo.child('LayerElementColor'))
    for n in mesh['normals']:self.assertAlmostEqual(sum(x*x for x in n),1,places=8)
    for raw,flipped in zip(mesh['uvs_fbx'],mesh['uvs_roblox_flip_v']):self.assertEqual(flipped,[raw[0],1-raw[1]])
 def test_static_nonidentity_transform_formula(self):
  matrix,geo=neutral.static_matrix({'Lcl Translation':[10,20,30],'RotationPivot':[2,0,0],'PreRotation':[0,0,90],'GeometricTranslation':[1,0,0],'GeometricScaling':[2,1,1]})
  self.assertAlmostEqual(neutral.transform(neutral.mul(matrix,geo),[1,0,0])[0],12,places=8)
  self.assertAlmostEqual(neutral.transform(neutral.mul(matrix,geo),[1,0,0])[1],21,places=8)
  normal=neutral.normal_transform(neutral.mul(matrix,geo),[1,0,0]);self.assertAlmostEqual(normal[0],0,places=8);self.assertAlmostEqual(normal[1],1,places=8)
if __name__=='__main__':unittest.main(verbosity=2)
