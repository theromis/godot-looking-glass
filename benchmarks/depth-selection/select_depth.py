"""Select anchors exclusively from GPU depth counters; never opens any image."""
import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'interval-placement'))
from optimize import select_anchors
parser=argparse.ArgumentParser()
parser.add_argument('directory',type=Path)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
raw=json.loads((args.directory/'raw.json').read_text())
protocol=json.loads((Path(__file__).parent/'protocol.json').read_text())
uniform=[int(i*47/23+0.5) for i in range(24)]
result={'protocol':protocol,'cases':{}}
for case in raw['cases']:
    selected={}
    for metric in protocol['depth_policies']:
        costs={(a,a+1):0.0 for a in range(47)}
        for layout in case['layouts']:
            if not layout['label'].startswith('gap'): continue
            probe=layout['probe']
            index=probe['metrics'].index(metric)
            if probe['sample_grid']!=[256,256]: raise SystemExit('Unexpected sample grid')
            for a,b in zip(layout['anchors'],layout['anchors'][1:]):
                value=sum(row['counts'][index] for row in probe['rows'] if a<row['view']<b)
                if (a,b) in costs and costs[a,b]!=value: raise SystemExit('Depth interval differs between layouts')
                costs[a,b]=value
        if len(costs)!=138: raise SystemExit('Incomplete candidate intervals')
        anchors,total=select_anchors(costs,48,24,3,uniform)
        selected[metric]={'anchors':anchors,'depth_counter_cost':total,'uniform_depth_counter_cost':sum(costs[a,b] for a,b in zip(uniform,uniform[1:]))}
    result['cases'][case['name']]=selected
if len(result['cases'])!=9: raise SystemExit('Incomplete poses')
args.output.write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
