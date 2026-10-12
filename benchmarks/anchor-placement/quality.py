"""Compare all 48 output tiles fairly; report synthesized subset separately."""
import argparse,json,math
from pathlib import Path
import numpy as np
from PIL import Image
parser=argparse.ArgumentParser()
parser.add_argument('directory',type=Path)
parser.add_argument('--reference',type=Path,required=True)
args=parser.parse_args()
p=args.directory
s=json.loads((p/'summary.json').read_text())
tile=s['scene']['tile']
reference=Image.open(args.reference)
result={}
reference_hash=__import__('hashlib').sha256(args.reference.read_bytes()).hexdigest()
if 'reference_sha256' in s['selection'] and s['selection']['reference_sha256'] != reference_hash:
    raise SystemExit('Reference differs from selection reference')
for count in ['uniform','selected']:
    image=Image.open(p/f'{count}-1.png')
    if image.size!=reference.size or image.size!=(4*tile,12*tile):
        raise SystemExit('Wrong quilt dimensions')
    anchors=set(s['selection']['anchors']) if count=='selected' else {int(math.floor(i*47/23+0.5)) for i in range(24)}
    per_view=[]
    for i in range(48):
        x,y=(i%4)*tile,(11-i//4)*tile
        box=(x,y,x+tile,y+tile)
        a=np.asarray(image.crop(box))[:,:,:3].astype(np.float32)
        b=np.asarray(reference.crop(box))[:,:,:3].astype(np.float32)
        delta=a-b
        per_view.append({'view':i,'real':i in anchors,'sse':float(np.sum(delta*delta,dtype=np.float64)), 'sae':float(np.sum(np.abs(delta),dtype=np.float64)), 'changed':int(np.count_nonzero(np.any(delta!=0,axis=2)))})
    entry={'anchors':sorted(anchors),'per_view':per_view}
    for subset,views in [('whole_quilt',per_view),('synthesized',[v for v in per_view if not v['real']]),('real_anchors',[v for v in per_view if v['real']])]:
        mse=sum(v['sse'] for v in views)/(len(views)*tile*tile*3)
        entry[subset]={'rgb_mae_8bit':sum(v['sae'] for v in views)/(len(views)*tile*tile*3),'rgb_psnr_db':10*math.log10(255**2/mse) if mse else None,'changed_pixel_fraction':sum(v['changed'] for v in views)/(len(views)*tile*tile), 'exact_rgb':mse==0}
    if not entry['real_anchors']['exact_rgb']:
        raise SystemExit('Real anchor pixels differ from all-real reference; comparison is confounded')
    result[str(count)]=entry
if 'predicted_sse' in s['selection']:
    for name,key in [('uniform','uniform_predicted_sse'),('selected','predicted_sse')]:
        actual=sum(v['sse'] for v in result[name]['per_view'])
        predicted=s['selection'][key]
        if actual != predicted:
            raise SystemExit(f'{name}: interval prediction mismatch: {predicted} vs rendered {actual}')
    result['interval_prediction_exact']=True
result['reference_sha256']=reference_hash
result['limitations']=['Offline selection and evaluation use the same static scene/reference; quality is in-sample, not generalization.', '8-bit gamma-mapped RGB; not perceptual/HDR/temporal quality.', 'One static opaque scene and one GPU; presets cannot be universal.']
(p/'quality.json').write_text(json.dumps(result,indent=2))
print(json.dumps({n:{k:v for k,v in entry.items() if k not in ['anchors','per_view']} if isinstance(entry,dict) else entry for n,entry in result.items()},indent=2))
