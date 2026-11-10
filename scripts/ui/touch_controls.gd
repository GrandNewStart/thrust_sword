class_name TouchControls
extends Control
## Portrait two-thumb touch layout.
##   Top area (game view): tap = lock-on, double-tap empty = release, drag = camera.
##   Bottom-left: floating joystick. Push to the edge to run. Double-flick = thrust dash.
##   Bottom-right attack pad:
##     tap            = light attack
##     swipe (flick)  = directional slash (left / right / up = thrust / down = smash)
##     hold, release  = charged heavy attack
##     slow drag      = camera (a swipe undoes its own camera movement)
##   Buttons: GUARD (hold = block, tap just before a hit = parry), FIRE (secondary weapon),
##            JUMP (press again in the air = vertical dash).
## Mouse input is emulated as touch on desktop (see project settings).

## Share of the screen height used by the thumb control zone.
@export_range(0.2, 0.6) var control_zone_ratio := 0.42
@export var joystick_radius := 110.0
@export_range(0.0, 0.5) var joystick_deadzone := 0.12
## Knob distance (0..1 of radius) at which running starts.
@export_range(0.5, 1.0) var run_threshold := 0.95
@export var look_sensitivity := 1.0
@export var tap_max_move := 24.0
@export var double_tap_time := 0.32
@export var double_tap_distance := 90.0
## Holding the pad still this long starts charging. Shorter touches are taps.
@export var hold_time := 0.28
@export var swipe_max_time := 0.3
@export var swipe_min_distance := 50.0
## A flick = stick pushed from near-center to near-edge within this time.
@export var flick_time := 0.15
## Two flicks in roughly the same direction within this time = dash.
@export var double_flick_window := 0.4
@export var double_flick_max_angle_deg := 50.0
## Used only to draw the charge ring.
@export var full_charge_time := 1.0

## Buttons, positioned from the bottom-right corner.
var buttons := {
	&"guard": { "offset": Vector2(100, 150), "radius": 70.0, "label": "GUARD" },
	&"fire": { "offset": Vector2(100, 315), "radius": 56.0, "label": "AIM" },
	&"jump": { "offset": Vector2(255, 85), "radius": 52.0, "label": "JUMP" },
}
## Controls (e.g. HUD buttons) whose area this layer should ignore.
var exclusion_controls: Array[Control] = []

enum Role { NONE, VIEW, JOYSTICK, PAD, BUTTON }

var intent := PlayerIntent.new()
## Set by the player controller. In aim mode the left stick moves the crosshair and the
## attack pad is the trigger.
var aiming := false
## Buttons that are currently hidden (e.g. AIM for a sword without a gun).
var hidden_buttons: Array[StringName] = []
## When false (menus, results screen) touches are ignored and nothing is drawn.
var enabled := true:
	set(v):
		enabled = v
		if not v:
			reset_input()
		visible = v

var _fingers := {}  # index -> finger state dictionary
var _joy_finger := -1
var _joy_base := Vector2.ZERO
var _joy_knob := Vector2.ZERO
var _last_tap_time := -10.0
var _last_tap_pos := Vector2.ZERO
var _tap_count := 0
var _swipe_fx := []  # [{ from, to, t }] for drawing
var _joy_amount := 0.0
var _joy_low_time := -10.0  # last time the stick was near center
var _last_flick_time := -10.0
var _last_flick_dir := Vector2.ZERO
var _dash_fx := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Drop all touches and held inputs (e.g. when a menu opens).
func reset_input() -> void:
	_fingers.clear()
	_joy_finger = -1
	_joy_amount = 0.0
	intent = PlayerIntent.new()
	queue_redraw()


func control_top() -> float:
	return size.y * (1.0 - control_zone_ratio)


func button_center(button: StringName) -> Vector2:
	return size - buttons[button].offset - Vector2(0, SafeArea.insets(self).bottom)


func is_joystick_active() -> bool:
	return _joy_finger != -1


func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		var e := make_input_local(event) as InputEventScreenTouch
		if e.pressed:
			_on_press(e.index, e.position)
		else:
			_on_release(e.index, e.position)
	elif event is InputEventScreenDrag:
		var d := make_input_local(event) as InputEventScreenDrag
		_on_drag(d.index, d.position, d.relative)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func set_button_visible(button: StringName, value: bool) -> void:
	if value:
		hidden_buttons.erase(button)
	elif not hidden_buttons.has(button):
		hidden_buttons.append(button)
	queue_redraw()


func _button_at(pos: Vector2) -> StringName:
	for b in buttons:
		if hidden_buttons.has(b):
			continue
		if pos.distance_to(button_center(b)) <= buttons[b].radius:
			return b
	return &""


func _is_excluded(pos: Vector2) -> bool:
	for c in exclusion_controls:
		if is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().has_point(pos):
			return true
	return false


