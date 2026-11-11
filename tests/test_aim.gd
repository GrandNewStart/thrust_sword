extends "res://tests/test_base.gd"
## Manual aim mode (desktop scheme): toggle, planted, close-up camera, no auto-aim,
## lock-on suspended/restored, escape exits, swords without a gun.
## Run: godot --headless --path . -s tests/test_aim.gd




func _run() -> void:
	await frames(20)

	# --- Toggle + planted + close-up camera ---
	await _face_off()
	var spring0: float = rig._arm.spring_length
	var fov0: float = rig.camera.fov
	key_tap(KEY_F)
	await frames(30)
	check(player.aiming, "F = aim mode on")
	check(rig._arm.spring_length < spring0 * 0.5 and rig.camera.fov < fov0, "camera pulls in close (%.1f m, fov %.0f)" % [rig._arm.spring_length, rig.camera.fov])
	check(not rig.is_locked(), "lock-on suspended while aiming")
	var p0 := player.global_position
	key(KEY_W, true)
	await frames(40)
	key(KEY_W, false)
	check(player.global_position.distance_to(p0) < 0.05, "position fixed while aiming")

	# --- No auto-aim: shots go where the crosshair points ---
	rig.yaw += 0.6  # crosshair well off to the side
	await frames(5)
	mouse_button(MOUSE_BUTTON_LEFT, true)
	await frames(30)
	mouse_button(MOUSE_BUTTON_LEFT, false)
	await frames(15)
	check(player.ammo < 60 and is_equal_approx(opponent.health, 100.0), "aiming away = miss (ammo %d, health %.0f)" % [player.ammo, opponent.health])
	await aim_at(opponent)
	mouse_button(MOUSE_BUTTON_LEFT, true)
	await frames(30)
	mouse_button(MOUSE_BUTTON_LEFT, false)
	await frames(15)
	check(opponent.health < 100.0, "crosshair on target = hit (health %.1f)" % opponent.health)

	# --- Leaving restores the lock ---
	key_tap(KEY_F)
	await frames(5)
	check(not player.aiming and rig.lock_target == opponent, "F again: aim off, lock-on restored")

	# --- No hip fire: LMB outside aim mode is a sword attack ---
	await _face_off()
	var ammo0 := player.ammo
	mouse_button(MOUSE_BUTTON_LEFT, true)
	mouse_button(MOUSE_BUTTON_LEFT, false)
	await frames(5)
	check(player.ammo == ammo0 and player.current_attack != null, "LMB without aim mode = sword attack, no shot")

	# --- Escape exits ---
	for exit in ["jump", "dash", "guard", "hit"]:
		await _face_off()
		key_tap(KEY_F)
		await frames(10)
		match exit:
			"jump":
				key_tap(KEY_SPACE)
			"dash":
				key_tap(KEY_D)
				await frames(2)
				key_tap(KEY_D)
			"guard":
				mouse_button(MOUSE_BUTTON_RIGHT, true)
			"hit":
				opponent.global_position = player.global_position + player.forward() * 2.0
				opponent.request_attack(&"slash_left")
				await frames(30)
		await frames(4)
		var did := {"jump": not player.is_on_floor(), "dash": player.state == Fighter.State.DASH,
			"guard": player.state == Fighter.State.GUARD, "hit": player.health < player.max_health}
		check(not player.aiming and did[exit], "%s leaves aim mode (and happens)" % exit)
		mouse_button(MOUSE_BUTTON_RIGHT, false)

	# --- Breaker: no gun, no aim mode ---
	await _face_off()
	player.apply_loadout(SwordDef.breaker(), ArmorDef.by_id(&"medium"))
	await frames(2)
	key_tap(KEY_F)
	await frames(5)
	check(not player.aiming, "Breaker: F does nothing")
	player.apply_loadout(SwordDef.lancer(), ArmorDef.by_id(&"medium"))
	await frames(2)
	key_tap(KEY_F)
	await frames(5)
	check(player.aiming, "Lancer: F aims again")
	key_tap(KEY_F)
	await frames(5)

	# --- AI still fires from the hip ---
	await _face_off()
	var opp_ammo := opponent.ammo
	opponent.request_fire()
	await frames(3)
	check(opponent.ammo < opp_ammo, "AI can still hip-fire")

	finish()


func _face_off() -> void:
	brain.mode = DummyBrain.Mode.IDLE
	for node in main.get_children():
		if node is Projectile:
			node.queue_free()
	for k in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE, KEY_F]:
		key(k, false)
	mouse_button(MOUSE_BUTTON_RIGHT, false)
	manager.reset_fighters()
	player.apply_loadout(SwordDef.striker(), ArmorDef.by_id(&"medium"))
	opponent.apply_loadout(SwordDef.striker(), ArmorDef.by_id(&"medium"))
	player.reset_to(Vector3(0, 0, 26), 0.0)
	opponent.reset_to(Vector3(0, 0, 20), PI)
	rig.yaw = 0.0
	rig.set_lock_target(opponent)
	await frames(10)
