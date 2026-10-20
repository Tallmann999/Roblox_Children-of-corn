"""Illustrative 3D flashlight previews, not a Roblox runtime recording.

Small deterministic NumPy triangle renderer. Spotlight illumination is evaluated
at world-space surface positions; all three options share one scene and motion.
"""
from pathlib import Path
import json
import math
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parent
W,H=640,360
F=H/(2*math.tan(math.radians(59)/2))
RNG=np.random.default_rng(4816)
TRI=[]

def unit(v):
    a=np.asarray(v,dtype=np.float32)
    return a/np.maximum(np.linalg.norm(a,axis=-1,keepdims=True),1e-8)

def triangle(a,b,c,col,kind=0):
    v=np.array([a,b,c],dtype=np.float32)
    n=unit(np.cross(v[1]-v[0],v[2]-v[0]))
    TRI.append((v,n,np.array(col,dtype=np.float32),kind))

def ribbon(points,width,col):
    points=np.array(points,dtype=np.float32)
    for i in range(len(points)-1):
        tangent=unit(points[i+1]-points[i])
        across=unit(np.cross(tangent,[0,1,0]))
        if np.linalg.norm(across)<.1: across=np.array([1,0,0])
        a=width*math.sin(math.pi*(i+.15)/(len(points)-.6))
        b=width*math.sin(math.pi*(i+1+.15)/(len(points)-.6))
        if i==len(points)-2:b=0
        q0=points[i]-across*a; q1=points[i]+across*a
        q2=points[i+1]+across*b; q3=points[i+1]-across*b
        triangle(q0,q1,q2,col);triangle(q0,q2,q3,np.array(col)*.87)

def make_scene():
    for side in (-1,1):
        for row in range(3):
            for k in range(20):
                x=side*(1.05+row*.46+RNG.uniform(-.15,.15))
                z=.7+k*.46+RNG.uniform(-.15,.15)
                height=RNG.uniform(2.2,2.8)
                stem=np.array([x,0,z]); lean=np.array([RNG.uniform(-.13,.13),0,RNG.uniform(-.1,.1)])
                ribbon([stem,stem+[0,height*.5,0]+lean*.5,stem+[0,height,0]+lean],.021,[.34,.29,.12])
                for j,y in enumerate(np.arange(.45,height-.1,.34)):
                    angle=j*2.37+RNG.uniform(-.4,.4)
                    direction=np.array([math.cos(angle),0,math.sin(angle)])
                    length=RNG.uniform(.47,.88)
                    start=stem+[0,y,0]+lean*y/height
                    points=[start+direction*(length*t)+[0,.38*math.sin(t*math.pi)-.28*t*t,0] for t in np.linspace(0,1,6)]
                    c=np.array([.36,.34,.17])*RNG.uniform(.75,1.1)
                    ribbon(points,.07,c)
                # Slim seed tassels give a recognisable dry corn silhouette.
                top=stem+[0,height,0]+lean
                for branch in (-1,0,1):
                    ribbon([top,top+[branch*.09,.18,.03],top+[branch*.16,.31,.04]],.009,[.42,.34,.18])
    # Two rough low stones along the path, never centred in the beam comparison.
    for x,z,s in [(-.7,3.2,.12),(.75,5.1,.18),(-.85,6.1,.11)]:
        p=np.array([x,0,z]);top=p+[0,s*.7,0]
        pts=[p+[s*math.cos(i*math.pi/3),0,s*math.sin(i*math.pi/3)] for i in range(6)]
        for i in range(6):triangle(pts[i],pts[(i+1)%6],top,[.19,.18,.16])


YY,XX=np.mgrid[0:H,0:W].astype(np.float32)
CRAYS=np.stack(((XX-W/2)/F,-(YY-H/2)/F,np.ones((H,W),dtype=np.float32)),axis=-1)

def camera(phase):
    yaw=.075*math.sin(phase)
    pitch=.009*math.sin(phase*2)
    forward=unit([math.sin(yaw),pitch,math.cos(yaw)])
    right=unit(np.cross([0,1,0],forward));up=unit(np.cross(forward,right))
    rotation=np.stack([right,up,forward],axis=1)
    position=np.array([.025*math.sin(phase),1.61+.018*math.cos(phase*2),.04*math.cos(phase)],dtype=np.float32)
    return position,rotation

