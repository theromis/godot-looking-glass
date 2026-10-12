"""Interleaved same-scene instances/MultiMesh plus pixel-cost control."""
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
parser.add_argument('--suite', choices=['instances', 'synthesis'], default='instances')
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
(lab / 'project.godot').write_text((root / 'project.godot').read_text().replace(
    '[rendering]', '[rendering]\nlights_and_shadows/tighter_shadow_caster_culling=false'))
results = {}
scenarios = [('instances', 128, False, 48), ('multimesh', 128, True, 48), ('instances-half-resolution', 64, False, 48)] if args.suite == 'instances' else [('synthesis-12', 128, True, 12), ('synthesis-24', 128, True, 24)]
for repeat in range(args.repeats):
    for name, tile, batch, real in scenarios:
        dest = out / f'{name}-{repeat + 1}'
        command = [args.godot, '--path', str(lab), '--rendering-driver', 'vulkan', '--',
                   '--views=48', f'--tile={tile}', '--objects=512', '--positional-lights=4',
                   '--no-mesh-lod', '--fixed-motion', '--opaque', '--shared-shadows',
                   f'--benchmark={dest}.json']
        if real != 48:
            command.append(f'--real={real}')
        if batch:
            command.append('--batch-objects')
        if repeat == 0:
            command.append(f'--capture={dest}.png')
        run = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        dest.with_suffix('.log').write_text(run.stdout)
        if run.returncode or '\nERROR:' in run.stdout or 'SCRIPT ERROR' in run.stdout:
            raise SystemExit(run.stdout)
        data = json.loads(dest.with_suffix('.json').read_text())
        if data['samples'] != 240:
            raise SystemExit('Invalid sample count')
        if not data['shared_shadow_api_available']:
            raise SystemExit('Shared shadow patch required for this experiment')
        results.setdefault(name, []).append(data)
        print(name, repeat + 1, data['frame_mean_ms'], flush=True)
metrics = ['frame_mean_ms', 'anchor_gpu_sum_mean_ms', 'anchor_cpu_sum_mean_ms',
           'frame_setup_cpu_mean_ms', 'scene_draw_calls_sum_mean', 'shadow_draw_calls_sum_mean']
summary = {name: {metric: {'mean': statistics.mean(row[metric] for row in rows),
                         'run_stddev': statistics.stdev(row[metric] for row in rows) if len(rows) > 1 else None}
                  for metric in metrics} for name, rows in results.items()}
if args.suite == 'synthesis':
    for name, rows in results.items():
        summary[name]['quilt_compute_gpu_mean_ms'] = {'mean': statistics.mean(row['quilt_compute_gpu_mean_ms'] for row in rows)}
summary['image_sha256'] = {name: hashlib.sha256((out / f'{name}-1.png').read_bytes()).hexdigest()
                           for name in results}
if args.suite == 'synthesis' and (out / 'multimesh-1.png').exists():
    quality = {}
    for name in results:
        comparison = subprocess.run([args.godot, '--headless', '--path', str(lab),
                                     '--script', 'res://tests/compare_images.gd', '--',
                                     str(out / 'multimesh-1.png'), str(out / f'{name}-1.png')],
                                    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
        (out / f'quality-{name.split("-")[-1]}.log').write_text(comparison.stdout)
        if comparison.returncode or 'ERROR:' in comparison.stdout:
            raise SystemExit(comparison.stdout)
        quality[name] = next(json.loads(line) for line in comparison.stdout.splitlines() if line.startswith('{'))
    summary['quality_against_all_real'] = quality
    summary['quality_note'] = 'Full quilt RGB error includes gamma/tonemapping mismatch; not isolated reprojection error'
summary['binary_sha256'] = hashlib.sha256(pathlib.Path(args.godot).read_bytes()).hexdigest()
summary['notes'] = ['48 output views, 512 static boxes plus moving original caster, four spots, shared shadows',
                    'Synthesis suite uses 12 or 24 real views with MultiMesh; different quality and preview transfer function',
                    'Viewport CPU/GPU sums are not frame critical path; CPU excludes main/quilt viewport',
                    'Half-resolution changes image quality and pixel count; it is a bottleneck control']
(out / ('summary.json' if args.suite == 'instances' else 'synthesis-summary.json')).write_text(json.dumps(summary, indent=2))
print(json.dumps(summary, indent=2))
