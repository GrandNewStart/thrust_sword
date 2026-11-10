class_name CharacterAnimator
extends Node
## Drives the Mixamo character's animations from the Fighter's state.
##
## Gameplay timing stays in charge: attack clips are not "played", they are scrubbed so the
## clip's swing lines up with the attack's windup / active / recovery phases (and they freeze
## during hitstop).
##
## The body is layered by region:
##   legs, hips — natural walk / jog / run clips (long strides), matched to ground speed
##   both arms  — great-sword clips: both hands stay on the grip
##   torso/head — partly natural while moving: chest counter-rotates and bobs with the steps,
##                carrying arms + sword with it (so they sway instead of looking frozen)
## Actions either take the upper body only (guard, charge, firing: legs keep moving) or the
## whole body (attacks, hit reactions, jumps, K.O.: their footwork matters).
##
## Tree:  legs ─ right_arm(armsR) ─ torso(armsT) ─ left_arm(armsL) ─ loco_speed ─┐
##        full-body action slots (F) ── full ── upper-body action slots (U, spine filter) ── output
## Full-body actions are applied first, upper-body actions on top, so one moment can mix both
## (e.g. a dash: braced legs from one clip, the sword thrust forward from another).
## Two action slots crossfade, so attack -> attack (combos) and guard -> hit blend smoothly.

## Mixamo character + animations, merged by tools/blender/build_character.py.
const SCENE_PATH := "res://assets/mixamo/vanguard.glb"
const HAND_BONE := "mixamorig_RightHand"
const TARGET_HEIGHT := 1.9
const SOURCE_HEIGHT := 1.73

## Sword grip in right-hand bone space (skeleton units are cm).
## Measured from the great-sword clips: blade continues past the right hand, along the
## line from the left hand to the right hand; the cutting edge leads the swings.
const GRIP_POS := Vector3(-6.6, 8.5, 9.4)
const BLADE_DIR := Vector3(0.56, -0.25, -0.78)
const EDGE_DIR := Vector3(-0.82, -0.09, -0.56)

## Attack name -> clip and clip times (s): start, contact (fastest point of the swing), end.
## The game's active (hit) window is mapped around the contact time.
const ATTACK_CLIPS := {
	# Light chain: the spin-kick clip's two sweeps (the kick between them is skipped), then a poke.
	&"light": ["gs_kick", 0.10, 0.37, 0.62],     # swing to the left (right -> left)
	&"light_2": ["gs_kick", 0.85, 1.20, 1.50],   # swing to the right (left -> right)
	&"light_3": ["spear_stab", 0.00, 0.40, 1.00],  # forward poke (blade levelled by FighterVisual)
	&"slash_left": ["gs_power_slash", 0.30, 0.77, 1.50],
	&"slash_right": ["gs_high_spin", 0.62, 0.92, 1.25],  # left -> right sweep
	&"thrust": ["spear_stab", 0.00, 0.40, 1.00],
	&"smash": ["gs_downward_slash", 0.10, 0.57, 1.27],
	# Starts from the wound-up frame the charge pose ends on (blade drawn behind), so the
	# release flows straight into the combo slash's big behind-to-front sweep.
	&"heavy": ["gs_combo_slash", 0.40, 0.80, 1.20],
}
const CONTACT_HALF_WIDTH := 0.12

