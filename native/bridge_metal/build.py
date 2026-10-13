"""Build own adapter and tests; do not copy SDK headers or runtime binaries."""
import argparse,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--sdk-headers',type=pathlib.Path,required=True);p.add_argument('--output',type=pathlib.Path,default=pathlib.Path('native/bridge_metal/build'));a=p.parse_args()
root=pathlib.Path(__file__).resolve().parent;a.output.mkdir(parents=True,exist_ok=True)
common=['clang++','-std=c++17','-fobjc-arc','-Wall','-Wextra','-I'+str(a.sdk_headers),'-I'+str(root),'-framework','Metal','-framework','Foundation','-framework','IOSurface']
subprocess.run(common+['-dynamiclib',str(root/'fixture.mm'),'-o',str(a.output/'fixture.dylib')],check=True)
subprocess.run(common+[str(root/'adapter.mm'),str(root/'test.mm'),'-o',str(a.output/'test-adapter')],check=True)
subprocess.run(common+[str(root/'probe_offscreen.mm'),'-o',str(a.output/'probe-offscreen')],check=True)
subprocess.run(common+[str(root/'probe_hardware.mm'),'-o',str(a.output/'probe-hardware')],check=True)
subprocess.run(common+[str(root/'adapter.mm'),str(root/'benchmark_target.mm'),'-o',str(a.output/'benchmark-target')],check=True)
subprocess.run(common+[str(root/'adapter.mm'),str(root/'probe_copy.mm'),'-o',str(a.output/'probe-copy')],check=True)
subprocess.run(common+['-Wno-deprecated-declarations',str(root/'probe_persistent.mm'),'-framework','OpenGL','-o',str(a.output/'probe-persistent')],check=True)
subprocess.run(['clang++','-std=c++17','-Wall','-Wextra',str(root/'test_shared_frame.cpp'),'-o',str(a.output/'test-shared-frame')],check=True)
subprocess.run(['clang++','-std=c++17','-Wall','-Wextra',str(root/'test_surface_mailbox.cpp'),'-o',str(a.output/'test-surface-mailbox')],check=True)
subprocess.run(['clang++','-std=c++17','-fobjc-arc','-Wno-deprecated-declarations',str(root/'test_surface_port.mm'),'-framework','Foundation','-framework','IOSurface','-o',str(a.output/'test-surface-port')],check=True)

subprocess.run(common+['-Wno-deprecated-declarations',str(root/'test_surface_async.mm'),'-o',str(a.output/'test-surface-async')],check=True)
