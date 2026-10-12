"""Compare diagnostic snapshots; never treat empty buffers as equivalence."""
import argparse
import hashlib
import json
import math
import pathlib
import struct

parser = argparse.ArgumentParser()
parser.add_argument('--input', type=pathlib.Path, required=True)
parser.add_argument('--output', type=pathlib.Path, required=True)
args = parser.parse_args()

def compare(a, b, half):
    assert len(a) == len(b) and a, 'Missing or incompatible snapshot'
    va = [v[0] for v in struct.iter_unpack('<e', a)] if half else list(a)
    vb = [v[0] for v in struct.iter_unpack('<e', b)] if half else list(b)
    delta = [abs(x-y) for x, y in zip(va, vb)]
    assert all(math.isfinite(d) for d in delta), 'Nonfinite output'
    return dict(exact=a == b, components=len(delta), changed=sum(d != 0 for d in delta),
                max_absolute=max(delta), mean_absolute=sum(delta)/len(delta))

rows = []
for stage in ['settled', 'frozen']:
    for part, half in [('0-color', True), ('1-color', True), ('0-viewport', False),
                       ('1-viewport', False), ('quilt', True)]:
        baseline = (args.input/f'{stage}-0-{part}.bin').read_bytes()
        for rig in range(1, 9):
            row = compare(baseline, (args.input/f'{stage}-{rig}-{part}.bin').read_bytes(), half)
            row.update(stage=stage, part=part, baseline=0, compared=rig,
                       units='linear half-float color' if part.endswith('color') else
                             ('preview half-float' if half else 'viewport byte values'))
            rows.append(row)
first = (args.input/'frozen-0-0-color.bin').read_bytes()
opposite = (args.input/'frozen-1-1-color.bin').read_bytes()
manifest = {p.name: dict(bytes=p.stat().st_size, sha256=hashlib.sha256(p.read_bytes()).hexdigest())
            for p in sorted(args.input.glob('*.bin'))}
assert all(item['bytes'] for item in manifest.values()), 'Empty artifact'
args.output.write_text(json.dumps(dict(
    scope='Nine rigs; two source cameras; three capture modes and three workgroups; 120 warmup draws; 12 frozen draws',
    first_left_matches_other_right=compare(first, opposite, True)['exact'],
    rows=rows, local_artifacts=manifest), indent=2)+'\n')
print('PASS nonempty finite snapshot analysis; exact comparisons:', sum(r['exact'] for r in rows), '/', len(rows))
