"""Compare delivery cadence, not desktop FPS as the optimization target."""
import argparse,json,os,pathlib,re,subprocess
p=argparse.ArgumentParser();p.add_argument('--godot',required=True);p.add_argument('--runtime',required=True);a=p.parse_args()
modes=[('sync',[]),('async',['--async-copy']),('sync-display-only',['--no-desktop-3d']),('sync-display-overlap',['--no-desktop-3d','--overlap']),('async-display-overlap',['--no-desktop-3d','--overlap','--async-copy'])]
records=[]
for name,flags in modes:
 r=subprocess.run([a.godot,'--path','.','--rendering-driver','metal','--script','looking_glass/tests/benchmark_profiles.gd','--','--profile=fast']+flags,env=dict(os.environ,GODOT_MTL_SYNC_MODE='none',BRIDGE_LIBRARY=a.runtime),capture_output=True,text=True,timeout=180)
 lines=(r.stdout+'\n'+r.stderr).splitlines();data=[json.loads(x[6:]) for x in lines if x.startswith('BENCH ')];errors=[re.sub(r'/Users/[^\s:]+','<local path>',x) for x in lines if x.startswith('ERROR:') or 'SCRIPT ERROR:' in x]
 record={'mode':name,'exit_code':r.returncode,'measurements':data[0] if data else None,'errors':errors,'full_test_passed':r.returncode==0 and not errors and 'PASS TPS profile benchmark' in lines};records.append(record);print(json.dumps(record),flush=True)
 pathlib.Path('looking_glass/tests/results-copy-modes.json').write_text(json.dumps({'date':'2026-10-12','engine':'Godot 4.8 c61fc0118 native Metal editor','hardware':'Apple M4','scope':'Fast preset, fixed spawn and yaw; 4s warmup, 8s sample, once per mode. Publication rate and gap are stream proxies, not physical presentation measurements. Copy latency is wall time including GPU work queued earlier and polling delay.','runs':records},indent=2)+'\n')
