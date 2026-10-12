"""Compare predefined depth-only proxies with full-tile reconstruction errors."""
import argparse, hashlib, json, math
from pathlib import Path
import numpy as np
from PIL import Image
parser=argparse.ArgumentParser()
parser.add_argument('directory',type=Path)
args=parser.parse_args()
p=args.directory
raw=json.loads((p/'raw.json').read_text())
metrics=raw['rows'][0]['metrics']
tile=raw['tile']

def ranks(a):
    a=np.asarray(a,dtype=np.float64)
    order=np.argsort(a,kind='stable')
    result=np.empty(len(a),dtype=np.float64)
    first=0
    while first<len(a):
        last=first+1
        while last<len(a) and a[order[last]]==a[order[first]]: last+=1
        result[order[first:last]]=(first+last-1)*0.5
        first=last
    return result

def correlation(a,b):
    a=np.asarray(a,dtype=np.float64);b=np.asarray(b,dtype=np.float64)
    if np.std(a)==0 or np.std(b)==0: return None
    return float(np.corrcoef(a,b)[0,1])

def top_recall(scores,errors):
    scores=np.asarray(scores);errors=np.asarray(errors)
    if np.std(scores)==0 or np.std(errors)==0: return None
    k=len(scores)//4
    truth=np.argsort(errors)[-k:]
    cutoff=np.sort(scores)[-k]
    selected=scores>cutoff
    tied=scores==cutoff
    remaining=k-int(selected.sum())
    probability=selected.astype(float)+tied*remaining/int(tied.sum())
    return float(probability[truth].sum()/k)

def statistics(rows):
    result={}
    mse=[r['rgb_mse'] for r in rows]
    for name in [*metrics,'geometric_baseline']:
        scores=[r[name] for r in rows]
        result[name]={'pearson_mse':correlation(scores,mse),'spearman_mse':correlation(ranks(scores),ranks(mse)),
                      'top_quartile_recall':top_recall(scores,mse),'minimum':min(scores),'maximum':max(scores)}
    return result

rows=[];cases=[];hashes={}
for case in raw['rows']:
    name=case['name']
    synth_path=p/f'{name}-synth.png';ref_path=p/f'{name}-reference.png'
    synth=Image.open(synth_path);ref=Image.open(ref_path)
    if synth.size!=ref.size or ref.size!=(4*tile,12*tile): raise SystemExit('Invalid quilt dimensions')
    hashes[name]={'synth':hashlib.sha256(synth_path.read_bytes()).hexdigest(),'reference':hashlib.sha256(ref_path.read_bytes()).hexdigest()}
    records=[];sse_total=0;sae_total=0
    for probe in case['rows']:
        i=probe['view'];x,y=(i%4)*tile,(11-i//4)*tile
        box=(x,y,x+tile,y+tile)
        a=np.asarray(synth.crop(box))[:,:,:3].astype(np.float32)
        b=np.asarray(ref.crop(box))[:,:,:3].astype(np.float32)
        delta=a-b
        sse=float(np.sum(delta*delta,dtype=np.float64));sae=float(np.sum(np.abs(delta),dtype=np.float64))
        sse_total+=sse;sae_total+=sae
        if probe['real']:
            if sse!=0: raise SystemExit(f'Confounded reference: real view {i} in {name} differs')
            continue
        record={'case':name,'scene':case['scene'],'snapshot':case['snapshot'],'view':i,'rgb_mse':sse/(3*tile*tile),'rgb_mae':sae/(3*tile*tile),
                'geometric_baseline':(i-probe['a'])*(probe['b']-i)}
        for index,metric in enumerate(metrics): record[metric]=probe['counts'][index]/probe['samples']
        records.append(record)
    if len(records)!=32: raise SystemExit('Expected 32 synthesized views')
    rows.extend(records)
    mse=sse_total/(48*3*tile*tile)
    cases.append({'name':name,'scene':case['scene'],'snapshot':case['snapshot'],'camera_x':case['camera_x'],'camera_yaw_radians':case['camera_yaw_radians'],
                  'whole_quilt_psnr_db':10*math.log10(255**2/mse) if mse else None,'statistics':statistics(records)})
    synth.close();ref.close()
centered=[]
for case in cases:
    records=[r for r in rows if r['case']==case['name']]
    for r in records:
        record=r.copy()
        for key in ['rgb_mse',*metrics,'geometric_baseline']:
            record[key]=r[key]-np.mean([v[key] for v in records])
        centered.append(record)
partial={}
baseline=np.asarray([r['geometric_baseline'] for r in centered],dtype=float)
errors=np.asarray([r['rgb_mse'] for r in centered],dtype=float)
errors_residual=errors-baseline*np.dot(baseline,errors)/np.dot(baseline,baseline)
for name in metrics:
    scores=np.asarray([r[name] for r in centered],dtype=float)
    score_residual=scores-baseline*np.dot(baseline,scores)/np.dot(baseline,baseline)
    partial[name]=correlation(score_residual,errors_residual)
report={'motion':raw['motion'],'partial_pearson_controlling_snapshot_and_linear_geometric_baseline':partial,'godot':raw['godot'],'adapter':raw['adapter'],'tile':tile,'sample_grid':raw['rows'][0]['sample_grid'],'synthesized_view_observations':len(rows),'metrics':metrics,
        'pooled_statistics':statistics(rows),'within_snapshot_centered_statistics':statistics(centered),'cases':cases,'rows':rows,'image_sha256':hashes,
        'limitations':['No fitted weights: four predefined metrics and an anchor-distance baseline evaluated separately.',
                       'Pooled correlations may be explained by scene differences; inspect per-snapshot and centered values.',
                       'Nine sampled poses across three unshaded opaque fixtures; camera motion mode recorded separately. Not a temporal quality/flicker test or production scenes.',
                       'Probe sample grid is recorded; output tiles are 256x256. No quality/speed guarantee at other resolutions.',
                       'Top-quartile recall uses fractional selection at score ties; constant scores are undefined, not evidence of prediction.',
                       'CPU-synchronized buffer readback, shader creation and compile included in diagnostic workflow; runtime overhead not benchmarked.',
                       'No runtime anchor selection or default rendering change is enabled.']}
(p/'analysis.json').write_text(json.dumps(report,indent=2))
print(json.dumps({k:report[k] for k in ['synthesized_view_observations','pooled_statistics','within_snapshot_centered_statistics','partial_pearson_controlling_snapshot_and_linear_geometric_baseline','cases']},indent=2))
