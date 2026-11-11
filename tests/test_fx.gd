extends "res://tests/test_base.gd"
## Effects wiring: screen effects react to the player's events only; world effects spawn.
## Run: godot --headless --path . -s tests/test_fx.gd

var fx: ScreenFx



func _run() -> void:
	await frames(20)
	fx = main.get_node("ScreenFxLayer/ScreenFx")

	# --- Player dash: blur + FOV kick + shake; AI dash: nothing on screen ---
	await _reset()
	opponent.request_dash(Vector2(1, 0))
	await frames(3)
	check(fx.blur == 0.0 and rig.trauma == 0.0, "AI dash: no screen effects")
	player.request_dash(Vector2(0, -1))
	await frames(2)  # the dash shake is tiny and gone within a few frames
	check(fx.blur > 0.0 and rig._fov_kick > 1.0 and rig.trauma > 0.0, "player dash: blur, FOV kick, shake")
	await frames(6)
	check(fx.held_blur > fx.dash_blur * 0.8, "heavy blur held through the dash (%.3f)" % fx.held_blur)
	await frames(40)
	check(maxf(fx.blur, fx.held_blur) < 0.01, "blur fades out after the dash")

	# --- Walking: no blur. Running: mild blur. ---
	await _reset()
	player.move_input = Vector2(0, 1)  # away from the opponent (it stands right in front)
	player.wants_run = false
	main.get_node("PlayerController").set_physics_process(false)
	await frames(60)
	check(fx.held_blur < 0.002, "walking: no blur (%.3f)" % fx.held_blur)
	player.wants_run = true
	await frames(90)
	check(absf(fx.held_blur - fx.run_blur) < fx.run_blur * 0.2 and fx.held_blur < fx.dash_blur * 0.25, "running: mild blur (%.3f)" % fx.held_blur)
	player.move_input = Vector2.ZERO
	player.wants_run = false
	main.get_node("PlayerController").set_physics_process(true)

	# --- Charging: vibration, zoom-in, focus blur/darkening grow; ping at full; burst on release ---
	await _reset()
	var pc := main.get_node("PlayerController")
	pc.set_physics_process(false)
	player.charge_input = true
	await frames(20)
	var early_shake: float = rig._held_shake
	var early_dark := fx.darken
	await frames(60)  # past full charge
	check(rig._held_shake > early_shake and rig._held_shake > 0.05, "vibration builds with the charge (%.3f -> %.3f)" % [early_shake, rig._held_shake])
	check(rig._fov_hold < -3.0 and fx.darken > early_dark and fx.darken > 0.4, "zoom-in + edge darkening at full charge (fov %.1f, dark %.2f)" % [rig._fov_hold, fx.darken])
	var light: OmniLight3D = player.get_node("Visual")._charge_light
	check(light.light_energy > 2.0 and player.get_node("Visual")._charge_motes.emitting, "sword glow light + energy motes while charging")
	var trauma_before: float = rig.trauma
	player.charge_input = false
	await frames(2)
	check(rig.trauma > trauma_before + 0.1 and rig._fov_kick > 2.0, "release bursts: shake + FOV kick")
	await frames(60)
	check(absf(rig._fov_hold) < 0.5 and fx.darken < 0.05 and light.light_energy == 0.0, "all charge effects end after the swing")
	pc.set_physics_process(true)

	# --- AI charging: its sword lights up, but your screen stays calm ---
	await _reset()
	brain.set_physics_process(false)
	opponent.charge_input = true
	await frames(60)
	var opp_light: OmniLight3D = opponent.get_node("Visual")._charge_light
	check(opp_light.light_energy > 1.0 and rig._held_shake < 0.002 and fx.darken < 0.01, "AI charge: glow on its sword, no screen effects for you")
	opponent.charge_input = false
	brain.set_physics_process(true)

	# --- Attack signatures ---
	await _reset()
	var phases := []
	player.attack_moment.connect(func(atk, ph): phases.append([atk.name, ph]))
	player.request_attack(&"slash_left")
	await frames(60)
	check(phases.size() >= 3 and phases[0] == [&"slash_left", 0] and phases[1][1] == 1 and phases[2][1] == 2, "attack phases announced: windup, live, follow-through")
	await _reset()
	player.request_attack(&"slash_left")
	await _until(func(): return player.attack_phase() == 1)
	await frames(1)
	check(rig._roll_kick > 0.02, "slash rolls the camera with the swing (%.3f)" % rig._roll_kick)

	await _reset()
	player.request_attack(&"thrust")
	await frames(4)
	var vis: FighterVisual = player.get_node("Visual")
	check(vis.is_thrust_lunge() and vis._flame.visible, "thrust lunge fires the sword's thruster")
	await _until(func(): return player.attack_phase() == 1)
	await frames(1)
	check(rig._fov_kick > 3.0, "thrust punches the field of view")

	# Smash hits the ground even on a miss, and shakes you if you're close.
	await _reset()
	opponent.global_position = player.global_position + Vector3(0, 0, -6)  # out of reach
	var count := main.get_child_count()
	player.request_attack(&"smash")
	await _until(func(): return player.attack_phase() == 2)
	await frames(1)
	check(main.get_child_count() > count + 3 and rig.trauma > 0.3, "smash slams the ground: shockwave + dust + shake (trauma %.2f)" % rig.trauma)
	await _reset()
	player.global_position = Vector3(0, 0, 60)  # far away
	opponent.request_attack(&"smash")
	await _until(func(): return opponent.attack_phase() == 2)
	await frames(1)
	check(rig.trauma < 0.01, "a far-away slam doesn't shake you")

	# Bullets that miss spark off the floor.
	await _reset()
	count = main.get_child_count()
	main.get_node("FxDirector").bullet_impact(Vector3(5, 0, 5), Vector3.UP)
	await frames(1)
	check(main.get_child_count() >= count + 3, "bullet impacts on the environment spawn sparks, dust and a flare")

	# Aim mode focuses the screen edges.
	await _reset()
	player.toggle_aiming()
	await frames(30)
	check(fx.darken > 0.2, "aim mode darkens the edges (%.2f)" % fx.darken)
	player.set_aiming(false)
	await frames(30)
	check(fx.darken < 0.05, "and lets go when you stop aiming")

	# --- Player hit: shake + vignette + sparks spawned ---
	await _reset()
	var nodes_before := main.get_child_count()
	opponent.request_attack(&"slash_left")
	await _until(func(): return player.health < player.max_health)
	await frames(1)
	check(rig.trauma > 0.2 and fx.vignette > 0.3, "player hit: shake + damage vignette (trauma %.2f)" % rig.trauma)
	check(main.get_child_count() > nodes_before, "impact spawns world effects")

	# --- Player lands a hit: small shake, no vignette ---
	await _reset()
	player.request_attack(&"slash_left")
	await _until(func(): return opponent.health < opponent.max_health)
	await frames(1)
	check(rig.trauma > 0.0 and fx.vignette == 0.0, "landing a hit: shake, no vignette")

	# --- Regression: particles used to burst at the scene origin. A new CPUParticles3D emits
	# the moment it enters the tree, so emitters must be created switched off and only started
	# once in position. (Headless runs don't simulate particles, so test the cause directly.)
	var fresh := Fx._particles(10, 0.5, 0.1, StandardMaterial3D.new())
	check(not fresh.emitting, "new particle emitters start switched off (positioned before emitting)")
	fresh.free()

	# --- Effects clean themselves up ---
	await frames(90)
	check(main.get_child_count() <= nodes_before + 1, "effects freed afterwards (%d -> %d)" % [nodes_before, main.get_child_count()])
	check(not fx.visible and rig.trauma == 0.0, "screen effects decay back to off")

	finish()


func _reset() -> void:
	brain.mode = DummyBrain.Mode.IDLE
	manager.reset_fighters()
	player.reset_to(Vector3(0, 0, 22), 0.0)
	opponent.reset_to(Vector3(0, 0, 20), PI)
	rig.set_lock_target(opponent)
	await frames(90)  # let earlier effects decay
	rig.trauma = 0.0
	fx.blur = 0.0
	fx.vignette = 0.0
	fx.aberration = 0.0


func _until(cond: Callable) -> void:
	for i in 90:
		if cond.call():
			return
		await frames(1)
