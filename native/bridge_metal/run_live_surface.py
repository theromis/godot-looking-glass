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
parser.add_argument('--duration', type=int, default=20, help='Bounded worker duration in seconds (20–600).')
args = parser.parse_args()
if args.check_before_draw and not (args.adaptive_flush and args.validate_flush): parser.error("--check-before-draw is a validation-only negative control; requires --adaptive-flush --validate-flush")
if not 20 <= args.duration <= 600: parser.error("--duration must be between 20 and 600")
suffix = (['--large'] if args.large else [])+(['--verify'] if args.verify else [])
if args.duration != 20: suffix += ['--duration='+str(args.duration)]
if args.uncapped: suffix += ['--uncapped']
worker = producer = None
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
        producer_flags=(['--adaptive-flush'] if args.adaptive_flush else [])+(['--validate-flush'] if args.validate_flush else [])+(['--check-before-draw'] if args.check_before_draw else [])
        producer = subprocess.Popen([args.godot, '--path', '.', '--rendering-driver', 'metal',
                                     '--script', 'tests/test_worker_live.gd', '--', '--surface-name='+name]+suffix+producer_flags,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
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
        pout, perr = producer.communicate(timeout=args.duration+35)
        wout, werr = worker.communicate(timeout=args.duration+30)
        stop_sampling.set()
        sampler.join(timeout=3)
        output = pout + perr + wout + werr
        ok = producer.returncode == 0 and worker.returncode == 0 and 'PASS live Godot producer' in pout and 'SCRIPT ERROR' not in output and '\nERROR:' not in output
        lines = [re.sub(r'@ /.*', '@ [SDK source location redacted]', line) for line in output.splitlines()
                 if any(key in line for key in ['live_sequence=', 'persistent_updates=', 'consumer_completion',
                                               'live_godot', 'PASS live', 'FAIL live', 'SCRIPT ERROR', 'ERROR:', 'GL_INVALID_ENUM', 'SURFACE producer', 'gpu_surface_input=', 'SURFACE import', 'FAIL surface', 'SURFACE port', 'worker_update_', 'PRODUCER animation_', 'PRODUCER mean_', 'PRODUCER adaptive_', 'worker_mean_', 'FAIL adaptive'])]
        base = Path('benchmarks/hardware')
        stem = 'live-surface-'+('4k' if args.large else 'small')+('-verify' if args.verify else '-gpu')
        if args.duration != 20: stem += '-duration-'+str(args.duration)
        if args.uncapped: stem += '-uncapped'
        if args.adaptive_flush: stem += '-adaptive'
        if args.validate_flush: stem += '-copy-validation'
        if args.check_before_draw: stem += '-precheck'
        (base/(stem+'.log')).write_text('\n'.join(lines)+'\n')
        result = {'execution_passed': ok, 'producer_exit': producer.returncode, 'worker_exit': worker.returncode,
                  'transport': 'IOSurface GPU sharing; 32-byte control mailbox with copy acknowledgment',
                  'quilt_size': [4092,4092] if args.large else [704,684], 'producer_frames_requested': None if args.duration!=20 else (8 if args.large else 24), 'worker_duration_seconds': args.duration,
                  'check_before_draw': args.check_before_draw, 'adaptive_flush': args.adaptive_flush, 'validation_pixel_readback': args.validate_flush, 'uncapped': args.uncapped, 'diagnostic_readback': args.verify, 'gpu_only_frame_transport': not (args.verify or args.validate_flush), 'user_observation': 'Pending', 'consumer_completion_contract_verified': False, 'production_ready': False}
        sequences = re.findall(r'live_sequence=(\d+)', wout)
        result['rss_samples']=memory_samples
        result['rss_scope']='Process resident memory sampled with ps; not GPU allocations or a leak proof.'
        result['received_sequences'] = [int(value) for value in sequences]
        for key in ('worker_update_span_seconds','worker_update_rate_hz','worker_mean_finish_ms','worker_mean_copy_wait_ms','worker_mean_new_frame_draw_ms'):
            measured=re.search(key+r'=([\d.]+)',wout)
            if measured: result[key]=float(measured[1])
        for key in ('mean_revision_flush_ms','mean_ack_wait_ms','mean_flush_count','exact_reference_frames','mean_process_wait_ms','mean_force_draw_ms','mean_force_sync_ms','mean_first_draw_ms','mean_later_draw_ms'):
            measured=re.search(key+r'=([\d.]+)',pout)
            if measured: result[key]=float(measured[1])
        produced=re.search(r'PASS live Godot producer frames=(\d+)',pout)
        if produced: result['producer_frames_completed']=int(produced[1])
        completed=result.get('producer_frames_completed',0)
        result['all_frames_received_in_order']=completed>0 and result['received_sequences']==list(range(1,completed+1))
        result['sdk_cleanup_passed']='sdk_calls_ok=1 release=1 shutdown=1' in wout
        ok=ok and result['all_frames_received_in_order'] and result['sdk_cleanup_passed']
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
                child.communicate()
        libc=ctypes.CDLL(None)
        libc.shm_unlink(name.encode())
        libc.sem_unlink((name+'_s').encode())
