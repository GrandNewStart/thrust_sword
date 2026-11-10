extends SceneTree
## Renders the setup menu and each sword (needs a real window, not --headless).
## Run: godot --path . -s tests/screenshot_loadouts.gd -- <output_dir>

var vp: SubViewport
var out_dir: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "user://"
	vp = SubViewport.new()
	vp.size = Vector2i(720, 1280)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	InputMode.forced = InputMode.Kind.TOUCH
	var main: Node = load("res://scenes/main.tscn").instantiate()
	(main.get_node("Session") as SessionManager).auto_start = false
	vp.add_child(main)
	var player: Fighter = main.get_node("Player")
	var opp: Fighter = main.get_node("Opponent")
	var rig: FighterCamera = main.get_node("CameraRig")
	var manager: SessionManager = main.get_node("Session")
	var brain: DummyBrain = main.get_node("DummyBrain")
	await _frames(20)
	manager.open_setup()
	await _frames(5)
	await _shot("menu")
	manager.menu._confirm()
	paused = false
	brain.mode = DummyBrain.Mode.IDLE

	for pair in [[&"striker", &"light", &"breaker", &"heavy"], [&"lancer", &"medium", &"striker", &"light"], [&"breaker", &"heavy", &"lancer", &"medium"]]:
		player.apply_loadout(SwordDef.by_id(pair[0]), ArmorDef.by_id(pair[1]))
		opp.apply_loadout(SwordDef.by_id(pair[2]), ArmorDef.by_id(pair[3]))
		player.reset_to(Vector3(1.5, 0, 4), 0.0)
		opp.reset_to(Vector3(0, 0, 0), PI)
		rig.yaw = 0.0
		rig.set_lock_target(opp)
		await _frames(40)
		await _shot("%s_vs_%s" % [pair[0], pair[2]])
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(out_dir.path_join(shot_name + ".png"))
