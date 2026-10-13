"""Sample process RSS during bounded managed-node restart and sustained tests."""
import argparse
import json
import os
import pathlib
import subprocess
import threading
import time

parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
parser.add_argument('--runtime', required=True)
parser.add_argument('--output', type=pathlib.Path, default=pathlib.Path('benchmarks/hardware/managed-metal-stress.json'))
args = parser.parse_args()
env = dict(os.environ, BRIDGE_LIBRARY=args.runtime, GODOT_MTL_SYNC_MODE='none')
started = time.monotonic()
process = subprocess.Popen([args.godot, '--path', '.', '--rendering-driver', 'metal', '--script', 'tests/test_metal_output_stress.gd'], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
lines = []
def drain():
    for line in process.stdout:
        # No raw SDK/installation diagnostics or private serial data in records.
        if line.startswith(('CYCLE_', 'PASS ', 'FAIL ')):
            lines.append(line.strip())
            print(line.strip(), flush=True)
        elif 'SCRIPT ERROR:' in line or line.startswith('ERROR:'):
            lines.append('FAIL Godot runtime error')
            print('FAIL Godot runtime error', flush=True)
reader = threading.Thread(target=drain)
reader.start()
samples = []
timed_out = False
while process.poll() is None:
    elapsed = time.monotonic()-started
    if elapsed > 180:
        timed_out = True
        # Only terminate this run's worker children and producer.
        children = subprocess.run(['pgrep', '-P', str(process.pid)], capture_output=True, text=True).stdout.split()
        for pid in children:
            subprocess.run(['kill', '-TERM', pid], capture_output=True)
        process.kill()
        break
    sample = {'seconds': round(elapsed, 3)}
    rss = subprocess.run(['ps', '-o', 'rss=', '-p', str(process.pid)], capture_output=True, text=True).stdout.strip()
    if rss.isdigit(): sample['godot_rss_kib'] = int(rss)
    children = subprocess.run(['ps', '-o', 'pid=,rss=,comm=', '-ax'], capture_output=True, text=True).stdout.splitlines()
    pids = subprocess.run(['pgrep', '-P', str(process.pid)], capture_output=True, text=True).stdout.split()
    for child in children:
        fields = child.split(None, 2)
        if len(fields)==3 and fields[0] in pids and fields[2].endswith('probe-persistent'):
            sample['worker_rss_kib'] = int(fields[1])
    samples.append(sample)
    time.sleep(1)
process.wait()
reader.join()
passed = process.returncode==0 and not timed_out and 'PASS managed Metal lifecycle stress' in lines and not any(x.startswith('FAIL ') for x in lines)
record = {'date':'2026-10-12','exit_code':process.returncode,'timed_out':timed_out,'passed':passed,'protocol':lines,'rss_samples':samples,'rss_scope':'Process resident memory; excludes separate GPU accounting and does not prove leak-free operation.','user_visual_confirmation':'Not collected for this run.','sdk_consumer_completion_verified':False,'production_ready':False}
steady = [sample for sample in samples if sample['seconds'] >= 40 and 'worker_rss_kib' in sample]
if steady:
    record['steady_window_seconds'] = [steady[0]['seconds'], steady[-1]['seconds']]
    record['steady_rss_summary'] = {
        key: {'first':steady[0][key], 'last':steady[-1][key], 'delta':steady[-1][key]-steady[0][key], 'peak':max(sample[key] for sample in steady)}
        for key in ('godot_rss_kib', 'worker_rss_kib')
    }
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(record, indent=2)+'\n')
print('RESULT passed='+str(passed), flush=True)
raise SystemExit(0 if passed else 1)
