"""Strict engine-save B audit: only LightingStyle.Soft to Realistic."""
from pathlib import Path
import argparse,importlib.util,json,hashlib
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('b_helpers',ROOT/'scripts/verify-flashlight-copy.py')
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
r,require,identity,remap_refs=h.r,h.r.require,h.identity,h.remap_refs
BASELINE=ROOT/'place/Children_of_corn_B.before-realistic-20261020.rbxl'
BASELINE_HASH='e34fe75f598aa99c121c0e271a1b3b2ed071b5f090a9dfdb6245c116da0565d7'
OUT=ROOT/'.artifacts/playtests/2026-10-20-realistic-B'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def canonicalize(before, after):
    before_ids = {identity(node): path for path, node in before.items()}
    require(len(before_ids) == len(before), "Duplicate baseline identity")
    paths, identities, targets = {}, set(), set()
    for path, node in after.items():
        uid = identity(node)
        require(uid not in identities, "Duplicate candidate identity")
        identities.add(uid)
        target = before_ids.get(uid)
        if target is None:
            require(path in r.SELECTION_PATHS and node["class"] == "Instance"
                    and node["properties"].get("Name") == ["string", "FilteredSelection", []], "Unexpected/replaced original identity: " + path)
            target = path
        require(target not in targets, "Duplicate canonical target")
        paths[path] = target
        targets.add(target)
    require(targets == set(before), "Missing/extra original instances")
    reindexed = sum(path != target for path, target in paths.items())
    canonical = {}
    for path, target in paths.items():
        original, actual = before[target], after[path]
        require(original["class"] == actual["class"] and original["properties"]["Name"] == actual["properties"].get("Name"), "Original class/Name changed: " + target)
        parent, actual_parent = target.rpartition("/")[0], path.rpartition("/")[0]
        require((not parent and not actual_parent) or (actual_parent in paths and paths[actual_parent] == parent), "Original parent identity changed: " + target)
        canonical[target] = actual if not reindexed else actual | {"properties": {prop: remap_refs(value, paths) for prop, value in actual["properties"].items()}}
    return canonical, reindexed



def validate_dom(before,after):
 require(len(before)==len(after)==4526,'Exact4526 B instances required')
 after,reindexed=canonicalize(before,after)
 require(sum('Source' in n['properties'] for n in after.values())==153,'Exact153 saved B Sources required')
 changes=[]
 for path,node in before.items():
  actual=after[path]
  require(set(node['properties'])==set(actual['properties']),'Property set changed:'+path)
  for prop,value in node['properties'].items():
   other=actual['properties'][prop]
   if value==other or r.normalized(value)==r.normalized(other):continue
   if path=='Lighting' and prop=='LightingStyle':
    require(value==['token','1',[]] and other==['token','0',[]],'OnlySoft->Realistic permitted')
    changes.append({'path':path,'property':prop,'reason':'author_approved_B_realistic'})
   elif path=='Workspace/Camera' and prop in {'CFrame','Focus'}:
    h.old.helpers.validate_camera_frame(other)
    changes.append({'path':path,'property':prop,'reason':'finite_editor_camera'})
   elif path in r.SELECTION_PATHS and prop=='UniqueId':
    changes.append({'path':path,'property':prop,'reason':'editor_selection'})
   else:raise ValueError('Unapproved B change:'+path+'/'+prop)
 require(sum(c['reason']=='author_approved_B_realistic' for c in changes)==1,'OneLightingStyle change required')
 return {'passed':True,'complete':True,'variant':'B','original_instances':4526,'candidate_instances':4526,'sources_unchanged':153,'source_changes':0,'new_instances':0,'removed_instances':0,'reindexed_exporter_paths':reindexed,'lighting_style':'Realistic','identities_classes_names_parents_preserved':True,'world_art_other_lighting_mesh_exact':True,'changes':changes}

def check(candidate):
 require(BASELINE.stat().st_size==1485700 and sha(BASELINE)==BASELINE_HASH,'Immutable B baseline differs')
 start=sha(candidate)
 before,bw=r.p.known_dom(BASELINE);after,aw=r.p.known_dom(candidate)
 ub,ua=r.p.unknown_properties(BASELINE),r.p.unknown_properties(candidate);r.validate_unknown(ub,ua)
 report=validate_dom(before,after)
 require(sha(BASELINE)==BASELINE_HASH and sha(candidate)==start,'Inputs changed during read-only audit')
 return report|{'baseline_sha256':BASELINE_HASH,'candidate_sha256':start,'bytes':candidate.stat().st_size,'raw_terrain_exact':True,'warnings':{'baseline':bw,'candidate':aw}}
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('candidate',type=Path);p.add_argument('--report',type=Path,required=True);args=p.parse_args()
 require(args.candidate.resolve()!=BASELINE.resolve(),'Separate candidate required')
 require(args.report.resolve().is_relative_to(OUT.resolve()) and args.report.suffix=='.json','Report must stay in new evidence directory')
 result=check(args.candidate);args.report.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print(json.dumps({k:v for k,v in result.items() if k not in {'warnings','changes'}}))
