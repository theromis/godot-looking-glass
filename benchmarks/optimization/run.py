import pathlib,subprocess,sys
root=pathlib.Path(__file__).resolve().parents[2];stage=sys.argv[1];tile=sys.argv[2] if len(sys.argv)>2 else '128'
for i in range(3):
 name=f'{stage}-{i+1}';rel=f'res://benchmarks/optimization/{name}'
 cmd=['/Users/roman/work/tools/Godot.app/Contents/MacOS/Godot','--path',str(root),'--rendering-driver','vulkan','--','--views=48','--real=12',f'--tile={tile}','--static','--opaque',f'--benchmark={rel}.json']
 if i==0:cmd.append(f'--capture={rel}.png')
 result=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=90)
 (root/f'benchmarks/optimization/{name}.log').write_text(result.stdout)
 if result.returncode or '\nERROR:' in result.stdout or 'SCRIPT ERROR' in result.stdout:print(result.stdout);raise SystemExit(1)
 print(name,flush=True)
