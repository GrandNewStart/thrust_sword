extends SceneTree
## Filmstrip of one attack from the front, the side and above (one row each)
## (needs a real window, not --headless).
## Run: godot --path . -s tests/screenshot_attack.gd -- <attack> <output.png>
## Light-chain steps (light_2, light_3) are played after the steps before them, as in a combo.

const W := 320
const FRAMES := 8

var vp: SubViewport


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var atk := StringName(args[0])
	# A hidden or covered window gets throttled by the OS and the capture crawls: keep it on top.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	vp = SubViewport.new()
	vp.size = Vector2i(W, W)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	(main.get_node("Session") as SessionManager).auto_start = false
	vp.add_child(main)
	main.get_node("UI").queue_free()
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
	cam.fov = 55.0
	var a: AttackDef = p.moveset[atk]
	var total := a.windup + a.active + a.recovery
	var sheet := Image.create(W * FRAMES, W * 3, false, Image.FORMAT_RGBA8)
	var views := [[Vector3(0.0, 1.5, -4.5), Vector3(0, 1.2, 1.6)], [Vector3(6.0, 1.5, 1.4), Vector3(0, 1.2, 1.4)], [Vector3(0.0, 8.0, 1.4), Vector3(0, 0, 1.39)]]
	for v in views.size():
		for i in FRAMES:
			p.move_input = Vector2.ZERO
			p.reset_to(Vector3(0, 0, 2.0), 0.0)
			o.reset_to(Vector3(0, 0, -12.0), PI)
			cam.position = views[v][0]
			cam.look_at(views[v][1])
			await _wait(25)
			await _start(p, atk)
			await _wait(maxi(1, roundi(total * (i + 0.5) / FRAMES * 60.0)))
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(0, 0, W, W), Vector2i(i * W, v * W))
	sheet.save_png(args[1])
	quit()


func _wait(n: int) -> void:
	for i in n:
		await physics_frame


## Start an attack the way it happens in play: later light-chain steps follow the earlier ones.
func _start(p: Fighter, atk: StringName) -> void:
	var step := Movesets.LIGHT_CHAIN.find(atk)
	if step <= 0:
		p.request_attack(atk)
		return
	p.request_attack(&"light")
	for i in 240:
		await physics_frame
		if p.current_attack and p.current_attack.name == atk:
			return
		p.request_attack(&"light")