## Legs: radius 1 = walk, 2 = jog, 3 = run.
const LEG_POINTS := {
	"gs_idle": Vector2(0, 0),
	"legs_walk_fwd": Vector2(0, 1), "legs_walk_back": Vector2(0, -1),
	"legs_walk_left": Vector2(-1, 0), "legs_walk_right": Vector2(1, 0),
	"legs_jog_fwd": Vector2(0, 2), "legs_jog_back": Vector2(0, -2),
	"legs_jog_left": Vector2(-2, 0), "legs_jog_right": Vector2(2, 0),
	"legs_run_fwd": Vector2(0, 3), "legs_run_back": Vector2(0, -3),
	"legs_run_left": Vector2(-3, 0), "legs_run_right": Vector2(3, 0),
}
## Upper body carry pose: radius 1 = great-sword walk, 2 = great-sword run.
const ARM_POINTS := {
	"gs_idle": Vector2(0, 0),
	"gs_walk": Vector2(0, 1), "gs_walk_back": Vector2(0, -1),
	"gs_strafe_left": Vector2(-1, 0), "gs_strafe_right": Vector2(1, 0),
	"gs_run": Vector2(0, 2), "gs_run_back": Vector2(0, -2),
	"gs_run_left": Vector2(-2, 0), "gs_run_right": Vector2(2, 0),
}
## How fast each leg clip "travels" (m/s at game scale), measured from the feet of the
## in-place clips. Used so the feet match the ground at any speed.
const STRIDES := [
	{ "fwd": 1.0, "back": 0.7, "side": 1.3 },  # walk
	{ "fwd": 2.3, "back": 2.1, "side": 2.4 },  # jog
	{ "fwd": 4.1, "back": 3.1, "side": 3.8 },  # run
]
const LAYERS := ["U", "F"]
## Dash pose: frames of the guard stance (braced legs) and the stab (blade thrust forward).
const DASH_STANCE_TIME := 0.3
const DASH_THRUST_TIME := 0.4
## Charge wind-up: combo-slash frames drawing the blade from the front-right to behind the body.
const CHARGE_WINDUP_TIME := Vector2(0.17, 0.40)
## Frame of the great-sword run with the blade over the shoulder (for backward dashes).
const DASH_BACK_TIME := 0.15
## Bones from here up belong to the upper body.
const UPPER_ROOT_BONE := "mixamorig_Spine"
const RIGHT_ARM_ROOT := "mixamorig_RightShoulder"
const LEFT_ARM_ROOT := "mixamorig_LeftShoulder"
## Share of the great-sword carry pose in the torso while moving (rest: natural motion).
const TORSO_CARRY_WEIGHT := 0.4
## The natural torso motion fades in between these ground speeds (m/s).
const STRIDE_SPEED := Vector2(0.4, 1.6)

const LOOPING := ["gs_idle", "gs_walk", "gs_walk_back", "gs_strafe_left", "gs_strafe_right",
	"gs_run", "gs_run_back", "gs_run_left", "gs_run_right", "gs_block_idle", "gs_power_up",
	"legs_walk_fwd", "legs_walk_back", "legs_walk_left", "legs_walk_right",
	"legs_jog_fwd", "legs_jog_back", "legs_jog_left", "legs_jog_right",
	"legs_run_fwd", "legs_run_back", "legs_run_left", "legs_run_right"]

var fighter: Fighter
var model: Node3D
var skeleton: Skeleton3D
var hand: BoneAttachment3D
var _player: AnimationPlayer
var _tree: AnimationTree
## Per action layer: which clip each of the two crossfade slots holds, the active slot,
## and the crossfade position.
var _layers := {
	"F": { "clips": ["", ""], "slot": 0, "ab": 0.0 },
	"U": { "clips": ["", ""], "slot": 0, "ab": 0.0 },
}
var _stride_weight := 0.0
var _upper_blend := 0.0
var _full_blend := 0.0
var _state_time := 0.0
var _last_state := -1
var _blocked_hit_time := 99.0
## Stunned straight out of an attack (parried / interrupted): use the bigger head-snap reaction.
var _parried := false
var _was_attacking := false


## Returns null if the character files aren't there (e.g. a fresh clone without Mixamo assets).
static func try_create(owner_fighter: Fighter, parent: Node3D) -> CharacterAnimator:
	if not ResourceLoader.exists(SCENE_PATH):
		return null
	var a := CharacterAnimator.new()
	a.fighter = owner_fighter
	parent.add_child(a)
	a._build(parent)
	return a


func _build(parent: Node3D) -> void:
	model = load(SCENE_PATH).instantiate()
	model.name = "Character"
	parent.add_child(model)
	model.rotation.y = PI  # Mixamo characters face +Z; fighters face -Z
	set_bulk(Vector3.ONE)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	_player = model.find_children("*", "AnimationPlayer", true, false)[0]
	_player.playback_active = false

	hand = BoneAttachment3D.new()
	hand.name = "RightHand"
	hand.bone_name = HAND_BONE
	skeleton.add_child(hand)

	for clip in LOOPING:
		if _player.has_animation(clip):
			_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_build_tree()
	fighter.got_hit.connect(func(blocked: bool):
		if blocked and fighter.state == Fighter.State.GUARD:
			_blocked_hit_time = 0.0)


## Transform that puts a sword model (origin = grip centre, blade +Y, front edge -Z, meters)
## into the right hand.
static func grip_transform() -> Transform3D:
	var y := BLADE_DIR.normalized()
	var front := (EDGE_DIR - y * EDGE_DIR.dot(y)).normalized()
	var z := -front
	var x := y.cross(z).normalized()
	return Transform3D(Basis(x, y, z).scaled(Vector3.ONE * 100.0), GRIP_POS)


