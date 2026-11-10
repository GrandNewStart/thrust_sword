extends "res://tests/test_base.gd"
## Step 3 check: double-flick dash, dash attacks, vertical thrust, fuel, secondary fire
## (machine gun + rocket), ammo and pickups.
## Run: godot --headless --path . -s tests/test_step3.gd

var joy: Vector2
var pad: Vector2


func _run() -> void:
	await frames(20)
	joy = Vector2(controls.size.x * 0.25, controls.size.y - 200)
	pad = Vector2(controls.size.x * 0.62, controls.size.y - 380)

	# --- Double-flick forward = dash ---
	await _face_off(8.0)
	var z0 := player.global_position.z
	await _double_flick(Vector2(0, 1))
	await frames(2)
	check(player.state == Fighter.State.DASH, "double-flick = dash (state %s)" % Fighter.State.keys()[player.state])
	check(is_equal_approx(player.fuel, 100.0 - player.thruster.dash_fuel), "dash costs fuel (%.1f)" % player.fuel)
	await frames(20)
	var moved := z0 - player.global_position.z
	check(moved > 4.0, "dash covers ground fast (%.1f m in ~0.35s)" % moved)

	# --- Single flick = no dash ---
	await _face_off(8.0)
	await _flick(Vector2(0, 1))
	await frames(3)
	check(player.state != Fighter.State.DASH, "single flick doesn't dash")

	# --- Sideways dash while locked keeps facing the opponent ---
	await _face_off(8.0)
	var x0 := player.global_position.x
	await _double_flick(Vector2(1, 0))
	await frames(20)
	check(player.global_position.x - x0 > 3.0, "dash right moves right (%.1f m)" % (player.global_position.x - x0))

	# --- No fuel = no dash ---
	await _face_off(8.0)
	player.fuel = 0.0
	await _double_flick(Vector2(0, 1))
	await frames(2)
	check(player.state != Fighter.State.DASH, "no fuel = no dash")

	# --- Dash attack (attack during dash) hits harder ---
	await _face_off(5.0)
	await _double_flick(Vector2(0, 1))
	await frames(4)
	tap(1, pad)
	await frames(40)
	var expected := 8.0 * player.thruster.dash_attack_damage_mult
	check(is_equal_approx(opponent.health, 100.0 - expected), "dash + tap = boosted light (%.1f dmg)" % (100.0 - opponent.health))

	# --- AFTER-type thruster: attack waits for the dash to end ---
	await _face_off(5.0)
	player.thruster.dash_attack = ThrusterDef.DashAttack.AFTER
	await _double_flick(Vector2(0, 1))
	await frames(4)
	tap(1, pad)
	await frames(2)
	check(player.state == Fighter.State.DASH, "AFTER thruster: still dashing after tap")
	await frames(12)
	check(player.state == Fighter.State.ATTACK, "AFTER thruster: attack fires as dash ends")
	player.thruster.dash_attack = ThrusterDef.DashAttack.DURING

	# --- Holding jump is just a jump (no hovering) ---
	await _face_off(8.0)
	var jump_btn := controls.button_center(&"jump")
	touch(2, jump_btn, true)
	var top := 0.0
	for i in 70:
		await frames(1)
		top = maxf(top, player.global_position.y)
	touch(2, jump_btn, false)
	check(top < 1.9 and is_equal_approx(player.fuel, 100.0), "holding jump = one plain jump, no fuel (%.1f m)" % top)

	# --- Second press in the air = one vertical dash ---
	await _face_off(8.0)
	tap(2, jump_btn)
	await frames(15)
	var fuel_before := player.fuel
	tap(2, jump_btn)
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
	tap(2, jump_btn)
	await frames(10)
	var boosts := 0
	for i in 4:
		tap(2, jump_btn)
		await frames(2)
		if player.is_vertical_dash():
			boosts += 1
		await frames(30)  # past the dash + its cooldown
	check(boosts == player.thruster.air_dash_limit, "boosts per airtime = air-dash limit (%d)" % boosts)
	await frames(120)

	# --- Tap jump stays a normal jump ---
	await _face_off(8.0)
	touch(2, jump_btn, true)
	await frames(3)
	touch(2, jump_btn, false)
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
	touch(1, pad, true)
	await frames(60)
	touch(1, pad, false)
	await frames(10)
	check(player.ammo <= 60 - 9, "MG fires while the trigger is held (ammo %d)" % player.ammo)
	check(opponent.health < 100.0, "MG bullets hit (health %.1f)" % opponent.health)
	check(opponent.state != Fighter.State.STAGGER, "MG doesn't stagger")

	# --- MG interrupts a charging opponent ---
	await _face_off(8.0)
	brain.set_physics_process(false)
	opponent.charge_input = true
	await _enter_aim()
	touch(1, pad, true)
	await frames(15)
	touch(1, pad, false)
	check(opponent.state == Fighter.State.STAGGER or opponent.state == Fighter.State.FREE, "MG interrupts charge (state %s)" % Fighter.State.keys()[opponent.state])
	opponent.charge_input = false
	brain.set_physics_process(true)

	# --- Rocket: one shot per press, explodes ---
	await _face_off(8.0)
	player.barrel = BarrelDef.rocket()
	player.ammo = player.barrel.max_ammo
	await _enter_aim()
	touch(1, pad, true)
	await frames(40)
	touch(1, pad, false)
	await frames(5)
	check(player.ammo == 3, "rocket = one shot per press (ammo %d)" % player.ammo)
	check(is_equal_approx(opponent.health, 84.0), "rocket hits for 16 (health %.1f)" % opponent.health)

	# --- Blocked rocket: chip + stamina ---
	await _face_off(8.0)
	player.barrel = BarrelDef.rocket()
	player.ammo = player.barrel.max_ammo
	brain.mode = DummyBrain.Mode.BLOCK
	await _enter_aim()
	tap(1, pad)
	await frames(40)
	check(is_equal_approx(opponent.health, 98.4), "blocked rocket = chip only (health %.1f)" % opponent.health)
	check(opponent.stamina < 80.0, "blocked rocket costs stamina (%.1f)" % opponent.stamina)

	# --- Out of ammo ---
	await _face_off(8.0)
	player.ammo = 0
	await _enter_aim()
	tap(1, pad)
	await frames(30)
	check(is_equal_approx(opponent.health, 100.0), "no ammo = no shot")
	tap(3, controls.button_center(&"fire"))  # leave aim mode
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


## Toggle aim mode with the AIM button, let the camera settle, put the crosshair on the opponent.
func _enter_aim() -> void:
	tap(3, controls.button_center(&"fire"))
	await frames(30)
	await aim_at(opponent)


func _flick(dir: Vector2) -> void:
	var to := joy + Vector2(dir.x, -dir.y) * 110.0
	touch(0, joy, true)
	drag(0, to, to - joy)
	await frames(2)
	touch(0, to, false)
	await frames(2)


func _double_flick(dir: Vector2) -> void:
	await _flick(dir)
	await _flick(dir)
