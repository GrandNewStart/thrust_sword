extends SceneTree
## Contact sheet of character animations per combat state, from a side camera
## (needs a real window, not --headless).
## Run: godot --path . -s tests/screenshot_anims.gd -- <output.png>

var vp: SubViewport
var frames: Array[Image] = []
var labels: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(400, 400)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	(main.get_node("Session") as SessionManager).auto_start = false
	vp.add_child(main)
	main.get_node("UI").queue_free()
	var p: Fighter = main.get_node("Player")
	var o: Fighter = main.get_node("Opponent")
	(main.get_node("PlayerController") as Node).queue_free()
	(main.get_node("DummyBrain") as Node).queue_free()
	await _wait(10)
	p.apply_loadout(SwordDef.lancer(), ArmorDef.by_id(&"medium"))
	o.apply_loadout(SwordDef.breaker(), ArmorDef.by_id(&"medium"))
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true

	for atk in [&"light", &"slash_left", &"slash_right", &"thrust", &"smash", &"heavy"]:
		var a: AttackDef = p.moveset[atk]
		for phase in [0.6, 1.0, 1.6]:  # late windup, contact, recovery
			await _reset(p, o, cam)
			p.request_attack(atk)
			var t: float = a.windup * phase if phase < 1.0 else (a.windup + a.active * 0.5 if phase == 1.0 else a.windup + a.active + a.recovery * 0.5)
			await _wait_time(t)
			await _shot("%s %s" % [atk, ["windup", "hit", "recover"][[0.6, 1.0, 1.6].find(phase)]])

	await _reset(p, o, cam); p.guard_input = true; await _wait(20); await _shot("guard"); p.guard_input = false
	await _reset(p, o, cam); p.charge_input = true; await _wait(40); await _shot("charge"); p.charge_input = false
	await _reset(p, o, cam); o.request_attack(&"slash_left"); await _wait(35); await _shot("hit react")
	await _reset(p, o, cam); p.health = 1; o.request_attack(&"slash_left"); await _wait(80); await _shot("K.O.")
	await _reset(p, o, cam); p.request_jump(); await _wait(18); await _shot("jump")
	await _reset(p, o, cam); p.move_input = Vector2(0, -1); p.wants_run = true; await _wait(40); await _shot("run")
	await _reset(p, o, cam); p.request_fire(); await _wait(6); await _shot("fire")
	await _reset(p, o, cam); p.request_dash(Vector2(0, -1)); await _wait(6); await _shot("dash")

	# Contact sheet: 6 columns.
	var cols := 6
	var rows := ceili(frames.size() / float(cols))
	var sheet := Image.create(400 * cols, 400 * rows, false, Image.FORMAT_RGBA8)
	for i in frames.size():
		sheet.blit_rect(frames[i], Rect2i(0, 0, 400, 400), Vector2i((i % cols) * 400, (i / cols) * 400))
	sheet.save_png(OS.get_cmdline_user_args()[0])
	print("LABELS ", labels)
	quit()


func _reset(p: Fighter, o: Fighter, cam: Camera3D) -> void:
	p.move_input = Vector2.ZERO
	p.wants_run = false
	p.reset_to(Vector3(0, 0, 2.5), 0.0)
	o.reset_to(Vector3(0, 0, 0), PI)
	cam.position = Vector3(5.5, 1.6, 1.2)
	cam.look_at(Vector3(0, 1.1, 1.2))
	await _wait(25)


func _wait(n: int) -> void:
	for i in n:
		await physics_frame


func _wait_time(t: float) -> void:
	await _wait(maxi(1, roundi(t * 60.0)))


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	frames.append(img)
	labels.append(label)
