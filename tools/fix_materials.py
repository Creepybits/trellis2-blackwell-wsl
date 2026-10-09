"""
Fix washed-out TRELLIS.2 GLBs: remove false metallic and restore color saturation.

The 1024/1536 texture models sometimes classify dark glossy materials (leather, vinyl)
as metal and desaturate the base color. This rewrites the GLB's material:
  - metallic is scaled by --metal (default 0 = fully non-metallic)
  - base color chroma is scaled by --saturation in CIELAB (keeps hue and brightness)

Usage:  ./run.sh fix_materials.py input.glb [output.glb] [--saturation 2.0] [--metal 0] [--brightness 1.0]
"""
import argparse
import os
import cv2
import numpy as np
import trimesh
from PIL import Image

p = argparse.ArgumentParser()
p.add_argument('input')
p.add_argument('output', nargs='?')
p.add_argument('--saturation', type=float, default=2.0)
p.add_argument('--metal', type=float, default=0.0)
p.add_argument('--brightness', type=float, default=1.0)
args = p.parse_args()
out = args.output or os.path.splitext(args.input)[0] + '_fixed.glb'

scene = trimesh.load(args.input)
for name, geom in scene.geometry.items():
    mat = geom.visual.material
    rgba = np.asarray(mat.baseColorTexture.convert('RGBA'))
    lab = cv2.cvtColor(rgba[..., :3], cv2.COLOR_RGB2LAB).astype(np.float32)
    lab[..., 0] = np.clip(lab[..., 0] * args.brightness, 0, 255)
    lab[..., 1:] = np.clip((lab[..., 1:] - 128) * args.saturation + 128, 0, 255)
    rgb = cv2.cvtColor(lab.astype(np.uint8), cv2.COLOR_LAB2RGB)
    mat.baseColorTexture = Image.fromarray(np.concatenate([rgb, rgba[..., 3:]], -1))

    mr = np.asarray(mat.metallicRoughnessTexture.convert('RGB')).copy()
    before = mr[..., 2].mean() / 255
    mr[..., 2] = np.clip(mr[..., 2].astype(np.float32) * args.metal, 0, 255).astype(np.uint8)
    mat.metallicRoughnessTexture = Image.fromarray(mr)
    print(f"{name}: metallic {before:.2f} -> {mr[..., 2].mean() / 255:.2f}, saturation x{args.saturation}")

scene.export(out, extension_webp=True)
print("Saved", out)
