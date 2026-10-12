"""Bounded CPU IOSurface GPU-sharing experiment. Run from project root; no SDK in Godot process."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import secrets
import ctypes
import select

parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
parser.add_argument('--runtime', required=True)
parser.add_argument('--display-index', default='1')
parser.add_argument('--large', action='store_true')
parser.add_argument('--verify', action='store_true')
args = parser.parse_args()
suffix = (['--large'] if args.large else [])+(['--verify'] if args.verify else [])
worker = producer = None
name = '/lg'+secrets.token_hex(6)
try:
        worker = subprocess.Popen(['native/bridge_metal/build/probe-persistent', args.runtime, args.display_index,
                                   '--experimental-reuse', '--live-surface='+name]+suffix, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, text=True)
        if not select.select([worker.stdout],[],[],5)[0] or worker.stdout.readline().strip()!='SURFACE ready':
            raise RuntimeError('Shared-memory worker did not become ready')
        env = dict(os.environ, GODOT_MTL_SYNC_MODE='none')
        producer = subprocess.Popen([args.godot, '--path', '.', '--rendering-driver', 'metal',
                                     '--script', 'tests/test_worker_live.gd', '--', '--surface-name='+name]+suffix,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        pout, perr = producer.communicate(timeout=35)
        wout, werr = worker.communicate(timeout=30)
        output = pout + perr + wout + werr
        ok = producer.returncode == 0 and worker.returncode == 0 and 'PASS live Godot producer' in pout and 'SCRIPT ERROR' not in output
        lines = [re.sub(r'@ /.*', '@ [SDK source location redacted]', line) for line in output.splitlines()
                 if any(key in line for key in ['live_sequence=', 'persistent_updates=', 'consumer_completion',
                                               'live_godot', 'PASS live', 'FAIL live', 'SCRIPT ERROR', 'ERROR:', 'GL_INVALID_ENUM', 'SURFACE producer', 'gpu_surface_input=', 'SURFACE import', 'FAIL surface', 'SURFACE port'])]
        base = Path('benchmarks/hardware')
        stem = 'live-surface-'+('4k' if args.large else 'small')+('-verify' if args.verify else '-gpu')
        (base/(stem+'.log')).write_text('\n'.join(lines)+'\n')
        result = {'execution_passed': ok, 'producer_exit': producer.returncode, 'worker_exit': worker.returncode,
                  'transport': 'IOSurface GPU sharing; 32-byte control mailbox with copy acknowledgment',
                  'quilt_size': [4092,4092] if args.large else [704,684], 'producer_frames_requested': 8 if args.large else 24, 'worker_duration_seconds': 20,
                  'diagnostic_readback': args.verify, 'gpu_only_frame_transport': not args.verify, 'user_observation': 'Pending', 'consumer_completion_contract_verified': False, 'production_ready': False}
        sequences = re.findall(r'live_sequence=(\d+)', wout)
        result['received_sequences'] = [int(value) for value in sequences]
        match = re.search(r'mean_readback_ms=([\d.]+)', pout)
        if match: result['mean_get_image_elapsed_ms'] = float(match[1])
        match = re.search(r'mean_pipe_write_ms=([\d.]+)', pout)
        if match: result['mean_surface_publish_elapsed_ms'] = float(match[1])
        (base/(stem+'.json')).write_text(json.dumps(result, indent=2)+'\n')
        print('\n'.join(lines))
        raise SystemExit(0 if ok else 1)
finally:
        for child in (producer, worker):
            if child is not None and child.poll() is None:
                child.kill()
                child.communicate()
        libc=ctypes.CDLL(None)
        libc.shm_unlink(name.encode())
        libc.sem_unlink((name+'_s').encode())
