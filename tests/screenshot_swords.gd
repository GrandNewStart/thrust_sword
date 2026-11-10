extends SceneTree
## Renders the imported sword models under the game's lighting (needs a real window).
## Run: godot --path . -s tests/screenshot_swords.gd -- <output_dir>

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out_dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	var vp := SubViewport.new()
	vp.size = Vector2i(1200, 900)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	(main.get_node("Session") as SessionManager).auto_start = false
	vp.add_child(main)
	# Hide the fighters and UI; keep the arena, sky and sun.
	for n in ["Player", "Opponent", "UI"]:
		main.get_node(n).queue_free()
	for i in 3:
		var id: String = ["striker", "breaker", "lancer"][i]
		var sword: Node3D = load("res://assets/swords/%s.glb" % id).instantiate()
		main.add_child(sword)
		sword.position = Vector3((i - 1) * 1.4, 1.0, 0)
		sword.rotation_degrees = Vector3(0, 70, 0)
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.position = Vector3(0, 2.3, 4.6)
	cam.look_at(Vector3(0, 2.0, 0))
	cam.fov = 55
	cam.current = true
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(out_dir.path_join("swords_godot.png"))
	quit()
