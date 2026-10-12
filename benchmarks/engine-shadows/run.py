"""Same binary/config, interleaved baseline/shared; isolate imports from main project."""
import pathlib, subprocess, sys, shutil
root=pathlib.Path(__file__).resolve().parents[2]
binary=sys.argv[1]
views=int(sys.argv[2]) if len(sys.argv)>2 else 12
prefix=f"v{views}-" if views!=12 else ""
lab=root/'benchmarks/engine-shadows/project'
lab.mkdir(exist_ok=True)
for name in ('addons','demo','tests'):
    dest=lab/name
    if not dest.exists(): dest.symlink_to(root/name, target_is_directory=True)
if not (lab/'.godot').exists(): shutil.copytree(root/'.godot',lab/'.godot')
config=(root/'project.godot').read_text().replace('[rendering]','[rendering]\nlights_and_shadows/tighter_shadow_caster_culling=false')
(lab/'project.godot').write_text(config)
for i in range(3):
 for shared in (False,True):
    name=prefix+f'{"shared" if shared else "baseline"}-{i+1}'
    dest=root/'benchmarks/engine-shadows'/name
    cmd=[binary,'--path',str(lab),'--rendering-driver','vulkan','--',f'--views={views}','--tile=128','--positional-lights=4','--no-mesh-lod','--fixed-motion','--opaque',f'--benchmark={dest}.json']
    if shared: cmd.append('--shared-shadows')
    if i==0: cmd.append(f'--capture={dest}.png')
    result=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=120)
    dest.with_suffix('.log').write_text(result.stdout)
    if result.returncode or '\nERROR:' in result.stdout or 'SCRIPT ERROR' in result.stdout:
        print(result.stdout);raise SystemExit(1)
    if not dest.with_suffix('.json').exists(): raise SystemExit('Missing benchmark output')
    print(name,flush=True)
