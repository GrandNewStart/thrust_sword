"""Merges the Mixamo character + animation FBX files into one .glb for the game.

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/build_character.py -- \
          assets/mixamo/source  assets/mixamo/vanguard.glb  assets/mixamo/anim_info.json

(assets/mixamo/source/ holds the raw Mixamo downloads; it has a .gdignore so Godot doesn't
import or ship them — only the merged vanguard.glb is used by the game.)

- character.fbx (with skin) provides the mesh + skeleton; every other <name>.fbx provides one
  animation, exported as an action called <name>.
- Horizontal root (Hips) motion is removed: the game moves the character itself.
- anim_info.json lists each clip's length and the frame where the right hand moves fastest
  (used to line up the moment a swing connects with the game's hit window).
Output stays inside assets/mixamo/ (Mixamo content: not for redistribution, git-ignored).
"""
import glob
import json
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT_GLB, OUT_INFO = argv[0], argv[1], argv[2]
FPS = 30

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = FPS

# 1. Character (mesh + armature).
bpy.ops.import_scene.fbx(filepath=os.path.join(SRC, "character.fbx"), automatic_bone_orientation=False)
armature = next(o for o in bpy.data.objects if o.type == "ARMATURE")
armature.name = "Character"
if armature.animation_data and armature.animation_data.action:
    armature.animation_data.action.name = "gs_idle"
    armature.animation_data.action.use_fake_user = True
keep = set(bpy.data.objects)

# 2. Animations: import each, take its action, delete its armature.
for path in sorted(glob.glob(os.path.join(SRC, "*.fbx"))):
    name = os.path.splitext(os.path.basename(path))[0]
    if name == "character":
        continue
    before_actions = set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=path, automatic_bone_orientation=False)
    new_actions = [a for a in bpy.data.actions if a not in before_actions]
    if new_actions:
        act = new_actions[0]
        act.name = name
        act.use_fake_user = True
    for o in [o for o in bpy.data.objects if o not in keep]:
        bpy.data.objects.remove(o, do_unlink=True)


def fcurves(action):
    """All F-curves of an action (Blender 4.4+ layered actions, with a legacy fallback)."""
    if hasattr(action, "layers") and action.layers:
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    yield from bag.fcurves
    elif hasattr(action, "fcurves"):
        yield from action.fcurves


def assign(anim_data, action):
    anim_data.action = action
    if action and hasattr(anim_data, "action_slot") and action.slots:
        anim_data.action_slot = action.slots[0]


def strip_root_motion(action):
    """Hips location: keep height, freeze horizontal movement at its first value."""
    for fc in fcurves(action):
        if fc.data_path.endswith('"].location') and "Hips" in fc.data_path and fc.array_index in (0, 2):
            first = fc.keyframe_points[0].co[1] if fc.keyframe_points else 0.0
            for kp in fc.keyframe_points:
                kp.co[1] = first
                kp.handle_left[1] = first
                kp.handle_right[1] = first


# 3. Analyse each clip + push it onto the armature as an NLA strip so the exporter writes it.
info = {}
hand = next(b for b in armature.pose.bones if b.name.endswith("RightHand"))
lhand = next(b for b in armature.pose.bones if b.name.endswith("LeftHand"))
armature.animation_data_create()
scene = bpy.context.scene
for act in sorted(bpy.data.actions, key=lambda a: a.name):
    strip_root_motion(act)
    assign(armature.animation_data, act)
    start, end = int(act.frame_range[0]), int(act.frame_range[1])
    prev = None
    speeds = []
    for f in range(start, end + 1):
        scene.frame_set(f)
        p = armature.matrix_world @ hand.head
        speeds.append(0.0 if prev is None else (p - prev).length * FPS)
        prev = p.copy()
    lo, hi = int(len(speeds) * 0.1), max(int(len(speeds) * 0.9), 2)
    peak = max(range(lo, hi), key=lambda i: speeds[i]) if hi > lo else 0
    info[act.name] = {
        "length": (end - start) / FPS,
        "contact": peak / FPS,
        "peak_hand_speed": round(speeds[peak], 2),
    }
    track = armature.animation_data.nla_tracks.new()
    track.name = act.name
    strip = track.strips.new(act.name, start, act)
    if hasattr(strip, "action_slot") and act.slots:
        strip.action_slot = act.slots[0]
assign(armature.animation_data, None)

# Height of the character in the first idle frame (for scaling in the game).
scene.frame_set(0)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
zs = [(o.matrix_world @ Vector(c)).z for o in meshes for c in o.bound_box]
info["_height"] = max(zs) - min(zs)
info["_bones"] = [b.name for b in armature.pose.bones][:8]

bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", export_animation_mode="NLA_TRACKS",
                          export_yup=True, export_apply=False)
with open(OUT_INFO, "w") as f:
    json.dump(info, f, indent=1)
print("CHARACTER_DONE", len(info) - 2, "clips, height", round(info["_height"], 2))
