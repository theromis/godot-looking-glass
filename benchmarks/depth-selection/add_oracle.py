"""Append a clearly labeled RGB-reference oracle; depth policies stay frozen."""
import argparse,hashlib,json,sys
from pathlib import Path
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'interval-placement'))
from optimize import select_anchors
parser=argparse.ArgumentParser()
parser.add_argument('directory',type=Path)
parser.add_argument('--depth-selections',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args();p=args.directory
raw=json.loads((p/'raw.json').read_text());result=json.loads(args.depth_selections.read_text())
tile=raw['tile'];uniform=[int(i*47/23+0.5) for i in range(24)]
for case in raw['cases']:
    name=case['name'];ref=Image.open(p/f'{name}-reference.png')
    if ref.size!=(4*tile,12*tile): raise SystemExit('Reference dimensions')
    costs={(a,a+1):0.0 for a in range(47)};whole_sse={}
    for layout in case['layouts']:
        if layout['label']=='reference': continue
        image=Image.open(p/f'{name}-{layout["label"]}.png')
        if image.size!=ref.size: raise SystemExit('Capture dimensions')
        per_view={}
        for i in range(48):
            x,y=(i%4)*tile,(11-i//4)*tile;box=(x,y,x+tile,y+tile)
            a=np.asarray(image.crop(box))[:,:,:3].astype(np.float32);b=np.asarray(ref.crop(box))[:,:,:3].astype(np.float32)
            sse=float(np.sum((a-b)**2,dtype=np.float64));per_view[i]=sse
            if i in layout['anchors'] and sse!=0: raise SystemExit(f'Real tile differs: {name}/{layout["label"]}/{i}')
        whole_sse[layout['label']]=sum(per_view.values())
        if layout['label'].startswith('gap'):
            for a,b in zip(layout['anchors'],layout['anchors'][1:]):
                value=sum(per_view[i] for i in range(a+1,b))
                if (a,b) in costs and costs[a,b]!=value: raise SystemExit('RGB interval differs across layouts')
                costs[a,b]=value
        image.close()
    if len(costs)!=138: raise SystemExit('Incomplete RGB intervals')
    anchors,total=select_anchors(costs,48,24,3,uniform)
    entry=result['cases'][name]
    entry['oracle']={'anchors':anchors,'predicted_rgb_sse':total}
    entry['uniform_predicted_rgb_sse']=sum(costs[a,b] for a,b in zip(uniform,uniform[1:]))
    if entry['uniform_predicted_rgb_sse']!=whole_sse['uniform']: raise SystemExit('Uniform prediction differs')
    for policy in result['protocol']['depth_policies']:
        chosen=entry[policy]['anchors']
        entry[policy]['predicted_rgb_sse']=sum(costs[a,b] for a,b in zip(chosen,chosen[1:]))
    entry['reference_sha256']=hashlib.sha256((p/f'{name}-reference.png').read_bytes()).hexdigest()
    ref.close()
result['frozen_depth_selection_sha256']=hashlib.sha256(args.depth_selections.read_bytes()).hexdigest()
args.output.write_text(json.dumps(result,indent=2))
print('Added oracle and predicted evaluation; depth selections unchanged')
