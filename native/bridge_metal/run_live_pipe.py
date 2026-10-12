"""Bounded CPU pipe experiment. Run from project root; no SDK in Godot process."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
parser.add_argument('--runtime', required=True)
parser.add_argument('--display-index', default='1')
args = parser.parse_args()
worker = producer = None
with tempfile.TemporaryDirectory(prefix='lg-live-pipe-') as directory:
    path = Path(directory) / 'frames'
    os.mkfifo(path, 0o600)
    fd = os.open(path, os.O_RDWR)
    try:
        worker = subprocess.Popen(['native/bridge_metal/build/probe-persistent', args.runtime, args.display_index,
                                   '--experimental-reuse', '--live-stdin'], stdin=fd, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, text=True)
        os.close(fd)
        fd = None
        env = dict(os.environ, GODOT_MTL_SYNC_MODE='none')
        producer = subprocess.Popen([args.godot, '--path', '.', '--rendering-driver', 'metal',
                                     '--script', 'tests/test_worker_live.gd', '--', '--pipe-path='+str(path)],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        pout, perr = producer.communicate(timeout=35)
        wout, werr = worker.communicate(timeout=30)
        output = pout + perr + wout + werr
        ok = producer.returncode == 0 and worker.returncode == 0 and 'PASS live Godot producer' in pout and 'SCRIPT ERROR' not in output
        lines = [re.sub(r'@ /.*', '@ [SDK source location redacted]', line) for line in output.splitlines()
                 if any(key in line for key in ['live_sequence=', 'persistent_updates=', 'consumer_completion',
                                               'live_godot', 'PASS live', 'FAIL live', 'SCRIPT ERROR', 'ERROR:', 'GL_INVALID_ENUM'])]
        base = Path('benchmarks/hardware')
        (base/'live-pipe-worker.log').write_text('\n'.join(lines)+'\n')
        result = {'execution_passed': ok, 'producer_exit': producer.returncode, 'worker_exit': worker.returncode,
                  'transport': 'POSIX FIFO to worker stdin; CPU readback/upload; no per-frame disk files',
                  'quilt_size': [704, 684], 'producer_frames_requested': 24, 'worker_duration_seconds': 20,
                  'user_observation': 'Pending', 'consumer_completion_contract_verified': False, 'production_ready': False}
        sequences = re.findall(r'live_sequence=(\d+)', wout)
        result['received_sequences'] = [int(value) for value in sequences]
        match = re.search(r'mean_readback_ms=([\d.]+)', pout)
        if match: result['mean_get_image_elapsed_ms'] = float(match[1])
        (base/'live-pipe-worker.json').write_text(json.dumps(result, indent=2)+'\n')
        print('\n'.join(lines))
        raise SystemExit(0 if ok else 1)
    finally:
        if fd is not None: os.close(fd)
        for child in (producer, worker):
            if child is not None and child.poll() is None:
                child.kill()
                child.communicate()
