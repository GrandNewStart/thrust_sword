extends SceneTree
## Shared setup for automated tests. Runs the game in a fixed 720x1280 portrait
## viewport (headless has no real window) and drives it with simulated touches.
## Subclasses implement _run() and call finish() at the end.

var _failures := 0
var vp: SubViewport
var main: Node
var player: Fighter
var opponent: Fighter
var rig: FighterCamera
var controls: TouchControls
var brain: DummyBrain
var manager: SessionManager


func _initialize() -> void:
	seed(20261110)  # AI and weapon spread use randomness; keep test runs repeatable
	vp = SubViewport.new()
	vp.size = Vector2i(720, 1280)
	root.add_child(vp)
	InputMode.forced = _input_kind()
	main = load("res://scenes/main.tscn").instantiate()
	# Keep built-in default stats unless a test applies loadouts itself.
	(main.get_node("Session") as SessionManager).auto_start = false
	vp.add_child(main)
	player = main.get_node("Player")
	opponent = main.get_node("Opponent")
	rig = main.get_node("CameraRig")
	controls = main.get_node("UI/TouchControls")
	brain = main.get_node("DummyBrain")
	brain.rng.seed = 20261110
	player.rng.seed = 1
	opponent.rng.seed = 2
	manager = main.get_node("Session")
	_run.call_deferred()
	create_timer(90.0).timeout.connect(func(): print("TIMEOUT"); quit(2))


func _run() -> void:
	pass


## Which control scheme the test drives. Override in desktop tests.
func _input_kind() -> InputMode.Kind:
	return InputMode.Kind.TOUCH


func finish() -> void:
	print("\n%s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures else 0)


func check(ok: bool, label: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		_failures += 1


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	vp.push_input(e, true)


func drag(index: int, pos: Vector2, relative: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	e.relative = relative
	vp.push_input(e, true)


func key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	vp.push_input(e, true)


func key_tap(code: Key) -> void:
	key(code, true)
	key(code, false)


func mouse_button(button: MouseButton, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = Vector2(640, 360)
	vp.push_input(e, true)


func mouse_move(relative: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.relative = relative
	e.position = Vector2(640, 360)
	vp.push_input(e, true)


## Point the camera so the crosshair (screen centre) sits on `target`'s chest (aim mode).
func aim_at(target: Node3D, height := 1.1) -> void:
	for i in 5:
		var to := target.global_position + Vector3.UP * height - rig.camera.global_position
		rig.yaw = FighterCamera.yaw_towards(to)
		rig.pitch = atan2(to.y, Vector2(to.x, to.z).length())
		await frames(2)


func tap(index: int, pos: Vector2) -> void:
	touch(index, pos, true)
	touch(index, pos, false)


func swipe(index: int, from: Vector2, delta: Vector2) -> void:
	touch(index, from, true)
	drag(index, from + delta, delta)
	touch(index, from + delta, false)
