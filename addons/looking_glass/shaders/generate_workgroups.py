"""Generate local-size/iteration-limit variants from canonical 8x8/8 shaders."""
from pathlib import Path
root = Path(__file__).resolve().parent
for stem in ("synthesize", "synthesize_raw_depth", "synthesize_rescue", "synthesize_raw_depth_rescue", "synthesize_raw_depth_inverse", "synthesize_raw_depth_inverse_rescue"):
    source = (root / f"{stem}.glsl").read_text()
    marker = "local_size_x=8,local_size_y=8"
    loop = "for(int k=0;k<8;k++)"
    if source.count(marker) != 1 or source.count(loop) != 1:
        raise SystemExit(f"Unexpected canonical shader: {stem}")
    for limit in (2, 4, 8):
        for x, y in ((8, 8), (16, 8), (16, 16)):
            if limit == 8 and (x, y) == (8, 8):
                continue
            suffix = f"_iterations{limit}" if limit != 8 else ""
            if (x, y) != (8, 8):
                suffix += f"_{x}x{y}"
            (root / f"{stem}{suffix}.glsl").write_text(
                source.replace(marker, f"local_size_x={x},local_size_y={y}")
                .replace(loop, f"for(int k=0;k<{limit};k++)")
            )
