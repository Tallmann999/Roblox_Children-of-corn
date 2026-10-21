"""Assemble the closed B maze world transaction; never serialize a place."""
import json
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '.artifacts/playtests/2026-10-21-maze02'

def typed(kind, values):
    return {'kind': kind, 'value': values}

def properties(n):
    p = {}
    for field, prop in {'frame':'CFrame','size':'Size','transparency':'Transparency',
                       'material':'Material','anchored':'Anchored','collide':'CanCollide',
                       'touch':'CanTouch','query':'CanQuery','castShadow':'CastShadow',
                       'meshId':'MeshId','textureId':'TextureID'}.items():
        if field in n:
            value = n[field]
            if field == 'frame': value = typed('CFrame', value)
            if field == 'size': value = typed('Vector3', value)
            p[prop] = value
    return p

def main():
    native=json.loads((OUT/'native-before.json').read_text())
    layout=json.loads((OUT/'layout.json').read_text())
    world=json.loads((OUT/'world-delta.json').read_text())
    editor=json.loads((OUT/'editor-before.json').read_text())
    changes=world['changes'][:]
    guards=[]
    counts={}
    for n in native['nodes']:
        counts[n['path']]=counts.get(n['path'],0)+1
    for n in native['nodes']+editor['nodes']:
        g={'path':n['path'],'class':n['class'],'properties':properties(n),
           'attributes':n.get('attrs') or {},'tags':n.get('tags') or []}
        if counts.get(n['path'],0)>1 or '/Editor' in n['path']:
            g['selector']={'CFrame':typed('CFrame',n['frame'])}
            moves=[c for c in changes if c['path']==n['path'] and c['property']=='CFrame'
                   and c.get('selector')==g['selector']]
            g['installedSelector']=moves[0]['installedSelector'] if moves else g['selector']
        guards.append(g)
        if '/Editor' in n['path']:
            assert n['transparency']==0
            changes.append({'path':n['path'],'property':'Transparency','attribute':False,
                            'before':0,'after':1,'selector':g['selector'],
                            'installedSelector':g['selector']})
    owner={'corn_project_id':'children_of_corn','CornMazeOwner':'corn_maze02_v1'}
    folder='Workspace/CornMap/NoCornZones/Maze02Masks'
    nodes=[{'path':folder,'class':'Folder','properties':{},'attributes':owner,'tags':[]}]
    for segment in layout['segments']:
        if segment['kind']!='trail': continue
        x,z=segment['center_xz']; sx,sz=segment['size_xz']
        nodes.append({'path':folder+'/'+segment['id'],'class':'Part','attributes':owner,
            'tags':[], 'properties':{
                'CFrame':typed('CFrame',[x,layout['floor_y']+.055,z,1,0,0,0,1,0,0,0,1]),
                'Size':typed('Vector3',[sx,.08,sz]),
                'Color':typed('Color3',[94/255,78/255,49/255]),
                'Material':typed('Enum',['Material','Ground']),
                'Anchored':True,'CanCollide':False,'CanTouch':False,'CanQuery':False,
                'CastShadow':False,'Transparency':0,'TopSurface':typed('Enum',['SurfaceType','Smooth']),
                'BottomSurface':typed('Enum',['SurfaceType','Smooth'])}})
    payload={'owner':'corn_maze02_v1','sources':native['sources'],'changes':changes,'nodes':nodes,'guards':guards}
    data=json.dumps(payload,ensure_ascii=False,separators=(',',':'))+'\n'
    (OUT/'payload.json').write_text(data,encoding='utf-8',newline='\n')
    factory=(ROOT/'scripts/maze02-native-core.luau').read_text(encoding='utf-8')
    code='local payload=game:GetService("HttpService"):JSONDecode([====['+data+']====])\nlocal factory=(function()\n'+factory+'\nend)()\nreturn game:GetService("HttpService"):JSONEncode(factory(payload))\n'
    (ROOT/'scripts/install-maze02.luau').write_text(code,encoding='utf-8',newline='\n')
    print(json.dumps({'nodes':len(nodes),'changes':len(changes),'guards':len(guards),'editor_hidden':len(editor['nodes']),
                      'payload_sha256':hashlib.sha256(data.encode()).hexdigest(),'installer_bytes':len(code.encode())}))

if __name__=='__main__': main()
