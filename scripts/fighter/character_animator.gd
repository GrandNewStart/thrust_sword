class_name CharacterAnimator
extends Node
## Drives the Mixamo character's animations from the Fighter's state.
##
## Gameplay timing stays in charge: attack clips are not "played", they are scrubbed so the
## clip's swing lines up with the attack's windup / active / recovery phases (and they freeze
## during hitstop). Locomotion is a 2D blend space driven by the fighter's local velocity.
##
## Tree:  loco (BlendSpace2D) -> loco_speed ─┐
##        actA -> seekA -> freezeA ─┐         ├─ blend -> output
##        actB -> seekB -> freezeB ─┴─ ab ────┘
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
	&"light": ["gs_low_slash", 0.35, 0.80, 1.40],
	&"slash_left": ["gs_power_slash", 0.30, 0.77, 1.50],
	&"slash_right": ["gs_combo_slash", 0.25, 0.73, 1.20],
	&"thrust": ["spear_stab", 0.00, 0.40, 1.00],
	&"smash": ["gs_downward_slash", 0.10, 0.57, 1.27],
	&"heavy": ["gs_high_spin", 0.45, 1.10, 1.87],
}
const CONTACT_HALF_WIDTH := 0.12

const LOCO_POINTS := {
	"gs_idle": Vector2(0, 0),
	"gs_walk": Vector2(0, 1), "gs_walk_back": Vector2(0, -1),
	"gs_strafe_left": Vector2(-1, 0), "gs_strafe_right": Vector2(1, 0),
	"gs_run": Vector2(0, 2), "gs_run_back": Vector2(0, -2),
	"gs_run_left": Vector2(-2, 0), "gs_run_right": Vector2(2, 0),
}
const LOOPING := ["gs_idle", "gs_walk", "gs_walk_back", "gs_strafe_left", "gs_strafe_right",
	"gs_run", "gs_run_back", "gs_run_left", "gs_run_right", "gs_block_idle", "gs_power_up"]

var fighter: Fighter
var model: Node3D
var skeleton: Skeleton3D
var hand: BoneAttachment3D
var _player: AnimationPlayer
var _tree: AnimationTree
var _slot_clips := ["", ""]
var _slot := 0
var _ab := 0.0
var _blend := 0.0
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


func _build_tree() -> void:
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace2D.new()
	loco.min_space = Vector2(-2.2, -2.2)
	loco.max_space = Vector2(2.2, 2.2)
	for clip in LOCO_POINTS:
		var n := AnimationNodeAnimation.new()
		n.animation = clip
		loco.add_blend_point(n, LOCO_POINTS[clip], -1, clip)
	bt.add_node("loco", loco)
	bt.add_node("loco_speed", AnimationNodeTimeScale.new())
	bt.connect_node("loco_speed", 0, "loco")
	for s in ["A", "B"]:
		var act := AnimationNodeAnimation.new()
		act.animation = "gs_idle"
		bt.add_node("act" + s, act)
		bt.add_node("seek" + s, AnimationNodeTimeSeek.new())
		bt.add_node("freeze" + s, AnimationNodeTimeScale.new())
		bt.connect_node("seek" + s, 0, "act" + s)
		bt.connect_node("freeze" + s, 0, "seek" + s)
	bt.add_node("ab", AnimationNodeBlend2.new())
	bt.connect_node("ab", 0, "freezeA")
	bt.connect_node("ab", 1, "freezeB")
	bt.add_node("blend", AnimationNodeBlend2.new())
	bt.connect_node("blend", 0, "loco_speed")
	bt.connect_node("blend", 1, "ab")
	bt.connect_node("output", 0, "blend")

	_tree = AnimationTree.new()
	_tree.tree_root = bt
	model.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_player)
	_tree.set("parameters/freezeA/scale", 0.0)
	_tree.set("parameters/freezeB/scale", 0.0)
	_tree.active = true


func _process(delta: float) -> void:
	if fighter.state != _last_state:
		_last_state = fighter.state
		_state_time = 0.0
		_parried = fighter.state == Fighter.State.STAGGER and fighter.current_attack == null and _was_attacking
	_was_attacking = fighter.state == Fighter.State.ATTACK
	_state_time += delta
	_blocked_hit_time += delta

	# Locomotion from local velocity (1 = walk speed, 2 = run speed).
	var local := fighter.global_basis.inverse() * fighter.velocity
	var flat := Vector2(local.x, -local.z) / maxf(fighter.walk_speed, 0.1)
	if flat.length() > 1.0:
		var run_ratio := fighter.run_speed / fighter.walk_speed
		flat = flat.normalized() * remap(minf(flat.length(), run_ratio), 1.0, run_ratio, 1.0, 2.0)
	_tree.set("parameters/loco/blend_position", flat.limit_length(2.0))
	_tree.set("parameters/loco_speed/scale", 1.6 if fighter.state == Fighter.State.DASH else 1.0)

	var action := _action()  # [clip, time] or []
	if action.is_empty():
		_blend = move_toward(_blend, 0.0, delta * 8.0)
	else:
		_blend = move_toward(_blend, 1.0, delta * 14.0)
		_show(action[0], action[1])
	_ab = move_toward(_ab, float(_slot), delta * 10.0)
	_tree.set("parameters/ab/blend_amount", _ab)
	_tree.set("parameters/blend/blend_amount", _blend)



## Put `clip` at `time` into an action slot (switching slots when the clip changes).
func _show(clip: String, time: float) -> void:
	if _slot_clips[_slot] != clip:
		_slot = 1 - _slot
		_slot_clips[_slot] = clip
		var node: AnimationNodeAnimation = _tree.tree_root.get_node("act" + ("A" if _slot == 0 else "B"))
		node.animation = clip
		if _blend < 0.05:
			_ab = float(_slot)  # nothing visible yet: no need to crossfade
	_tree.set("parameters/seek%s/seek_request" % ("A" if _slot == 0 else "B"), maxf(time, 0.0))


func _clip_len(clip: String) -> float:
	return _player.get_animation(clip).length if _player.has_animation(clip) else 1.0


func _action() -> Array:
	var f := fighter
	match f.state:
		Fighter.State.ATTACK:
			return _attack_frame(f.current_attack, f.attack_time)
		Fighter.State.CHARGE:
			# Powering-up loop, wound up more as the charge fills.
			return ["gs_power_up", lerpf(0.2, 1.4, f.charge_ratio()) + fmod(_state_time, 0.4) * 0.1]
		Fighter.State.GUARD:
			if _blocked_hit_time < 0.4:
				return ["gs_blocked_impact", _blocked_hit_time * 1.4]
			return ["gs_block_idle", fmod(_state_time, _clip_len("gs_block_idle"))]
		Fighter.State.STAGGER:
			var clip := "gs_head_impact" if _parried else "gs_impact"
			return [clip, minf(_state_time * 1.5, _clip_len(clip) - 0.01)]
		Fighter.State.DEAD:
			return ["sword_death", minf(_state_time, _clip_len("sword_death") - 0.01)]
		Fighter.State.FREE:
			if f.thrusting_up:
				return ["gs_jump", _clip_len("gs_jump") * 0.4]
			if not f.is_on_floor():
				var t := remap(clampf(f.velocity.y, -8.0, 8.0), 8.0, -8.0, 0.25, 0.7)
				return ["gs_jump", _clip_len("gs_jump") * t]
			if f.since_shot < 0.3:
				return ["spear_stab", 0.4]  # blade levelled forward like a gun
	return []


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
