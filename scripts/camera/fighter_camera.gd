class_name FighterCamera
extends Node3D
## Third-person camera fixed behind the fighter.
## Free mode: player drags to rotate (the fighter turns with it).
## Lock-on mode: keeps both the fighter and the target in view.

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

var follow: Node3D
var lock_target: Node3D = null
var yaw := 0.0
var pitch := 0.0

@onready var _pitch_node: Node3D = $Pitch
@onready var _arm: SpringArm3D = $Pitch/SpringArm3D
@onready var camera: Camera3D = $Pitch/SpringArm3D/Camera3D


func _ready() -> void:
	pitch = deg_to_rad(default_pitch_deg)
	# Run after fighters have moved this tick.
	process_physics_priority = 10


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


func is_locked() -> bool:
	return is_instance_valid(lock_target)


func set_lock_target(target: Node3D) -> void:
	lock_target = target


func apply_look(delta_px: Vector2) -> void:
	if is_locked() or delta_px == Vector2.ZERO:
		return
	yaw -= delta_px.x * look_sensitivity
	pitch = clampf(pitch - delta_px.y * look_sensitivity, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))


func _physics_process(delta: float) -> void:
	if follow == null:
		return
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
