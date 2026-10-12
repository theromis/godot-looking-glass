"""Compare synthesized views against same-format all-real quilts; no optical metric."""
from pathlib import Path
import hashlib,json,math
import numpy as np
from PIL import Image
root=Path(__file__).resolve().parent
config=json.loads((root/'configurations.json').read_text())
width,height=config['tile_size'];columns=config['columns'];rows=config['rows']
reference=np.asarray(Image.open(root/'views-66.png').convert('RGB'),dtype=np.float64)/255
variants=[c for c in config['configurations'] if c['real_views']!=66]
common=set(range(66))
for c in variants: common-=set(c['anchors'])
def tile(image,index):
 y=(rows-1-index//columns)*height;x=(index%columns)*width
 return image[y:y+height,x:x+width]
def metrics(a,b):
 e=a-b;mse=float(np.mean(e*e))
 return {'mae_0_1':float(np.mean(np.abs(e))),'psnr_db':-10*math.log10(mse) if mse else None,'pixels_max_channel_error_gt_0_1_fraction':float(np.mean(np.max(np.abs(e),axis=-1)>0.1))}
results=[]
for c in variants:
 image=np.asarray(Image.open(root/f"views-{c['real_views']}.png").convert('RGB'),dtype=np.float64)/255
 views=[i for i in range(66) if i not in c['anchors']]
 a=np.stack([tile(reference,i) for i in views]);b=np.stack([tile(image,i) for i in views])
 anchor_error=max(float(np.max(np.abs(tile(reference,i)-tile(image,i)))) for i in c['anchors'])
 if anchor_error: raise SystemExit(f"Anchor mismatch: {c['real_views']} max_error={anchor_error}")
 edges=np.maximum(np.max(np.abs(np.diff(a,axis=1,prepend=a[:,:1])),axis=-1),np.max(np.abs(np.diff(a,axis=2,prepend=a[:,:,:1])),axis=-1))>0.1
 per_view=[{'view':i,**metrics(tile(reference,i),tile(image,i))} for i in views]
 worst=max(per_view,key=lambda r:r['mae_0_1'])
 results.append({'real_views':c['real_views'],'synthesized_views':len(views),'exact_anchor_tiles':True,'synthetic_tiles_metrics':metrics(a,b),'common_synthetic_tiles_metrics':metrics(np.stack([tile(reference,i) for i in sorted(common)]),np.stack([tile(image,i) for i in sorted(common)])),'reference_depth_or_color_boundary_mae':float(np.mean(np.abs(a-b)[edges])),'worst_view':worst,'per_view':per_view})
report={'date':'2026-10-12','engine':'Godot 4.8 c61fc0118 native Metal','environment':{'GODOT_MTL_SYNC_MODE':'none'},'configuration':config,'common_synthesized_views':sorted(common),'results':results,'image_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in root.glob('views-*.png')},'limitations':['Static opaque scene only, no motion/transparency/particles','No physical display or optical assessment','Scene-specific metrics, not a universal acceptable preset','Per-budget synthetic masks differ; common-view comparison provided','Boundary proxy is color gradient, not a measured disocclusion mask']}
(root/'quality.json').write_text(json.dumps(report,indent=2)+'\n')
for r in results: print(r['real_views'],json.dumps({k:v for k,v in r.items() if k not in ['per_view','worst_view']}))
