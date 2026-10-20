from pathlib import Path
import hashlib, json, re, subprocess, sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / '.tools/audio-python'))
import imageio_ffmpeg
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parent
source = Path('D:/Desktop/2026-10-20 11-49-35.mp4')
ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
probe = subprocess.run([ffmpeg, '-hide_banner', '-i', str(source)], capture_output=True)
info = probe.stderr.decode('utf-8', errors='replace')
m = re.search(r'Duration: (\d+):(\d+):(\d+\.\d+)', info)
assert m, info
duration = int(m[1])*3600 + int(m[2])*60 + float(m[3])
times = [duration * x for x in (.02,.15,.29,.43,.57,.71,.85,.97)]
sheet = Image.new('RGB', (1280, 4*384), (18,18,18))
for i, time in enumerate(times):
    target = root / f'reference-{i:02d}.jpg'
    subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-nostdin','-y','-ss',str(time),'-i',str(source),'-frames:v','1','-vf','scale=640:-1',str(target)], check=True)
    im = Image.open(target).convert('RGB'); im.thumbnail((640,360))
    x,y=(i%2)*640,(i//2)*384
    sheet.paste(im,(x,y+24)); ImageDraw.Draw(sheet).text((x+8,y+5),f'{time:.2f} s',fill='white')
sheet.save(root/'reference-contact-sheet.jpg',quality=92)
(root/'reference-video.json').write_text(json.dumps({'path':str(source),'bytes':source.stat().st_size,'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'duration':duration,'frames_at':times,'ffmpeg_metadata':info},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'duration':duration,'frames':len(times),'sheet':str(root/'reference-contact-sheet.jpg')}))
