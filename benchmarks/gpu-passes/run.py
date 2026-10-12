"""Compare marker profiling overhead and collect per-pass intervals serially."""
import argparse
import hashlib
import json
import pathlib
import shutil
import statistics
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
parser.add_argument('--repeats', type=int, default=3)
parser.add_argument('--suite', choices=['passes', 'overhead'], default='passes')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[2]
out = pathlib.Path(__file__).resolve().parent
lab = out / 'project'
lab.mkdir(exist_ok=True)
for name in ('addons', 'demo', 'tests'):
    if not (lab / name).exists():
        (lab / name).symlink_to(root / name, target_is_directory=True)
if not (lab / '.godot').exists():
    shutil.copytree(root / '.godot', lab / '.godot')
config = (root / 'project.godot').read_text().replace('[rendering]', '[rendering]\nlights_and_shadows/tighter_shadow_caster_culling=false')
config = config.replace('[debug]', '[debug]\nsettings/profiler/max_timestamp_query_elements=4096')
(lab / 'project.godot').write_text(config)
results = {}
scenarios = [('control', False, 128), ('profile', True, 128), ('profile-half-resolution', True, 64)] if args.suite == 'passes' else [('timing-off', False, 128), ('timing-off-independent', False, 128), ('markers-only', False, 128)]
for repeat in range(args.repeats):
    for name, profile, tile in scenarios:
        dest = out / f'{name}-{repeat + 1}'
        command = [args.godot, '--path', str(lab), '--rendering-driver', 'vulkan']
        if profile or name == 'markers-only':
            command += ['--gpu-profile']
        command += ['--', '--views=48', f'--tile={tile}', '--objects=512', '--batch-objects',
                    '--positional-lights=4', '--shared-shadows', '--no-mesh-lod', '--fixed-motion',
                    '--opaque', f'--benchmark={dest}.json']
        if name == 'timing-off-independent':
            command.remove('--shared-shadows')
        if name.startswith('timing-off'):
            command += ['--no-viewport-timing']
        if profile:
            command += ['--profile-passes']
        if repeat == 0:
            command += [f'--capture={dest}.png']
        run = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
        dest.with_suffix('.log').write_text(run.stdout)
        if run.returncode or '\nERROR:' in run.stdout or 'SCRIPT ERROR' in run.stdout:
            raise SystemExit(run.stdout)
        data = json.loads(dest.with_suffix('.json').read_text())
        if data['samples'] != 240 or not data['shared_shadow_api_available']:
            raise SystemExit('Invalid runtime or sample count')
        if profile:
            captured = data['gpu_pass_profile']
            if captured['frames'] < 200 or not any('Render Opaque Pass' in label for label in captured['adjacent_intervals_mean_ms']):
                raise SystemExit('Missing engine GPU pass timestamps')
        results.setdefault(name, []).append(data)
        print(name, repeat + 1, data['wall_frame_mean_ms'], flush=True)
summary = {}
for name, rows in results.items():
    summary[name] = {}
    for metric in ['frame_mean_ms', 'wall_frame_mean_ms', 'anchor_cpu_sum_mean_ms', 'anchor_gpu_sum_mean_ms', 'shadow_draw_calls_sum_mean', 'scene_draw_calls_sum_mean']:
        values = [row[metric] for row in rows]
        summary[name][metric] = {'mean': statistics.mean(values), 'run_stddev': statistics.stdev(values) if len(values) > 1 else None}
    if 'gpu_pass_profile' in rows[0]:
        for metric in ['adjacent_intervals_mean_ms', 'viewport_spans_mean_ms']:
            labels = set().union(*(row['gpu_pass_profile'][metric] for row in rows))
            summary[name][metric] = {label: statistics.mean(row['gpu_pass_profile'][metric].get(label, 0.0) for row in rows) for label in sorted(labels)}
        summary[name]['marker_span_mean_ms'] = statistics.mean(row['gpu_pass_profile']['marker_span_mean_ms'] for row in rows)
summary['binary_sha256'] = hashlib.sha256(pathlib.Path(args.godot).read_bytes()).hexdigest()
summary['image_sha256'] = {name: hashlib.sha256((out / f'{name}-1.png').read_bytes()).hexdigest() for name in results}
summary['limitations'] = ['Profiling timestamps alter workload; use control for performance.', 'Adjacent markers can include transitions/barriers/idle, not just named shader work.', 'Marker span does not include presentation or all asynchronous activity.']
(out / ('summary.json' if args.suite == 'passes' else 'overhead-summary.json')).write_text(json.dumps(summary, indent=2))
print(json.dumps(summary, indent=2))
