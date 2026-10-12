from pathlib import Path
import struct,zlib,json,hashlib,collections

class Node:
    def __init__(self,name,props,raw,children,has_null=False):
        self.name,self.props,self.raw,self.children,self.has_null=name,props,raw,children,has_null
    def child(self,name):return next((n for n in self.children if n.name==name),None)

def read_fbx(path):
    data=Path(path).read_bytes()
    assert data[:23]==b'Kaydara FBX Binary  \x00\x1a\x00'
    version=struct.unpack_from('<I',data,23)[0];wide=version>=7500;header=25 if wide else 13
    def node(pos):
        end,count,length,nlen=struct.unpack_from('<QQQB' if wide else '<IIIB',data,pos);pos+=header
        if end==0:return None,pos
        name=data[pos:pos+nlen].decode();pos+=nlen;raw_start=pos;raw=data[pos:pos+length];props=[]
        for _ in range(count):
            kind=chr(data[pos]);pos+=1
            if kind in 'YCFDIL':
                fmt={'Y':'h','C':'?','F':'f','D':'d','I':'i','L':'q'}[kind];value=struct.unpack_from('<'+fmt,data,pos)[0];pos+=struct.calcsize(fmt)
            elif kind in 'SR':
                size=struct.unpack_from('<I',data,pos)[0];pos+=4;value=data[pos:pos+size];pos+=size
                if kind=='S':value=value.decode('utf-8','replace')
            elif kind in 'fdlibc':
                size,encoding,packed=struct.unpack_from('<III',data,pos);pos+=12;payload=data[pos:pos+packed];pos+=packed
                assert encoding in {0,1}
                buf=zlib.decompress(payload) if encoding else payload;fmt={'f':'f','d':'d','l':'q','i':'i','b':'b','c':'b'}[kind]
                assert len(buf)==size*struct.calcsize(fmt);value=list(struct.unpack('<'+str(size)+fmt,buf))
            else:raise ValueError((name,kind,pos))
            props.append(value)
        assert pos==raw_start+length,(name,'property payload')
        children=[];has_null=False
        while pos<end:
            child,pos=node(pos)
            if child is None:has_null=True;break
            children.append(child)
        assert pos==end,(name,pos,end)
        return Node(name,props,raw,children,has_null),end
    nodes=[];pos=27
    while pos<len(data):
        n,pos=node(pos)
        if n is None:break
        nodes.append(n)
    return {'version':version,'nodes':nodes,'footer':data[pos:],'header':data[:27]}

def structural_hash(node):
    digest=hashlib.sha256(node.name.encode()+b'\x00'+node.raw)
    for child in node.children:digest.update(bytes.fromhex(structural_hash(child)))
    return digest.hexdigest()

def encode_s(value):
    raw=value.encode('utf-8');return b'S'+struct.pack('<I',len(raw))+raw

def patch_single_string(node,value):
    assert len(node.props)==1 and isinstance(node.props[0],str)
    assert node.raw==encode_s(node.props[0])
    node.props[0]=value;node.raw=encode_s(value)

def write_fbx(parsed):
    wide=parsed['version']>=7500;header_size=25 if wide else 13;null=b'\x00'*header_size
    def node(n,start):
        name=n.name.encode();position=start+header_size+len(name)+len(n.raw);parts=[]
        for child in n.children:
            part=node(child,position);parts.append(part);position+=len(part)
        if n.has_null:parts.append(null);position+=len(null)
        header=struct.pack('<QQQB' if wide else '<IIIB',position,len(n.props),len(n.raw),len(name))
        return header+name+n.raw+b''.join(parts)
    output=parsed['header']
    for n in parsed['nodes']:output+=node(n,len(output))
    output+=null
    footer=parsed['footer'];version_bytes=struct.pack('<I',parsed['version'])
    version_pos=footer.index(version_bytes,16)
    assert footer[-16:]==bytes.fromhex('f85a8c6adef5d97eece90ce3758f290b')
    assert all(v==0 for v in footer[16:version_pos])
    suffix=footer[version_pos:]
    assert len(suffix)==140 and all(v==0 for v in suffix[4:-16])
    pad=(4-(len(output)+16)%16)%16
    output+=footer[:16]+b'\x00'*pad+suffix
    assert len(output)%16==0
    return output

