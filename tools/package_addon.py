"""Create an installable addon ZIP without SDK headers, runtimes or project caches."""
import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import tempfile
import zipfile

root = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--preview-only', action='store_true')
parser.add_argument('--godot-cpp-license', type=pathlib.Path)
parser.add_argument('--output', type=pathlib.Path)
args = parser.parse_args()
flavor = 'preview' if args.preview_only else 'macos-arm64'
output = args.output or root/'dist'/('looking-glass-godot-0.1.0-experimental-'+flavor+'.zip')
output.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='lg-package-', dir=output.parent) as directory:
    stage = pathlib.Path(directory)
    addon = stage/'addons'/'looking_glass'
    addon.mkdir(parents=True)
    for source in (root/'addons'/'looking_glass').rglob('*'):
        if source.is_file() and source.suffix in ('.gd', '.glsl', '.uid', '.cfg') and 'native' not in source.relative_to(root/'addons'/'looking_glass').parts:
            target = addon/source.relative_to(root/'addons'/'looking_glass')
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
    shutil.copyfile(root/'LICENSE', addon/'LICENSE')
    examples = addon/'examples'
    examples.mkdir()
    shutil.copyfile(root/'demo'/'metal_output.gd', examples/'metal_output.gd')
    scene = (root/'demo'/'metal_output.tscn').read_text().replace('res://demo/metal_output.gd','res://addons/looking_glass/examples/metal_output.gd')
    (examples/'metal_output.tscn').write_text(scene)
    shutil.copyfile(root/'docs'/'addon-installation.md', addon/'INSTALL.md')
    if not args.preview_only:
        if args.godot_cpp_license is None or not args.godot_cpp_license.is_file():
            raise SystemExit('Provide the external godot-cpp LICENSE.md for statically linked bindings.')
        native = addon/'native'
        native.mkdir()
        for name in ('probe-persistent', 'liblooking-glass-diagnostic.dylib'):
            source = root/'native'/'bridge_metal'/'build'/name
            if not source.is_file(): raise SystemExit('Build native artifacts before packaging: '+name)
            arch = subprocess.check_output(['lipo','-archs',str(source)], text=True).strip()
            if arch != 'arm64': raise SystemExit('Expected arm64 native artifacts.')
            dependencies = subprocess.check_output(['otool','-L',str(source)], text=True).splitlines()[1:]
            for line in dependencies:
                dependency = line.strip().split(' (',1)[0]
                if not dependency.startswith(('/System/Library/','/usr/lib/','@rpath/')):
                    raise SystemExit('Native artifact has a nonportable dependency/install name; rebuild it.')
            target = native/name
            shutil.copyfile(source,target)
            target.chmod(0o755)
            subprocess.run(['codesign','--verify',str(target)], check=True, capture_output=True)
        (native/'looking_glass_diagnostic.gdextension').write_text('[configuration]\nentry_symbol = "looking_glass_diagnostic_init"\ncompatibility_minimum = "4.5"\n[libraries]\nmacos.release.arm64 = "res://addons/looking_glass/native/liblooking-glass-diagnostic.dylib"\nmacos.debug.arm64 = "res://addons/looking_glass/native/liblooking-glass-diagnostic.dylib"\n')
        shutil.copyfile(args.godot_cpp_license, addon/'GODOT-CPP-LICENSE.md')
        # Own adapter sources only. External bridge.h and SDK implementation are excluded.
        source_dir = native/'source'
        source_dir.mkdir()
        for name in ('adapter.hpp','adapter.mm','godot_diagnostic.mm','probe_persistent.mm','shared_frame.hpp','surface_mailbox.hpp','surface_publisher.hpp','surface_port.hpp'):
            shutil.copyfile(root/'native'/'bridge_metal'/name, source_dir/name)
    files = sorted(path for path in stage.rglob('*') if path.is_file())
    manifest = {'version':'0.1.0-experimental','flavor':flavor,'source_repository':'https://github.com/theromis/godot-looking-glass','tested_engine':'Godot 4.8 c61fc0118','sdk_runtime_included':False,'sdk_headers_included':False,'notarized':False,'production_ready':False,'files':{str(path.relative_to(stage)):hashlib.sha256(path.read_bytes()).hexdigest() for path in files}}
    (addon/'PACKAGE.json').write_text(json.dumps(manifest,indent=2)+'\n')
    temporary_zip = stage/'package.zip'
    with zipfile.ZipFile(temporary_zip,'w',zipfile.ZIP_DEFLATED) as archive:
        for path in sorted((stage/'addons').rglob('*')):
            if path.is_file():
                entry = zipfile.ZipInfo(str(path.relative_to(stage)), date_time=(1980,1,1,0,0,0))
                entry.create_system = 3
                mode = 0o755 if path.name in ('probe-persistent','liblooking-glass-diagnostic.dylib') else 0o644
                entry.external_attr = (0o100000 | mode) << 16
                entry.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(entry, path.read_bytes())
    temporary_zip.replace(output)
print('Package: '+output.name)
print('SHA256: '+hashlib.sha256(output.read_bytes()).hexdigest())
