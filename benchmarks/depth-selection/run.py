"""Sequential cost capture or independent validation; not a timing benchmark."""
import argparse,hashlib,json,pathlib,subprocess
parser=argparse.ArgumentParser()
parser.add_argument('--godot',required=True)
parser.add_argument('--results-dir',type=pathlib.Path,required=True)
parser.add_argument('--selections',type=pathlib.Path)
args=parser.parse_args()
root=pathlib.Path(__file__).resolve().parents[2];out=args.results_dir.resolve();out.mkdir(parents=True,exist_ok=True)
command=[args.godot,'--path',str(root),'--rendering-driver','vulkan','--script','res://tests/test_depth_selection.gd','--',f'--output={out}']
if args.selections: command.append('--selections='+str(args.selections.resolve()))
try: run=subprocess.run(command,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=240)
except subprocess.TimeoutExpired as error:
 (out/'timeout.log').write_bytes(error.stdout or b'');raise SystemExit('Timeout: no valid experiment')
(out/'run.log').write_text(run.stdout)
if run.returncode or 'PASS depth selection:' not in run.stdout or '\nERROR:' in run.stdout or 'SCRIPT ERROR' in run.stdout or 'FAIL ' in run.stdout: raise SystemExit(run.stdout)
raw=json.loads((out/'raw.json').read_text());stage='validation' if args.selections else 'costs'
if raw['stage']!=stage or len(raw['cases'])!=9: raise SystemExit('Incomplete experiment')
for case in raw['cases']:
 if len(case['layouts'])!=(5 if args.selections else 7): raise SystemExit('Missing layouts')
 for layout in case['layouts']:
  if layout['dispatches']<8: raise SystemExit('Missing actual compute work')
  if not (out/f'{case["name"]}-{layout["label"]}.png').exists(): raise SystemExit('Missing capture')
(out/'run.json').write_text(json.dumps({'command':command,'binary_sha256':hashlib.sha256(pathlib.Path(args.godot).read_bytes()).hexdigest(),'timing_status':'Quality experiment only, with extra candidate renders and synchronous readbacks.'},indent=2))
print('PASS',stage,'nine sampled poses; run selector/evaluation scripts for verified results')
