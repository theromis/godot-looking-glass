"""Verify depth counters and decoded PNGs across two diagnostic runs."""
import argparse,json
from pathlib import Path
import numpy as np
from PIL import Image
parser=argparse.ArgumentParser()
parser.add_argument('baseline',type=Path)
parser.add_argument('other',type=Path)
args=parser.parse_args()
a=json.loads((args.baseline/'raw.json').read_text());b=json.loads((args.other/'raw.json').read_text())
if [r['name'] for r in a['rows']] != [r['name'] for r in b['rows']]: raise SystemExit('Cases differ')
rows=[]
for x,y in zip(a['rows'],b['rows']):
    row={'case':x['name'],'depth_counters_exact':x['rows']==y['rows']}
    for kind in ['synth','reference']:
        p=np.asarray(Image.open(args.baseline/f'{x["name"]}-{kind}.png')).astype(np.int16)
        q=np.asarray(Image.open(args.other/f'{x["name"]}-{kind}.png')).astype(np.int16)
        if p.shape != q.shape: raise SystemExit('Dimensions differ')
        d=p-q
        row[kind]={'exact_decoded_rgba':bool(np.all(d==0)), 'rgb_mae_8bit':float(np.mean(np.abs(d[:,:,:3]))), 'changed_pixel_fraction':float(np.mean(np.any(d!=0,axis=2)))}
    rows.append(row)
aa=json.loads((args.baseline/'analysis.json').read_text());bb=json.loads((args.other/'analysis.json').read_text())
result={'baseline':str(args.baseline),'other':str(args.other),'rows':rows,'max_whole_quilt_psnr_difference_db':max(abs(x['whole_quilt_psnr_db']-y['whole_quilt_psnr_db']) for x,y in zip(aa['cases'],bb['cases']))}
(args.other/'comparison.json').write_text(json.dumps(result,indent=2))
print('Depth counters exact:',all(r['depth_counters_exact'] for r in rows))
print('Decoded quilts exact:',all(r[k]['exact_decoded_rgba'] for r in rows for k in ['synth','reference']))
print('Max PSNR difference:',result['max_whole_quilt_psnr_difference_db'])
