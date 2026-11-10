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

	# Thruster flame comes out of the model's nozzle.
	var nozzle := model.find_child("Nozzle", true, false) as Node3D
	if nozzle:
		_flame.position = model.transform * nozzle.position + Vector3(0, -0.5, 0)


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
	_update_effects(delta)


## Capsule mode: sword swings on a shoulder pivot, body leans when stunned / falls at K.O.
func _update_placeholder_pose(delta: float) -> void:
	var target := POSE_REST
	var snap := false
	var lean := 0.0

	match fighter.state:
		Fighter.State.FREE:
			if fighter.thrusting_up:
				target = POSE_THRUST_UP
			elif fighter.since_shot < 0.3:
				target = POSE_GUN
				snap = fighter.since_shot < 0.05
		Fighter.State.DASH:
			target = _dash_pose()
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
	var thrusting := fighter.is_thrusting()
	_thruster_mat.emission_energy_multiplier = _glow_base_energy * (1.0 + 5.0 * charge + (3.0 if thrusting else 0.0))
	_flame.visible = thrusting
	if thrusting:
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
