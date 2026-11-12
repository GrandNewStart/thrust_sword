class_name FighterVisual
extends Node3D
## Look of a Fighter. Reads fighter state; never changes it.
## With the Mixamo character available (assets/mixamo/vanguard.glb), a CharacterAnimator animates
## a real armored suit holding the sword in its right hand. Otherwise: placeholder capsule with
## procedural sword poses. Both: sword model, charge / thrust glow, flame and hit flash.

const POSE_REST := Vector3(-20, 0, -12)
const POSE_GUARD := Vector3(-30, 0, 40)
const POSE_STAGGER := Vector3(15, 0, -45)
const POSE_DEAD := Vector3(60, 0, -70)
## Blade pointing forward like a gun barrel.
const POSE_GUN := Vector3(-88, 4, 0)
## Blade straight up, thruster pointing down.
const POSE_THRUST_UP := Vector3(0, 0, 0)

@onready var fighter: Fighter = get_parent()
@onready var _pivot: Node3D = $SwordPivot
@onready var _holder: Node3D = $SwordPivot/Sword
@onready var _flame: MeshInstance3D = $SwordPivot/Sword/Flame

var _body_mat: StandardMaterial3D
var _pose := POSE_REST
var _char: CharacterAnimator
## Materials that flash when hit (capsule material, or the character's suit materials).
var _flash_mats: Array[StandardMaterial3D] = []
var _thruster_mat: StandardMaterial3D
var _flash := 0.0
var _flash_color := Color.WHITE
var _glow_base_energy := 1.5
## Lean angle (radians) into a thruster dash.
const DASH_LEAN := 0.32
## Charging: shoulders turn away from the target by up to this (radians), like loading a swing.
const CHARGE_TWIST := 0.3
## Attacks whose clip (a spear stab) holds the blade at the wrong angle for our sword:
## the blade is re-aimed level at the target while they play. Firing gets the same treatment.
const LEVELLED_ATTACKS: Array[StringName] = [&"light_3", &"thrust"]
var _grip_rest := Transform3D.IDENTITY
var _blade_aim := 0.0
var _frame_delta := 0.0
var _hand_bone := -1
var _nozzle: Node3D
var _tip: Node3D
var _trail: SwordTrail
var _charge_light: OmniLight3D
var _charge_motes: CPUParticles3D
var _flame_rest := Transform3D.IDENTITY
var _prev_velocity := Vector3.ZERO
var _smoothed_accel := Vector3.ZERO
## Own random stream: cosmetic jitter must not change gameplay / AI rolls.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = fighter.body_color
	_body_mat.metallic = 0.4
	_body_mat.roughness = 0.5
	_body_mat.emission_enabled = true
	_body_mat.emission = Color.BLACK
	$Body.material_override = _body_mat
	_flash_mats = [_body_mat]

	_char = CharacterAnimator.try_create(fighter, self)
	if _char:
		$Body.visible = false
		$Visor.visible = false
		var holder: Node3D = $SwordPivot/Sword
		holder.reparent(_char.hand, false)
		holder.transform = CharacterAnimator.grip_transform()
		_grip_rest = holder.transform
		# Re-aim the blade right after each pose update, so it uses this frame's hand (a frame
		# late, the blade wobbles off level during fast swings).
		_hand_bone = _char.skeleton.find_bone(CharacterAnimator.HAND_BONE)
		_char.skeleton.skeleton_updated.connect(func(): _update_blade_aim(_frame_delta))
		var team_tint := Color.WHITE.lerp(fighter.body_color.lightened(0.35), 0.5)
		_flash_mats = _char.tint(team_tint)
		_set_sword_model(&"lancer")  # until a loadout picks one: never show the placeholder slab in hand

	var thruster: MeshInstance3D = _holder.get_node("Thruster")
	_thruster_mat = thruster.get_surface_override_material(0).duplicate()
	thruster.set_surface_override_material(0, _thruster_mat)

	fighter.got_hit.connect(_on_got_hit)
	fighter.loadout_changed.connect(_apply_loadout_look)
	fighter.combat_event.connect(_on_combat_event)


## Sword model, glow and suit bulk follow the loadout.
func _apply_loadout_look() -> void:
	if fighter.sword:
		_set_sword_model(fighter.sword.id)
	if fighter.armor:
		$Body.scale = fighter.armor.body_scale
		if _char:
			_char.set_bulk(fighter.armor.body_scale)