def raster_triangle(v,n,col,kind,cam,rot,depth,world,normals,albedo,kinds):
    q=(v-cam)@rot
    if np.min(q[:,2])<=.04:return
    sx=W/2+q[:,0]*F/q[:,2];sy=H/2-q[:,1]*F/q[:,2]
    x0=max(0,int(math.floor(min(sx))));x1=min(W-1,int(math.ceil(max(sx))))
    y0=max(0,int(math.floor(min(sy))));y1=min(H-1,int(math.ceil(max(sy))))
    if x1<x0 or y1<y0:return
    px=XX[y0:y1+1,x0:x1+1]+.5;py=YY[y0:y1+1,x0:x1+1]+.5
    denominator=(sy[1]-sy[2])*(sx[0]-sx[2])+(sx[2]-sx[1])*(sy[0]-sy[2])
    if abs(denominator)<1e-7:return
    a=((sy[1]-sy[2])*(px-sx[2])+(sx[2]-sx[1])*(py-sy[2]))/denominator
    b=((sy[2]-sy[0])*(px-sx[2])+(sx[0]-sx[2])*(py-sy[2]))/denominator
    c=1-a-b
    iz=a/q[0,2]+b/q[1,2]+c/q[2,2]
    z=1/np.maximum(iz,1e-8)
    region=depth[y0:y1+1,x0:x1+1]
    mask=(a>=0)&(b>=0)&(c>=0)&(z<region)
    if not np.any(mask):return
    region[mask]=z[mask]
    weights=np.stack((a/q[0,2],b/q[1,2],c/q[2,2]),axis=-1)*z[...,None]
    positions=weights@v
    world[y0:y1+1,x0:x1+1][mask]=positions[mask]
    normals[y0:y1+1,x0:x1+1][mask]=n
    albedo[y0:y1+1,x0:x1+1][mask]=col
    kinds[y0:y1+1,x0:x1+1][mask]=kind

def cylinder_mesh(center,direction,length,radius,col,kind=2,sides=16):
    center=np.asarray(center);direction=unit(direction)
    side=unit(np.cross(direction,[0,1,0]));up=unit(np.cross(side,direction))
    a=center-direction*length*.5;b=center+direction*length*.5
    ring=[side*math.cos(i*2*math.pi/sides)*radius+up*math.sin(i*2*math.pi/sides)*radius for i in range(sides)]
    out=[]
    for i in range(sides):
        j=(i+1)%sides
        verts=[a+ring[i],a+ring[j],b+ring[j],b+ring[i]]
        for indices in [(0,1,2),(0,2,3)]:
            v=np.array([verts[k] for k in indices],dtype=np.float32)
            out.append((v,unit(np.cross(v[1]-v[0],v[2]-v[0])),np.array(col),kind))
        v=np.array([b,b+ring[i],b+ring[j]],dtype=np.float32)
        out.append((v,direction,np.array(col),kind))
    return out

def gbuffer(phase):
    cam,rot=camera(phase)
    rays=CRAYS@rot.T
    depth=np.full((H,W),100,dtype=np.float32)
    world=cam+rays*depth[...,None]
    normal=np.zeros((H,W,3),dtype=np.float32)
    albedo=np.full((H,W,3),.02,dtype=np.float32)
    kinds=np.zeros((H,W),dtype=np.uint8)
    # Analytic ground plane, with world-space dry dirt/track marks.
    t=-cam[1]/np.minimum(rays[:,:,1],-1e-6)
    ground=(rays[:,:,1]<0)&(t<45)
    depth[ground]=t[ground];world[ground]=(cam+rays*t[...,None])[ground];normal[ground]=[0,1,0]
    gx=world[:,:,0];gz=world[:,:,2]
    noise=.83+.12*np.sin(gx*121+gz*43)*np.sin(gx*57-gz*109)
    base=np.stack((noise*.24,noise*.20,noise*.145),axis=-1)
    tracks=(np.abs(gx-.36)<.09)|(np.abs(gx+.36)<.09)
    base[tracks]*=.78
    albedo[ground]=base[ground]
    # Old timber barn end wall. Perspective and beam projection remain physical.
    tw=(9-cam[2])/rays[:,:,2]
    hit=cam+rays*tw[...,None]
    wall=(tw>0)&(tw<depth)&(abs(hit[:,:,0])<3.6)&(hit[:,:,1]>0)&(hit[:,:,1]<3.8)
    depth[wall]=tw[wall];world[wall]=hit[wall];normal[wall]=[0,0,-1]
    bx=hit[:,:,0];by=hit[:,:,1]
    boards=.68+.17*np.sin(bx*37)+.045*np.sin(by*100+bx*17)
    seams=np.minimum(np.mod(bx+.1,.29),.29-np.mod(bx+.1,.29))<.008
    boards[seams]*=.18
    wallcol=np.stack((boards*.30,boards*.255,boards*.19),axis=-1)
    albedo[wall]=wallcol[wall]
    # A dark doorway breaks up the beam and anchors the farm setting.
    door=wall&(abs(bx-.9)<.55)&(by<2.3)
    albedo[door]=[.014,.012,.009]
    for data in TRI:raster_triangle(*data,cam,rot,depth,world,normal,albedo,kinds)
    # Compact handheld body, in camera space, points ahead toward the lit centre.
    lens_local=np.array([.22,-.19,.68],dtype=np.float32)
    direction_local=unit([-.17,.13,1])
    lens=cam+rot@lens_local;direction=rot@direction_local
    shapes=[]
    shapes+=cylinder_mesh(lens-direction*.085,direction,.17,.037,[.045,.049,.053])
    shapes+=cylinder_mesh(lens-direction*.012,direction,.032,.051,[.15,.16,.16])
    shapes+=cylinder_mesh(lens+direction*.007,direction,.006,.043,[.60,.63,.57],3)
    shapes+=cylinder_mesh(cam+rot@np.array([.29,-.29,.50]),rot@unit([-.20,.8,.5]),.16,.052,[.26,.19,.13],2)
    shapes+=cylinder_mesh(cam+rot@np.array([.34,-.40,.45]),rot@unit([-.2,.8,.5]),.16,.07,[.055,.052,.046],2)
    for data in shapes:raster_triangle(*data,cam,rot,depth,world,normal,albedo,kinds)
    return cam,rot,rays,depth,world,normal,albedo,kinds,lens,direction

