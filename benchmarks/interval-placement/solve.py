"""Measure interval RGB errors and optimize a constrained static anchor layout."""
import argparse, hashlib, json, math
from pathlib import Path
import numpy as np
from PIL import Image
from optimize import select_anchors
parser = argparse.ArgumentParser()
parser.add_argument('directory', type=Path)
parser.add_argument('--reference', type=Path,required=True)
parser.add_argument('--output', type=Path,required=True)
args=parser.parse_args()
meta=json.loads((args.directory/'layouts.json').read_text())
if len(meta['layouts']) != 5:
    raise SystemExit('Need all five interval capture layouts')
tile=meta['tile']
ref=Image.open(args.reference)
if ref.size != (4*tile,12*tile):
    raise SystemExit('Invalid reference dimensions')
costs={(i,i+1):0.0 for i in range(47)}
intervals={f"{i},{i+1}": {"sse":0.0,"source_layout":None,"views":{},"reason":"Adjacent anchors have no synthesized output views"} for i in range(47)}
for layout in meta['layouts']:
    path=args.directory/(layout['name']+'.png')
    if hashlib.sha256(path.read_bytes()).hexdigest() != layout['sha256']:
        raise SystemExit('Capture hash changed')
    image=Image.open(path)
    if image.size != ref.size:
        raise SystemExit('Invalid capture dimensions')
    per_view={}
    anchors=layout['anchors']
    for i in range(48):
        x,y=(i%4)*tile,(11-i//4)*tile
        box=(x,y,x+tile,y+tile)
        a=np.asarray(image.crop(box))[:,:,:3].astype(np.float32)
        b=np.asarray(ref.crop(box))[:,:,:3].astype(np.float32)
        sse=float(np.sum((a-b)**2,dtype=np.float64))
        if i in anchors and sse != 0:
            raise SystemExit(f'Real anchor {i} differs from reference in {layout["name"]}')
        per_view[i]=sse
    for left,right in zip(anchors,anchors[1:]):
        value=sum(per_view[i] for i in range(left+1,right))
        if (left,right) in costs and costs[left,right] != value:
            raise SystemExit('Interval cost differs between layouts')
        costs[left,right]=value
        intervals[f'{left},{right}']={'sse':value,'source_layout':layout['name'],'views':{i:per_view[i] for i in range(left+1,right)}}
    image.close()
for gap in (1,2,3):
    for left in range(48-gap):
        if (left,left+gap) not in costs:
            raise SystemExit(f'Missing interval {left},{left+gap}')
anchors,total=select_anchors(costs,48,24,3)
uniform=[int(i*47/23+0.5) for i in range(24)]
baseline=sum(costs[a,b] for a,b in zip(uniform,uniform[1:]))
result={'anchors':anchors,'method':'Exact dynamic programming over measured whole-interval RGB SSE, 24 anchors, maximum gap 3; offline static reference-assisted, in-sample optimization.',
        'predicted_sse':total,'uniform_predicted_sse':baseline,'predicted_error_reduction_fraction':1-total/baseline,
        'predicted_psnr_db':10*math.log10(255**2*48*tile*tile*3/total),
        'uniform_predicted_psnr_db':10*math.log10(255**2*48*tile*tile*3/baseline),
        'reference_sha256':hashlib.sha256(args.reference.read_bytes()).hexdigest(),
        'capture_binary_sha256':meta['binary_sha256'],'max_gap':3,'real_views':24,'cost_table':'costs1024/interval-costs.json'}
(args.directory/'interval-costs.json').write_text(json.dumps(intervals,indent=2))
args.output.write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
