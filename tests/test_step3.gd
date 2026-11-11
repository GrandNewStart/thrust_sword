extends "res://tests/test_base.gd"
## Step 3 check: double-tap dash, dash attacks, vertical thrust, fuel, secondary fire
## (machine gun + rocket), ammo and pickups.
## Run: godot --headless --path . -s tests/test_step3.gd

func _run() -> void:
	await frames(20)

	# --- Double-tap forward = dash ---
	await _face_off(8.0)
	var z0 := player.global_position.z
	await double_tap_dir(Vector2(0, 1))
	await frames(2)
	check(player.state == Fighter.State.DASH, "double-tap = dash (state %s)" % Fighter.State.keys()[player.state])
	check(is_equal_approx(player.fuel, 100.0 - player.thruster.dash_fuel), "dash costs fuel (%.1f)" % player.fuel)
	await frames(20)
	var moved := z0 - player.global_position.z
	check(moved > 3.5, "dash covers ground fast (%.1f m in ~0.35s)" % moved)

	# --- Single tap = no dash ---
	await _face_off(8.0)
	key_tap(KEY_W)
	await frames(3)
	check(player.state != Fighter.State.DASH, "single tap doesn't dash")

	# --- Sideways dash while locked keeps facing the opponent ---
	await _face_off(8.0)
	var x0 := player.global_position.x
	await double_tap_dir(Vector2(1, 0))
	await frames(20)
	check(player.global_position.x - x0 > 3.0, "dash right moves right (%.1f m)" % (player.global_position.x - x0))

	# --- No fuel = no dash ---
	await _face_off(8.0)
	player.fuel = 0.0
	await double_tap_dir(Vector2(0, 1))
	await frames(2)
	check(player.state != Fighter.State.DASH, "no fuel = no dash")

	# --- Dash attack (attack during dash) hits harder ---
	await _face_off(5.0)
	await double_tap_dir(Vector2(0, 1))
	await frames(4)
	click()
	await frames(40)
	var expected := 8.0 * player.thruster.dash_attack_damage_mult
	check(is_equal_approx(opponent.health, 100.0 - expected), "dash + tap = boosted light (%.1f dmg)" % (100.0 - opponent.health))

	# --- AFTER-type thruster: attack waits for the dash to end ---
	await _face_off(5.0)
	player.thruster.dash_attack = ThrusterDef.DashAttack.AFTER
	await double_tap_dir(Vector2(0, 1))
	await frames(4)
	click()
	await frames(2)
	check(player.state == Fighter.State.DASH, "AFTER thruster: still dashing after tap")
	await frames(12)
	check(player.state == Fighter.State.ATTACK, "AFTER thruster: attack fires as dash ends")
	player.thruster.dash_attack = ThrusterDef.DashAttack.DURING

	# --- Holding jump is just a jump (no hovering) ---
	await _face_off(8.0)
	key(KEY_SPACE, true)
	var top := 0.0
	for i in 70:
		await frames(1)
		top = maxf(top, player.global_position.y)
	key(KEY_SPACE, false)
	check(top < 1.9 and is_equal_approx(player.fuel, 100.0), "holding jump = one plain jump, no fuel (%.1f m)" % top)

	# --- Second press in the air = one vertical dash ---
	await _face_off(8.0)
	key_tap(KEY_SPACE)
	await frames(15)
	var fuel_before := player.fuel
	key_tap(KEY_SPACE)
	await frames(2)
	check(player.is_vertical_dash(), "jump again in the air = vertical dash")
	check(is_equal_approx(player.fuel, fuel_before - player.thruster.vertical_dash_fuel), "vertical dash costs fuel once (%.1f)" % player.fuel)
	top = 0.0
	for i in 70:
		await frames(1)
		top = maxf(top, player.global_position.y)
	check(top > 2.5, "boost goes well above a jump (%.1f m)" % top)
	check(is_equal_approx(player.fuel, fuel_before - player.thruster.vertical_dash_fuel), "one-time boost, not continuous (fuel %.1f)" % player.fuel)

	# --- Air dash limit is shared with vertical dashes ---
	await _face_off(8.0)
	key_tap(KEY_SPACE)
	await frames(10)
	var boosts := 0
	for i in 4:
		key_tap(KEY_SPACE)
		await frames(2)
		if player.is_vertical_dash():
			boosts += 1
		await frames(30)  # past the dash + its cooldown
	check(boosts == player.thruster.air_dash_limit, "boosts per airtime = air-dash limit (%d)" % boosts)
	await frames(120)

	# --- Tap jump stays a normal jump ---
	await _face_off(8.0)
	key(KEY_SPACE, true)
	await frames(3)
	key(KEY_SPACE, false)
	top = 0.0
	for i in 60:
		await frames(1)
		top = maxf(top, player.global_position.y)
	check(top < 3.2 and is_equal_approx(player.fuel, 100.0), "tap jump = normal jump, no fuel (%.1f m, fuel %.1f, state %s)" % [top, player.fuel, Fighter.State.keys()[player.state]])

	# Firing happens in aim mode: AIM button toggles it, the crosshair is aimed by hand
	# (aim_at), and the attack pad is the trigger.
	# --- Machine gun: hold the trigger ---
	await _face_off(8.0)
	await _enter_aim()
	mouse_button(MOUSE_BUTTON_LEFT, true)
	await frames(60)
	mouse_button(MOUSE_BUTTON_LEFT, false)
	await frames(10)
	check(player.ammo <= 60 - 9, "MG fires while the trigger is held (ammo %d)" % player.ammo)
	check(opponent.health < 100.0, "MG bullets hit (health %.1f)" % opponent.health)
	check(opponent.state != Fighter.State.STAGGER, "MG doesn't stagger")

	# --- MG interrupts a charging opponent ---
	await _face_off(8.0)
	brain.set_physics_process(false)
	opponent.charge_input = true
	await _enter_aim()
	mouse_button(MOUSE_BUTTON_LEFT, true)
	await frames(15)
	mouse_button(MOUSE_BUTTON_LEFT, false)
	check(opponent.state == Fighter.State.STAGGER or opponent.state == Fighter.State.FREE, "MG interrupts charge (state %s)" % Fighter.State.keys()[opponent.state])
	opponent.charge_input = false
	brain.set_physics_process(true)

	# --- Rocket: one shot per press, explodes ---
	await _face_off(8.0)
	player.barrel = BarrelDef.rocket()
	player.ammo = player.barrel.max_ammo
	await _enter_aim()
	mouse_button(MOUSE_BUTTON_LEFT, true)
	await frames(40)
	mouse_button(MOUSE_BUTTON_LEFT, false)
	await frames(5)
	check(player.ammo == 3, "rocket = one shot per press (ammo %d)" % player.ammo)
	check(is_equal_approx(opponent.health, 84.0), "rocket hits for 16 (health %.1f)" % opponent.health)

	# --- Blocked rocket: chip + stamina ---
	await _face_off(8.0)
	player.barrel = BarrelDef.rocket()
	player.ammo = player.barrel.max_ammo
	brain.mode = DummyBrain.Mode.BLOCK
	await _enter_aim()
	click()
	await frames(40)
	check(is_equal_approx(opponent.health, 98.4), "blocked rocket = chip only (health %.1f)" % opponent.health)
	check(opponent.stamina < 80.0, "blocked rocket costs stamina (%.1f)" % opponent.stamina)

	# --- Out of ammo ---
	await _face_off(8.0)
	player.ammo = 0
	await _enter_aim()
	click()
	await frames(30)
	check(is_equal_approx(opponent.health, 100.0), "no ammo = no shot")
	key_tap(KEY_F)  # leave aim mode
	await frames(3)

	# --- Pickups ---
	var fuel_pack: Pickup = main.get_node("Pickups/FuelPackA")
	var ammo_pack: Pickup = main.get_node("Pickups/AmmoPackA")
	await _face_off(8.0)
	player.fuel = 10.0
	player.ammo = 0
	player.global_position = fuel_pack.global_position
	await frames(5)
	check(is_equal_approx(player.fuel, 60.0), "fuel pack +50 (fuel %.1f)" % player.fuel)
	check(not fuel_pack.available, "fuel pack used up")
	player.global_position = ammo_pack.global_position
	await frames(5)
	check(player.ammo == 30, "ammo pack refills half (ammo %d/60)" % player.ammo)
	# A full fighter doesn't waste a pack.
	var fuel_pack_b: Pickup = main.get_node("Pickups/FuelPackB")
	player.fuel = player.max_fuel
	player.global_position = fuel_pack_b.global_position
	await frames(5)
	check(fuel_pack_b.available, "full fuel = pack stays")
	player.fuel = 50.0
	await frames(3)
	check(not fuel_pack_b.available and is_equal_approx(player.fuel, 100.0), "standing on pack picks it up once fuel drops")

	finish()


## Reset fighters `dist` apart on open ground, facing each other, locked on.
func _face_off(dist: float) -> void:
	brain.mode = DummyBrain.Mode.IDLE
	for node in main.get_children():
		if node is Projectile:
			node.queue_free()
	manager.reset_fighters()
	player.set_aiming(false)
	player.barrel = BarrelDef.machine_gun()
	player.reset_to(Vector3(0, 0, 20 + dist), 0.0)
	opponent.reset_to(Vector3(0, 0, 20), PI)
	rig.yaw = 0.0
	rig.set_lock_target(opponent)
	await frames(8)


## Toggle aim mode with F, let the camera settle, put the crosshair on the opponent.
func _enter_aim() -> void:
	key_tap(KEY_F)
	await frames(30)
	await aim_at(opponent)
