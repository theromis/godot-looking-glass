"""Sequential profiled depth-probe overhead on latest local Godot 4.8 only."""
import argparse,hashlib,json,pathlib,statistics,subprocess
parser=argparse.ArgumentParser()
parser.add_argument('--godot',required=True)
parser.add_argument('--results-dir',type=pathlib.Path,required=True)
parser.add_argument('--tile',type=int,default=1024)
parser.add_argument('--repeats',type=int,default=3)
parser.add_argument('--isolate',action='store_true',help='Calibrated GPU timer with explicit blit encoder boundaries')
args=parser.parse_args();root=pathlib.Path(__file__).resolve().parents[2];out=args.results_dir.resolve();out.mkdir(parents=True,exist_ok=True)
lab=out/'project';lab.mkdir(exist_ok=True)
for name in ['addons','demo','tests']:
 if not (lab/name).exists(): (lab/name).symlink_to(root/name,target_is_directory=True)
(lab/'.godot').mkdir(exist_ok=True)
(lab/'.godot/global_script_class_cache.cfg').write_text((root/'.godot/global_script_class_cache.cfg').read_text())
if not (lab/'.godot/imported').exists(): (lab/'.godot/imported').symlink_to(root/'.godot/imported',target_is_directory=True)
(lab/'project.godot').write_text((root/'project.godot').read_text().replace('[rendering]','[rendering]\nlights_and_shadows/tighter_shadow_caster_culling=false'))
modes=[('async256_every16',256,16,False),('async_reduced256_every16',256,16,False)]
if args.isolate: modes=[('timer_idle',0,1,False),('gpu256',256,1,False),('gpu_reduced256',256,1,False)]
warmup,frames=(30,60) if args.isolate else (90,240)
results={};images={}
for repeat in range(args.repeats):
 ordered=modes[repeat:]+modes[:repeat]
 for name,grid,period,sync in ordered:
  dest=out/f'{name}-{repeat+1}'
  cmd=[args.godot,'--path',str(lab),'res://tests/benchmark_depth_overhead.tscn','--rendering-driver','vulkan','--','--views=48','--real=24',f'--tile={args.tile}','--objects=512','--batch-objects','--positional-lights=4','--shared-shadows','--no-viewport-timing','--static','--opaque','--rendered-benchmark','--borrow-depth','--iterations=8','--workgroup=8x8',f'--benchmark={dest}.json',f'--probe-grid={grid}',f'--probe-period={period}']
  cmd += [f'--bench-warmup={warmup}',f'--bench-frames={frames}']
  if args.isolate: cmd.append('--probe-isolate-timer')
  if name.startswith('async'): cmd.append('--probe-async')
  if 'reduced' in name: cmd.append('--probe-reduce-gpu')
  if sync: cmd.append('--probe-sync')
  if repeat==0: cmd.append(f'--capture={dest}.png')
  try: run=subprocess.run(cmd,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=240)
  except subprocess.TimeoutExpired as error:
   dest.with_suffix('.timeout.log').write_bytes(error.stdout or b'');raise SystemExit('Timeout: '+name)
  dest.with_suffix('.log').write_text(run.stdout)
  if run.returncode or '\nERROR:' in run.stdout or 'SCRIPT ERROR' in run.stdout or 'FAIL ' in run.stdout: raise SystemExit(run.stdout)
  row=json.loads(dest.with_suffix('.json').read_text());probe=json.loads(pathlib.Path(str(dest)+'.json.probe.json').read_text())
  if row['godot']['major']!=4 or row['godot']['minor']!=8: raise SystemExit('Only current 4.8-dev allowed')
  if row['samples']!=frames or row['compute_dispatches']<warmup+frames or row['real_views']!=24 or row['effective_borrowed_depth_views']!=24 or row['viewport_timing_enabled'] or not row['shared_shadow_api_available']: raise SystemExit('Invalid quilt workload')
  if probe['grid']!=grid or probe['period']!=period or probe['synchronous_feedback']!=sync or probe['configuration_error']: raise SystemExit('Probe mode mismatch')
  if grid or args.isolate:
   expected=sum(i%period==0 for i in range(warmup+1,warmup+frames+1))
   if probe['measured_dispatches']!=expected or (args.isolate and len(probe['gpu_ms'])!=expected) or len(probe['submission_ms'])!=expected: raise SystemExit('Missing measured probe timestamps/work')
   if len(probe['feedback_ms'])!=(expected if sync or name.startswith('async') else 0): raise SystemExit('Invalid feedback samples')
   if grid and (probe['readback_bytes']!=(768 if 'reduced' in name else 12*grid*grid) or len(probe['validation_counts']['rows'])!=48): raise SystemExit('Incomplete probe feedback')
   for view in probe['validation_counts'].get('rows',[]):
    if any(v<0 or v>grid*grid or (view['real'] and v!=0) for v in view['counts']): raise SystemExit('Invalid counters')
  elif probe['dispatches'] or probe['gpu_ms'] or probe['feedback_ms']: raise SystemExit('Disabled probe still records')
  if not probe['reduction_exact'] or probe['gpu_reduction']!=('reduced' in name): raise SystemExit('GPU reduction mismatch')
  if probe['pending_feedback'] or probe['asynchronous_feedback']!=name.startswith('async'): raise SystemExit('Incomplete async callback or mode mismatch')
  entry={'quilt':row,'probe':probe,'wall_engine_anomaly':row['wall_frame_mean_ms']>row['frame_mean_ms']*1.5}
  results.setdefault(name,[]).append(entry)
  if repeat==0: images[name]=hashlib.sha256(dest.with_suffix('.png').read_bytes()).hexdigest()
  print(name,repeat+1,round(row['wall_frame_mean_ms'],3),flush=True)
