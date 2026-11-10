extends "res://tests/test_base.gd"
## Light attack chain: swing left → swing right → poke, and when it resets.
## Run: godot --headless --path . -s tests/test_combo.gd

var pad: Vector2


func _run() -> void:
	await frames(20)
	pad = Vector2(controls.size.x * 0.62, controls.size.y - 380)

	# --- Three taps = the full chain ---
	await _face_off()
	var seen: Array[StringName] = []
	for i in 3:
		await _tap_and_wait_start()
		seen.append(player.current_attack.name if player.current_attack else &"none")
		await _until_recovery()
	await frames(40)
	check(seen == [&"light", &"light_2", &"light_3"], "taps chain swing left → swing right → poke (%s)" % [seen])
	check(is_equal_approx(opponent.health, 100.0 - 8.0 - 8.0 - 11.0), "all three hits land (health %.1f)" % opponent.health)

	# --- After the poke, the chain starts over ---
	await _face_off()
	for i in 4:
		await _tap_and_wait_start()
		if i < 3:
			await _until_recovery()
	check(player.current_attack.name == &"light", "4th tap starts a new chain")

	# --- Pausing resets the chain ---
	await _face_off()
	tap(1, pad)
	await frames(80)  # well past the attack + chain grace
	tap(1, pad)
	await frames(3)
	check(player.current_attack.name == &"light", "pause = chain restarts at swing 1")

	# --- A quick follow-up after the hit ended still chains ---
	await _face_off()
	await _tap_and_wait_start()
	while player.state == Fighter.State.ATTACK:
		await frames(1)
	await frames(6)  # 0.1 s after it ended
	tap(1, pad)
	await frames(3)
	check(player.current_attack != null and player.current_attack.name == &"light_2", "tap right after a hit ends = next in chain (got %s, state %s, since %.2f)" % [player.current_attack.name if player.current_attack else "none", Fighter.State.keys()[player.state], player._since_light])

	# --- Another attack breaks the chain ---
	await _face_off()
	tap(1, pad)
	await _until_recovery()
	swipe(1, pad, Vector2(140, 0))  # slash
	await frames(3)
	while player.state == Fighter.State.ATTACK:
		await frames(1)
	tap(1, pad)
	await frames(3)
	check(player.current_attack.name == &"light", "a slash in between resets the chain")

	# --- Getting hit resets the chain ---
	await _face_off()
	tap(1, pad)
	await frames(3)
	player._stagger(0.2)
	await frames(20)
	tap(1, pad)
	await frames(3)
	check(player.current_attack.name == &"light", "being staggered resets the chain")

	finish()


func _face_off() -> void:
	brain.mode = DummyBrain.Mode.IDLE
	manager.reset_fighters()
	player.reset_to(Vector3(0, 0, 2), 0.0)
	opponent.reset_to(Vector3(0, 0, 0), PI)
	rig.yaw = 0.0
	rig.set_lock_target(opponent)
	await frames(5)


## Tap, then wait for the (possibly queued) new attack to actually begin.
func _tap_and_wait_start() -> void:
	var before := player.current_attack
	tap(1, pad)
	for i in 40:
		await frames(1)
		if player.current_attack != null and player.current_attack != before:
			return


## Wait until the current attack is in its recovery (where the next hit can be queued).
func _until_recovery() -> void:
	while player.state == Fighter.State.ATTACK and player.attack_phase() < 2:
		await frames(1)