## Swaps in the sword's 3D model (assets/swords/<id>.glb, built by tools/blender/build_swords.py).
## The placeholder box blade / thruster stay as a fallback if the model is missing.
func _set_sword_model(id: StringName) -> void:
	var holder := _holder
	var old := holder.get_node_or_null("Model")
	if old:
		old.free()
	var path := "res://assets/swords/%s.glb" % id
	if not ResourceLoader.exists(path):
		return
	var model: Node3D = load(path).instantiate()
	model.name = "Model"
	holder.add_child(model)
	holder.get_node("Blade").visible = false
	holder.get_node("Thruster").visible = false

	# One shared, per-fighter copy of the glow material, so charging / thrusting can power it up.
	var glow: StandardMaterial3D = null
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := mi as MeshInstance3D
		for i in mesh_inst.mesh.get_surface_count():
			var mat := mesh_inst.mesh.surface_get_material(i) as StandardMaterial3D
			if mat and mat.emission_enabled:
				if glow == null:
					glow = mat.duplicate()
				mesh_inst.set_surface_override_material(i, glow)
	if glow:
		_thruster_mat = glow
		_glow_base_energy = glow.emission_energy_multiplier

	# Sword trail in the sword's glow color, from mid-blade to the tip.
	_tip = model.find_child("Tip", true, false) as Node3D
	if _trail == null:
		_trail = SwordTrail.new()
		add_child(_trail)
	if glow:
		_trail.color = glow.emission

	# Charging: a light in the sword's colour and energy motes drawn into the blade.
	if _charge_light == null:
		_charge_light = OmniLight3D.new()
		_charge_light.shadow_enabled = false
		_charge_light.omni_range = 4.5
		_charge_light.light_energy = 0.0
		holder.add_child(_charge_light)
		_charge_motes = _make_motes()
		holder.add_child(_charge_motes)
	var mid := holder.to_local(_tip.global_position) * 0.55 if _tip else Vector3(0, 1.2, 0)
	_charge_light.position = mid
	_charge_motes.position = mid
	if glow:
		_charge_light.light_color = glow.emission
		_charge_motes.color = glow.emission

	# Thruster flame comes out of the model's nozzle.
	_nozzle = model.find_child("Nozzle", true, false) as Node3D
	if _nozzle:
		_flame.position = model.transform * _nozzle.position + Vector3(0, -0.5, 0)
	_flame_rest = _flame.transform


func _on_got_hit(blocked: bool) -> void:
	_flash = 1.0
	_flash_color = Color(0.4, 0.7, 1.0) if blocked else Color(1, 1, 1)


func _on_combat_event(text: String, _color: Color) -> void:
	if text == "PARRY!":
		_flash = 1.0
		_flash_color = Color(1.0, 0.85, 0.2)


func _process(delta: float) -> void:
	if _char == null:
		_update_placeholder_pose(delta)
	else:
		_update_lean(delta)
		_frame_delta = delta
	_update_effects(delta)
	_update_trail()
	_update_charge_fx()


func _make_motes() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 28
	p.lifetime = 0.45
	p.local_coords = true  # follow the sword
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	p.emission_sphere_radius = 0.9  # holder space is scaled; this is in sword units
	p.gravity = Vector3.ZERO
	p.radial_accel_min = -9.0
	p.radial_accel_max = -6.0
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.3
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	quad.material = Fx._glow()
	p.mesh = quad
	p.color_ramp = Fx._fade_ramp()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Charge glow light (brightens, then pulses at full charge) + motes while charging.
func _update_charge_fx() -> void:
	if _charge_light == null:
		return
	var charging := fighter.state == Fighter.State.CHARGE
	var r := fighter.charge_ratio() if charging else 0.0
	var pulse := 0.0
	if r >= 1.0:
		pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 14.0)
	_charge_light.light_energy = (0.4 + 3.0 * r + 2.0 * pulse) if charging else 0.0
	if _charge_motes.emitting != charging:
		_charge_motes.emitting = charging


## The sword's accent colour (its glow), for effects.
func accent_color() -> Color:
	return _trail.color if _trail else Color(0.4, 0.9, 1.0)


## Where the blade tip is right now (falls back to in front of the fighter).
func blade_tip_position() -> Vector3:
	if _tip:
		return _tip.global_position
	return fighter.global_position + fighter.forward() * 2.0 + Vector3.UP


## True while the thrust attack's lunge is being driven by the sword's thruster.
func is_thrust_lunge() -> bool:
	var a := fighter.current_attack
	return fighter.state == Fighter.State.ATTACK and a != null and a.name == &"thrust" and fighter.attack_phase() <= 1


## The trail draws while the blade is really moving: late windup through early recovery.
## Big swings (slashes, smash, heavy) get a wider, brighter ribbon.
func _update_trail() -> void:
	if _trail == null or _tip == null:
		return
	var a := fighter.current_attack
	var on := false
	if fighter.state == Fighter.State.ATTACK and a:
		var t := fighter.attack_time
		on = t >= a.windup * 0.5 and t <= a.windup + a.active + a.recovery * 0.35
	_trail.emitting = on
	if on:
		var big := a.name in [&"slash_left", &"slash_right", &"smash", &"heavy"]
		_trail.intensity = 1.0 if big else 0.75
		var tip := _tip.global_position
		var grip := _holder.global_position
		_trail.push(grip.lerp(tip, 0.18 if big else 0.35), tip)


