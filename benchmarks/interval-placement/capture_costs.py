"""Capture all intervals of length 2/3 using five interleaved anchor grids."""
import argparse, hashlib, json, pathlib, shutil, subprocess
parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
parser.add_argument('--results-dir', type=pathlib.Path, required=True)
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[2]
out = args.results_dir.resolve()
out.mkdir(parents=True, exist_ok=True)
lab = out / 'project'
lab.mkdir(exist_ok=True)
for name in ('addons','demo','tests'):
    if not (lab/name).exists():
        (lab/name).symlink_to(root/name, target_is_directory=True)
if not (lab/'.godot').exists():
    shutil.copytree(root/'.godot', lab/'.godot')
(lab/'project.godot').write_text((root/'project.godot').read_text().replace('[rendering]', '[rendering]\nlights_and_shadows/tighter_shadow_caster_culling=false'))
layouts = []
for gap in (2,3):
    for phase in range(gap):
        anchors = sorted({0,47,*range(phase,48,gap)})
        name = f'gap{gap}-phase{phase}'
        dest = out/name
        command = [args.godot, '--path',str(lab),'--rendering-driver','vulkan','--',
                   '--views=48', f'--real={len(anchors)}', '--tile=1024',
                   '--anchors='+','.join(map(str,anchors)),
                   '--objects=512','--batch-objects','--positional-lights=4','--shared-shadows',
                   '--no-viewport-timing','--no-quilt-timing','--static','--opaque',
                   '--borrow-depth','--iterations=8','--workgroup=8x8','--rendered-benchmark',
                   f'--benchmark={dest}.json', f'--capture={dest}.png']
        try:
            run = subprocess.run(command, stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=180)
        except subprocess.TimeoutExpired as error:
            dest.with_suffix('.timeout.log').write_bytes(error.stdout or b'')
            raise SystemExit(f'Timeout: {name}')
        dest.with_suffix('.log').write_text(run.stdout)
        if run.returncode or 'SCRIPT ERROR' in run.stdout or '\nERROR:' in run.stdout:
            raise SystemExit(run.stdout)
        row = json.loads(dest.with_suffix('.json').read_text())
        if row['anchor_indices'] != anchors or row['compute_dispatches'] < 330 or row['samples'] != 240 or row['quilt_profiling_enabled']:
            raise SystemExit(f'Invalid capture: {name}')
        if row['effective_borrowed_depth_views'] != len(anchors) or row['effective_borrowed_color_views'] != len(anchors) or row['capture_fallback_reasons'] or row['disocclusion_rescue'] or row['inverse_depth_reprojection'] or row['reprojection_iterations'] != 8 or not row['shared_shadow_api_available']:
            raise SystemExit(f'Unexpected rendering configuration: {name}')
        if not dest.with_suffix('.png').exists() or dest.with_suffix('.png').stat().st_size < 1000:
            raise SystemExit(f'Missing/empty capture: {name}')
        layouts.append({'name':name,'anchors':anchors,'sha256':hashlib.sha256(dest.with_suffix('.png').read_bytes()).hexdigest()})
        (out/'layouts.json').write_text(json.dumps({'layouts':layouts,'tile':1024,'binary_sha256':hashlib.sha256(pathlib.Path(args.godot).read_bytes()).hexdigest(),'timing_status':'Quality cost capture only; no performance claims from these runs.'},indent=2))
        print('Captured', name, flush=True)
