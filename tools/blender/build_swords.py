"""Builds the three sword models (Striker / Breaker / Lancer) and exports them as .glb.

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/build_swords.py -- <out_dir> [preview_dir]

Conventions (in Godot after export, Y-up):
  - Origin = middle of the grip (where the hands hold it).
  - Blade points +Y. Flat of the blade faces ±X. Edges face ±Z.
  - Named empties for gameplay effects:  Nozzle (thruster exit, points -Y),  Muzzle (barrel end),  Tip.
In Blender (Z-up) that means: blade along +Z, width along Y, thickness along X.
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = argv[0] if argv else "assets/swords"
PREVIEW_DIR = argv[1] if len(argv) > 1 else ""


# ------------------------------------------------------------------ helpers

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, color, metallic=0.9, roughness=0.35, emission=None, strength=4.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    return m


def finish(obj, mat, bevel=0.0, smooth=False):
    obj.data.materials.append(mat)
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
    for p in obj.data.polygons:
        p.use_smooth = smooth
    return obj


def box(name, size, loc, mat, bevel=0.01, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return finish(o, mat, bevel)


def cyl(name, radius, depth, loc, mat, rot=(0, 0, 0), verts=24, radius2=None, bevel=0.004):
    if radius2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius, radius2=radius2, depth=depth, location=loc, rotation=rot)
    o = bpy.context.object
    o.name = name
    return finish(o, mat, bevel, smooth=True)


def empty(name, loc):
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=loc)
    bpy.context.object.name = name


def blade(name, profile, thickness, mat, z0):
    """Faceted blade: diamond cross-section (sharp edges, thicker spine).
    profile: list of (z, width) from base to tip; width 0 = point."""
    bm = bmesh.new()
    rings = []
    for z, w in profile:
        t = thickness * (0.35 + 0.65 * min(1.0, w / max(p[1] for p in profile)))
        if w <= 0.0001:
            rings.append([bm.verts.new((0, 0, z0 + z))])
            continue
        rings.append([
            bm.verts.new((0, -w / 2, z0 + z)),   # back edge
            bm.verts.new((t / 2, 0, z0 + z)),    # spine, +X face
            bm.verts.new((0, w / 2, z0 + z)),    # front edge
            bm.verts.new((-t / 2, 0, z0 + z)),   # spine, -X face
        ])
    for a, b in zip(rings, rings[1:]):
        if len(b) == 1:
            for i in range(4):
                bm.faces.new((a[i], a[(i + 1) % 4], b[0]))
        else:
            for i in range(4):
                bm.faces.new((a[i], a[(i + 1) % 4], b[(i + 1) % 4], b[i]))
    bm.faces.new(list(reversed(rings[0])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)  # outward, or the blade renders see-through
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(mat)
    return o


def spine_strip(name, profile, thickness, mat, z0, inset=0.18):  # noqa
    """Glowing strip down the middle of both blade faces (stops before the tip)."""
    zs = [p[0] for p in profile]
    top = zs[-1] * 0.82
    length = top - inset
    for side in (1, -1):
        t = thickness * 0.5
        box(f"{name}_{'R' if side > 0 else 'L'}", (0.012, 0.03, length),
            (side * (t * 0.98 + 0.012), 0, z0 + inset + length / 2), mat, bevel=0.0)


def base_frame(m, grip_len=0.5, housing=(0.16, 0.30, 0.34), blade_w=0.4):
    """Shared base frame: thick grip with wraps, pommel ring, core housing with glowing cell
    and side vents, and a tapered collar that hands off to the blade."""
    cyl("Grip", 0.048, grip_len, (0, 0, 0), m["grip"], verts=16)
    for i in range(3):  # grip wraps
        z = -grip_len / 2 + 0.08 + i * (grip_len - 0.16) / 2
        cyl(f"Wrap{i}", 0.054, 0.05, (0, 0, z), m["dark"], verts=16)
    cyl("Pommel", 0.07, 0.06, (0, 0, -grip_len / 2 - 0.02), m["metal"], verts=20)
    hw = max(housing[1], blade_w * 1.15)
    hz = grip_len / 2 + housing[2] / 2
    box("Housing", (housing[0], hw, housing[2]), (0, 0, hz), m["dark"], bevel=0.03)
    for side in (1, -1):  # side cheek plates
        box(f"Cheek{side}", (0.025, hw * 0.8, housing[2] * 0.8), (side * (housing[0] / 2 + 0.01), 0, hz), m["plate"], bevel=0.01)
        # glowing vents on the cheeks
        for i in range(3):
            box(f"Vent{side}{i}", (0.012, hw * 0.5, 0.018),
                (side * (housing[0] / 2 + 0.024), 0, hz - housing[2] * 0.22 + i * housing[2] * 0.22), m["glow"], bevel=0.0)
    box("CoreCell", (housing[0] * 0.6, hw * 0.3, housing[2] * 0.3), (0, hw * 0.52, hz), m["glow"], bevel=0.008)
    # Tapered collar: from housing width down to the blade base.
    collar_h = housing[2] * 0.45
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=1, radius2=0.75, depth=collar_h,
                                    location=(0, 0, grip_len / 2 + housing[2] + collar_h / 2), rotation=(0, 0, math.pi / 4))
    c = bpy.context.object
    c.name = "Collar"
    c.scale = (housing[0] * 0.75, hw * 0.72, 1)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    finish(c, m["dark"], bevel=0.01)
    return grip_len / 2 + housing[2] + collar_h  # blade base z


def blade_panels(name, profile, thickness, m, z0, length_ratio=0.7, width_ratio=0.45):
    """Dark tech panels on both blade faces, under the glowing spine."""
    maxw = max(p[1] for p in profile)
    top = profile[-1][0] * length_ratio
    for side in (1, -1):
        box(f"{name}{side}", (0.014, maxw * width_ratio, top - 0.1), (side * thickness * 0.42, 0, z0 + 0.05 + (top - 0.1) / 2),
            m["panel"], bevel=0.004)


def thruster(m, grip_len, radius=0.09, length=0.28, twin=False):
    """Nozzle(s) under the pommel, pointing down (-Z in Blender = -Y in game)."""
    bottom = -grip_len / 2
    offsets = [(-0.07, 0), (0.07, 0)] if twin else [(0, 0)]
    for i, (dx, dy) in enumerate(offsets):
        cyl(f"NozzleBody{i}", radius * 0.75, length * 0.5, (dx, dy, bottom - length * 0.25), m["dark"], verts=20)
        cyl(f"NozzleBell{i}", radius * 0.7, length * 0.55, (dx, dy, bottom - length * 0.72), m["metal"], verts=24, radius2=radius * 1.1)
        cyl(f"NozzleGlow{i}", radius * 0.95, 0.02, (dx, dy, bottom - length * 1.0), m["glow"], verts=24)
    empty("Nozzle", (0, 0, bottom - length * 1.02))


def export(name):
    os.makedirs(OUT_DIR, exist_ok=True)
    # Apply modifiers on export so bevels are baked in.
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, f"{name}.glb"), export_format="GLB",
                              export_apply=True, export_yup=True)


def preview_all(names):
    """Imports the exported swords side by side at true scale and renders one comparison image."""
    if not PREVIEW_DIR:
        return
    reset()
    for i, n in enumerate(names):
        bpy.ops.import_scene.gltf(filepath=os.path.join(OUT_DIR, f"{n}.glb"))
        for o in bpy.context.selected_objects:
            if o.parent is None:
                o.location.x += (i - 1) * 1.3
                o.rotation_mode = "XYZ"  # glTF imports use quaternions
                o.rotation_euler.z += math.radians(-65)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 1000
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.35, 0.42, 0.52, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.7
    scene.world = world
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), 0, math.radians(30)))
    bpy.context.object.data.energy = 3.0
    bpy.ops.object.camera_add(location=(0, -6.2, 1.4))
    cam = bpy.context.object
    scene.camera = cam
    cam.rotation_euler = (Vector((0, 0, 1.25)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 38
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    scene.render.filepath = os.path.join(PREVIEW_DIR, "swords.png")
    bpy.ops.render.render(write_still=True)


def materials(accent):
    return {
        "dark": material("Gunmetal", (0.06, 0.065, 0.075), metallic=0.85, roughness=0.4),
        "metal": material("Steel", (0.55, 0.57, 0.6), metallic=0.8, roughness=0.3),
        "blade": material("Blade", (0.82, 0.84, 0.88), metallic=0.65, roughness=0.28),
        "panel": material("Panel", (0.16, 0.17, 0.2), metallic=0.8, roughness=0.4),
        "plate": material("Plate", (0.3, 0.32, 0.36), metallic=0.7, roughness=0.35),
        "grip": material("Grip", (0.03, 0.03, 0.035), metallic=0.1, roughness=0.8),
        "glow": material("Glow", accent, metallic=0.0, roughness=0.5, emission=accent, strength=1.2),
    }


# ------------------------------------------------------------------ swords

def striker():
    """Mobility: slim, fast blade. Long single nozzle with fins, twin machine-gun barrels."""
    reset()
    m = materials((0.2, 0.85, 1.0))
    grip = 0.46
    z0 = base_frame(m, grip, housing=(0.15, 0.26, 0.26), blade_w=0.3)
    profile = [(0.0, 0.24), (0.15, 0.30), (1.1, 0.28), (1.45, 0.22), (1.62, 0.1), (1.72, 0.0)]
    blade("Blade", profile, 0.07, m["blade"], z0)
    blade_panels("Panel", profile, 0.07, m, z0)
    spine_strip("Spine", profile, 0.07, m["glow"], z0)
    thruster(m, grip, radius=0.085, length=0.36)
    for side in (1, -1):  # stabilizer fins
        box(f"Fin{side}", (0.012, 0.12, 0.2), (0, side * 0.11, -grip / 2 - 0.1), m["plate"], bevel=0.004,
            rot=(side * 0.35, 0, 0))
    # Twin barrels along the back edge of the blade base.
    for i, dx in enumerate((-0.035, 0.035)):
        cyl(f"Barrel{i}", 0.022, 0.62, (dx, -0.19, z0 + 0.25), m["dark"], verts=12)
    box("BarrelMount", (0.11, 0.08, 0.16), (0, -0.16, z0 + 0.02), m["dark"], bevel=0.01)
    empty("Muzzle", (0, -0.19, z0 + 0.57))
    empty("Tip", (0, 0, z0 + 1.72))
    export("striker")


def breaker():
    """Power: huge cleaver slab with armor plates and bolts. Twin stubby nozzles. No gun."""
    reset()
    m = materials((1.0, 0.45, 0.1))
    grip = 0.55
    z0 = base_frame(m, grip, housing=(0.26, 0.5, 0.4), blade_w=0.76)
    profile = [(0.0, 0.62), (0.2, 0.76), (2.2, 0.76), (2.45, 0.6), (2.55, 0.3), (2.6, 0.0)]
    blade("Blade", profile, 0.16, m["blade"], z0)
    spine_strip("Spine", profile, 0.16, m["glow"], z0, inset=0.6)
    # Armor plates riveted onto the lower blade.
    for side in (1, -1):
        box(f"Plate{side}", (0.03, 0.62, 0.5), (side * 0.085, 0, z0 + 0.3), m["plate"], bevel=0.015)
        for i in range(3):
            for j in (-1, 1):
                cyl(f"Bolt{side}{i}{j}", 0.025, 0.02, (side * 0.102, j * 0.24, z0 + 0.1 + i * 0.2), m["metal"],
                    rot=(0, math.pi / 2, 0), verts=10)
    # Notch teeth on the back edge.
    for i in range(3):
        box(f"Tooth{i}", (0.12, 0.08, 0.1), (0, -0.4, z0 + 1.0 + i * 0.25), m["dark"], bevel=0.008)
    thruster(m, grip, radius=0.075, length=0.24, twin=True)
    empty("Muzzle", (0, 0, z0 + 0.4))  # unused (no gun) but keeps the node layout identical
    empty("Tip", (0, 0, z0 + 2.6))
    export("breaker")


def lancer():
    """Balanced: lance-like pointed blade with a rocket launcher tube along its back."""
    reset()
    m = materials((0.35, 1.0, 0.45))
    grip = 0.5
    z0 = base_frame(m, grip, housing=(0.18, 0.36, 0.3), blade_w=0.44)
    profile = [(0.0, 0.36), (0.15, 0.44), (1.4, 0.4), (1.8, 0.26), (2.0, 0.1), (2.1, 0.0)]
    blade("Blade", profile, 0.1, m["blade"], z0)
    blade_panels("Panel", profile, 0.1, m, z0)
    spine_strip("Spine", profile, 0.1, m["glow"], z0)
    # Launcher tube along the back edge.
    cyl("LauncherTube", 0.11, 1.05, (0, -0.32, z0 + 0.45), m["dark"], verts=20)
    cyl("LauncherMuzzle", 0.13, 0.08, (0, -0.32, z0 + 1.0), m["metal"], verts=20)
    cyl("LauncherGlow", 0.085, 0.01, (0, -0.32, z0 + 1.045), m["glow"], verts=20)
    for i in range(2):
        box(f"Clamp{i}", (0.06, 0.2, 0.06), (0, -0.22, z0 + 0.1 + i * 0.6), m["plate"], bevel=0.008)
    thruster(m, grip, radius=0.09, length=0.3)
    empty("Muzzle", (0, -0.32, z0 + 1.06))
    empty("Tip", (0, 0, z0 + 2.1))
    export("lancer")


striker()
breaker()
lancer()
preview_all(["striker", "breaker", "lancer"])
print("SWORDS_DONE")
