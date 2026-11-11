extends "res://tests/test_base.gd"
## Step 4 check: sword presets, armor, sword-specific guard rules, SPAR AI, setup menu.
## Run: godot --headless --path . -s tests/test_step4.gd



func _run() -> void:
	await frames(20)

	# --- Presets change stats ---
	player.apply_loadout(SwordDef.striker(), ArmorDef.by_id(&"light"))
	var light_run := player.run_speed
	check(is_equal_approx(player.max_health, 85.0) and light_run > ArmorDef.by_id(&"medium").run_speed, "light armor: less HP, faster (%.0f HP, run %.1f m/s)" % [player.max_health, light_run])
	check(player.barrel.kind == BarrelDef.Kind.MACHINE_GUN and player.thruster.vertical, "striker: machine gun + flight")
	var base_light: AttackDef = Movesets.standard()[&"light"]
	check(player.moveset[&"light"].windup < base_light.windup and player.moveset[&"light"].damage < base_light.damage, "striker: faster, lighter swings than the baseline")
	player.apply_loadout(SwordDef.breaker(), ArmorDef.by_id(&"heavy"))
	check(not player.barrel.has_gun() and player.ammo == 0 and not player.can_parry, "breaker: no gun, no parry")
	check(player.moveset[&"smash"].guard_break and player.moveset[&"heavy"].guard_break, "breaker: smash + heavy break guard")
	check(is_equal_approx(player.max_health, 140.0) and player.run_speed < light_run * 0.7 and player.acceleration < 6.0, "heavy armor: more HP, much slower and heavier (run %.1f m/s)" % player.run_speed)
	player.apply_loadout(SwordDef.lancer(), ArmorDef.by_id(&"medium"))
	check(player.barrel.kind == BarrelDef.Kind.ROCKET and player.thruster.dash_attack == ThrusterDef.DashAttack.AFTER, "lancer: rockets + attack-after-dash")

	# --- Breaker: even a quick (uncharged) heavy breaks guard ---
	await _face_off(SwordDef.breaker(), &"medium", SwordDef.lancer(), &"medium")
	brain.mode = DummyBrain.Mode.BLOCK
	await frames(20)
	mouse_button(MOUSE_BUTTON_LEFT, true)
	await frames(20)  # just past the hold threshold = barely charged
	mouse_button(MOUSE_BUTTON_LEFT, false)
	await frames(40)
	check(opponent.health < 80.0, "breaker uncharged heavy breaks guard (health %.1f)" % opponent.health)

	# --- Striker: small blade, a strong hit crushes its guard ---
	await _face_off(SwordDef.striker(), &"medium", SwordDef.breaker(), &"medium")
	mouse_button(MOUSE_BUTTON_RIGHT, true)
	await frames(20)  # past the parry window: plain block
	opponent.request_attack(&"slash_left")  # 12 * 1.45 = 17.4 > striker's block limit 14
	await frames(50)
	mouse_button(MOUSE_BUTTON_RIGHT, false)
	check(is_equal_approx(player.health, 100.0 - 17.4 * 0.5), "striker guard crushed by big hit: half damage (health %.1f)" % player.health)

	# --- Breaker blocks the same hit for chip only ---
	await _face_off(SwordDef.breaker(), &"medium", SwordDef.breaker(), &"medium")
	mouse_button(MOUSE_BUTTON_RIGHT, true)
	await frames(20)
	opponent.request_attack(&"slash_left")
	await frames(50)
	mouse_button(MOUSE_BUTTON_RIGHT, false)
	check(player.health > 98.5, "breaker blocks big hit, chip only (health %.1f)" % player.health)

	# --- Breaker can't parry ---
	await _face_off(SwordDef.breaker(), &"medium", SwordDef.lancer(), &"medium")
	opponent.request_attack(&"slash_left")
	await frames(6)
	mouse_button(MOUSE_BUTTON_RIGHT, true)
	await frames(30)
	mouse_button(MOUSE_BUTTON_RIGHT, false)
	check(opponent.state != Fighter.State.STAGGER and player.health < 100.0, "breaker: well-timed guard is only a block")

	# --- Armor scales damage taken ---
	await _face_off(SwordDef.lancer(), &"heavy", SwordDef.lancer(), &"light")
	opponent.request_attack(&"slash_left")
	await frames(40)
	check(is_equal_approx(player.health, 140.0 - 12.0 * 0.75), "heavy armor takes 75%% (health %.1f)" % player.health)
	click()
	await frames(40)
	check(is_equal_approx(opponent.health, 85.0 - 8.0 * 1.15), "light armor takes 115%% (health %.1f)" % opponent.health)

	# --- SPAR AI: defends against a button-masher ---
	await _face_off(SwordDef.lancer(), &"medium", SwordDef.lancer(), &"medium")
	brain.mode = DummyBrain.Mode.SPAR
	var events := { "PARRY!": 0, "BLOCK": 0, "dodge": 0 }
	opponent.combat_event.connect(func(t, _c): if events.has(t): events[t] += 1)
	var opp_dashes := 0
	var counts := { "player_hits": 0 }  # dict: lambdas copy plain ints
	player.got_hit.connect(func(_b): counts.player_hits += 1)
	for i in 900:  # 15 s
		if player.state == Fighter.State.FREE and player.global_position.distance_to(opponent.global_position) < 3.5:
			player.request_attack(&"light")
		elif player.state == Fighter.State.FREE:
			var to := opponent.global_position - player.global_position
			player.move_input = Vector2(to.x, to.z).normalized()
		player.desired_yaw = FighterCamera.yaw_towards(opponent.global_position - player.global_position)
		if opponent.state == Fighter.State.DASH and opponent.dash_time < 0.02:
			opp_dashes += 1
		if not player.is_alive() or not opponent.is_alive():
			break
		await frames(1)
	var player_hits: int = counts.player_hits
	print("    spar vs masher: parries %d, blocks %d, AI dashes %d, hits on player %d, HP you %.0f / AI %.0f" % [events["PARRY!"], events["BLOCK"], opp_dashes, player_hits, player.health, opponent.health])
	check(events["PARRY!"] + events["BLOCK"] >= 3, "SPAR AI guards / parries attacks")
	check(player.health <= player.max_health - 5.0, "SPAR AI fights back (took %.0f HP)" % (player.max_health - player.health))

	# --- SPAR AI: approaches from range and doesn't idle ---
	await _face_off(SwordDef.striker(), &"medium", SwordDef.striker(), &"medium")
	player.global_position = Vector3(0, 0, 40)
	brain.mode = DummyBrain.Mode.SPAR
	await frames(10)
	var start_dist := player.global_position.distance_to(opponent.global_position)
	await frames(240)
	var end_dist := player.global_position.distance_to(opponent.global_position)
	check(end_dist < start_dist - 8.0, "SPAR AI closes distance (%.0f m -> %.0f m)" % [start_dist, end_dist])

	# --- Setup menu applies choices ---
	brain.mode = DummyBrain.Mode.IDLE
	manager.open_setup()
	await process_frame
	check(paused and manager.menu.visible, "SETUP pauses and shows the menu")
	manager.menu.player_sword = &"breaker"
	manager.menu.player_armor = &"heavy"
	manager.menu.opponent_sword = &"striker"
	manager.menu.ai_mode = DummyBrain.Mode.BLOCK
	manager.menu._confirm()
	await frames(3)
	check(not paused and player.sword.id == &"breaker" and player.armor.id == &"heavy", "menu applies player loadout")
	check(opponent.sword.id == &"striker" and brain.mode == DummyBrain.Mode.BLOCK, "menu applies opponent loadout + AI mode")

	finish()


func _face_off(p_sword: SwordDef, p_armor: StringName, o_sword: SwordDef, o_armor: StringName) -> void:
	brain.mode = DummyBrain.Mode.IDLE
	for node in main.get_children():
		if node is Projectile:
			node.queue_free()
	player.apply_loadout(p_sword, ArmorDef.by_id(p_armor))
	opponent.apply_loadout(o_sword, ArmorDef.by_id(o_armor))
	player.reset_to(Vector3(0, 0, 22), 0.0)
	opponent.reset_to(Vector3(0, 0, 20), PI)
	rig.yaw = 0.0
	rig.set_lock_target(opponent)
	await frames(8)
