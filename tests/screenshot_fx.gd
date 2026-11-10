extends SceneTree
## Renders effects moments in the desktop view: swing trail + hit sparks, block, parry,
## dash blur, getting hit (vignette), rocket explosion. Needs a real window.
## Run: godot --path . -s tests/screenshot_fx.gd -- <output.png>

var vp: SubViewport
var shots: Array[Image] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	InputMode.forced = InputMode.Kind.DESKTOP
	vp = SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	(main.get_node("Session") as SessionManager).auto_start = false
	(main.get_node("DesktopControls") as DesktopControls).capture_mouse = false
	vp.add_child(main)
	var p: Fighter = main.get_node("Player")
	var o: Fighter = main.get_node("Opponent")
	var rig: FighterCamera = main.get_node("CameraRig")
	var brain: DummyBrain = main.get_node("DummyBrain")
	brain.mode = DummyBrain.Mode.IDLE
	await _frames(10)
	p.apply_loadout(SwordDef.striker(), ArmorDef.by_id(&"medium"))
	o.apply_loadout(SwordDef.lancer(), ArmorDef.by_id(&"medium"))

	# 1. Swing trail + hit sparks
	await _setup(p, o, rig, 2.4)
	p.request_attack(&"slash_left")
	await _until(func(): return o.health < o.max_health, 60)
	await _frames(1)
	await _shot()
	# 2. Blocked hit
	await _setup(p, o, rig, 2.4)
	brain.mode = DummyBrain.Mode.BLOCK
	await _frames(25)
	p.request_attack(&"slash_right")
	await _until(func(): return o.stamina < o.max_stamina - 5.0, 60)
	await _frames(2)
	await _shot()
	brain.mode = DummyBrain.Mode.IDLE
	# 3. Parry
	await _setup(p, o, rig, 2.4)
	o.request_attack(&"slash_left")
	await _frames(8)
	p.guard_input = true
	await _until(func(): return o.state == Fighter.State.STAGGER, 60)
	await _frames(2)
	await _shot()
	p.guard_input = false
	# 4. Dash (motion blur + FOV kick + dust)
	await _setup(p, o, rig, 9.0)
	p.request_dash(Vector2(0, -1))
	await _frames(5)
	await _shot()
	# 5. Getting hit (shake + red vignette + aberration)
	await _setup(p, o, rig, 2.4)
	o.request_attack(&"smash")
	await _until(func(): return p.health < p.max_health, 90)
	await _frames(3)
	await _shot()
	# 6. Rocket explosion
	await _setup(p, o, rig, 9.0)
	o.apply_loadout(SwordDef.lancer(), ArmorDef.by_id(&"medium"))
	o.aim_point = p.global_position + Vector3.UP
	o.request_fire()
	await _until(func(): return p.health < p.max_health, 90)
	await _frames(3)
	await _shot()

	var sheet := Image.create(1280 * 3, 720 * 2, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(0, 0, 1280, 720), Vector2i((i % 3) * 1280, (i / 3) * 720))
	sheet.save_png(OS.get_cmdline_user_args()[0])
	quit()


func _setup(p: Fighter, o: Fighter, rig: FighterCamera, dist: float) -> void:
	p.reset_to(Vector3(0, 0, 20 + dist), 0.0)
	o.reset_to(Vector3(0, 0, 20), PI)
	rig.yaw = 0.0
	rig.set_lock_target(o)
	await _frames(40)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _until(cond: Callable, max_frames: int) -> void:
	for i in max_frames:
		if cond.call():
			return
		await physics_frame


func _shot() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	shots.append(img)