## Rotates the sword in the hands (around the grip) so the blade points level at where you
## poke or shoot; blends in over the windup and back out during recovery.
func _update_blade_aim(delta: float) -> void:
	var want := 0.0
	var aim := fighter.forward()
	var a := fighter.current_attack
	var sweep := ""  # horizontal swing ("left" / "right"): keep the blade's direction, flatten it
	if fighter.state == Fighter.State.ATTACK and a and _char \
			and CharacterAnimator.ATTACK_STYLE.get(a.name, {}).has("level_blade"):
		sweep = CharacterAnimator.ATTACK_STYLE[a.name].level_blade
		var t := fighter.attack_time
		if t < a.windup:
			# Late in the windup only: early on the blade may still be raised near vertical,
			# where flattening it would swing it round to point anywhere.
			want = smoothstep(0.7, 1.0, t / a.windup)
		elif t < a.windup + a.active:
			want = 1.0
		else:
			want = 1.0 - smoothstep(0.0, 1.0, (t - a.windup - a.active) / a.recovery)
		_blade_aim = want
	elif fighter.state == Fighter.State.ATTACK and a and LEVELLED_ATTACKS.has(a.name):
		var t := fighter.attack_time
		if t < a.windup:
			want = ease(t / a.windup, 0.6)
		elif t < a.windup + a.active:
			want = 1.0
		else:
			want = 1.0 - smoothstep(0.0, 1.0, (t - a.windup - a.active) / a.recovery)
		_blade_aim = want  # follows the attack's own timing exactly
		aim = (aim + Vector3.DOWN * 0.08).normalized()
	elif fighter.state == Fighter.State.DASH and _char:
		# Blade along the dash, so the bottom-end thruster fires the other way.
		aim = _char.dash_blade_aim()
		_blade_aim = move_toward(_blade_aim, 1.0, delta * 14.0)
	else:
		if fighter.state == Fighter.State.FREE and (fighter.aiming or fighter.since_shot < 0.3):
			want = 1.0
			var to_target := fighter.aim_point - _holder.global_position
			if to_target.length() > 1.0:
				aim = to_target.normalized()
		_blade_aim = move_toward(_blade_aim, want, delta * 8.0)
	if _blade_aim <= 0.001:
		_holder.transform = _grip_rest
		return
	var sk := _char.skeleton
	var hand_basis := (sk.global_basis * sk.get_bone_global_pose(_hand_bone).basis).orthonormalized()
	var target: Basis
	if sweep != "":
		# Blade (+Y) where the clip points it, but level; front edge (-Z) leads the swing
		# (UP x blade points to the left of the blade, i.e. along a right -> left sweep).
		var natural := hand_basis * _grip_rest.basis.orthonormalized()
		var y := Vector3(natural.y.x, 0.0, natural.y.z).normalized()
		var lead := Vector3.UP.cross(y).normalized() * (1.0 if sweep == "left" else -1.0)
		var z := -lead
		target = Basis(y.cross(z).normalized(), y, z)
	else:
		# Blade (+Y) along the aim, front edge (-Z) facing down (forward, if aimed straight up).
		var y := aim
		var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else -fighter.forward()
		var z := (ref - y * y.dot(ref)).normalized()
		target = Basis(y.cross(z).normalized(), y, z)
	var local_target := Quaternion(hand_basis.inverse() * target)
	var rest_rot := _grip_rest.basis.get_rotation_quaternion()
	var rot := rest_rot.slerp(local_target.normalized(), _blade_aim)
	_holder.transform = Transform3D(Basis(rot).scaled(_grip_rest.basis.get_scale()), _grip_rest.origin)