def smoothstep(lo,hi,x):
    a=np.clip((x-lo)/(hi-lo),0,1);return a*a*(3-2*a)

def lighting(buffer,mode):
    cam,rot,rays,depth,world,normal,albedo,kinds,lens,direction=buffer
    vector=world-lens;distance=np.linalg.norm(vector,axis=-1)
    lightdir=vector/np.maximum(distance[...,None],1e-7)
    cosine=lightdir@direction
    if mode==1:
        outer,inner=math.cos(math.radians(13)),math.cos(math.radians(11.5))
        strength=39
    else:
        outer,inner=math.cos(math.radians(20)),math.cos(math.radians(12))
        strength=32
    cone=smoothstep(outer,inner,cosine)
    lambert=np.maximum(np.abs(np.sum(normal*-lightdir,axis=-1)),.12)
    # The light is evaluated in 3D at each receiving surface, not in screen space.
    irradiance=cone*lambert*strength/(distance*distance+1.8)
    if mode!=1:
        spill=smoothstep(math.cos(math.radians(37)),math.cos(math.radians(25)),cosine)*.8/(distance+1)
        irradiance+=spill
    color=albedo*(.011+irradiance[...,None])*np.array([1,.985,.92])
    hand=kinds==2;lens_pixels=kinds==3
    color[hand]=albedo[hand]*(.5+np.maximum(0,normal[hand]@unit([-1,1,-.7]))[:,None]*.75)
    color[lens_pixels]=albedo[lens_pixels]*1.6
    # Thin baseline air; option 3 adds actual cone/ray intersection scattering.
    fog=1-np.exp(-np.minimum(distance,35)*.016)
    color=color*(1-fog[...,None])+np.array([.0017,.0022,.0027])*fog[...,None]
    if mode==3:
        scatter=np.zeros((H,W),dtype=np.float32)
        maximum=np.minimum(depth,12)
        for i in range(36):
            t=maximum*((i+.5)/36)
            p=cam+rays*t[...,None]
            to=p-lens
            d=np.linalg.norm(to,axis=-1)
            cos=np.sum(to*direction,axis=-1)/np.maximum(d,.001)
            inside=smoothstep(outer,inner,cos)
            # Weak volumetric contribution. The cone stops at the receiving surface.
            scatter+=inside/(d*d+1.1)*maximum/36*.036
        scatter[kinds>0]=0
        color+=scatter[...,None]*np.array([.9,.94,1])
    # Display transform is identical for every option and frame.
    color=np.clip(color,0,None)
    color=color/(1+color)
    color=np.where(color<=.0031308,color*12.92,1.055*np.power(color,1/2.4)-.055)
    return Image.fromarray(np.uint8(np.clip(color,0,1)*255))

def main():
    make_scene()
    modes=[ROOT/f"mode-{i}" for i in range(1,4)]
    for folder in modes:folder.mkdir(exist_ok=True)
    count=24
    for frame in range(count):
        phase=2*math.pi*frame/count
        buffer=gbuffer(phase)
        for mode,folder in enumerate(modes,1):
            image=lighting(buffer,mode)
            image.save(folder/f"frame-{frame:02d}.png")
            if frame==0:image.save(ROOT/f"first-frame-{mode}.png")
        print(f"Rendered {frame+1}/{count}",flush=True)
    metadata={
        "illustrative":True,
        "renderer":"Deterministic NumPy 3D surface rasterizer and world-space spotlight/volume scattering",
        "not_runtime_capture":True,
        "roi_width":W,"roi_height":H,"fps":8,
        "titles":["1. Узкий луч · превью","2. Широкий мягкий · превью","3. Луч в тумане · превью"],
        "lighting_options":[{"mode":1,"outer_angle_degrees":26,"inner_angle_degrees":23},{"mode":2,"outer_angle_degrees":40,"inner_angle_degrees":24},{"mode":3,"outer_angle_degrees":40,"inner_angle_degrees":24,"volumetric_scattering":True}],
        "scene":"Illustrative corn corridor, old timber barn, short handheld flashlight",
        "motion":"Same 24-frame camera yaw, slow vertical walk sway and aim for all three variants",
    }
    (ROOT/"capture-metadata.json").write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("All illustrative frames ready",flush=True)

if __name__=="__main__":main()
