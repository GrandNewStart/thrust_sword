extends SceneTree
## Mid-dash poses: one row per dash direction (forward, back, left, right, up), seen from a
## front three-quarter view, the side and above (needs a real window, not --headless).
## Run: godot --path . -s tests/screenshot_dash.gd -- <output.png>

const W := 320
const DIRS := ["forward", "back", "left", "right", "up"]

var vp: SubViewport


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	vp = SubViewport.new()
	vp.size = Vector2i(W, W)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	(main.get_node("Session") as SessionManager).auto_start = false
	vp.add_child(main)
	main.get_node("UI").queue_free()
	main.get_node("ScreenFxLayer").queue_free()  # motion blur would smear the pose
	main.get_node("FxDirector").queue_free()
	main.get_node("PlayerController").queue_free()
	main.get_node("DummyBrain").queue_free()
	var p: Fighter = main.get_node("Player")
	var o: Fighter = main.get_node("Opponent")
	await _wait(10)
	p.apply_loadout(SwordDef.lancer(), ArmorDef.by_id(&"medium"))
	o.apply_loadout(SwordDef.breaker(), ArmorDef.by_id(&"medium"))
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 50.0
	# Camera offsets from the fighter (who faces -Z): front three-quarter, side (from the right), top.
	var views := [Vector3(2.2, 1.6, -3.4), Vector3(4.5, 1.3, 0.0), Vector3(0.0, 6.5, 0.01)]
	var sheet := Image.create(W * views.size(), W * DIRS.size(), false, Image.FORMAT_RGBA8)
	for d in DIRS.size():
		for v in views.size():
			p.reset_to(Vector3(0, 0, 4.0), 0.0)
			o.reset_to(Vector3(0, 0, -14.0), PI)
			p.fuel = 100.0
			await _wait(25)
			match DIRS[d]:
				"forward": p.request_dash(Vector2(0, -1))
				"back": p.request_dash(Vector2(0, 1))
				"left": p.request_dash(Vector2(-1, 0))
				"right": p.request_dash(Vector2(1, 0))
				"up":
					p.request_jump()
					await _wait(12)
					p.request_jump()
			await _wait(8)
			var at := p.global_position + Vector3.UP * 1.1
			cam.global_position = at + views[v]
			cam.look_at(at, Vector3.UP if v < 2 else Vector3.FORWARD)
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(0, 0, W, W), Vector2i(v * W, d * W))
	sheet.save_png(OS.get_cmdline_user_args()[0])
	quit()


func _wait(n: int) -> void:
	for i in n:
		await physics_frame