func _on_press(index: int, pos: Vector2) -> void:
	var f := { "role": Role.NONE, "start": pos, "start_time": _now(), "moved": false,
		"look_applied": Vector2.ZERO, "charging": false, "button": &"" }

	if _is_excluded(pos):
		pass
	elif pos.y < control_top():
		f.role = Role.VIEW
	elif _button_at(pos) != &"":
		f.role = Role.BUTTON
		f.button = _button_at(pos)
		_set_button(f.button, true)
	elif pos.x < size.x * 0.5:
		if _joy_finger == -1:
			f.role = Role.JOYSTICK
			_joy_finger = index
			_joy_base = pos
			_joy_knob = pos
			_joy_amount = 0.0
			_joy_low_time = _now()
	else:
		f.role = Role.PAD
		if aiming:
			intent.fire_pressed = true
			intent.fire_held = true

	_fingers[index] = f
	queue_redraw()


func _on_drag(index: int, pos: Vector2, relative: Vector2) -> void:
	var f: Dictionary = _fingers.get(index, {})
	if f.is_empty():
		return
	if not f.moved and pos.distance_to(f.start) > tap_max_move:
		f.moved = true

	match f.role:
		Role.JOYSTICK:
			_update_joystick(pos)
		Role.PAD:
			if aiming:
				pass  # trigger finger: no camera drag
			elif not f.charging and f.moved:
				var d: Vector2 = relative * look_sensitivity
				intent.look_delta += d
				f.look_applied += d
		Role.VIEW:
			if f.moved:
				intent.look_delta += relative * look_sensitivity
	queue_redraw()


func _on_release(index: int, pos: Vector2) -> void:
	var f: Dictionary = _fingers.get(index, {})
	if f.is_empty():
		return
	_fingers.erase(index)
	var age := _now() - float(f.start_time)

	match f.role:
		Role.JOYSTICK:
			_joy_finger = -1
			_joy_amount = 0.0
			intent.move = Vector2.ZERO
			intent.aim_stick = Vector2.ZERO
			intent.run = false
		Role.BUTTON:
			_set_button(f.button, false)
		Role.VIEW:
			if not f.moved and age <= hold_time:
				_register_tap(pos)
		Role.PAD:
			if aiming or intent.fire_held:
				intent.fire_held = false
				queue_redraw()
				return
			var swipe: Vector2 = pos - f.start
			if f.charging:
				_update_charge_flag()
			elif age <= swipe_max_time and swipe.length() >= swipe_min_distance:
				intent.look_delta -= f.look_applied  # a flick attacks, it doesn't turn the camera
				intent.attacks.append(_swipe_attack(swipe))
				_swipe_fx.append({ "from": f.start, "to": pos, "t": 0.0 })
			elif not f.moved and age < hold_time:
				intent.attacks.append(&"light")
	queue_redraw()


func _process(delta: float) -> void:
	# Turn a still, held pad finger into a charge.
	var now := _now()
	for index in _fingers:
		var f: Dictionary = _fingers[index]
		if f.role == Role.PAD and not aiming and not f.charging and not f.moved and now - float(f.start_time) >= hold_time:
			f.charging = true
			_update_charge_flag()
	_dash_fx = maxf(0.0, _dash_fx - delta)
	for fx in _swipe_fx:
		fx.t += delta
	_swipe_fx = _swipe_fx.filter(func(fx): return fx.t < 0.2)
	queue_redraw()


func _update_charge_flag() -> void:
	var any := false
	for index in _fingers:
		if _fingers[index].role == Role.PAD and _fingers[index].charging:
			any = true
	intent.charge_held = any


func _swipe_attack(swipe: Vector2) -> StringName:
	if absf(swipe.x) >= absf(swipe.y):
		return &"slash_right" if swipe.x > 0.0 else &"slash_left"
	return &"smash" if swipe.y > 0.0 else &"thrust"


func _set_button(button: StringName, held: bool) -> void:
	match button:
		&"guard":
			intent.guard_held = held
		&"jump":
			intent.jump_held = held
			if held:
				intent.jump_pressed = true
		&"fire":
			if held:
				intent.aim_toggle = true


func _is_button_held(button: StringName) -> bool:
	match button:
		&"guard":
			return intent.guard_held
		&"jump":
			return intent.jump_held
		&"fire":
			return aiming
	return false


func _register_tap(pos: Vector2) -> void:
	var now := _now()
	if now - _last_tap_time <= double_tap_time and pos.distance_to(_last_tap_pos) <= double_tap_distance:
		_tap_count += 1
	else:
		_tap_count = 1
	_last_tap_time = now
	_last_tap_pos = pos
	intent.taps.append({ "pos": pos, "count": _tap_count })


