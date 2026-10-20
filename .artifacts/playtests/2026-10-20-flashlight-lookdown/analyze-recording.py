from pathlib import Path
import hashlib,json,re,subprocess,sys
sys.path.insert(0,str(Path(__file__).resolve().parents[3]/'.tools/audio-python'))
import imageio_ffmpeg
from PIL import Image,ImageDraw

root=Path(__file__).resolve().parent
source=Path('D:/Desktop/2026-10-20 13-23-46.mp4')
ffmpeg=imageio_ffmpeg.get_ffmpeg_exe()
probe=subprocess.run([ffmpeg,'-hide_banner','-i',str(source)],capture_output=True)
info=probe.stderr.decode('utf-8',errors='replace')
m=re.search(r'Duration: (\d+):(\d+):(\d+\.\d+)',info);assert m,info
duration=int(m[1])*3600+int(m[2])*60+float(m[3])
times=[duration*x for x in (.02,.11,.2,.29,.38,.47,.56,.65,.74,.83,.92,.98)]
sheet=Image.new('RGB',(1600,4*474),(18,18,18))
for i,time in enumerate(times):
    target=root/f'recording-{i:02d}.jpg'
    subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-nostdin','-y','-ss',str(time),'-i',str(source),'-frames:v','1','-vf','scale=800:-1',str(target)],check=True)
    im=Image.open(target).convert('RGB');im.thumbnail((800,450))
    x,y=(i%2)*800,(i//2)*474
    if y+474>sheet.height:
        bigger=Image.new('RGB',(1600,y+474),(18,18,18));bigger.paste(sheet,(0,0));sheet=bigger
    sheet.paste(im,(x,y+24));ImageDraw.Draw(sheet).text((x+8,y+5),f'{time:.2f} s',fill='white')
sheet.save(root/'recording-contact-sheet.jpg',quality=92)
(root/'recording.json').write_text(json.dumps({'path':str(source),'bytes':source.stat().st_size,'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'duration':duration,'frames_at':times,'ffmpeg_metadata':info},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'duration':duration,'frames':len(times),'sheet':str(root/'recording-contact-sheet.jpg')}))
