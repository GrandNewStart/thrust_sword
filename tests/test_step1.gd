extends "res://tests/test_base.gd"
## Step 1 check: movement, running, camera drag, jump, lock-on and release,
## driven by simulated touch events through the real input path.
## Run: godot --headless --path . -s tests/test_step1.gd


func _run() -> void:
	await frames(30)  # settle on the floor
	var s := controls.size
	print("viewport: ", s)

	# 1. Walk forward with the joystick. The stick is analog: a 60% push walks at ~60% speed.
	var joy := Vector2(s.x * 0.25, s.y - 200)
	var z0 := player.global_position.z
	touch(0, joy, true)
	drag(0, joy + Vector2(0, -60), Vector2(0, -60))
	await frames(60)
	check(player.global_position.z < z0 - 2.0, "joystick moves forward (moved %.2f)" % (z0 - player.global_position.z))
	check(not player.wants_run, "small push doesn't run")
	var expected := player.walk_speed * 60.0 / controls.joystick_radius
	check(absf(player.horizontal_speed() - expected) < 0.3, "analog walk speed ~%.2f (got %.2f)" % [expected, player.horizontal_speed()])

	# 2. Push to the edge to run.
	drag(0, joy + Vector2(0, -130), Vector2(0, -70))
	await frames(30)
	check(player.wants_run, "edge push runs")
	check(absf(player.horizontal_speed() - player.run_speed) < 0.5, "run speed ~%.1f (got %.2f)" % [player.run_speed, player.horizontal_speed()])

	# 3. Release stops the player.
	touch(0, joy + Vector2(0, -130), false)
	await frames(30)
	check(player.horizontal_speed() < 0.1, "release stops (speed %.2f)" % player.horizontal_speed())

	# 4. Camera drag on the right pad turns camera and player.
	var pad := Vector2(s.x * 0.7, s.y - 380)
	var yaw0 := rig.yaw
	# Slow drag (held past the swipe time) = camera, not an attack.
	touch(1, pad, true)
	drag(1, pad + Vector2(100, 0), Vector2(100, 0))
	await frames(25)
	touch(1, pad + Vector2(100, 0), false)
	await frames(20)
	check(absf(rig.yaw - (yaw0 - 0.6)) < 0.01, "slow drag turns camera")
	check(absf(angle_difference(player.rotation.y, rig.yaw)) < 0.05, "player faces camera direction")

	# Turn back toward the opponent.
	touch(1, pad, true)
	drag(1, pad + Vector2(-100, 0), Vector2(-100, 0))
	await frames(25)
	touch(1, pad + Vector2(-100, 0), false)
	await frames(20)

	# 5. Jump button.
	touch(2, controls.button_center(&"jump"), true)
	await frames(12)
	touch(2, controls.button_center(&"jump"), false)
	check(player.global_position.y > 0.5, "jump lifts player (y %.2f)" % player.global_position.y)
	await frames(90)
	check(player.is_on_floor(), "player lands")

	# 6. Tap the opponent to lock on.
	var opp_screen := rig.camera.unproject_position(opponent.global_position + Vector3.UP)
	print("opponent on screen at ", opp_screen)
	check(opp_screen.y < controls.control_top(), "opponent is visible in the game view")
	tap(3, opp_screen)
	await frames(5)
	check(rig.lock_target == opponent, "tap on opponent locks on")

	# 7. While locked, strafing keeps facing the opponent.
	touch(0, joy, true)
	drag(0, joy + Vector2(100, 0), Vector2(100, 0))
	await frames(90)
	touch(0, joy + Vector2(100, 0), false)
	var to_opp := opponent.global_position - player.global_position
	check(absf(angle_difference(player.rotation.y, FighterCamera.yaw_towards(to_opp))) < 0.1, "locked player faces opponent while strafing")

	# 8. Single tap on empty area does NOT release; double-tap does.
	var empty := Vector2(60, 200)
	await frames(30)
	tap(3, empty)
	await frames(30)  # longer than the double-tap window
	check(rig.is_locked(), "single tap on empty keeps lock")
	tap(3, empty)
	await frames(2)
	tap(3, empty)
	await frames(3)
	check(not rig.is_locked(), "double-tap on empty releases lock")

	finish()
