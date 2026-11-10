extends "res://tests/test_base.gd"
## Movement feel: inertia, braking, turning arcs, dash easing, and armor weight differences.
## Run: godot --headless --path . -s tests/test_movement.gd


func _run() -> void:
	await frames(20)
	var light := ArmorDef.by_id(&"light")
	var medium := ArmorDef.by_id(&"medium")
	var heavy := ArmorDef.by_id(&"heavy")

	# --- Time to reach run speed, per armor ---
	var t_light := await _time_to_run(light)
	var t_medium := await _time_to_run(medium)
	var t_heavy := await _time_to_run(heavy)
	print("    0 -> run speed: light %.2fs, medium %.2fs, heavy %.2fs" % [t_light, t_medium, t_heavy])
	check(t_light < t_medium and t_medium < t_heavy, "heavier armor takes longer to get up to speed")
	check(t_medium > 0.35, "noticeable acceleration, not instant (medium %.2fs)" % t_medium)

	# --- Stopping distance from a run ---
	var d_light := await _stopping_distance(light)
	var d_heavy := await _stopping_distance(heavy)
	print("    stopping distance from run: light %.2fm, heavy %.2fm" % [d_light, d_heavy])
	check(d_light > 0.5 and d_heavy > 0.5, "momentum carries after letting go")
	check(d_heavy > d_light, "heavy suit is harder to stop, even from its lower top speed")

	# --- Reversal skids before going the other way ---
	await _setup(medium)
	_run_dir(Vector2(0, -1))
	await frames(60)
	_run_dir(Vector2(0, 1))
	var t := 0.0
	while player.velocity.z < 0.0 and t < 2.0:
		await frames(1)
		t += 1.0 / 60.0
	check(t > 0.2, "reversing direction skids first (%.2fs still sliding)" % t)

	# --- 90° turn carves an arc instead of snapping ---
	await _setup(medium)
	_run_dir(Vector2(0, -1))
	await frames(60)
	var x0 := player.global_position.x
	var z0 := player.global_position.z
	_run_dir(Vector2(1, 0))
	await frames(12)
	var drift := z0 - player.global_position.z
	check(drift > 0.3, "sharp turn keeps forward momentum for a moment (%.2fm drift)" % drift)
	check(player.global_position.x > x0, "and starts moving the new way")

	# --- Dash eases out instead of stopping dead ---
	await _setup(medium)
	player.request_dash(Vector2(0, -1))
	await frames(int(player.thruster.dash_duration * 60.0) + 2)
	var exit_speed := player.horizontal_speed()
	check(exit_speed <= player.run_speed * player.dash_exit_speed_mult + 0.1 and exit_speed > player.run_speed,
		"dash exits fast but capped (%.1f m/s)" % exit_speed)
	await frames(20)
	check(player.horizontal_speed() > 0.5, "and keeps sliding briefly")

	# --- Heavy armor is shoved less ---
	await _setup(heavy, true)
	opponent.request_attack(&"thrust")
	await frames(40)
	var push_heavy := player.global_position.distance_to(Vector3(0, 0, 22))
	await _setup(light, true)
	opponent.request_attack(&"thrust")
	await frames(40)
	var push_light := player.global_position.distance_to(Vector3(0, 0, 22))
	check(push_heavy < push_light, "heavy armor is knocked back less (%.2fm vs %.2fm)" % [push_heavy, push_light])

	finish()


## Opponent stands 2 m ahead only when `near` (knockback); otherwise well out of the way.
func _setup(armor: ArmorDef, near := false) -> void:
	brain.mode = DummyBrain.Mode.IDLE
	brain.set_physics_process(false)
	main.get_node("PlayerController").set_physics_process(false)  # drive the fighter directly
	player.apply_loadout(SwordDef.lancer(), armor)
	opponent.apply_loadout(SwordDef.lancer(), ArmorDef.by_id(&"medium"))
	player.reset_to(Vector3(0, 0, 22), 0.0)
	opponent.reset_to(Vector3(0, 0, 20) if near else Vector3(30, 0, 40), PI)
	_run_dir(Vector2.ZERO)
	await frames(10)


func _run_dir(world_dir: Vector2) -> void:
	player.move_input = world_dir
	player.wants_run = world_dir != Vector2.ZERO
	player.desired_yaw = 0.0


func _time_to_run(armor: ArmorDef) -> float:
	await _setup(armor)
	_run_dir(Vector2(0, -1))
	var t := 0.0
	while player.horizontal_speed() < armor.run_speed * 0.97 and t < 3.0:
		await frames(1)
		t += 1.0 / 60.0
	return t


func _stopping_distance(armor: ArmorDef) -> float:
	await _setup(armor)
	_run_dir(Vector2(0, -1))
	await frames(120)
	var start := player.global_position
	_run_dir(Vector2.ZERO)
	await frames(90)
	return start.distance_to(player.global_position)
