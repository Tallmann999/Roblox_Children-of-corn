from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys

PROJECT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(PROJECT / '.tools/audio-python'))
from PIL import Image, ImageDraw
import imageio_ffmpeg

ROOT = Path(__file__).resolve().parent
SOURCE = Path('D:/Downloads/The Haunted Harvest 2022 _ Haunted Corn Maze POV _ Chino CA.mp4')
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
probe = subprocess.run([FFMPEG, '-hide_banner', '-i', str(SOURCE)], capture_output=True)
metadata = probe.stderr.decode('utf-8', errors='replace')
match = re.search(r'Duration: (\d+):(\d+):(\d+\.\d+)', metadata)
assert match, metadata
duration = int(match[1]) * 3600 + int(match[2]) * 60 + float(match[3])
report = {'source': str(SOURCE), 'bytes': SOURCE.stat().st_size,
          'sha256': hashlib.file_digest(SOURCE.open('rb'), 'sha256').hexdigest(),
          'duration_seconds': duration, 'ffmpeg_metadata': metadata, 'samples': {}}

for name, start, end, step in [('overview', 0, duration, 5), ('focus', 120, 180.01, 1)]:
    folder = ROOT / name
    folder.mkdir(exist_ok=True)
    command = [FFMPEG, '-hide_banner', '-loglevel', 'error', '-nostdin', '-y',
               '-ss', str(start), '-i', str(SOURCE), '-t', str(end - start),
               '-vf', f'select=not(mod(n\\,{int(step * 30)})),scale=640:-1',
               '-fps_mode', 'vfr', '-q:v', '2', str(folder / 'frame-%03d.jpg')]
    subprocess.run(command, check=True)
    frames = sorted(folder.glob('frame-*.jpg'))
    sheets = []
    for offset in range(0, len(frames), 12):
        group = frames[offset:offset + 12]
        sheet = Image.new('RGB', (1920, 4 * 388), (18, 18, 18))
        draw = ImageDraw.Draw(sheet)
        for j, frame in enumerate(group):
            timestamp = start + (offset + j) * step
            x, y = j % 3 * 640, j // 3 * 388
            image = Image.open(frame).convert('RGB')
            sheet.paste(image, (x, y + 28))
            draw.text((x + 8, y + 7), f'{int(timestamp)//60:02d}:{timestamp%60:05.2f} | {frame.name}', fill='white')
        target = ROOT / f'{name}-sheet-{offset//12 + 1:02d}.jpg'
        sheet.save(target, quality=92)
        sheets.append(str(target))
    report['samples'][name] = {'start': start, 'end': end, 'step': step,
                               'frames': len(frames), 'sheets': sheets}
    print(json.dumps({'set': name, 'frames': len(frames), 'sheets': sheets}), flush=True)
(ROOT / 'video-metadata.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
