extends "res://tests/test_base.gd"
## Step 2 check: attacks (click / mouse flick / hold), combos, block, parry, guard break,
## stamina and K.O., driven by simulated mouse input.
## Run: godot --headless --path . -s tests/test_step2.gd



func _run() -> void:
	await frames(20)

	# --- Light attack (tap) ---
	await _face_off()
	click()
	await frames(3)
	check(player.state == Fighter.State.ATTACK and player.current_attack.name == &"light", "click = light attack")
	await frames(30)
	check(is_equal_approx(opponent.health, 92.0), "light hits for 8 (health %.1f)" % opponent.health)

	# --- Combo: tap again during recovery ---
	await _face_off()
	click()
	await frames(20)
	click()
	await frames(50)
	check(is_equal_approx(opponent.health, 84.0), "two clicks = two-hit combo (health %.1f)" % opponent.health)

	# --- Swipes pick the attack ---
	var dirs := { &"slash_right": Vector2(140, 0), &"slash_left": Vector2(-140, 0),
		&"thrust": Vector2(0, -140), &"smash": Vector2(0, 140) }
	for attack in dirs:
		await _face_off()
		flick(dirs[attack])
		await frames(3)
		var got: StringName = player.current_attack.name if player.current_attack else &"none"
		check(got == attack, "flick %s = %s (got %s)" % [dirs[attack], attack, got])
		await frames(50)

	# --- Swipe doesn't turn the camera (when not locked) ---
	await _face_off()
	rig.set_lock_target(null)
	await frames(2)
	var yaw0 := rig.yaw
	flick(Vector2(140, 0))
	await frames(3)
	check(absf(rig.yaw - yaw0) < 0.001, "flick leaves camera where it was")
	await frames(40)

	# --- Block: dummy guards, light only chips ---
	await _face_off()
	brain.mode = DummyBrain.Mode.BLOCK
	await frames(30)
	click()
	await frames(30)
	check(is_equal_approx(opponent.health, 99.2), "block reduces light to chip damage (health %.1f)" % opponent.health)
	check(opponent.stamina < 100.0 - 9.0, "blocking costs stamina (%.1f)" % opponent.stamina)

	# --- Charged heavy breaks guard ---
	await _face_off()
	brain.mode = DummyBrain.Mode.BLOCK
	await frames(30)
	mouse_button(MOUSE_BUTTON_LEFT, true)
	await frames(85)
	check(player.state == Fighter.State.CHARGE and player.charge_ratio() >= 1.0, "hold = full charge (ratio %.2f)" % player.charge_ratio())
	mouse_button(MOUSE_BUTTON_LEFT, false)
	await frames(30)
	check(is_equal_approx(opponent.health, 100.0 - 18.0 * 1.8), "full charge breaks guard for full damage (health %.1f)" % opponent.health)
	brain.mode = DummyBrain.Mode.IDLE

	# --- Parry: guard tapped just before the hit ---
	await _face_off()
	opponent.request_attack(&"slash_left")
	await frames(6)  # windup is 0.16s; hit lands ~0.1s after this
	mouse_button(MOUSE_BUTTON_RIGHT, true)
	await frames(20)
	mouse_button(MOUSE_BUTTON_RIGHT, false)
	check(opponent.state == Fighter.State.STAGGER, "parry staggers the attacker")
	check(is_equal_approx(player.health, 100.0), "parry takes no damage (health %.1f)" % player.health)

	# --- Held guard blocks (parry window over) ---
	await _face_off()
	mouse_button(MOUSE_BUTTON_RIGHT, true)
	await frames(30)
	opponent.request_attack(&"slash_left")
	await frames(30)
	check(player.state == Fighter.State.GUARD and opponent.state != Fighter.State.STAGGER, "held guard blocks, no parry")
	check(is_equal_approx(player.health, 98.8), "block takes chip damage (health %.1f)" % player.health)
	mouse_button(MOUSE_BUTTON_RIGHT, false)

	# --- No guard: full hit ---
	await _face_off()
	opponent.request_attack(&"slash_left")
	await frames(30)
	check(is_equal_approx(player.health, 88.0), "unguarded hit takes 12 (health %.1f)" % player.health)

	# --- Out of stamina: can't attack ---
	await _face_off()
	player.stamina = 0.0
	player._regen_wait = 5.0
	click()
	await frames(5)
	check(player.state != Fighter.State.ATTACK, "no stamina = no attack")

	# --- K.O. and reset ---
	await _face_off()
	opponent.health = 5.0
	click()
	await frames(30)
	check(opponent.state == Fighter.State.DEAD, "lethal hit = K.O.")
	await frames(170)
	check(opponent.is_alive() and is_equal_approx(opponent.health, 100.0), "training resets after K.O.")

	finish()


## Reset both fighters 2m apart, facing each other, dummy idle, locked on.
func _face_off() -> void:
	brain.mode = DummyBrain.Mode.IDLE
	manager.reset_fighters()
	player.reset_to(Vector3(0, 0, 2), 0.0)
	opponent.reset_to(Vector3(0, 0, 0), PI)
	rig.yaw = 0.0
	rig.set_lock_target(opponent)
	await frames(5)