def prepare():
    root=Path(__file__).resolve().parent.parent
    source=Path('D:/ROBLOX/CrazeEfGG/Assets/Sort_main_ferm/Сарай серый')
    target=root/'assets/farm';target.mkdir(parents=True,exist_ok=True)
    texture=root/'assets/farm/PolygonFarm_Texture_01_A.png';png=texture.read_bytes();atlas_hash=hashlib.sha256(png).hexdigest()
    assert atlas_hash=='ae59540efad76de089c17059762d627caff3a74bc30b64dc497f0a5d855322dd'
    texture_name='PolygonFarm_Texture_01_A.png'
    if (target/texture_name).exists():assert (target/texture_name).read_bytes()==png
    else:(target/texture_name).write_bytes(png)
    records=[]
    for path in sorted(source.glob('*.fbx')):
        raw=path.read_bytes();dest=target/path.name
        if dest.exists():assert dest.read_bytes()==raw,'Refuse different original copy: '+str(dest)
        else:dest.write_bytes(raw)
        before=read_fbx(dest);after=read_fbx(dest)
        objects=next(n for n in after['nodes'] if n.name=='Objects')
        videos=[n for n in objects.children if n.name=='Video'];textures=[n for n in objects.children if n.name=='Texture']
        assert len(videos)==len(textures)==1
        changes=[]
        for video in videos:
            assert video.child('Content') is None
            for key in ('Filename','RelativeFilename'):
                leaf=video.child(key);assert leaf and 'PolygonFarm_Texture_01_A_2k.psd' in leaf.props[0]
                changes.append('Video/'+key);patch_single_string(leaf,texture_name)
            props=video.child('Properties70')
            prop=next(n for n in props.children if n.name=='P' and n.props[0]=='Path')
            old=encode_s(prop.props[-1]);assert prop.raw.endswith(old)
            prop.raw=prop.raw[:-len(old)]+encode_s(texture_name);prop.props[-1]=texture_name;changes.append('Video/Properties70/Path')
            video.children.append(Node('Content',[png],b'R'+struct.pack('<I',len(png))+png,[]));changes.append('Video/Content(add)')
        for tex in textures:
            for key in ('FileName','RelativeFilename'):
                leaf=tex.child(key);assert leaf and 'PolygonFarm_Texture_01_A_2k.psd' in leaf.props[0]
                patch_single_string(leaf,texture_name);changes.append('Texture/'+key)
        derived=target/(path.stem+'_textured.fbx');output=write_fbx(after)
        if derived.exists():assert derived.read_bytes()==output,'Refuse different derivative: '+str(derived)
        else:derived.write_bytes(output)
        reparsed=read_fbx(derived)
        original_objs=next(n for n in before['nodes'] if n.name=='Objects')
        final_objs=next(n for n in reparsed['nodes'] if n.name=='Objects')
        original_by={n.props[0]:n for n in original_objs.children};final_by={n.props[0]:n for n in final_objs.children}
        assert set(original_by)==set(final_by),'Object IDs changed'
        hashes={}
        for oid,node in original_by.items():
            if node.name in {'Video','Texture'}:continue
            hashes[node.name+':'+str(oid)]=structural_hash(node)
            assert structural_hash(node)==structural_hash(final_by[oid]),'Original object changed'
        top_hashes={}
        for node in before['nodes']:
            if node.name=='Objects':continue
            other=next(n for n in reparsed['nodes'] if n.name==node.name)
            assert structural_hash(node)==structural_hash(other),'Non-Objects node changed: '+node.name
            top_hashes[node.name]=structural_hash(node)
        video=next(n for n in final_objs.children if n.name=='Video')
        assert video.child('Content').props[0]==png
        assert dest.read_bytes()==raw and path.read_bytes()==raw
        record={'original':path.name,'source_path':str(path),'original_bytes':len(raw),'original_sha256':hashlib.sha256(raw).hexdigest(),'derived':derived.name,'derived_bytes':len(output),'derived_sha256':hashlib.sha256(output).hexdigest(),'fbx_version':before['version'],'original_object_count':len(original_by),'original_objects_except_texture_video_preserved':True,'original_object_structural_sha256':hashes,'all_other_top_level_nodes_preserved':True,'top_level_structural_sha256':top_hashes,'geometry_compressed_arrays_preserved':True,'original_connections_preserved':True,'original_global_settings_preserved':True,'changed_metadata_paths':changes,'embedded_png_sha256':atlas_hash,'embedded_png_bytes':len(png),'external_psd_reference_replaced':True,'parse_verified':True,'studio_import_verified':False}
        records.append(record)
        print(json.dumps({k:record[k] for k in ('original','derived','derived_bytes','fbx_version','original_object_count','parse_verified')},ensure_ascii=False))
    assert len(records)==4
    probe=json.loads((root/'build/farm-fbx-probe-20261012.json').read_text(encoding='utf-8'))
    report={'date':'2026-10-12','scope':'Original FBX copied byte-for-byte, existing Texture/Video metadata only changed in derived copies; no Studio or scene changes.','texture_source':str(texture),'texture_sha256':atlas_hash,'texture_layout':'Original PolygonFarm_Texture_01_A_2k PSD references confirmed on all four; the exact supplied original PolygonFarm_Texture_01_A PNG is embedded, retaining intended barn/rust palette.','assets':records,'fbx_metadata':probe,'verified':True,'studio_import_verified':False}
    (target/'asset-verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
if __name__=='__main__':prepare()