summary={'binary_sha256':hashlib.sha256(pathlib.Path(args.godot).read_bytes()).hexdigest(),'image_sha256':images,'exact_png':len(set(images.values()))==1,'modes':{},'anomalies':[],'isolated_timer':args.isolate,'warmup':warmup,'samples_per_run':frames,'gpu_timing_status':'Encoder-boundary isolation with empty timer calibration' if args.isolate else 'Raw probe deltas invalid on MoltenVK: stage queries share an encoder','scene':{'output_views':48,'real_views':24,'tile':args.tile,'objects':512,'static':True,'shared_spotlights':4},'limitations':['Profiled experiment: quilt markers enabled in all runs, probe markers when active.','GPU timing excludes setup, buffer readback and CPU reduction; submission timer excludes initialization.','Feedback timer includes queued GPU waits, readback and GDScript block reduction; it is not pure transfer time.','Observed quilt update intervals include scheduling/presentation; no hardware-display FPS claim.']}
for name,rows in results.items():
 metrics={'wall_ms':[r['quilt']['wall_frame_mean_ms'] for r in rows],'probe_interval_ms':[statistics.mean(r['probe']['gpu_ms']) for r in rows if r['probe']['gpu_ms']], 'submission_ms':[statistics.mean(r['probe']['submission_ms']) for r in rows if r['probe']['submission_ms']], 'feedback_latency_ms':[statistics.mean(r['probe']['feedback_latency_ms']) for r in rows if r['probe']['feedback_latency_ms']], 'feedback_ms':[statistics.mean(r['probe']['feedback_ms']) for r in rows if r['probe']['feedback_ms']]}
 summary['modes'][name]={k:{'mean':statistics.mean(v),'run_stddev':statistics.stdev(v) if len(v)>1 else None} if v else None for k,v in metrics.items()}
 for i,r in enumerate(rows):
  if r['wall_engine_anomaly']: summary['anomalies'].append({'mode':name,'repeat':i+1,'wall_ms':r['quilt']['wall_frame_mean_ms'],'engine_ms':r['quilt']['frame_mean_ms']})
(out/'summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary,indent=2))
if not summary['exact_png']: raise SystemExit('Probe changed quilt output')
