extends "res://tests/test_base.gd"
## Controls check: movement, camera, lock-on, attacks, guard, jump, dash, aim and pause
## through keyboard + mouse.
## Run: godot --headless --path . -s tests/test_desktop.gd




func _run() -> void:
	await frames(20)
	check(desktop.enabled, "keyboard + mouse active")

	# --- WASD + Shift ---
	await _face_off(10.0)
	var z0 := player.global_position.z
	key(KEY_W, true)
	await frames(40)
	check(z0 - player.global_position.z > 0.9 and absf(player.horizontal_speed() - player.walk_speed) < 0.3, "W walks forward (%.1f m/s)" % player.horizontal_speed())
	key(KEY_SHIFT, true)
	await frames(30)
	check(player.is_running() and absf(player.horizontal_speed() - player.run_speed) < 0.3, "Shift runs (%.1f m/s)" % player.horizontal_speed())
	key(KEY_SHIFT, false)
	key(KEY_W, false)
	await frames(30)
	check(player.horizontal_speed() < 0.1, "release stops")

	# --- Mouse look (unlocked) ---
	await _face_off(10.0)
	rig.set_lock_target(null)
	var yaw0 := rig.yaw
	mouse_move(Vector2(200, 0))
	await frames(20)
	check(rig.yaw < yaw0 - 0.2 and absf(angle_difference(player.rotation.y, rig.yaw)) < 0.05, "mouse turns camera + fighter")

	# --- Tab lock-on / release ---
	await _face_off(10.0)
	rig.set_lock_target(null)
	key_tap(KEY_TAB)
	await frames(3)
	check(rig.lock_target == opponent, "Tab locks on")
	key_tap(KEY_TAB)
	await frames(3)
	check(not rig.is_locked(), "Tab again releases")

	# --- LMB gestures ---
	await _face_off(2.0)
	mouse_button(MOUSE_BUTTON_LEFT, true)
	mouse_button(MOUSE_BUTTON_LEFT, false)
	await frames(3)
	check(player.current_attack != null and player.current_attack.name == &"light", "click = light attack")
	await frames(30)
	check(is_equal_approx(opponent.health, 92.0), "light hits (health %.1f)" % opponent.health)

	var flicks := { &"slash_right": Vector2(80, 0), &"slash_left": Vector2(-80, 0),
		&"thrust": Vector2(0, -80), &"smash": Vector2(0, 80) }
	for attack in flicks:
		await _face_off(2.0)
		var yaw_before := rig.yaw
		mouse_button(MOUSE_BUTTON_LEFT, true)
		mouse_move(flicks[attack])
		mouse_button(MOUSE_BUTTON_LEFT, false)
		await frames(3)
		var got: StringName = player.current_attack.name if player.current_attack else &"none"
		check(got == attack and is_equal_approx(rig.yaw, yaw_before), "LMB flick %s = %s, camera still (got %s)" % [flicks[attack], attack, got])
		await frames(50)

	await _face_off(2.0)
	brain.mode = DummyBrain.Mode.BLOCK
	await frames(20)
	mouse_button(MOUSE_BUTTON_LEFT, true)
	await frames(85)
	check(player.state == Fighter.State.CHARGE and player.charge_ratio() >= 1.0, "hold LMB = charge")
	mouse_button(MOUSE_BUTTON_LEFT, false)
	await frames(30)
	check(is_equal_approx(opponent.health, 100.0 - 18.0 * 1.8), "release = full heavy, breaks guard (health %.1f)" % opponent.health)

	# --- RMB guard / parry ---
	await _face_off(2.0)
	opponent.request_attack(&"slash_left")
	await frames(6)
	mouse_button(MOUSE_BUTTON_RIGHT, true)
	await frames(20)
	mouse_button(MOUSE_BUTTON_RIGHT, false)
	check(opponent.state == Fighter.State.STAGGER and is_equal_approx(player.health, 100.0), "RMB tap just before hit = parry")
	await _face_off(2.0)
	mouse_button(MOUSE_BUTTON_RIGHT, true)
	await frames(30)
	opponent.request_attack(&"slash_left")
	await frames(30)
	check(player.state == Fighter.State.GUARD and is_equal_approx(player.health, 98.8), "RMB held = block (health %.1f)" % player.health)
	mouse_button(MOUSE_BUTTON_RIGHT, false)

	# --- Space: jump, then Space again in the air = vertical dash ---
	await _face_off(10.0)
	key(KEY_SPACE, true)
	var top := 0.0
	for i in 70:
		await frames(1)
		top = maxf(top, player.global_position.y)
	key(KEY_SPACE, false)
	check(top < 1.9 and is_equal_approx(player.fuel, 100.0), "hold Space = plain jump (%.1f m)" % top)
	await _face_off(10.0)
	key_tap(KEY_SPACE)
	await frames(15)
	key_tap(KEY_SPACE)
	await frames(2)
	check(player.is_vertical_dash() and player.fuel < 100.0, "Space again in the air = vertical dash")

	# --- Dashes ---
	await _face_off(10.0)
	key_tap(KEY_W)
	await frames(2)
	key_tap(KEY_W)
	await frames(2)
	check(player.state == Fighter.State.DASH, "double-tap W = dash")
	await _face_off(10.0)
	key(KEY_D, true)
	key_tap(KEY_C)
	await frames(2)
	key(KEY_D, false)
	check(player.state == Fighter.State.DASH and player.dash_dir.x > 0.9, "C = dash toward movement (D = right)")

	# --- F toggles aim mode; LMB is the trigger while aiming ---
	await _face_off(8.0)
	key_tap(KEY_F)
	await frames(30)
	check(player.aiming and desktop.aiming, "F enters aim mode")
	await aim_at(opponent)
	mouse_button(MOUSE_BUTTON_LEFT, true)
	await frames(40)
	mouse_button(MOUSE_BUTTON_LEFT, false)
	await frames(10)
	check(player.ammo < 60 and opponent.health < 100.0 and player.current_attack == null, "LMB fires in aim mode, no sword attack (ammo %d)" % player.ammo)
	key_tap(KEY_F)
	await frames(3)
	check(not player.aiming, "F again leaves aim mode")

	# --- Esc menu ---
	manager.mode = SessionManager.Mode.TRAINING
	key_tap(KEY_ESCAPE)
	await process_frame
	check(paused and manager.menu.visible and not desktop.enabled, "Esc opens setup, input off")
	manager.menu.mode = SessionManager.Mode.TRAINING
	manager.menu._confirm()
	await frames(3)
	check(not paused and desktop.enabled, "confirm resumes with input on")

	finish()


func _face_off(dist: float) -> void:
	brain.mode = DummyBrain.Mode.IDLE
	for node in main.get_children():
		if node is Projectile:
			node.queue_free()
	for k in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT, KEY_SPACE, KEY_F]:
		key(k, false)
	manager.reset_fighters()
	player.set_aiming(false)
	player.barrel = BarrelDef.machine_gun()
	player.reset_to(Vector3(0, 0, 20 + dist), 0.0)
	opponent.reset_to(Vector3(0, 0, 20), PI)
	rig.yaw = 0.0
	rig.set_lock_target(opponent)
	await frames(8)
