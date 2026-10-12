import argparse,os,pathlib,subprocess
parser=argparse.ArgumentParser(description='Run three sequential addon optimization measurements.')
parser.add_argument('stage')
parser.add_argument('tile',nargs='?',default='128')
parser.add_argument('--godot',default=os.environ.get('GODOT_LG_BIN','godot'),help='Godot on PATH or a path to the selected binary')
args=parser.parse_args()
root=pathlib.Path(__file__).resolve().parents[2];stage=args.stage;tile=args.tile
for i in range(3):
 name=f'{stage}-{i+1}';rel=f'res://benchmarks/optimization/{name}'
 cmd=[args.godot,'--path',str(root),'--rendering-driver','vulkan','--','--views=48','--real=12',f'--tile={tile}','--static','--opaque',f'--benchmark={rel}.json']
 if i==0:cmd.append(f'--capture={rel}.png')
 result=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=90)
 (root/f'benchmarks/optimization/{name}.log').write_text(result.stdout)
 if result.returncode or '\nERROR:' in result.stdout or 'SCRIPT ERROR' in result.stdout:print(result.stdout);raise SystemExit(1)
 print(name,flush=True)