func set_bulk(bulk: Vector3) -> void:
	model.scale = bulk * (TARGET_HEIGHT / SOURCE_HEIGHT)


## Tints the suit (team color) and returns the per-fighter materials for hit flashes.
func tint(color: Color) -> Array[StandardMaterial3D]:
	var mats: Array[StandardMaterial3D] = []
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(i) as StandardMaterial3D
			if src == null:
				continue
			var mat := src.duplicate() as StandardMaterial3D
			mat.albedo_color = src.albedo_color * color
			mat.emission_enabled = true
			mat.emission = Color.BLACK
			m.set_surface_override_material(i, mat)
			mats.append(mat)
	return mats


func _blend_space(points: Dictionary, extent: float) -> AnimationNodeBlendSpace2D:
	var bs := AnimationNodeBlendSpace2D.new()
	bs.min_space = Vector2(-extent, -extent)
	bs.max_space = Vector2(extent, extent)
	bs.sync = true  # keep cycles in step while blending (no double footsteps)
	for clip in points:
		var n := AnimationNodeAnimation.new()
		n.animation = clip
		bs.add_blend_point(n, points[clip], -1, clip)
	return bs


## A Blend2 that only affects the upper body (spine and everything attached to it).
func _upper_body_blend() -> AnimationNodeBlend2:
	return _region_blend(UPPER_ROOT_BONE, [])


## A Blend2 that only affects the bones under `root_bone`, minus the subtrees in `exclude`.
func _region_blend(root_bone: String, exclude: Array) -> AnimationNodeBlend2:
	var b := AnimationNodeBlend2.new()
	b.filter_enabled = true
	var root := skeleton.find_bone(root_bone)
	var excluded := exclude.map(func(n): return skeleton.find_bone(n))
	var prefix := String(model.get_path_to(skeleton)) + ":"
	for i in skeleton.get_bone_count():
		var j := i
		var inside := false
		while j != -1:
			if excluded.has(j):
				break
			if j == root:
				inside = true
				break
			j = skeleton.get_bone_parent(j)
		if inside:
			b.set_filter_path(NodePath(prefix + skeleton.get_bone_name(i)), true)
	return b


func _build_tree() -> void:
	var bt := AnimationNodeBlendTree.new()
	# Locomotion: natural full-body clips, with regions swapped for the great-sword carry pose.
	# (Each great-sword blend space is a separate copy: a node output feeds one input only.)
	bt.add_node("legs", _blend_space(LEG_POINTS, 3.2))
	var prev := "legs"
	for region in [["right_arm", RIGHT_ARM_ROOT, []], ["torso", UPPER_ROOT_BONE, [RIGHT_ARM_ROOT, LEFT_ARM_ROOT]], ["left_arm", LEFT_ARM_ROOT, []]]:
		var arms_node: String = "arms_" + region[0]
		bt.add_node(arms_node, _blend_space(ARM_POINTS, 2.2))
		bt.add_node(region[0], _region_blend(region[1], region[2]))
		bt.connect_node(region[0], 0, prev)
		bt.connect_node(region[0], 1, arms_node)
		prev = region[0]
	bt.add_node("loco_speed", AnimationNodeTimeScale.new())
	bt.connect_node("loco_speed", 0, prev)
	# A node's output can feed only one input, so the upper-body and full-body layers each get
	# their own copy of the two action slots (U = upper, F = full); both are driven identically.
	for layer in LAYERS:
		for s in ["A", "B"]:
			var act := AnimationNodeAnimation.new()
			act.animation = "gs_idle"
			bt.add_node("act" + layer + s, act)
			bt.add_node("seek" + layer + s, AnimationNodeTimeSeek.new())
			bt.add_node("freeze" + layer + s, AnimationNodeTimeScale.new())
			bt.connect_node("seek" + layer + s, 0, "act" + layer + s)
			bt.connect_node("freeze" + layer + s, 0, "seek" + layer + s)
		bt.add_node("ab" + layer, AnimationNodeBlend2.new())
		bt.connect_node("ab" + layer, 0, "freeze" + layer + "A")
		bt.connect_node("ab" + layer, 1, "freeze" + layer + "B")
	bt.add_node("full", AnimationNodeBlend2.new())
	bt.connect_node("full", 0, "loco_speed")
	bt.connect_node("full", 1, "abF")
	bt.add_node("upper", _upper_body_blend())
	bt.connect_node("upper", 0, "full")
	bt.connect_node("upper", 1, "abU")
	bt.connect_node("output", 0, "upper")

	_tree = AnimationTree.new()
	_tree.tree_root = bt
	model.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_player)
	_tree.set("parameters/right_arm/blend_amount", 1.0)
	_tree.set("parameters/left_arm/blend_amount", 1.0)
	for layer in LAYERS:
		_tree.set("parameters/freeze%sA/scale" % layer, 0.0)
		_tree.set("parameters/freeze%sB/scale" % layer, 0.0)
	_tree.active = true


