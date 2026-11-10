extends "res://tests/test_base.gd"
## Step 5 check: match loop — intro countdown, rounds won by K.O. and timeout, draws,
## match end, results screen, rematch, setup flow and pickups resetting.
## Run: godot --headless --path . -s tests/test_step5.gd

var pad: Vector2


func _run() -> void:
	await frames(20)
	pad = Vector2(controls.size.x * 0.62, controls.size.y - 380)

	# --- Start a match: intro freezes the fighters ---
	manager.start_match()
	await frames(5)
	check(manager.phase == SessionManager.Phase.INTRO and manager.round_number == 1, "match starts with round 1 intro")
	check(manager.banner == "ROUND 1", "intro banner (%s)" % manager.banner)
	tap(1, pad)
	await frames(5)
	check(player.state != Fighter.State.ATTACK, "can't attack during the intro")
	await _wait_phase(SessionManager.Phase.FIGHT, 4.0)
	check(manager.phase == SessionManager.Phase.FIGHT and player.controllable, "FIGHT! after the countdown")
	var t0 := manager.time_left
	await frames(60)
	check(manager.time_left < t0 - 0.8, "round timer runs (%.1f s left)" % manager.time_left)

	# --- Round 1: player wins by K.O. ---
	_put_in_range()
	await frames(5)
	opponent.health = 1.0
	tap(1, pad)
	await frames(40)
	check(manager.phase == SessionManager.Phase.ROUND_END and manager.banner == "K.O.", "K.O. ends the round")
	check(Engine.time_scale < 1.0, "K.O. slow motion")
	check(manager.player_wins == 1 and manager.last_round_outcome == SessionManager.Outcome.PLAYER, "player wins round 1")

	# Use a pickup now; it should be back next round.
	var pack: Pickup = main.get_node("Pickups/FuelPackA")
	player.fuel = 10.0
	player.global_position = pack.global_position
	await frames(3)

	await _wait_phase(SessionManager.Phase.INTRO, 6.0)
	check(manager.round_number == 2 and is_equal_approx(opponent.health, opponent.max_health), "round 2: fighters reset")
	check(pack.available and is_equal_approx(Engine.time_scale, 1.0), "round 2: pickups back, normal speed")

	# --- Round 2: draw on timeout with equal health ---
	await _wait_phase(SessionManager.Phase.FIGHT, 4.0)
	manager.time_left = 0.3
	await frames(30)
	check(manager.last_round_outcome == SessionManager.Outcome.DRAW and manager.banner == "TIME", "timeout with equal health = draw")
	check(manager.player_wins == 1 and manager.opponent_wins == 0, "draw gives no wins")

	# --- Round 3: opponent wins on timeout with more health ---
	await _wait_phase(SessionManager.Phase.FIGHT, 8.0)
	check(manager.round_number == 3, "round 3 starts")
	player.health = 50.0
	manager.time_left = 0.3
	await frames(30)
	check(manager.opponent_wins == 1, "more health left wins on timeout")

	# --- Round 4: player K.O.s again -> 2 wins -> VICTORY ---
	await _wait_phase(SessionManager.Phase.FIGHT, 8.0)
	_put_in_range()
	await frames(5)
	opponent.health = 1.0
	tap(1, pad)
	await _wait_phase(SessionManager.Phase.MATCH_END, 8.0)
	check(manager.match_result() == SessionManager.Outcome.PLAYER, "2 round wins = match won")
	check(manager.result_panel.visible and not controls.enabled, "results screen shown, touch controls off")

	# --- Rematch ---
	manager.result_panel.rematch_pressed.emit()
	await frames(5)
	check(manager.round_number == 1 and manager.player_wins == 0 and manager.phase == SessionManager.Phase.INTRO, "rematch restarts at round 1")
	check(not manager.result_panel.visible and controls.enabled, "rematch hides results")

	# --- Losing a match ---
	for i in 2:
		await _wait_phase(SessionManager.Phase.FIGHT, 8.0)
		player.health = 1.0
		opponent.request_attack(&"light")
		_put_in_range()
		await frames(40)
	await _wait_phase(SessionManager.Phase.MATCH_END, 8.0)
	check(manager.match_result() == SessionManager.Outcome.OPPONENT, "lose 2 rounds = DEFEAT")

	# --- SETUP from results, choose TRAINING ---
	manager.result_panel.setup_pressed.emit()
	await process_frame
	check(paused and manager.menu.visible, "SETUP from results opens the menu")
	manager.menu.mode = SessionManager.Mode.TRAINING
	manager.menu.ai_mode = DummyBrain.Mode.IDLE
	manager.menu._confirm()
	await frames(5)
	check(manager.mode == SessionManager.Mode.TRAINING and manager.phase == SessionManager.Phase.FIGHT and player.controllable, "TRAINING mode: straight into play")
	opponent.health = 1.0
	_put_in_range()
	await frames(3)
	tap(1, pad)
	await frames(200)
	check(opponent.is_alive() and manager.phase == SessionManager.Phase.FIGHT, "TRAINING: K.O. just resets, no rounds")

	# --- Restarting mid-intro doesn't leave stale timers behind ---
	manager.start_match()
	await frames(30)
	manager.start_match()
	await _wait_phase(SessionManager.Phase.FIGHT, 4.0)
	await frames(60)
	check(manager.round_number == 1 and manager.phase == SessionManager.Phase.FIGHT, "restart mid-intro: single clean round 1")

	finish()


## Opponent 2 m in front of the player, facing each other, locked on.
func _put_in_range() -> void:
	player.global_position = Vector3(0, 0, 22)
	player.rotation.y = 0.0
	player.desired_yaw = 0.0
	opponent.global_position = Vector3(0, 0, 20)
	opponent.rotation.y = PI
	opponent.desired_yaw = PI
	rig.yaw = 0.0
	rig.set_lock_target(opponent)


func _wait_phase(p: SessionManager.Phase, max_seconds: float) -> void:
	# Session timers run in real time, so wait in real time too.
	var start := Time.get_ticks_msec()
	while manager.phase != p and Time.get_ticks_msec() - start < int(max_seconds * 1000):
		await process_frame
