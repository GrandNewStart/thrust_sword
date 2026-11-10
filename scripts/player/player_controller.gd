class_name PlayerController
extends Node
## Glue between the active input scheme (touch or keyboard + mouse) and the player's
## fighter and camera. Both schemes produce a PlayerIntent; everything after that is shared.

@export var fighter: Fighter
@export var camera_rig: FighterCamera
@export var controls: TouchControls
@export var desktop: DesktopControls
## Extra screen-space slack (pixels) when tapping on an opponent.
@export var lock_tap_slack := 70.0

var touch_mode := true


func _ready() -> void:
	# Give orders before the fighters tick, so input isn't a frame late.
	process_physics_priority = -10
	touch_mode = InputMode.is_touch()
	camera_rig.setup(fighter)
	camera_rig.configure_for(touch_mode)
	controls.enabled = touch_mode
	if desktop:
		desktop.enabled = not touch_mode
		desktop.set_process(not touch_mode)
		desktop.set_process_input(not touch_mode)


## Menus / results screens turn player input off and back on.
func set_input_enabled(value: bool) -> void:
	if touch_mode:
		controls.enabled = value
	elif desktop:
		desktop.enabled = value


func active_intent() -> PlayerIntent:
	return controls.intent if touch_mode or desktop == null else desktop.intent


func _physics_process(_delta: float) -> void:
	var intent := active_intent()

	camera_rig.apply_look(intent.look_delta)
	for tap in intent.taps:
		_handle_tap(tap.pos, tap.count)
	if intent.lock_toggle:
		camera_rig.set_lock_target(null if camera_rig.is_locked() else _opponent_in_view())
	if intent.jump_pressed:
		fighter.request_jump()
	if intent.fire_pressed:
		fighter.request_fire()
	for attack in intent.attacks:
		fighter.request_attack(attack)
	for d in intent.dashes:
		var world := camera_rig.flat_right() * d.x + camera_rig.flat_forward() * d.y
		fighter.request_dash(Vector2(world.x, world.z))
	intent.clear_one_shots()

	fighter.thrust_input = intent.jump_held
	fighter.fire_input = intent.fire_held
	fighter.aim_point = _aim_point()
	fighter.guard_input = intent.guard_held
	fighter.charge_input = intent.charge_held

	var dir := camera_rig.flat_right() * intent.move.x + camera_rig.flat_forward() * intent.move.y
	fighter.move_input = Vector2(dir.x, dir.z)
	fighter.wants_run = intent.run

	if camera_rig.is_locked():
		var to_target := camera_rig.lock_target.global_position - fighter.global_position
		fighter.desired_yaw = FighterCamera.yaw_towards(to_target)
	else:
		fighter.desired_yaw = camera_rig.yaw


## Locked on: the target's chest. Otherwise: straight ahead of the camera.
func _aim_point() -> Vector3:
	if camera_rig.is_locked():
		return camera_rig.lock_target.global_position + Vector3.UP * 1.0
	var cam := camera_rig.camera
	return cam.global_position - cam.global_basis.z * 60.0


func _handle_tap(screen_pos: Vector2, count: int) -> void:
	var target := pick_lock_target(screen_pos)
	if target:
		camera_rig.set_lock_target(target)
	elif count >= 2:
		camera_rig.set_lock_target(null)


## Returns the opponent under (or near) a screen position, or null.
func pick_lock_target(screen_pos: Vector2) -> Node3D:
	var cam := camera_rig.camera
	var best: Node3D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("lockable"):
		if node == fighter or not node is Node3D:
			continue
		var feet: Vector3 = node.global_position
		var head: Vector3 = feet + Vector3.UP * 1.9
		if cam.is_position_behind(feet) or cam.is_position_behind(head):
			continue
		var feet_s := cam.unproject_position(feet)
		var head_s := cam.unproject_position(head)
		var center := (feet_s + head_s) * 0.5
		var radius := feet_s.distance_to(head_s) * 0.5 + lock_tap_slack
		var d := center.distance_to(screen_pos)
		if d <= radius and d < best_dist:
			best = node
			best_dist = d
	return best


## Desktop lock-on: the opponent closest to the screen centre (in front of the camera),
## falling back to the nearest one.
func _opponent_in_view() -> Node3D:
	var cam := camera_rig.camera
	var center := cam.get_viewport().get_visible_rect().size * 0.5
	var best: Node3D = null
	var best_score := INF
	for node in get_tree().get_nodes_in_group("lockable"):
		if node == fighter or not node is Node3D:
			continue
		var p: Vector3 = node.global_position + Vector3.UP
		var score := fighter.global_position.distance_to(p) * 100.0  # fallback: nearest
		if not cam.is_position_behind(p):
			score = cam.unproject_position(p).distance_to(center)
		if score < best_score:
			best = node
			best_score = score
	return best
