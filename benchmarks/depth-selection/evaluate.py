"""Independent render verification against frozen depth choices and RGB oracle."""
import argparse,hashlib,json,math
from pathlib import Path
import numpy as np
from PIL import Image
parser=argparse.ArgumentParser()
parser.add_argument('validation',type=Path)
parser.add_argument('--costs',type=Path,required=True)
parser.add_argument('--selections',type=Path,required=True)
args=parser.parse_args();p=args.validation
raw=json.loads((p/'raw.json').read_text());selection=json.loads(args.selections.read_text());tile=raw['tile']
if raw['stage']!='validation' or len(raw['cases'])!=9: raise SystemExit('Incomplete validation')
methods=['uniform','both_invalid','source_horizontal_depth_edge','oracle']
rows=[];hashes={}
for case in raw['cases']:
 name=case['name'];selected=selection['cases'][name]
 ref_path=p/f'{name}-reference.png';ref=Image.open(ref_path)
 cost_ref=Image.open(args.costs/f'{name}-reference.png')
 if ref.size!=(4*tile,12*tile) or ref.tobytes()!=cost_ref.tobytes(): raise SystemExit('Reference changes between cost and independent validation renders')
 cost_ref.close();by_label={layout['label']:layout for layout in case['layouts']}
 records={};hashes[name]={'reference':hashlib.sha256(ref_path.read_bytes()).hexdigest()}
 for method in methods:
  path=p/f'{name}-{method}.png';image=Image.open(path)
  if image.size!=ref.size: raise SystemExit('Quilt dimensions')
  anchors=by_label[method]['anchors']
  if len(anchors)!=24 or (method!='uniform' and anchors!=selected[method]['anchors']): raise SystemExit('Camera selection mismatch')
  sse=sae=0.0;changed=0
  for i in range(48):
   x,y=(i%4)*tile,(11-i//4)*tile;box=(x,y,x+tile,y+tile)
   a=np.asarray(image.crop(box))[:,:,:3].astype(np.float32);b=np.asarray(ref.crop(box))[:,:,:3].astype(np.float32);d=a-b
   value=float(np.sum(d*d,dtype=np.float64))
   if i in anchors and value!=0: raise SystemExit(f'Real anchor differs: {name}/{method}/{i}')
   sse+=value;sae+=float(np.sum(np.abs(d),dtype=np.float64));changed+=int(np.count_nonzero(np.any(d!=0,axis=2)))
  expected=selected['uniform_predicted_rgb_sse'] if method=='uniform' else selected[method]['predicted_rgb_sse']
  if sse!=expected: raise SystemExit(f'Interval model mismatch: {name}/{method}: {sse} vs {expected}')
  records[method]={'sse':sse,'rgb_mae_8bit':sae/(48*tile*tile*3),'whole_quilt_psnr_db':10*math.log10(255**2*48*tile*tile*3/sse),'changed_pixel_fraction':changed/(48*tile*tile),'anchors':anchors,'real_anchors_exact':True,'interval_prediction_exact':True}
  hashes[name][method]=hashlib.sha256(path.read_bytes()).hexdigest();image.close()
 for method in methods:
  records[method]['sse_change_fraction_vs_uniform']=records[method]['sse']/records['uniform']['sse']-1
  records[method]['psnr_delta_db_vs_uniform']=records[method]['whole_quilt_psnr_db']-records['uniform']['whole_quilt_psnr_db']
 rows.append({'name':name,'scene':case['scene'],'snapshot':case['snapshot'],'methods':records});ref.close()
aggregates={}
for group in ['smooth','bars','layers','all']:
 cases=[c for c in rows if group=='all' or c['scene']==group];uniform=sum(c['methods']['uniform']['sse'] for c in cases)
 aggregates[group]={}
 for method in methods:
  sse=sum(c['methods'][method]['sse'] for c in cases)
  aggregates[group][method]={'sse_change_fraction_vs_uniform':sse/uniform-1,'whole_quilt_psnr_db':10*math.log10(255**2*len(cases)*48*tile*tile*3/sse),'improved_poses':sum(c['methods'][method]['sse']<c['methods']['uniform']['sse'] for c in cases),'worsened_poses':sum(c['methods'][method]['sse']>c['methods']['uniform']['sse'] for c in cases),'poses':len(cases)}
result={'godot':raw['godot'],'tile':tile,'cases':rows,'aggregates':aggregates,'image_sha256':hashes,'frozen_depth_selection_sha256':selection['frozen_depth_selection_sha256'],
        'limitations':['Depth choices frozen before image/reference analysis; oracle is separately labeled and reference-assisted.',
                       'All candidate view depths are measured in five extra grids. No runtime selection cost/speedup is measured.',
                       'Three previously inspected fixtures at nine poses, unshaded opaque materials, not new held-out production scenes.',
                       'Sixteen moving-camera draws followed by two settling draws; no adaptive transition or flicker test.',
                       'Aggregate error weights poses by squared RGB error; inspect per-scene and per-pose results. No universal quality/performance claim.',
                       'Normal addon defaults and engine rendering code unchanged.']}
(p/'analysis.json').write_text(json.dumps(result,indent=2))
print(json.dumps(aggregates,indent=2))
