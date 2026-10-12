"""Bounded IOSurface GPU-sharing experiment. Run from project root; no SDK in Godot process."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import secrets
import ctypes
import select
import threading
import time
import tempfile
from concurrent.futures import ThreadPoolExecutor

parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
parser.add_argument('--runtime', required=True)
parser.add_argument('--display-index', default='1')
parser.add_argument('--large', action='store_true')
parser.add_argument('--verify', action='store_true')
parser.add_argument('--uncapped', action='store_true')
parser.add_argument('--adaptive-flush', action='store_true')
parser.add_argument('--validate-flush', action='store_true')
parser.add_argument('--check-before-draw', action='store_true')
parser.add_argument('--capture-compose', action='store_true')
parser.add_argument('--full-shadow-casters', action='store_true')
parser.add_argument('--warm-shadow-mode', default='shared', choices=('both','shared','independent'))
parser.add_argument('--warm-shadow-draws', default=1, type=int, choices=(1,2,4,8))
parser.add_argument('--warm-shadow-atlases', action='store_true')
parser.add_argument('--collect-shadow-diffs', action='store_true')
parser.add_argument('--shared-shadows', action='store_true')
parser.add_argument('--no-shadows', action='store_true')
parser.add_argument('--no-alpha-panel', action='store_true')
parser.add_argument('--complex-scene', action='store_true')
parser.add_argument('--run-label', default='')
parser.add_argument('--real-views', type=int, default=66, choices=(12,24,36,48,66))
parser.add_argument('--duration', type=int, default=20, help='Bounded worker duration in seconds (20–600).')
args = parser.parse_args()
if args.run_label and not re.fullmatch(r"[a-z0-9-]{1,48}",args.run_label): parser.error("--run-label requires 1–48 lowercase letters, digits or hyphens")
if args.warm_shadow_atlases and not args.shared_shadows: parser.error("--warm-shadow-atlases requires --shared-shadows")
if args.collect_shadow_diffs and not (args.shared_shadows and args.validate_flush): parser.error("--collect-shadow-diffs requires --shared-shadows --validate-flush")
if args.shared_shadows and not args.full_shadow_casters: parser.error("--shared-shadows requires --full-shadow-casters for the isolated compatible fixture")
if args.capture_compose and not args.adaptive_flush: parser.error("--capture-compose requires --adaptive-flush")
if args.check_before_draw and not (args.adaptive_flush and (args.validate_flush or args.capture_compose)): parser.error("--check-before-draw is a validation-only negative control; requires --adaptive-flush --validate-flush")
if not 20 <= args.duration <= 600: parser.error("--duration must be between 20 and 600")
suffix = (['--large'] if args.large else [])+(['--verify'] if args.verify else [])
if args.duration != 20: suffix += ['--duration='+str(args.duration)]
if args.uncapped: suffix += ['--uncapped']
stage=None
project_path='.'
if args.full_shadow_casters:
    stage=tempfile.TemporaryDirectory(prefix='lg-shadow-project-')
    staged=Path(stage.name)
    for entry in ('addons','tests','native','.godot','benchmarks'):
        if Path(entry).exists(): (staged/entry).symlink_to(Path(entry).resolve(),target_is_directory=True)
    (staged/'project.godot').write_text(Path('project.godot').read_text()+'\n[rendering]\nlights_and_shadows/tighter_shadow_caster_culling=false\n')
    project_path=str(staged)
worker = producer = None
worker_reader=None
stop_sampling=threading.Event()
memory_samples=[]
sampler=None
name = '/lg'+secrets.token_hex(6)
try:
        worker = subprocess.Popen(['native/bridge_metal/build/probe-persistent', args.runtime, args.display_index,
                                   '--experimental-reuse', '--live-surface='+name]+suffix, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, text=True)
        if not select.select([worker.stdout],[],[],5)[0] or worker.stdout.readline().strip()!='SURFACE ready':
            raise RuntimeError('Shared-memory worker did not become ready')
        env = dict(os.environ, GODOT_MTL_SYNC_MODE='none')
        producer_flags=['--real-views='+str(args.real_views)]+(['--adaptive-flush'] if args.adaptive_flush else [])+(['--validate-flush'] if args.validate_flush else [])+(['--check-before-draw'] if args.check_before_draw else [])+(['--capture-compose'] if args.capture_compose else [])+(['--complex-scene'] if args.complex_scene else [])+(['--no-shadows'] if args.no_shadows else [])+(['--no-alpha-panel'] if args.no_alpha_panel else [])+(['--shared-shadows'] if args.shared_shadows else [])+(['--collect-shadow-diffs'] if args.collect_shadow_diffs else [])+(['--warm-shadow-atlases','--warm-shadow-mode='+args.warm_shadow_mode,'--warm-shadow-draws='+str(args.warm_shadow_draws)] if args.warm_shadow_atlases else [])
        producer = subprocess.Popen([args.godot, '--path', project_path, '--rendering-driver', 'metal',
                                     '--script', 'tests/test_worker_live.gd', '--', '--surface-name='+name]+suffix+producer_flags,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        def collect_worker():
            try:
                return worker.communicate(timeout=args.duration+30)
            except subprocess.TimeoutExpired:
                worker.kill()
                output,error=worker.communicate()
                return output,error+"\nFAIL live worker timeout\n"
        worker_reader=ThreadPoolExecutor(max_workers=1)
        worker_output=worker_reader.submit(collect_worker)
        def sample_memory():
            began=time.monotonic()
            while not stop_sampling.is_set():
                sample={'elapsed_seconds':round(time.monotonic()-began,3)}
                for label,child in (('producer',producer),('worker',worker)):
                    value=subprocess.run(['ps','-o','rss=','-p',str(child.pid)],capture_output=True,text=True).stdout.strip()
                    if value.isdigit(): sample[label+'_rss_kib']=int(value)
                memory_samples.append(sample)
                stop_sampling.wait(1)
        sampler=threading.Thread(target=sample_memory,daemon=True)
        sampler.start()
        try:
            pout, perr = producer.communicate(timeout=args.duration+35)
        except subprocess.TimeoutExpired:
            producer.kill()
            pout, perr = producer.communicate()
            perr += "\nFAIL live producer timeout\n"
        wout, werr = worker_output.result(timeout=args.duration+35)
        stop_sampling.set()
        sampler.join(timeout=3)
        output = pout + perr + wout + werr
        ok = producer.returncode == 0 and worker.returncode == 0 and 'PASS live Godot producer' in pout and 'SCRIPT ERROR' not in output and '\nERROR:' not in output
        lines = [re.sub(r'@ /.*', '@ [SDK source location redacted]', line) for line in output.splitlines()
                 if any(key in line for key in ['live_sequence=', 'persistent_updates=', 'consumer_completion',
                                               'live_godot', 'PASS live', 'FAIL live', 'SCRIPT ERROR', 'ERROR:', 'GL_INVALID_ENUM', 'SURFACE producer', 'gpu_surface_input=', 'SURFACE import', 'FAIL surface', 'SURFACE port', 'worker_update_', 'PRODUCER animation_', 'PRODUCER mean_', 'PRODUCER comparison_', 'PRODUCER adaptive_', 'worker_mean_', 'FAIL adaptive'])]
        base = Path('benchmarks/hardware')
        stem = 'live-surface-'+('4k' if args.large else 'small')+('-verify' if args.verify else '-gpu')
        if args.duration != 20: stem += '-duration-'+str(args.duration)
        if args.uncapped: stem += '-uncapped'
        if args.adaptive_flush: stem += '-adaptive'
        if args.validate_flush: stem += '-copy-validation'
        if args.check_before_draw: stem += '-precheck'
        if args.capture_compose: stem += '-capture-compose'
        if args.real_views != 66: stem += '-real-'+str(args.real_views)
        if args.run_label: stem += '-'+args.run_label
        if args.complex_scene: stem += '-complex'
        if args.no_shadows: stem += '-no-shadows'
        if args.no_alpha_panel: stem += '-no-alpha'
        if args.shared_shadows: stem += '-shared-shadows'
        if args.full_shadow_casters: stem += '-full-casters'
        if args.collect_shadow_diffs: stem += '-pose-diffs'
        if args.warm_shadow_atlases: stem += '-warmed'
        if args.warm_shadow_atlases and (args.warm_shadow_mode!='both' or args.warm_shadow_draws!=8): stem += '-'+args.warm_shadow_mode+'-'+str(args.warm_shadow_draws)
        (base/(stem+'.log')).write_text('\n'.join(lines)+'\n')
        result = {'execution_passed': ok, 'producer_exit': producer.returncode, 'worker_exit': worker.returncode,
                  'worker_output_drained_concurrently': True, 'transport': 'IOSurface GPU sharing; 32-byte control mailbox with copy acknowledgment',
                  'quilt_size': [4092,4092] if args.large else [704,684], 'producer_frames_requested': None if args.duration!=20 else (8 if args.large else 24), 'worker_duration_seconds': args.duration,
                  'warm_shadow_mode': args.warm_shadow_mode if args.warm_shadow_atlases else None, 'warm_shadow_draws': args.warm_shadow_draws if args.warm_shadow_atlases else 0, 'warm_shadow_atlases': args.warm_shadow_atlases, 'full_shadow_casters': args.full_shadow_casters, 'shared_positional_shadows_requested': args.shared_shadows, 'shadows_enabled': args.complex_scene and not args.no_shadows, 'alpha_panel_enabled': args.complex_scene and not args.no_alpha_panel, 'scene': 'lit occlusion and alpha panel' if args.complex_scene else 'unshaded cube', 'run_label': args.run_label, 'real_views': args.real_views, 'total_views': 66, 'capture_compose': args.capture_compose, 'check_before_draw': args.check_before_draw or args.capture_compose, 'adaptive_flush': args.adaptive_flush, 'validation_pixel_readback': args.validate_flush, 'uncapped': args.uncapped, 'diagnostic_readback': args.verify, 'gpu_only_frame_transport': not (args.verify or args.validate_flush), 'user_observation': 'Pending', 'consumer_completion_contract_verified': False, 'production_ready': False}
        sequences = re.findall(r'live_sequence=(\d+)', wout)
        result['rss_samples']=memory_samples
        result['rss_scope']='Process resident memory sampled with ps; not GPU allocations or a leak proof.'
        result['received_sequences'] = [int(value) for value in sequences]
        for key in ('worker_update_span_seconds','worker_update_rate_hz','worker_mean_finish_ms','worker_mean_copy_wait_ms','worker_mean_new_frame_draw_ms'):
            measured=re.search(key+r'=([\d.]+)',wout)
            if measured: result[key]=float(measured[1])
        for key in ('mean_revision_flush_ms','mean_ack_wait_ms','mean_flush_count','exact_reference_frames','mean_process_wait_ms','mean_force_draw_ms','mean_force_sync_ms','mean_first_draw_ms','mean_later_draw_ms','mean_shadow_draw_calls','comparison_mismatches'):
            measured=re.search(key+r'=([\d.]+)',pout)
            if measured: result[key]=float(measured[1])
        produced=re.search(r'PASS live Godot producer frames=(\d+)',pout)
        if produced: result['producer_frames_completed']=int(produced[1])
        completed=result.get('producer_frames_completed',0)
        result['all_frames_received_in_order']=completed>0 and result['received_sequences']==list(range(1,completed+1))
        result['sdk_cleanup_passed']='sdk_calls_ok=1 release=1 shutdown=1' in wout
        ok=ok and result['all_frames_received_in_order'] and result['sdk_cleanup_passed']
        result['transport_execution_passed']=ok
        result['source_comparison_passed']=(completed>0 and result.get('comparison_mismatches',0)==0 and result.get('exact_reference_frames',0)==completed) if args.validate_flush else None
        ok=ok and result['source_comparison_passed'] is not False
        result['execution_passed']=ok
        result['worker_updates_completed']=len(sequences)
        result['rate_scope']='Worker SDK update submissions, not measured physical display FPS; Optional pacing; revisions flushed synchronously; stage means overlap across processes and must not be summed as frame latency.'
        match = re.search(r'mean_readback_ms=([\d.]+)', pout)
        if match: result['mean_get_image_elapsed_ms'] = float(match[1])
        match = re.search(r'mean_pipe_write_ms=([\d.]+)', pout)
        if match: result['mean_surface_publish_elapsed_ms'] = float(match[1])
        if args.validate_flush:
            result['mean_surface_publish_elapsed_ms']=None
            result['validation_scope']='Normal native GPU publication occurs before any quilt readback; copied IOSurface bytes compared to a fresh eight-flush reference. Publication timing is not measured in this mode.'
        (base/(stem+'.json')).write_text(json.dumps(result, indent=2)+'\n')
        print('\n'.join(line for line in lines if not line.startswith('live_sequence=')))
        raise SystemExit(0 if ok else 1)
finally:
        stop_sampling.set()
        if sampler is not None: sampler.join(timeout=3)
        for child in (producer, worker):
            if child is not None and child.poll() is None:
                child.kill()
                if child is not worker or worker_reader is None: child.communicate()
        if worker_reader is not None: worker_reader.shutdown(wait=True)
        libc=ctypes.CDLL(None)
        libc.shm_unlink(name.encode())
        libc.sem_unlink((name+'_s').encode())

        if stage is not None: stage.cleanup()
