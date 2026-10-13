"""Preserve originals and prepare named, level-matched Roblox audio imports."""
import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / '.tools/audio-python'))
import imageio_ffmpeg

SOURCES = {
    'COC_Energy_Open': 'adrenaline can open.mp3',
    'COC_Trap_Place': 'Bear trap.mp3',
    'COC_Crickets_15s': 'crickets (1).mp3',
    'COC_Hunt': 'Enemy_Hunt_00-30_to_02-00_fade (1).mp3',
    'COC_Background_02': 'Fon 2.mp3',
    'COC_Fire': 'fire.wav',
    **{'COC_Monster_' + str(i).zfill(2): 'Monster_Spider_' + str(i).zfill(2) + '.mp3' for i in range(1, 4)},
    **{'COC_Corn_' + str(i).zfill(2): 'corn/rustle' + str(i).zfill(2) + '.flac' for i in (2, 10, 11, 13, 18, 20)},
}


def run(args):
    result = subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-hide_banner', '-nostdin', *args], capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.decode('utf-8', errors='replace')[-3000:])
    return result.stderr.decode('utf-8', errors='replace')


def stats(path, channels=None, cricket=False):
    prefix = ['-stream_loop', '-1'] if cricket else []
    duration_limit = ['-t', '15'] if cricket else []
    layout = ('aformat=sample_rates=44100:channel_layouts=' + ('mono' if channels == 1 else 'stereo') + ',') if channels else ''
    log = run([*prefix, '-i', str(path), *duration_limit, '-af', layout + 'loudnorm=I=-20:TP=-4:LRA=9:print_format=json', '-f', 'null', '-'])
    match = re.search(r'\{\s*"input_i".*?\}', log, flags=re.S)
    if not match:
        raise ValueError('No loudness analysis: ' + str(path))
    duration = re.search(r'Duration: (\d+):(\d+):([\d.]+)', log)
    if not duration:
        raise ValueError('No duration: ' + str(path))
    return json.loads(match.group()), int(duration[1]) * 3600 + int(duration[2]) * 60 + float(duration[3])


def main(source):
    output = ROOT / 'assets/audio/roblox-import'
    output.mkdir(parents=True, exist_ok=True)
    report = {'source_directory': str(source), 'target_lufs': -20, 'true_peak_db': -2, 'encoding_headroom_db': -4, 'files': []}
    for name, relative in SOURCES.items():
        original = source / relative
        before = hashlib.sha256(original.read_bytes()).hexdigest()
        channels = 2 if name in ('COC_Hunt', 'COC_Background_02') else 1
        analysis, duration = stats(original, channels, name == 'COC_Crickets_15s')
        prefix = ['-stream_loop', '-1'] if name == 'COC_Crickets_15s' else []
        suffix = ['-t', '15'] if name == 'COC_Crickets_15s' else []
        # Linear matching when possible; loudnorm limits peaks for transient effects.
        measured = ':'.join(f'{key}={analysis[value]}' for key, value in (
            ('measured_I', 'input_i'), ('measured_TP', 'input_tp'), ('measured_LRA', 'input_lra'),
            ('measured_thresh', 'input_thresh'), ('offset', 'target_offset')))
        normalize = ('aformat=sample_rates=44100:channel_layouts=' + ('mono' if channels == 1 else 'stereo') +
                     ',loudnorm=I=-20:TP=-4:LRA=9:' + measured + ':linear=true,alimiter=limit=0.631:level=false:attack=1:release=30')
        if analysis['input_i'] == '-inf':
            raise ValueError('Audio is silent/too short: ' + str(original))
        target = output / (name + '.mp3')
        run(['-y', *prefix, '-i', str(original), *suffix, '-vn', '-map_metadata', '-1',
             '-af', normalize, '-ar', '44100', '-ac', str(channels), '-codec:a', 'libmp3lame',
             '-b:a', '160k' if channels == 2 else '128k', str(target)])
        matched, actual_duration = stats(target)
        assert target.stat().st_size < 20_000_000 and actual_duration < 420
        assert float(matched['input_tp']) <= -2, 'Encoded audio peak too high: ' + name
        assert hashlib.sha256(original.read_bytes()).hexdigest() == before
        report['files'].append({'key': name, 'source': relative, 'source_sha256': before,
            'source_duration_sec': duration, 'source_analysis': analysis,
            'file': str(target.relative_to(ROOT)), 'bytes': target.stat().st_size,
            'sha256': hashlib.sha256(target.read_bytes()).hexdigest(), 'duration_sec': actual_duration,
            'channels': channels, 'sample_rate': 44100, 'analysis': matched})
        print(json.dumps({'prepared': name, 'sec': actual_duration, 'lufs': matched['input_i'],
                          'peak_db': matched['input_tp']}, ensure_ascii=False), flush=True)
    (ROOT / 'assets/audio/prepared-manifest.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    main(parser.parse_args().source.resolve())
