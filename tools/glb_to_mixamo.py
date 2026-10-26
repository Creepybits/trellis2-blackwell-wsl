"""
Convert a TRELLIS.2 GLB into a zip that Mixamo's auto-rigger accepts.

Keeps the full triangle count on purpose: reducing triangles on TRELLIS meshes (thousands of
UV islands) damaged the texture with dark specks and broke Mixamo's marker placement in our tests.
Mixamo handled ~500k-triangle uploads fine.

The zip holds a textured OBJ with a matte material (no specular), so the rigged FBX that Mixamo
returns doesn't look like shiny plastic. Only the color texture is included; Mixamo ignores PBR maps.

Usage:  ~/TRELLIS.2/run.sh glb_to_mixamo.py input.glb [output.zip]
"""
import os
import sys
import tempfile
import zipfile

import trimesh

if len(sys.argv) < 2:
    sys.exit(__doc__)
src = sys.argv[1]
dst = sys.argv[2] if len(sys.argv) > 2 else os.path.splitext(src)[0] + '_mixamo.zip'

mesh = trimesh.load(src, force='mesh')
mesh.visual.material = mesh.visual.material.to_simple()

with tempfile.TemporaryDirectory() as work:
    mesh.export(os.path.join(work, 'character.obj'), include_texture=True, mtl_name='character.mtl')
    mtl = os.path.join(work, 'character.mtl')
    lines = [l.rstrip('\n') for l in open(mtl) if not l.strip().startswith(('Ks', 'Ns'))]
    lines += ['Ks 0.000000 0.000000 0.000000', 'Ns 0.000000']
    open(mtl, 'w').write('\n'.join(lines) + '\n')
    with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as z:
        for f in os.listdir(work):
            z.write(os.path.join(work, f), f)

print(f"{len(mesh.faces)} triangles -> {dst} ({os.path.getsize(dst) / 1e6:.1f} MB). Upload the zip to Mixamo as is.")