## Lean into acceleration: forward when speeding up, back when braking, into the turn when
## cornering. Small angles, smoothed — enough to read the body's weight shifting.
func _update_lean(delta: float) -> void:
	var v := Vector3(fighter.velocity.x, 0.0, fighter.velocity.z)
	var a := (v - _prev_velocity) / maxf(delta, 0.001)
	_prev_velocity = v
	_smoothed_accel = _smoothed_accel.lerp(a, 1.0 - exp(-8.0 * delta))
	var pitch := 0.0
	var roll := 0.0
	if fighter.state == Fighter.State.DASH:
		# Dragged by the thrust: lean hard into the dash direction.
		var d := fighter.global_basis.inverse() * fighter.dash_dir
		pitch = d.z * DASH_LEAN
		roll = -d.x * DASH_LEAN
	elif fighter.is_on_floor() and fighter.state in [Fighter.State.FREE, Fighter.State.GUARD, Fighter.State.CHARGE]:
		var local := fighter.global_basis.inverse() * _smoothed_accel
		pitch = clampf(local.z * 0.010, -0.14, 0.14)  # accelerating forward (-Z) tips the top forward
		roll = clampf(-local.x * 0.010, -0.12, 0.12)
	var twist := 0.0
	if fighter.state == Fighter.State.CHARGE:
		var r := fighter.charge_ratio()
		twist = -CHARGE_TWIST * smoothstep(0.0, 1.0, minf(r * 2.0, 1.0))  # right shoulder back
		pitch += 0.05 * r  # settle back onto the rear leg
		if r >= 1.0:  # fully charged: straining
			twist += _rng.randf_range(-0.012, 0.012)
	var k := 1.0 - exp(-(22.0 if fighter.state == Fighter.State.DASH else 10.0) * delta)
	rotation.y = lerpf(rotation.y, twist, 1.0 - exp(-(30.0 if fighter.state == Fighter.State.ATTACK else 8.0) * delta))
	rotation.x = lerpf(rotation.x, pitch, k)
	rotation.z = lerpf(rotation.z, roll, k)


## Capsule mode: sword swings on a shoulder pivot, body leans when stunned / falls at K.O.
func _update_placeholder_pose(delta: float) -> void:
	var target := POSE_REST
	var snap := false
	var lean := 0.0

	match fighter.state:
		Fighter.State.FREE:
			if fighter.since_shot < 0.3:
				target = POSE_GUN
				snap = fighter.since_shot < 0.05
		Fighter.State.DASH:
			target = POSE_THRUST_UP if fighter.is_vertical_dash() else _dash_pose()
			snap = fighter.dash_time < 0.03
		Fighter.State.GUARD:
			target = POSE_GUARD
		Fighter.State.CHARGE:
			var r := fighter.charge_ratio()
			target = fighter.moveset[&"heavy"].pose_start
			target += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0) * 3.0 * r
			snap = r > 0.2
		Fighter.State.ATTACK:
			target = _attack_pose(fighter.current_attack, fighter.attack_time)
			snap = true
		Fighter.State.STAGGER:
			target = POSE_STAGGER
			lean = 12.0
		Fighter.State.DEAD:
			target = POSE_DEAD
			lean = 85.0

	if snap:
		_pose = target
	else:
		_pose = _pose.lerp(target, 1.0 - exp(-18.0 * delta))
	_pivot.rotation_degrees = _pose
	rotation_degrees.x = lerpf(rotation_degrees.x, lean, 1.0 - exp(-10.0 * delta))


func _update_effects(delta: float) -> void:
	# Thruster glows while charging; flame while dashing / thrusting up.
	var charge := fighter.charge_ratio() if fighter.state == Fighter.State.CHARGE else 0.0
	var thrusting := fighter.is_thrusting() or is_thrust_lunge()
	_thruster_mat.emission_energy_multiplier = _glow_base_energy * (1.0 + 5.0 * charge + (3.0 if thrusting else 0.0))
	_flame.visible = thrusting
	if thrusting:
		_aim_flame()
		_flame.scale = Vector3.ONE * _rng.randf_range(0.85, 1.15)



	# Hit flash.
	_flash = maxf(0.0, _flash - delta * 6.0)
	for m in _flash_mats:
		m.emission = _flash_color * _flash
		m.emission_energy_multiplier = 2.0


## Blade points along the dash so the thruster at the grip fires backwards.
func _dash_pose() -> Vector3:
	var local := fighter.global_basis.inverse() * fighter.dash_dir
	var yaw := rad_to_deg(atan2(-local.x, -local.z))
	return Vector3(-100, yaw, 0)


func _attack_pose(a: AttackDef, t: float) -> Vector3:
	if a == null:
		return POSE_REST
	if t < a.windup:
		return POSE_REST.lerp(a.pose_start, ease(t / a.windup, 0.5))
	t -= a.windup
	if t < a.active:
		return a.pose_start.lerp(a.pose_end, t / a.active)
	t -= a.active
	return a.pose_end.lerp(POSE_REST, smoothstep(0.0, 1.0, t / a.recovery))


## The flame starts at the nozzle and always points away from where the thrust pushes you
## (behind a dash, straight down when flying up), whatever angle the sword is at.
func _aim_flame() -> void:
	if _nozzle == null or _char == null:
		_flame.transform = _flame_rest
		return
	# Straight out of the sword's bottom end: along the sword, away from the blade.
	var y := _holder.global_basis.y.normalized()  # flame mesh: wide end at +Y (nozzle), tip along -Y
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var basis := Basis(x, y, x.cross(y).normalized())
	var scale := _flame.global_basis.get_scale()
	_flame.global_basis = basis.scaled(scale)
	_flame.global_position = _nozzle.global_position - y * 0.5 * scale.y
