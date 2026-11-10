class_name FighterCamera
extends Node3D
## Third-person camera fixed behind the fighter.
## Free mode: player drags to rotate (the fighter turns with it).
## Lock-on mode: keeps both the fighter and the target in view.
## Aim mode (gun): pulls in tight over the right shoulder with a narrower FOV; lock-on is
## suspended (and restored afterwards) and the crosshair is the screen centre.

@export var pivot_height := 2.0
@export var look_sensitivity := 0.006  # radians per pixel
@export var min_pitch_deg := -55.0
@export var max_pitch_deg := 30.0
@export var default_pitch_deg := -14.0
@export var lock_sharpness := 10.0
@export var lock_pitch_bias_deg := -8.0
## Lock-on never tilts down more than this, so the horizon stays in view up close.
@export var lock_min_pitch_deg := -20.0
@export var max_lock_distance := 60.0
@export_group("Aim mode")
@export var aim_spring_length := 1.7
@export var aim_shoulder_offset := 0.6
@export var aim_pivot_height := 1.65
@export var aim_fov_mult := 0.72
## Finer mouse / stick response while aiming.
@export var aim_sensitivity_mult := 0.55
@export var aim_transition_speed := 7.0

var follow: Node3D
var lock_target: Node3D = null
var yaw := 0.0
var pitch := 0.0
var aiming := false
var _aim_blend := 0.0
var _saved_lock: Node3D
## Camera shake: trauma 0..1 decays over time; the shake is trauma² (small hits stay subtle).
var trauma := 0.0
@export var trauma_decay := 1.8
@export var max_shake_angle := 0.045
@export var max_shake_offset := 0.12
var _fov_kick := 0.0
var _roll_kick := 0.0
## Continuous shake / FOV offset requested every frame (e.g. while charging); 0 = none.
var _held_shake := 0.0
var _held_shake_target := 0.0
var _fov_hold := 0.0
var _fov_hold_target := 0.0
var _shake_time := 0.0
## Normal (non-aim) view settings, captured after configure_for().
var _base := {}

@onready var _pitch_node: Node3D = $Pitch
@onready var _arm: SpringArm3D = $Pitch/SpringArm3D
@onready var camera: Camera3D = $Pitch/SpringArm3D/Camera3D


func _ready() -> void:
	pitch = deg_to_rad(default_pitch_deg)
	# Run after fighters have moved this tick.
	process_physics_priority = 10
	_capture_base()


func setup(fighter: Node3D) -> void:
	follow = fighter
	yaw = fighter.rotation.y
	if fighter is CollisionObject3D:
		_arm.add_excluded_object(fighter.get_rid())
	_snap()


## Portrait phones need a tall, wide-angle view with the fighter above the thumbs;
## a landscape desktop window wants a normal FOV with the fighter nearer the middle.
func configure_for(touch: bool) -> void:
	if touch:
		return  # scene defaults are tuned for portrait touch
	camera.fov = 62.0
	camera.v_offset = 0.0
	pivot_height = 1.8
	_arm.spring_length = 4.6
	_arm.position.x = 0.75
	default_pitch_deg = -10.0
	pitch = deg_to_rad(default_pitch_deg)
	_capture_base()


func _capture_base() -> void:
	_base = { "fov": camera.fov, "v_offset": camera.v_offset, "pivot": pivot_height,
		"spring": _arm.spring_length, "shoulder": _arm.position.x }


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


## Tilt the camera briefly (radians, + = roll left), e.g. following a sword swing.
func kick_roll(radians: float) -> void:
	_roll_kick = radians


## Keep a steady vibration (0..1 shake intensity) for as long as it's requested each frame.
func hold_shake(intensity: float) -> void:
	_held_shake_target = intensity


## Keep the view widened (+) or narrowed (-) by this many degrees while requested each frame.
func hold_fov(degrees: float) -> void:
	_fov_hold_target = degrees


## Briefly widen the view (speed burst), in degrees.
func kick_fov(degrees: float) -> void:
	_fov_kick = maxf(_fov_kick, degrees)


