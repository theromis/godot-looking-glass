"""Sequential capture-rate comparisons using the unchanged fast visual preset."""
import argparse,json,os,pathlib,re,subprocess
p=argparse.ArgumentParser()
p.add_argument('--godot',required=True)
p.add_argument('--runtime',required=True)
p.add_argument('--rates',nargs='+',type=float,default=[0,15,10,5])
p.add_argument('--output',default='looking_glass/tests/results-pacing.json')
a=p.parse_args()
records=[]
for rate in a.rates:
    result=subprocess.run([a.godot,'--path','.','--rendering-driver','metal','--script','looking_glass/tests/benchmark_profiles.gd','--','--profile=fast','--capture-hz='+str(rate)],env=dict(os.environ,GODOT_MTL_SYNC_MODE='none',BRIDGE_LIBRARY=a.runtime),capture_output=True,text=True,timeout=180)
    lines=(result.stdout+'\n'+result.stderr).splitlines()
    data=[json.loads(line[6:]) for line in lines if line.startswith('BENCH ')]
    errors=[re.sub(r'/Users/[^\s:]+','<local path>',line) for line in lines if line.startswith('ERROR:') or 'SCRIPT ERROR:' in line]
    record={'capture_hz_limit':rate,'exit_code':result.returncode,'measurements':data[0] if data else None,'errors':errors,'full_test_passed':result.returncode==0 and not errors and 'PASS TPS profile benchmark' in lines}
    records.append(record);print(json.dumps(record),flush=True)
    pathlib.Path(a.output).write_text(json.dumps({'date':'2026-10-12','engine':'Godot 4.8 c61fc0118 native Metal editor','hardware':'Apple M4','scope':'Same fast preset, fixed first player spawn and yaw animation, 4s warmup, 8s measurement per rate; one run per rate; process wall frame times; submission rate is not panel FPS','runs':records},indent=2)+'\n')
