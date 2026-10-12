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
images = {name: Image.open(p / f'{name}-1.png') for name in ['baseline','rescue']}
images['reference'] = Image.open(p / 'reference.png')
if any(im.size != (tile * 4, tile * 12) for im in images.values()):
    raise SystemExit('Unexpected quilt dimensions')
result = {}
for name in ['baseline','rescue']:
    result[name] = {}
    for reference in ['baseline', 'reference']:
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
holes = {name: Image.open(p / f'{name}-holes.png') for name in ['baseline','rescue']}
counts = {'baseline':0, 'rescue':0, 'resolved':0, 'new_holes':0, 'pixels':0, 'changed_outside_baseline_holes':0}
errors = {'baseline':0.0,'rescue':0.0}
for i in [i for i in range(48) if i not in anchors]:
    x, y = (i % 4) * tile, (11 - i // 4) * tile
    box = (x, y, x + tile, y + tile)
    masks = {name: np.all(np.asarray(im.crop(box))[:, :, :3] == np.array([255,0,255]), axis=2) for name, im in holes.items()}
    resolved = masks['baseline'] & ~masks['rescue']
    counts['baseline'] += int(masks['baseline'].sum())
    counts['rescue'] += int(masks['rescue'].sum())
    counts['resolved'] += int(resolved.sum())
    counts['new_holes'] += int((masks['rescue'] & ~masks['baseline']).sum())
    counts['pixels'] += tile * tile
    original = np.asarray(images['baseline'].crop(box))[:, :, :3]
    repaired = np.asarray(images['rescue'].crop(box))[:, :, :3]
    counts['changed_outside_baseline_holes'] += int(np.count_nonzero(np.any(original != repaired, axis=2) & ~masks['baseline']))
    reference = np.asarray(images['reference'].crop(box))[:, :, :3].astype(np.float32)
    for name in errors:
        delta = np.asarray(images[name].crop(box))[:, :, :3].astype(np.float32) - reference
        errors[name] += float(np.sum(delta[resolved] ** 2, dtype=np.float64))
counts['resolved_fraction_of_baseline_holes'] = counts['resolved']/counts['baseline'] if counts['baseline'] else 0
counts['resolved_pixel_rgb_psnr_vs_real'] = {name: 10*math.log10(255**2/(value/(counts['resolved']*3))) if value and counts['resolved'] else None for name,value in errors.items()}
result['hole_diagnostics'] = counts
result['limitations'] = ['PNG RGB after simple gamma transfer, not HDR/perceptual quality.', 'Static opaque scene only; temporal artifacts, transparency and other scenes untested.', 'Baseline is not ground truth; all-real reference shares shader transfer and lighting settings.', 'Magenta holes indicate two failed gathers, not all geometric disocclusions; diagnostics assume no exact-magenta material.']
(p / 'quality.json').write_text(json.dumps(result, indent=2))
print(json.dumps(result, indent=2))