func _process(delta: float) -> void:
	if fighter.state != _last_state:
		_last_state = fighter.state
		_state_time = 0.0
		_parried = fighter.state == Fighter.State.STAGGER and fighter.current_attack == null and _was_attacking
	_was_attacking = fighter.state == Fighter.State.ATTACK
	_state_time += delta
	_blocked_hit_time += delta

	var loco := _locomotion(fighter.velocity)
	_tree.set("parameters/legs/blend_position", loco[0])
	for arms in ["arms_right_arm", "arms_torso", "arms_left_arm"]:
		_tree.set("parameters/%s/blend_position" % arms, loco[1])
	_tree.set("parameters/loco_speed/scale", loco[2])

	# Moving: the torso picks up the natural stride motion and carries arms + sword with it.
	var ground_speed := Vector2(fighter.velocity.x, fighter.velocity.z).length()
	var moving := fighter.is_on_floor() and fighter.state in [Fighter.State.FREE, Fighter.State.GUARD, Fighter.State.CHARGE]
	var want := clampf(inverse_lerp(STRIDE_SPEED.x, STRIDE_SPEED.y, ground_speed), 0.0, 1.0) if moving else 0.0
	_stride_weight = move_toward(_stride_weight, want, delta * 4.0)
	_tree.set("parameters/torso/blend_amount", lerpf(1.0, TORSO_CARRY_WEIGHT, _stride_weight))

	# Actions: { "F": [clip, time] full body, "U": [clip, time] upper body } — either may be absent.
	var action := _action()
	for layer in LAYERS:
		if action.has(layer):
			_show(layer, action[layer][0], action[layer][1])
		var st: Dictionary = _layers[layer]
		st.ab = move_toward(st.ab, float(st.slot), delta * 10.0)
		_tree.set("parameters/ab%s/blend_amount" % layer, st.ab)
	var want_full := 1.0 if action.has("F") else 0.0
	var want_upper := 1.0 if action.has("U") else 0.0
	_full_blend = move_toward(_full_blend, want_full, delta * (14.0 if want_full > _full_blend else 8.0))
	_upper_blend = move_toward(_upper_blend, want_upper, delta * (14.0 if want_upper > _upper_blend else 8.0))
	_tree.set("parameters/full/blend_amount", _full_blend)
	_tree.set("parameters/upper/blend_amount", _upper_blend)



## Leg blend position (radius 1 walk, 2 jog, 3 run), upper-body blend position
## (1 great-sword walk, 2 great-sword run) and playback speed, so the animated stride matches
## the actual ground speed: blend between gaits by speed, then speed up the run beyond it.
func _locomotion(world_velocity: Vector3) -> Array:
	var local := fighter.global_basis.inverse() * world_velocity
	var v := Vector2(local.x, -local.z)  # x = right, y = forward
	var speed := v.length()
	if speed < 0.05:
		return [Vector2.ZERO, Vector2.ZERO, 1.0]
	var dir := v / speed
	var noms := [_stride(STRIDES[0], dir), _stride(STRIDES[1], dir), _stride(STRIDES[2], dir)]
	var radius := 3.0
	var playback := 1.0
	if speed <= noms[0]:
		radius = speed / noms[0]
	elif speed <= noms[1]:
		radius = 1.0 + (speed - noms[0]) / (noms[1] - noms[0])
	elif speed <= noms[2]:
		radius = 2.0 + (speed - noms[1]) / (noms[2] - noms[1])
	else:
		playback = speed / noms[2]
	var arm_radius := radius if radius <= 1.0 else 1.0 + (radius - 1.0) * 0.5
	return [dir * radius, dir * arm_radius, clampf(playback, 0.5, 3.0)]


## Stride speed for a direction, mixing forward/back and sideways clips.
static func _stride(table: Dictionary, dir: Vector2) -> float:
	var fb: float = table["fwd"] if dir.y >= 0.0 else table["back"]
	var w := absf(dir.y) + absf(dir.x)
	return (fb * absf(dir.y) + table["side"] * absf(dir.x)) / maxf(w, 0.001)


