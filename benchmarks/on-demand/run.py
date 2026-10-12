"""Static idle-work experiment; presentation intervals are not new-quilt FPS."""
import argparse,hashlib,json,pathlib,statistics,subprocess
p=argparse.ArgumentParser();p.add_argument('--godot',required=True);p.add_argument('--results-dir',type=pathlib.Path,required=True);args=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[2];out=args.results_dir.resolve();out.mkdir(parents=True,exist_ok=True);lab=out/'project';lab.mkdir(exist_ok=True)
for name in ['addons','demo','tests']:
 if not (lab/name).exists(): (lab/name).symlink_to(root/name,target_is_directory=True)
(lab/'.godot').mkdir(exist_ok=True)
(lab/'.godot/global_script_class_cache.cfg').write_text((root/'.godot/global_script_class_cache.cfg').read_text())
if not (lab/'.godot/imported').exists(): (lab/'.godot/imported').symlink_to(root/'.godot/imported',target_is_directory=True)
(lab/'project.godot').write_text((root/'project.godot').read_text().replace('[rendering]','[rendering]\nlights_and_shadows/tighter_shadow_caster_culling=false'))
rows={};images={}
for repeat in range(3):
 for name in (['continuous','on_demand'] if repeat%2==0 else ['on_demand','continuous']):
  dest=out/f'{name}-{repeat+1}'
  command=[args.godot,'--path',str(lab),'res://tests/benchmark_on_demand.tscn','--rendering-driver','vulkan','--','--views=48','--real=24','--tile=1024','--objects=512','--batch-objects','--positional-lights=4','--shared-shadows','--no-viewport-timing','--no-quilt-timing','--static','--opaque','--borrow-depth',f'--benchmark={dest}.json']
  if name=='on_demand': command.append('--on-demand')
  if repeat==0: command.append(f'--capture={dest}.png')
  run=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=180)
  dest.with_suffix('.log').write_text(run.stdout)
  if run.returncode or 'SCRIPT ERROR' in run.stdout or '\nERROR:' in run.stdout or 'FAIL ' in run.stdout: raise SystemExit(run.stdout)
  row=json.loads(dest.with_suffix('.json').read_text())
  if row['godot']['minor']!=8 or row['samples']!=240 or row['real_views']!=24 or row['benchmark_sampling']!='process calls' or row['quilt_profiling_enabled'] or row['viewport_timing_enabled']: raise SystemExit('Invalid workload')
  if row['update_on_demand']!=(name=='on_demand') or row['effective_borrowed_depth_views']!=24: raise SystemExit('Wrong render/capture mode')
  if name=='on_demand':
   if row['compute_dispatches']!=2 or row['source_capture_counts']!=[2]*24 or row['requested_revision']!=row['completed_revision']: raise SystemExit('Idle rendering continues or refresh incomplete')
  elif row['compute_dispatches']<300 or min(row['source_capture_counts'])<300: raise SystemExit('Continuous rendering not executed')
  rows.setdefault(name,[]).append(row)
  if repeat==0: images[name]=hashlib.sha256(dest.with_suffix('.png').read_bytes()).hexdigest()
  print(name,repeat+1,row['wall_frame_mean_ms'],row['compute_dispatches'],flush=True)
summary={'binary_sha256':hashlib.sha256(pathlib.Path(args.godot).read_bytes()).hexdigest(),'images':images,'exact_png':len(set(images.values()))==1,'modes':{},'scene':{'real':24,'output':48,'tile':1024,'static_opaque_objects':512,'shared_spotlights':4},'metric':'Observed process/presentation interval during static idle; not new-quilt throughput','warmup':90,'explicit_refresh_process_frame':86,'samples_per_run':240,'repeats':3,'limitations':['No physical display, power measurement or dynamic-scene speedup.','UPDATE_ONCE removes repeated scene and compute work; cached quilt is still presented.','Object/light/material/shader/particle/environment changes require explicit request_update().','Main viewport and preview continue rendering; buffers remain allocated.']}
for name,group in rows.items():
 values=[r['wall_frame_mean_ms'] for r in group];summary['modes'][name]={'wall_ms_mean':statistics.mean(values),'wall_ms_run_stddev':statistics.stdev(values),'compute_dispatches':[r['compute_dispatches'] for r in group],'source_capture_counts':[r['source_capture_counts'] for r in group]}
(out/'summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary,indent=2))
if not summary['exact_png']: raise SystemExit('Initial cached quilt differs from continuous final image')
