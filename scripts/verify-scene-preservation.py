"""Read-only scene comparison. Lune-known DOM plus exact unknown binary PROP payloads.
Usage: python scripts/verify-scene-preservation.py original.rbxl candidate.rbxl [--lune path/to/lune.exe]
Neither input is written. New candidate instances are allowed. Existing instances
and their properties must remain equal outside the three Rojo code containers.
Lune's decode coverage is limited; unknown binary properties are checked separately.
"""
import argparse
import base64
import collections
import hashlib
import json
import pathlib
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET
from compression import zstd

OWNED = (
    'ReplicatedStorage/GameShared',
    'ServerScriptService/GameServer',
    'StarterPlayer/StarterPlayerScripts/GameClient',
)
KNOWN_TYPES = set(range(1, 15)) | {0x10, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
    0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1E, 0x1F, 0x20, 0x21, 0x22}
HERE = pathlib.Path(__file__).resolve().parent
LUNE = HERE.parent / '.tools' / 'lune' / 'lune.exe'


def lz4_block(buf):
    out = bytearray()
    offset = 0
    while offset < len(buf):
        token = buf[offset]
        offset += 1
        literals = token >> 4
        if literals == 15:
            while True:
                count = buf[offset]
                offset += 1
                literals += count
                if count != 255:
                    break
        out.extend(buf[offset:offset + literals])
        offset += literals
        if offset == len(buf):
            break
        distance = buf[offset] | (buf[offset + 1] << 8)
        offset += 2
        length = (token & 15) + 4
        if (token & 15) == 15:
            while True:
                count = buf[offset]
                offset += 1
                length += count
                if count != 255:
                    break
        if not 0 < distance <= len(out):
            raise ValueError('Invalid LZ4 back-reference')
        for _ in range(length):
            out.append(out[-distance])
    return bytes(out)


def binary_string(buf, offset):
    length = struct.unpack_from('<I', buf, offset)[0]
    offset += 4
    if offset + length > len(buf):
        raise ValueError('Truncated binary string')
    return buf[offset:offset + length], offset + length


def unknown_properties(path):
    data = path.read_bytes()
    if data[:8] != b'<roblox!':
        return {'supported': False, 'reason': 'Input is not binary RBXL'}
    classes = {}
    props = []
    offset = 32
    while offset < len(data):
        tag, compressed, raw_len, _ = struct.unpack_from('<4sIII', data, offset)
        offset += 16
        body = data[offset:offset + (compressed or raw_len)]
        offset += compressed or raw_len
        if compressed:
            body = zstd.decompress(body) if body[:4] == b'\x28\xb5\x2f\xfd' else lz4_block(body)
        if len(body) != raw_len:
            raise ValueError('Invalid decoded chunk length')
        if tag == b'INST':
            class_id = struct.unpack_from('<I', body)[0]
            name, pos = binary_string(body, 4)
            count = struct.unpack_from('<I', body, pos + 1)[0]
            classes[class_id] = (name.decode(), count)
        elif tag == b'PROP':
            class_id = struct.unpack_from('<I', body)[0]
            name, pos = binary_string(body, 4)
            data_type = body[pos]
            if data_type not in KNOWN_TYPES:
                props.append((class_id, name.decode(), data_type, body[pos + 1:]))
        elif tag == b'END\x00':
            break
    records = {}
    for class_id, name, data_type, payload in props:
        class_name, instance_count = classes[class_id]
        records[f'{class_name}.{name}'] = {
            'type': data_type,
            'instance_count': instance_count,
            'payload_bytes': len(payload),
            'payload_sha256': hashlib.sha256(payload).hexdigest(),
            'payload_hex': payload.hex() if len(payload) <= 32 else None,
        }
    return {'supported': True, 'properties': records}