func _process(delta: float) -> void:
	trauma = maxf(0.0, trauma - trauma_decay * delta)
	_fov_kick = move_toward(_fov_kick, 0.0, delta * 28.0)
	_roll_kick = lerpf(_roll_kick, 0.0, 1.0 - exp(-9.0 * delta))
	_shake_time += delta
	_held_shake = lerpf(_held_shake, _held_shake_target, 1.0 - exp(-12.0 * delta))
	_fov_hold = lerpf(_fov_hold, _fov_hold_target, 1.0 - exp(-6.0 * delta))
	var s := maxf(trauma * trauma, _held_shake)
	camera.rotation = Vector3(_noise(1.0) * max_shake_angle * s, _noise(2.0) * max_shake_angle * s, _noise(3.0) * max_shake_angle * 1.3 * s + _roll_kick)
	camera.h_offset = _noise(4.0) * max_shake_offset * s


## Smooth pseudo-random in -1..1 (sum of sines; one stream per `seed`).
func _noise(seed: float) -> float:
	var t := _shake_time
	return sin(t * 47.0 + seed * 11.3) * 0.5 + sin(t * 29.0 + seed * 5.7) * 0.3 + sin(t * 71.0 + seed * 2.1) * 0.2


func set_aiming(value: bool) -> void:
	if aiming == value:
		return
	aiming = value
	if value:
		_saved_lock = lock_target
		lock_target = null
	else:
		if is_instance_valid(_saved_lock) and not (_saved_lock is Fighter and not (_saved_lock as Fighter).is_alive()):
			lock_target = _saved_lock
		_saved_lock = null


## World-space ray through the crosshair (screen centre): [origin, direction].
func crosshair_ray() -> Array:
	var center := camera.get_viewport().get_visible_rect().size * 0.5
	return [camera.project_ray_origin(center), camera.project_ray_normal(center)]


func is_locked() -> bool:
	return is_instance_valid(lock_target)


func set_lock_target(target: Node3D) -> void:
	lock_target = target


func apply_look(delta_px: Vector2) -> void:
	if is_locked() or delta_px == Vector2.ZERO:
		return
	var sens := look_sensitivity * (aim_sensitivity_mult if aiming else 1.0)
	yaw -= delta_px.x * sens
	pitch = clampf(pitch - delta_px.y * sens, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))


func _physics_process(delta: float) -> void:
	if follow == null:
		return
	_aim_blend = move_toward(_aim_blend, 1.0 if aiming else 0.0, delta * aim_transition_speed)
	if not _base.is_empty():
		var k := smoothstep(0.0, 1.0, _aim_blend)
		camera.fov = lerpf(_base.fov, _base.fov * aim_fov_mult, k) + _fov_kick + _fov_hold
		camera.v_offset = lerpf(_base.v_offset, 0.0, k)
		_arm.spring_length = lerpf(_base.spring, aim_spring_length, k)
		_arm.position.x = lerpf(_base.shoulder, aim_shoulder_offset, k)
		pivot_height = lerpf(_base.pivot, aim_pivot_height, k)
	global_position = follow.global_position + Vector3.UP * pivot_height

	if is_locked():
		var to_target := lock_target.global_position + Vector3.UP * 1.0 - global_position
		var flat := Vector2(to_target.x, to_target.z).length()
		if flat > max_lock_distance:
			lock_target = null
		elif flat > 0.5:
			var t := 1.0 - exp(-lock_sharpness * delta)
			yaw = lerp_angle(yaw, yaw_towards(to_target), t)
			var target_pitch := atan2(to_target.y, flat) + deg_to_rad(lock_pitch_bias_deg)
			target_pitch = clampf(target_pitch, deg_to_rad(lock_min_pitch_deg), deg_to_rad(max_pitch_deg))
			pitch = lerpf(pitch, target_pitch, t)

	_apply_rotation()


func _snap() -> void:
	global_position = follow.global_position + Vector3.UP * pivot_height
	_apply_rotation()


func _apply_rotation() -> void:
	rotation = Vector3(0.0, yaw, 0.0)
	_pitch_node.rotation = Vector3(pitch, 0.0, 0.0)


## Yaw that faces along a direction (Godot forward is -Z).
static func yaw_towards(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


## Camera-relative forward and right on the ground plane.
func flat_forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func flat_right() -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))
