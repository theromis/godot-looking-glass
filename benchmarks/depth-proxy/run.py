"""Run and validate the offline depth-only diagnostic; no performance claim."""
import argparse,hashlib,json,pathlib,subprocess
parser=argparse.ArgumentParser()
parser.add_argument('--godot',required=True)
parser.add_argument('--results-dir',type=pathlib.Path,required=True)
parser.add_argument('--grid',type=int,choices=[64,128,256],default=64)
parser.add_argument('--motion',action='store_true')
args=parser.parse_args()
root=pathlib.Path(__file__).resolve().parents[2]
out=args.results_dir.resolve();out.mkdir(parents=True,exist_ok=True)
command=[args.godot,'--path',str(root),'--rendering-driver','vulkan','--script','res://tests/test_depth_proxy.gd','--',f'--output={out}',f'--grid={args.grid}']
if args.motion: command.append('--continuous-motion')
try:
    run=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=120)
except subprocess.TimeoutExpired as error:
    (out/'timeout.log').write_bytes(error.stdout or b'')
    raise SystemExit('Timeout: no valid diagnostic result')
(out/'run.log').write_text(run.stdout)
if run.returncode or 'PASS depth proxy:' not in run.stdout or 'SCRIPT ERROR' in run.stdout or '\nERROR:' in run.stdout or 'FAIL ' in run.stdout:
    raise SystemExit(run.stdout)
raw=json.loads((out/'raw.json').read_text())
if len(raw['rows'])!=9 or raw['continuous_motion']!=args.motion: raise SystemExit('Incomplete run')
for case in raw['rows']:
    if case['sample_grid'] != [args.grid,args.grid] or case['readback_bytes'] != 12*args.grid**2 or len(case['rows'])!=48: raise SystemExit('Probe configuration mismatch')
    if len(case['anchor_indices'])!=16 or case['dispatches']<8: raise SystemExit('Missing synthesis work')
    if not all(0<=v<=args.grid**2 and (not row['real'] or v==0) for row in case['rows'] for v in row['counts']): raise SystemExit('Invalid GPU counters')
    for kind in ['synth','reference']:
        if (out/f'{case["name"]}-{kind}.png').stat().st_size<1000: raise SystemExit('Empty capture')
(out/'run.json').write_text(json.dumps({'command':command,'binary_sha256':hashlib.sha256(pathlib.Path(args.godot).read_bytes()).hexdigest(),'timing_status':'Diagnostic with synchronous readbacks, not a performance benchmark.'},indent=2))
print('PASS depth diagnostic: nine cases; run analyze.py with Pillow/NumPy to validate real pixels and evaluate correlation')
