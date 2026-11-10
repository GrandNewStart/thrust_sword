extends SceneTree
## Renders portrait screenshots of key moments (needs a real window, not --headless).
## Run: godot --path . -s tests/screenshot.gd -- <output_dir>

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
	var intent: PlayerIntent = (main.get_node("UI/TouchControls") as TouchControls).intent
	await _frames(30)

	player.reset_to(Vector3(0, 0, 3), 0.0)
	opp.reset_to(Vector3(0, 0, 0), PI)
	rig.yaw = 0.0
	rig.set_lock_target(opp)
	await _frames(30)
	await _shot("idle")

	player.request_attack(&"slash_left")
	await _frames(17)
	await _shot("slash")

	await _frames(60)
	intent.guard_held = true
	opp.request_attack(&"smash")
	await _frames(14)
	await _shot("guard_vs_smash")
	intent.guard_held = false

	await _frames(60)
	intent.charge_held = true
	await _frames(55)
	await _shot("charge")
	intent.charge_held = false
	await _frames(7)
	await _shot("heavy")

	# Step 3: dash, vertical thrust, machine gun, rocket, pickups
	await _frames(60)
	player.reset_to(Vector3(0, 0, 9), 0.0)
	opp.reset_to(Vector3(0, 0, 0), PI)
	await _frames(20)
	player.request_dash(Vector2(0.7, -0.7))
	await _frames(6)
	await _shot("dash")
	await _frames(40)
	intent.jump_pressed = true
	intent.jump_held = true
	await _frames(45)
	await _shot("thrust_up")
	intent.jump_held = false
	await _frames(90)
	intent.fire_held = true
	await _frames(14)
	await _shot("machine_gun")
	intent.fire_held = false
	await _frames(30)
	player.barrel = BarrelDef.rocket()
	player.ammo = 4
	intent.fire_pressed = true
	await _frames(12)
	await _shot("rocket")
	await _frames(10)
	await _shot("rocket_hit")
	rig.set_lock_target(null)
	player.reset_to(Vector3(-6, 0, 6), 0.0)
	rig.yaw = 0.0
	await _frames(30)
	await _shot("pickup")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(out_dir.path_join(shot_name + ".png"))
