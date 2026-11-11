extends SceneTree
## Renders match-flow screens (needs a real window, not --headless).
## Run: godot --path . -s tests/screenshot_match.gd -- <output_dir>

var vp: SubViewport
var out_dir: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "user://"
	vp = SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	vp.add_child(main)
	var session: SessionManager = main.get_node("Session")
	var player: Fighter = main.get_node("Player")
	var opp: Fighter = main.get_node("Opponent")
	await _frames(20)
	await _shot("m0_setup")
	session.menu.ai_mode = DummyBrain.Mode.IDLE
	session.menu._confirm()
	await _frames(10)
	await _shot("m1_intro")
	await _until(func(): return session.banner == "2")
	await _shot("m2_countdown")
	await _until(func(): return session.phase == SessionManager.Phase.FIGHT)
	await _frames(4)
	await _shot("m3_fight")
	player.health = 15.0
	session.time_left = 8.4
	await _frames(20)
	await _shot("m4_low_health")
	player.global_position = Vector3(0, 0, 2.2)
	opp.global_position = Vector3(0, 0, 0)
	(main.get_node("CameraRig") as FighterCamera).set_lock_target(opp)
	opp.health = 1.0
	player.request_attack(&"light")
	await _until(func(): return session.banner == "K.O.")
	await _frames(10)
	await _shot("m5_ko")
	await _until(func(): return session.banner == "ROUND WON")
	await _frames(5)
	await _shot("m6_round_won")
	session.player_wins = 1
	session._end_match()
	await _frames(10)
	await _shot("m7_result")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _until(cond: Callable) -> void:
	var start := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - start < 8000:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(out_dir.path_join(shot_name + ".png"))
