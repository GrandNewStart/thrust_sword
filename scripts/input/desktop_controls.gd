class_name DesktopControls
extends Node
## Keyboard + mouse controls. Produces the same PlayerIntent as TouchControls, so the
## gameplay is identical; only the way you express it changes.
##
##   WASD            move            Shift  run
##   double-tap WASD thrust dash     C      dash toward the movement direction
##   Space           jump (hold in the air = vertical thrust)
##   Mouse           camera (while not locked on)
##   LMB click       light attack
##   LMB + flick     directional slash (← → slashes, ↑ thrust, ↓ smash) — like a swipe
##   LMB hold        charge heavy, release to strike
##   RMB             guard (hold) / parry (tap just before a hit)
##   F               fire secondary weapon
##   Tab / MMB       lock on / release
## Key state is tracked from events (not the global Input singleton), so tests can drive it.

@export var mouse_sensitivity := 0.35
## Mouse gesture thresholds (in mouse pixels) — mirror the touch pad's tap / swipe / hold.
@export var tap_max_move := 12.0
@export var swipe_min_distance := 40.0
@export var swipe_max_time := 0.3
@export var hold_time := 0.28
@export var double_tap_time := 0.25

const MOVE_KEYS := {
	KEY_W: Vector2(0, 1), KEY_S: Vector2(0, -1),
	KEY_A: Vector2(-1, 0), KEY_D: Vector2(1, 0),
}

var intent := PlayerIntent.new()
## Off while menus are open: mouse is released and input ignored.
var enabled := true:
	set(v):
		enabled = v
		if not v:
			reset_input()
		_update_mouse_mode()
## Capture the mouse for camera look (off in headless tests).
var capture_mouse := true

var _keys := {}
var _lmb_down := false
var _lmb_time := 0.0
var _lmb_delta := Vector2.ZERO
var _charging := false
var _last_tap_key := -1
var _last_tap_time := -10.0


func _ready() -> void:
	_update_mouse_mode()


func reset_input() -> void:
	_keys.clear()
	_lmb_down = false
	_charging = false
	intent = PlayerIntent.new()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _update_mouse_mode() -> void:
	if not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if enabled and capture_mouse else Input.MOUSE_MODE_VISIBLE


func is_key_down(key: Key) -> bool:
	return _keys.get(key, false)


func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventKey and not event.echo:
		_on_key(event.physical_keycode, event.pressed)
	elif event is InputEventMouseButton:
		# Clicking back into the window re-captures the mouse without attacking.
		if event.pressed and capture_mouse and DisplayServer.get_name() != "headless" \
				and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			_update_mouse_mode()
			return
		_on_mouse_button(event.button_index, event.pressed)
	elif event is InputEventMouseMotion:
		if _lmb_down:
			_lmb_delta += event.relative  # gesture, like a swipe on the touch pad: camera holds still
		else:
			intent.look_delta += event.relative * mouse_sensitivity


func _on_key(key: Key, pressed: bool) -> void:
	_keys[key] = pressed
	if not pressed:
		return
	match key:
		KEY_SPACE:
			intent.jump_pressed = true
		KEY_F:
			intent.fire_pressed = true
		KEY_TAB:
			intent.lock_toggle = true
		KEY_C:
			intent.dashes.append(_move_vector())
	if MOVE_KEYS.has(key):
		var now := _now()
		if key == _last_tap_key and now - _last_tap_time <= double_tap_time:
			intent.dashes.append(MOVE_KEYS[key])
			_last_tap_key = -1
		else:
			_last_tap_key = key
			_last_tap_time = now


func _on_mouse_button(button: MouseButton, pressed: bool) -> void:
	match button:
		MOUSE_BUTTON_LEFT:
			if pressed:
				_lmb_down = true
				_lmb_time = _now()
				_lmb_delta = Vector2.ZERO
			elif _lmb_down:
				_lmb_down = false
				_resolve_gesture()
		MOUSE_BUTTON_RIGHT:
			intent.guard_held = pressed
		MOUSE_BUTTON_MIDDLE:
			if pressed:
				intent.lock_toggle = true


## Left button released: decide light / slash / heavy, exactly like the touch attack pad.
func _resolve_gesture() -> void:
	var age := _now() - _lmb_time
	if _charging:
		_charging = false
		intent.charge_held = false
	elif age <= swipe_max_time and _lmb_delta.length() >= swipe_min_distance:
		var d := _lmb_delta
		if absf(d.x) >= absf(d.y):
			intent.attacks.append(&"slash_right" if d.x > 0.0 else &"slash_left")
		else:
			intent.attacks.append(&"smash" if d.y > 0.0 else &"thrust")
	elif _lmb_delta.length() <= tap_max_move and age < hold_time:
		intent.attacks.append(&"light")


func _move_vector() -> Vector2:
	var v := Vector2.ZERO
	for key in MOVE_KEYS:
		if is_key_down(key):
			v += MOVE_KEYS[key]
	return v.normalized()


func _process(_delta: float) -> void:
	if not enabled:
		return
	intent.move = _move_vector()
	intent.run = is_key_down(KEY_SHIFT)
	intent.jump_held = is_key_down(KEY_SPACE)
	intent.fire_held = is_key_down(KEY_F)
	# Left button held still long enough = charging a heavy attack.
	if _lmb_down and not _charging and _lmb_delta.length() <= tap_max_move and _now() - _lmb_time >= hold_time:
		_charging = true
	intent.charge_held = _charging