func _update_joystick(pos: Vector2) -> void:
	var offset := pos - _joy_base
	# The base follows the finger if it drifts far, so the stick never "runs out".
	var max_drift := joystick_radius * 1.5
	if offset.length() > max_drift:
		_joy_base = pos - offset.normalized() * max_drift
		offset = pos - _joy_base

	var amount := offset.length() / joystick_radius
	var clamped := offset.limit_length(joystick_radius)
	_joy_knob = _joy_base + clamped
	_detect_flick(amount, clamped)
	_joy_amount = amount

	var stick := Vector2.ZERO
	if amount >= joystick_deadzone:
		var v := clamped / joystick_radius
		stick = Vector2(v.x, -v.y)  # screen up = forward / up
	if aiming:
		intent.aim_stick = stick
		intent.move = Vector2.ZERO
		intent.run = false
		return
	intent.move = stick
	intent.run = amount >= run_threshold


func _detect_flick(amount: float, offset: Vector2) -> void:
	var now := _now()
	if amount < 0.35:
		_joy_low_time = now
		return
	var crossed := _joy_amount < 0.85 and amount >= 0.85
	if not crossed or now - _joy_low_time > flick_time:
		return
	var dir := Vector2(offset.x, -offset.y).normalized()  # stick space: y = forward
	var angle := rad_to_deg(absf(dir.angle_to(_last_flick_dir)))
	if now - _last_flick_time <= double_flick_window and angle <= double_flick_max_angle_deg:
		intent.dashes.append(dir)
		_last_flick_time = -10.0
		_dash_fx = 0.25
	else:
		_last_flick_time = now
		_last_flick_dir = dir


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var top := control_top()

	# Control zone divider
	draw_line(Vector2(0, top), Vector2(size.x, top), Color(1, 1, 1, 0.12), 2.0)
	draw_line(Vector2(size.x * 0.5, top + 30), Vector2(size.x * 0.5, size.y - 30), Color(1, 1, 1, 0.06), 2.0)

	# Joystick
	if is_joystick_active():
		var knob_color := Color(1.0, 0.6, 0.2, 0.85) if intent.run else Color(0.4, 0.85, 1.0, 0.8)
		draw_arc(_joy_base, joystick_radius, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
		draw_circle(_joy_knob, 46, knob_color)
		if _dash_fx > 0.0:
			draw_arc(_joy_base, joystick_radius + 20.0 * (1.0 - _dash_fx / 0.25), 0, TAU, 48, Color(1.0, 0.6, 0.2, _dash_fx * 4.0), 6.0)
	else:
		var ghost := Vector2(size.x * 0.25, size.y - 230 - SafeArea.insets(self).bottom)
		draw_arc(ghost, joystick_radius, 0, TAU, 48, Color(1, 1, 1, 0.12), 2.0)
		draw_string(font, ghost + Vector2(-40, 8), "MOVE", HORIZONTAL_ALIGNMENT_CENTER, 80, 22, Color(1, 1, 1, 0.25))

	# Attack pad hint
	var hint_pos := Vector2(size.x * 0.5, top + 46)
	if aiming:
		draw_string(font, hint_pos, "TAP / HOLD = FIRE", HORIZONTAL_ALIGNMENT_CENTER, size.x * 0.5, 20, Color(1, 0.8, 0.5, 0.5))
		draw_string(font, hint_pos + Vector2(0, 26), "left stick = aim", HORIZONTAL_ALIGNMENT_CENTER, size.x * 0.5, 16, Color(1, 0.8, 0.5, 0.35))
	else:
		draw_string(font, hint_pos, "TAP · SWIPE · HOLD", HORIZONTAL_ALIGNMENT_CENTER, size.x * 0.5, 20, Color(1, 1, 1, 0.22))
		draw_string(font, hint_pos + Vector2(0, 26), "slow drag = camera", HORIZONTAL_ALIGNMENT_CENTER, size.x * 0.5, 16, Color(1, 1, 1, 0.15))

	# Charge ring under a held finger
	var now := _now()
	for index in _fingers:
		var f: Dictionary = _fingers[index]
		if f.role == Role.PAD and f.charging:
			var r := clampf((now - float(f.start_time) - hold_time) / full_charge_time, 0.0, 1.0)
			var c := Color(1.0, 0.55, 0.15, 0.9) if r >= 1.0 else Color(1, 1, 1, 0.7)
			draw_arc(f.start, 64, -PI / 2, -PI / 2 + TAU * r, 48, c, 6.0)

	# Swipe trails
	for fx in _swipe_fx:
		var a: float = 1.0 - fx.t / 0.2
		draw_line(fx.from, fx.to, Color(1, 1, 1, 0.7 * a), 10.0 * a + 2.0)

	# Buttons
	for b in buttons:
		if hidden_buttons.has(b):
			continue
		var c := button_center(b)
		var r: float = buttons[b].radius
		var held := _is_button_held(b)
		draw_circle(c, r, Color(1, 1, 1, 0.3 if held else 0.12))
		draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.5), 3.0)
		var fs := 22 if r > 60 else 18
		draw_string(font, c + Vector2(-r, fs * 0.35), buttons[b].label, HORIZONTAL_ALIGNMENT_CENTER, r * 2, fs, Color(1, 1, 1, 0.8))
