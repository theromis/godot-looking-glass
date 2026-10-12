"""RGB error on synthesized tiles of display-mapped PNG; not perceptual quality."""
import argparse, json, math
from pathlib import Path
import numpy as np
from PIL import Image
parser = argparse.ArgumentParser()
parser.add_argument('directory', type=Path)
args = parser.parse_args()
p = args.directory
summary = json.loads((p / 'summary.json').read_text())
tile = summary['scene']['tile']
anchors = {int(math.floor(i * 47 / (summary['scene']['real_views'] - 1) + 0.5)) for i in range(summary['scene']['real_views'])}
images = {name: Image.open(p / f'{name}-1.png') for name in ['8','4','2']}
images['reference'] = Image.open(p / 'reference.png')
if any(im.size != (tile * 4, tile * 12) for im in images.values()):
    raise SystemExit('Unexpected quilt dimensions')
result = {}
for name in ['8','4','2']:
    result[name] = {}
    for reference in ['8', 'reference']:
        for subset, views in [('synthesized', [i for i in range(48) if i not in anchors]), ('real_anchors', sorted(anchors))]:
            squared = absolute = changed = components = pixels = 0
            for i in views:
                x, y = (i % 4) * tile, (11 - i // 4) * tile
                box = (x, y, x + tile, y + tile)
                a = np.asarray(images[name].crop(box))[:, :, :3].astype(np.float32)
                b = np.asarray(images[reference].crop(box))[:, :, :3].astype(np.float32)
                delta = a - b
                squared += float(np.sum(delta * delta, dtype=np.float64))
                absolute += float(np.sum(np.abs(delta), dtype=np.float64))
                changed += int(np.count_nonzero(np.any(delta != 0, axis=2)))
                components += delta.size
                pixels += delta.shape[0] * delta.shape[1]
            mse = squared / components
            result[name][f'{subset}_vs_{reference}'] = {'rgb_mae_8bit': absolute / components, 'rgb_psnr_db': 10 * math.log10(255**2 / mse) if mse else None, 'changed_pixel_fraction': changed / pixels, 'exact_rgb': squared == 0}
result['limitations'] = ['PNG RGB after simple gamma transfer, not HDR/perceptual quality.', 'Static opaque scene only; temporal artifacts, transparency and other scenes untested.', 'The 8-iteration baseline is not ground truth; all-real reference shares shader transfer and lighting settings.']
(p / 'quality.json').write_text(json.dumps(result, indent=2))
print(json.dumps(result, indent=2))