## Put `clip` at `time` into a layer's action slot (switching slots when the clip changes,
## so the old clip crossfades out).
func _show(layer: String, clip: String, time: float) -> void:
	var st: Dictionary = _layers[layer]
	var weight := _full_blend if layer == "F" else _upper_blend
	if st.clips[st.slot] != clip:
		st.slot = 1 - st.slot
		st.clips[st.slot] = clip
		var node: AnimationNodeAnimation = _tree.tree_root.get_node("act" + layer + ("A" if st.slot == 0 else "B"))
		node.animation = clip
		if weight < 0.05:
			st.ab = float(st.slot)  # nothing visible yet: no need to crossfade
	_tree.set("parameters/seek%s%s/seek_request" % [layer, "A" if st.slot == 0 else "B"], maxf(time, 0.0))


func _clip_len(clip: String) -> float:
	return _player.get_animation(clip).length if _player.has_animation(clip) else 1.0


func _action() -> Dictionary:
	var f := fighter
	match f.state:
		Fighter.State.ATTACK:
			var frame := _attack_frame(f.current_attack, f.attack_time)
			return {} if frame.is_empty() else { "F": frame }
		Fighter.State.DASH:
			return _dash_pose()
		Fighter.State.CHARGE:
			# Low, planted stance; the blade is drawn back behind the body as the charge builds
			# (fully wound early, then held).
			var wind := smoothstep(0.0, 1.0, minf(f.charge_ratio() * 2.5, 1.0))
			return {
				"F": ["gs_block_idle", DASH_STANCE_TIME],
				"U": ["gs_combo_slash", lerpf(CHARGE_WINDUP_TIME.x, CHARGE_WINDUP_TIME.y, wind)],
			}
		Fighter.State.GUARD:
			if _blocked_hit_time < 0.4:
				return { "U": ["gs_blocked_impact", _blocked_hit_time * 1.4] }
			return { "U": ["gs_block_idle", fmod(_state_time, _clip_len("gs_block_idle"))] }
		Fighter.State.STAGGER:
			var clip := "gs_head_impact" if _parried else "gs_impact"
			return { "F": [clip, minf(_state_time * 1.5, _clip_len(clip) - 0.01)] }
		Fighter.State.DEAD:
			return { "F": ["sword_death", minf(_state_time, _clip_len("sword_death") - 0.01)] }
		Fighter.State.FREE:
			if not f.is_on_floor():
				var t := remap(clampf(f.velocity.y, -8.0, 8.0), 8.0, -8.0, 0.25, 0.7)
				return { "F": ["gs_jump", _clip_len("gs_jump") * t] }
			if f.aiming or f.since_shot < 0.3:
				return { "U": ["spear_stab", 0.4] }  # blade levelled forward like a gun
	return {}


## Thruster dash: not running — the sword's thrust drags you. Low braced stance held still
## (feet slide), and for forward dashes the blade is thrust ahead with the thruster behind.
## The body lean into the dash comes from FighterVisual.
func _dash_pose() -> Dictionary:
	if fighter.is_vertical_dash():
		return { "F": ["gs_jump", _clip_len("gs_jump") * 0.4] }  # tucked, rising
	var pose := { "F": ["gs_block_idle", DASH_STANCE_TIME] }
	var local := fighter.global_basis.inverse() * fighter.dash_dir
	if -local.z > 0.5:
		pose["U"] = ["spear_stab", DASH_THRUST_TIME]  # forward: blade ahead, thruster behind
	elif local.z > 0.5:
		pose["U"] = ["gs_run", DASH_BACK_TIME]  # backward: blade over the shoulder, thruster ahead
	return pose


## Map the attack's windup / active / recovery onto the clip's start -> contact -> end.
func _attack_frame(a: AttackDef, t: float) -> Array:
	if a == null or not ATTACK_CLIPS.has(a.name):
		return []
	var c: Array = ATTACK_CLIPS[a.name]
	var start: float = c[1]
	var c0: float = c[2] - CONTACT_HALF_WIDTH
	var c1: float = c[2] + CONTACT_HALF_WIDTH
	var end: float = c[3]
	var time: float
	if t < a.windup:
		time = lerpf(start, c0, t / a.windup)
	elif t < a.windup + a.active:
		time = lerpf(c0, c1, (t - a.windup) / a.active)
	else:
		time = lerpf(c1, end, clampf((t - a.windup - a.active) / a.recovery, 0.0, 1.0))
	return [c[0], time]
