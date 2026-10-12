"""Compare fixed reprojection limits; capture all-real reference for quality."""
import argparse
import hashlib
import json
import pathlib
import shutil
import statistics
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
parser.add_argument('--tile', type=int, default=1024)
parser.add_argument('--real', type=int, default=24)
parser.add_argument('--repeats', type=int, default=3)
parser.add_argument('--results-dir', type=pathlib.Path)
parser.add_argument('--rendered', action='store_true', help='Static scene, sample completed quilt updates')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[2]
out = args.results_dir.resolve() if args.results_dir else pathlib.Path(__file__).resolve().parent
out.mkdir(parents=True, exist_ok=True)
lab = out / 'project'
lab.mkdir(exist_ok=True)
for name in ('addons', 'demo', 'tests'):
    if not (lab / name).exists():
        (lab / name).symlink_to(root / name, target_is_directory=True)
if not (lab / '.godot').exists():
    shutil.copytree(root / '.godot', lab / '.godot')
(lab / 'project.godot').write_text((root / 'project.godot').read_text().replace('[rendering]', '[rendering]\nlights_and_shadows/tighter_shadow_caster_culling=false'))
results = {}
for repeat in range(args.repeats):
    # Alternate order to reduce monotonic thermal/scheduling bias.
    groups = ['8', '4', '2']
    names = groups[repeat % 3:] + groups[:repeat % 3]
    for name in names:
        dest = out / f'{name}-{repeat + 1}'
        command = [args.godot, '--path', str(lab), '--rendering-driver', 'vulkan', '--',
                   '--views=48', f'--real={args.real}', f'--tile={args.tile}',
                   '--objects=512', '--batch-objects', '--positional-lights=4', '--shared-shadows',
                   '--no-viewport-timing', '--fixed-motion', '--opaque', f'--benchmark={dest}.json']
        if args.rendered:
            command += ['--rendered-benchmark', '--static']
        command += ['--borrow-depth', '--workgroup=8x8', f'--iterations={name}']
        if repeat == 0:
            command.append(f'--capture={dest}.png')
        run = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        dest.with_suffix('.log').write_text(run.stdout)
        if run.returncode or '\nERROR:' in run.stdout or 'SCRIPT ERROR' in run.stdout:
            raise SystemExit(run.stdout)
        row = json.loads(dest.with_suffix('.json').read_text())
        if row['reprojection_iterations'] != int(name):
            raise SystemExit('Iteration configuration mismatch')
        if row['compute_dispatches'] < 330 or row['quilt_timestamp_samples'] < 200:
            raise SystemExit('Invalid synthesis run: no compute work or GPU timestamp samples')
        if row['samples'] != 240 or row['viewport_timing_enabled'] or not row['shared_shadow_api_available']:
            raise SystemExit('Invalid runtime or sample count')
        results.setdefault(name, []).append(row)
        print(name, repeat + 1, row['wall_frame_mean_ms'], flush=True)
summary = {}
for name, rows in results.items():
    summary[name] = {}
    for metric in ['wall_frame_mean_ms', 'frame_mean_ms', 'quilt_compute_gpu_mean_ms',
                   'quilt_submission_cpu_mean_ms', 'owned_capture_depth_bytes']:
        values = [row[metric] for row in rows if row[metric] is not None]
        if not values:
            raise SystemExit(f'Missing metric: {metric}')
        summary[name][metric] = {'mean': statistics.mean(values), 'run_stddev': statistics.stdev(values) if len(values) > 1 else None}
summary['wall_timing_anomalies'] = [
    {'variant': name, 'repeat': i + 1, 'wall_ms': row['wall_frame_mean_ms'], 'engine_delta_ms': row['frame_mean_ms']}
    for name, rows in results.items() for i, row in enumerate(rows)
    if row['wall_frame_mean_ms'] > row['frame_mean_ms'] * 1.5
]
summary['timing_status'] = 'Wall-clock anomalies; do not use wall means for speedup claims' if summary['wall_timing_anomalies'] else 'No wall/engine ratio > 1.5 detected; this is not a universal stability guarantee'
summary['image_sha256'] = {name: hashlib.sha256((out / f'{name}-1.png').read_bytes()).hexdigest() for name in results}
summary['exact_png'] = len(set(summary['image_sha256'].values())) == 1
summary['binary_sha256'] = hashlib.sha256(pathlib.Path(args.godot).read_bytes()).hexdigest()
summary['scene'] = {'output_views': 48, 'real_views': args.real, 'tile': args.tile, 'stress_objects': 512, 'transparent': False, 'rendered_sampling': args.rendered, 'static': args.rendered}
summary['limitations'] = ['No TAA, FSR2, MSAA or post-transparent effects enabled in this scene.',
                          'Iteration variants differ only in loop limit; quality may change.',
                          'Quilt GPU time excludes capture passes; its two timestamp commands remain enabled in both modes.']
(out / 'summary.json').write_text(json.dumps(summary, indent=2))
print(json.dumps(summary, indent=2))
# Render a reference with every view real, through the same HDR preview transfer.
dest = out / 'reference'
command = [args.godot, '--path', str(lab), '--rendering-driver', 'vulkan', '--',
           '--views=48', '--real=48', f'--tile={args.tile}', '--objects=512', '--batch-objects',
           '--positional-lights=4', '--shared-shadows', '--no-viewport-timing', '--opaque',
           '--borrow-depth', '--static', '--rendered-benchmark',
           f'--benchmark={dest}.json', f'--capture={dest}.png']
run = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240)
dest.with_suffix('.log').write_text(run.stdout)
if run.returncode or '\nERROR:' in run.stdout or 'SCRIPT ERROR' in run.stdout:
    raise SystemExit(run.stdout)
row = json.loads(dest.with_suffix('.json').read_text())
if row['samples'] != 240 or row['compute_dispatches'] < 330 or row['real_views'] != 48:
    raise SystemExit('Invalid all-real reference')
print('Captured all-real reference', flush=True)
