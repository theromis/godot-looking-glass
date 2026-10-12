"""Decode two prerecorded Godot PNG quilts for the fixed-size worker diagnostic."""
import argparse
from pathlib import Path
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("frame0", type=Path)
parser.add_argument("frame1", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
frames = []
for path in (args.frame0, args.frame1):
    with Image.open(path) as image:
        if image.size != (704, 684):
            parser.error("Worker diagnostic requires 704x684 quilts")
        frames.append(image.convert("RGBA").tobytes())
args.output.mkdir(parents=True, exist_ok=True)
for index, pixels in enumerate(frames):
    (args.output / f"frame-{index}.rgba").write_bytes(pixels)
print("Prepared two prerecorded RGBA8 quilts; not a live transport")
