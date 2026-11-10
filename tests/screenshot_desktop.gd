extends SceneTree
## Renders the desktop (landscape, keyboard + mouse) version: setup, intro, combat.
## Needs a real window. Run: godot --path . -s tests/screenshot_desktop.gd -- <output_dir>

var vp: SubViewport
var out_dir: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	out_dir = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	InputMode.forced = InputMode.Kind.DESKTOP
	vp = SubViewport.new()
	vp.size = Vector2i(1600, 900)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	(main.get_node("DesktopControls") as DesktopControls).capture_mouse = false
	vp.add_child(main)
	var session: SessionManager = main.get_node("Session")
	var p: Fighter = main.get_node("Player")
	var o: Fighter = main.get_node("Opponent")
	await _frames(20)
	await _shot("d0_setup")
	session.menu.player_sword = &"breaker"
	session.menu.ai_mode = DummyBrain.Mode.IDLE
	session.menu._confirm()
	await _frames(20)
	await _shot("d1_intro")
	var t0 := Time.get_ticks_msec()
	while session.phase != SessionManager.Phase.FIGHT and Time.get_ticks_msec() - t0 < 6000:
		await process_frame
	p.global_position = Vector3(0, 0, 3)
	o.global_position = Vector3(0, 0, 0)
	(main.get_node("CameraRig") as FighterCamera).set_lock_target(o)
	await _frames(40)
	p.request_attack(&"slash_left")
	await _frames(20)
	await _shot("d2_combat")
	await _frames(60)
	p.request_dash(Vector2(1, 0))
	await _frames(8)
	await _shot("d3_dash")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(out_dir.path_join(shot_name + ".png"))
