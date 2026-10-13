"""Verify an addon archive in a fresh project with a Godot editor build."""
import argparse
import hashlib
import json
import os
import pathlib
import subprocess
import tempfile
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('--package', type=pathlib.Path, required=True)
parser.add_argument('--godot-editor', required=True)
parser.add_argument('--runtime')
parser.add_argument('--output', type=pathlib.Path, required=True)
args = parser.parse_args()
env = dict(os.environ, GODOT_MTL_SYNC_MODE='none')
env.pop('BRIDGE_LIBRARY', None)
if args.runtime: env['BRIDGE_LIBRARY'] = args.runtime
checks = []
with tempfile.TemporaryDirectory(prefix='lg-install-check-') as directory:
    project = pathlib.Path(directory)
    with zipfile.ZipFile(args.package) as archive:
        names = archive.namelist()
        assert all(name.startswith('addons/looking_glass/') and '..' not in pathlib.PurePosixPath(name).parts for name in names)
        assert not any('.godot/' in name or name.endswith(('.import', 'bridge.h')) or 'libbridge' in name for name in names)
        assert not any(b'/Users/' in archive.read(name) for name in names)
        manifest = json.loads(archive.read('addons/looking_glass/PACKAGE.json'))
        for name, digest in manifest['files'].items():
            assert hashlib.sha256(archive.read(name)).hexdigest() == digest
        assert set(names) == set(manifest['files']) | {'addons/looking_glass/PACKAGE.json'}
        archive.extractall(project)
        for entry in archive.infolist():
            mode = entry.external_attr >> 16
            if mode: (project/entry.filename).chmod(mode & 0o777)
    checks.append({'stage':'archive manifest, contents and permissions','passed':True})
    (project/'project.godot').write_text('''config_version=5
[application]
config/name="Isolated addon installation check"
run/main_scene="res://addons/looking_glass/examples/metal_output.tscn"
run/flush_stdout_on_print=true
[display]
window/size/viewport_width=1152
window/size/viewport_height=720
window/vsync/vsync_mode=0
[rendering]
renderer/rendering_method="forward_plus"
[editor_plugins]
enabled=PackedStringArray("res://addons/looking_glass/plugin.cfg")
[debug]
file_logging/enable_file_logging=false
''')
    commands = [('editor import and plugin load',['--editor','--quit'],None),('hardware-free preview',['--','--preview-smoke'],'PASS Metal demo hardware-free preview')]
    if args.runtime:
        assert manifest['flavor']=='macos-arm64', 'Hardware checks require the native package.'
        commands.append(('physical output lifecycle',['--','--output-smoke'],'PASS Metal demo output'))
    for label, tail, expected in commands:
        completed = subprocess.run([args.godot_editor,'--path',str(project),'--rendering-driver','metal']+tail,env=env,capture_output=True,text=True,timeout=180)
        diagnostic = completed.stdout+'\n'+completed.stderr
        passed = completed.returncode==0 and 'SCRIPT ERROR:' not in diagnostic and '\nERROR:' not in '\n'+diagnostic and (expected is None or expected in diagnostic)
        if label=='editor import and plugin load':
            passed = passed and (project/'.godot/global_script_class_cache.cfg').is_file() and (project/'addons/looking_glass/shaders/capture.glsl.import').is_file()
        protocol = [line for line in diagnostic.splitlines() if line.startswith(('PASS ','FAIL ','DEMO '))]
        checks.append({'stage':label,'exit_code':completed.returncode,'passed':passed,'protocol':protocol})
        print(label+': '+('PASS' if passed else 'FAIL'),flush=True)
        if not passed: break
record = {'date':'2026-10-12','package':args.package.name,'sha256':hashlib.sha256(args.package.read_bytes()).hexdigest(),'checks':checks,'passed':all(check['passed'] for check in checks),'sdk_included':False,'project_cache_copied':False,'editor_plugin_enabled':True,'user_visual_confirmation':'Not collected for this run.','production_ready':False}
args.output.parent.mkdir(parents=True,exist_ok=True)
args.output.write_text(json.dumps(record,indent=2)+'\n')
raise SystemExit(0 if record['passed'] else 1)