def known_dom(path):
    command = [str(LUNE), 'run', str(HERE / 'export-known-place.luau'), str(path)]
    result = subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    root = ET.fromstring(result.stdout)
    shared = {}
    for node in root.findall('./SharedStrings/SharedString'):
        shared[node.attrib.get('md5')] = base64.b64decode(node.text or '').hex()
    records = {}
    referents = {}

    def collect(children, prefix):
        occurrences = collections.Counter()
        for item in children:
            props = item.find('Properties')
            name = next((p.text or '' for p in props if p.attrib.get('name') == 'Name'), item.attrib['class'])
            key = (item.attrib['class'], name)
            occurrences[key] += 1
            component = name if occurrences[key] == 1 else f'{name}#{occurrences[key]}'
            item_path = f'{prefix}/{component}' if prefix else component
            referents[item.attrib.get('referent')] = item_path
            records[item_path] = (item.attrib['class'], props)
            collect(item.findall('Item'), item_path)
    collect(root.findall('Item'), '')

    def value(node):
        text = node.text or ''
        if node.tag == 'Ref':
            text = referents.get(text, text)
        elif node.tag == 'SharedString':
            text = shared.get(text, 'UNRESOLVED_SHARED_STRING:' + text)
        elif node.tag == 'BinaryString':
            text = base64.b64decode(text).hex()
        return [node.tag, text, [[child.tag, value(child)] for child in node]]
    canonical = {
        path: {'class': cls, 'properties': {p.attrib['name']: value(p) for p in props}}
        for path, (cls, props) in records.items()
    }
    return canonical, result.stderr.decode('utf-8', 'replace').strip()


def owned(path):
    return any(path == prefix or path.startswith(prefix + '/') for prefix in OWNED)


def compare(original, candidate):
    before, before_warnings = known_dom(original)
    after, after_warnings = known_dom(candidate)
    problems = []
    compared = 0
    for path, item in before.items():
        if owned(path):
            continue
        compared += 1
        other = after.get(path)
        if other is None:
            problems.append({'path': path, 'problem': 'missing_original_instance'})
            continue
        if item['class'] != other['class']:
            problems.append({'path': path, 'problem': 'class_changed'})
        for prop, value in item['properties'].items():
            if other['properties'].get(prop) != value:
                problems.append({'path': path, 'property': prop, 'problem': 'property_changed_or_missing'})
    unknown_before = unknown_properties(original)
    unknown_after = unknown_properties(candidate)
    unknown_check = unknown_before['supported'] and unknown_after['supported']
    if unknown_check:
        for prop, value in unknown_before['properties'].items():
            if unknown_after['properties'].get(prop) != value:
                problems.append({'property': prop, 'problem': 'unknown_raw_property_changed_or_missing'})
    else:
        problems.append({'problem': 'unknown_binary_property_check_unavailable'})
    return {
        'original': str(original), 'candidate': str(candidate),
        'original_sha256': hashlib.sha256(original.read_bytes()).hexdigest(),
        'candidate_sha256': hashlib.sha256(candidate.read_bytes()).hexdigest(),
        'original_instances': len(before), 'candidate_instances': len(after),
        'compared_original_instances': compared,
        'excluded_rojo_containers': list(OWNED),
        'known_dom_preserved': not any(p['problem'] != 'unknown_raw_property_changed_or_missing' for p in problems),
        'unknown_original_properties': unknown_before,
        'unknown_candidate_properties': unknown_after,
        'problems': problems,
        'warnings': {'original': before_warnings, 'candidate': after_warnings},
        'scope': 'Read-only comparison of Lune-known original properties and exact unknown PROP payloads; not a Studio runtime test.',
        'passed': not problems,
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('original', type=pathlib.Path)
    parser.add_argument('candidate', type=pathlib.Path)
    parser.add_argument('--lune', type=pathlib.Path, default=LUNE, help='Lune executable; default: project .tools/lune/lune.exe')
    args = parser.parse_args()
    LUNE = args.lune.resolve()
    answer = compare(args.original.resolve(), args.candidate.resolve())
    print(json.dumps(answer, ensure_ascii=False, indent=2))
    sys.exit(0 if answer['passed'] else 1)