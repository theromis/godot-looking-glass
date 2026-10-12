import pathlib,json,statistics,hashlib,sys
root=pathlib.Path(__file__).resolve().parent
views=int(sys.argv[1]) if len(sys.argv)>1 else 12
prefix=f'v{views}-' if views!=12 else ''
out={'description':'Interleaved 3 baseline/3 shared runs on the same patched Godot binary; N real views, four SpotLight, deterministic moving caster, no shadow mesh LOD, full caster culling. Per-viewport GPU sum is not frame critical path.'}
for stage in ('baseline','shared'):
 rows=[json.loads((root/f'{prefix}{stage}-{i+1}.json').read_text()) for i in range(3)]
 out[stage]={'runs':rows,'means':{k:statistics.mean(x[k] for x in rows) for k in ('frame_mean_ms','anchor_gpu_sum_mean_ms','shadow_draw_calls_sum_mean')}}
 png=root/f'{prefix}{stage}-1.png'
 out[stage]['sample_stdev']={k:statistics.stdev(x[k] for x in rows) for k in ('frame_mean_ms','anchor_gpu_sum_mean_ms')}
 out[stage]['png_sha256']=hashlib.sha256(png.read_bytes()).hexdigest()
out['views']=views
out['reduction_percent']={k:100*(1-out['shared']['means'][k]/out['baseline']['means'][k]) for k in out['baseline']['means']}
out['png_byte_identical']=out['baseline']['png_sha256']==out['shared']['png_sha256']
(root/f'{prefix}summary.json').write_text(json.dumps(out,indent=2))
print(json.dumps({s:out[s]['means'] for s in ('baseline','shared')},indent=2))
print('PNG byte identical:',out['png_byte_identical'])
