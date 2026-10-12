"""Run meaningful project checks; hardware rendering remains a separate test."""
import argparse, pathlib, subprocess, sys
parser=argparse.ArgumentParser()
parser.add_argument('--godot',required=True)
parser.add_argument('--driver',default='vulkan')
parser.add_argument('--output-dir',type=pathlib.Path,help='Store logs and compatibility results separately from historical benchmarks')
args=parser.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
output=args.output_dir or root/'benchmarks'
output.mkdir(parents=True,exist_ok=True)
fixture=subprocess.Popen([sys.executable,str(root/'tests/bridge_fixture.py')],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
checks=[('projection-test','test_rig.gd',True,[]),('gpu-test','test_gpu.gd',False,[]),('gpu-2-iterations','test_gpu.gd',False,['--iterations=2']),('gpu-4-iterations','test_gpu.gd',False,['--iterations=4']),('gpu-rescue','test_gpu.gd',False,['--rescue-test']),('gpu-rescue-raw','test_gpu.gd',False,['--rescue-test','--raw-depth']),('gpu-inverse','test_gpu.gd',False,['--inverse-depth']),('gpu-inverse-rescue','test_gpu.gd',False,['--inverse-depth','--rescue-test']),('gpu-inverse-clip','test_gpu.gd',False,['--inverse-depth','--clip=0.01,5000']),('depth-proxy-analytic','test_depth_proxy_analytic.gd',False,[]),('on-demand','test_on_demand.gd',False,[]),('capture-lifetime-test','test_capture_lifetime.gd',False,[]),('custom-anchor-lifetime','test_capture_lifetime.gd',False,['--custom-anchors']),('buffer-compat','test_buffer_compat.gd',False,['--output=res://benchmarks/buffer-compat/regression.json']),('profiling','test_profiling.gd',False,[]),('bridge-fixture','test_bridge.gd',True,['--url=http://127.0.0.1:33335'])]
try:
    for name,script,headless,user_args in checks:
        if name=='buffer-compat' and args.output_dir:
            user_args=['--output='+str((output/'buffer-compat.json').resolve())]
        command=[args.godot,'--path',str(root),'--quit-after','1800' if name in ['buffer-compat','profiling','capture-lifetime-test','custom-anchor-lifetime'] else '600','--script',f'res://tests/{script}']
        command+=['--headless'] if headless else ['--rendering-driver',args.driver]
        if user_args:command+=['--']+user_args
        result=subprocess.run(command,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=60 if name in ['buffer-compat','profiling','capture-lifetime-test','custom-anchor-lifetime'] else 35)
        (output/f'{name}.log').write_text(result.stdout)
        if result.returncode or 'PASS ' not in result.stdout or 'SCRIPT ERROR' in result.stdout or '\nERROR:' in result.stdout:
            print(result.stdout);raise SystemExit(f'FAIL {name}')
        print(f'PASS {name}')
finally:
    fixture.terminate();fixture.wait(timeout=5)
