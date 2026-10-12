"""Build the optional diagnostic GDExtension against external MIT bindings."""
import argparse,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--godot-cpp',type=pathlib.Path,required=True);p.add_argument('--sdk-headers',type=pathlib.Path,required=True);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parent;out=root/'build';out.mkdir(exist_ok=True)
libs=list((a.godot_cpp/'bin').glob('libgodot-cpp.macos.template_release.arm64.a'))
if len(libs)!=1:raise SystemExit('Build godot-cpp for macos/template_release/arm64 first')
cmd=['clang++','-std=c++17','-fobjc-arc','-dynamiclib','-Wall','-Wextra','-Wno-unused-parameter','-I'+str(a.sdk_headers),'-I'+str(a.godot_cpp/'include'),'-I'+str(a.godot_cpp/'gen/include'),'-I'+str(a.godot_cpp/'gdextension'),str(root/'adapter.mm'),str(root/'godot_diagnostic.mm'),str(libs[0]),'-framework','Metal','-framework','Foundation','-framework','IOSurface','-o',str(out/'liblooking-glass-diagnostic.dylib')]
subprocess.run(cmd,check=True)
(out/'looking_glass_diagnostic.gdextension').write_text('''[configuration]
entry_symbol = "looking_glass_diagnostic_init"
compatibility_minimum = "4.5"
[libraries]
macos.release.arm64 = "res://native/bridge_metal/build/liblooking-glass-diagnostic.dylib"
macos.debug.arm64 = "res://native/bridge_metal/build/liblooking-glass-diagnostic.dylib"
''')
