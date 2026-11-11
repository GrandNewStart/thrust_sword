class_name Hud
extends Control
## Health/stamina bars, round timer and wins, center banners, lock-on reticle,
## combat popups, hints and a low-health warning.

@export var camera_rig: FighterCamera
@export var player: Fighter
@export var opponent: Fighter
@export var session: SessionManager
@export var show_debug := false

const POPUP_TIME := 0.8

## Own random stream: cosmetic jitter must not change gameplay / AI rolls.
var _rng := RandomNumberGenerator.new()
var _popups := []  # [{ text, color, pos: Vector3, t }]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep redrawing under pause menus (hides stale hints)
	for f in [player, opponent]:
		if f:
			f.combat_event.connect(_on_combat_event.bind(f))


func _on_combat_event(text: String, color: Color, f: Fighter) -> void:
	var jitter := Vector3(_rng.randf_range(-0.3, 0.3), 0, 0)
	_popups.append({ "text": text, "color": color, "pos": f.global_position + Vector3.UP * 2.3 + jitter, "t": 0.0 })


func _process(delta: float) -> void:
	for p in _popups:
		p.t += delta
	_popups = _popups.filter(func(p): return p.t < POPUP_TIME)
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	# Bars, timer and hints live in a column at most 760 px wide, centred (landscape desktop).
	var w := minf(size.x, 760.0)
	var x0 := (size.x - w) * 0.5
	var top_hud := Vector2(x0, 0)
	_draw_low_health_warning()
	draw_set_transform(top_hud)

	# Opponent health (top)
	if opponent:
		var label := "OPPONENT" + _loadout_text(opponent)
		draw_string(font, Vector2(24, 34), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.7, 0.65, 0.9))
		_draw_wins(Vector2(24 + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 16, 28),
			session.opponent_wins if session else 0, Color(1, 0.45, 0.4))
		_bar(Rect2(24, 44, w - 48, 16), opponent.health / opponent.max_health, Color(0.9, 0.25, 0.2))

	# Player health + stamina
	if player:
		var label := "YOU" + _loadout_text(player)
		draw_string(font, Vector2(24, 92), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 1, 0.75, 0.9))
		_draw_wins(Vector2(24 + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 16, 86),
			session.player_wins if session else 0, Color(0.45, 1, 0.55))
		_bar(Rect2(24, 102, w * 0.55, 16), player.health / player.max_health, Color(0.3, 0.85, 0.4))
		var stamina_color := Color(0.95, 0.8, 0.25) if player.stamina > 0.0 else Color(0.6, 0.3, 0.2)
		_bar(Rect2(24, 124, w * 0.45, 10), player.stamina / player.max_stamina, stamina_color)
		var fuel_color := Color(1.0, 0.55, 0.15) if player.fuel > 0.0 else Color(0.4, 0.25, 0.2)
		_bar(Rect2(24, 140, w * 0.45, 10), player.fuel / player.max_fuel, fuel_color)
		var x := 24 + w * 0.45 + 10
		draw_string(font, Vector2(x, 134), "STA", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.45))
		draw_string(font, Vector2(x, 150), "FUEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.45))
		if player.barrel.has_gun():
			var ammo_color := Color(0.5, 0.9, 1.0) if player.ammo > 0 else Color(1, 0.4, 0.3)
			draw_string(font, Vector2(x + 50, 150), "AMMO %d/%d" % [player.ammo, player.barrel.max_ammo],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ammo_color)

	# Round timer (top right)
	if _in_match():
		var secs := ceili(session.time_left)
		var timer_color := Color(1, 0.4, 0.35) if secs <= 10 else Color(1, 1, 1, 0.9)
		draw_string(font, Vector2(0, 36), str(secs), HORIZONTAL_ALIGNMENT_RIGHT, w - 24, 32, timer_color)

	# Lock-on reticle + hint
	var hint := "Tab / middle mouse: lock on"
	var aiming := player != null and player.aiming
	var hint_color := Color(1, 1, 1, 0.5)
	if aiming:
		hint = "AIMING · mouse = aim, LMB = fire · F to exit"
		hint_color = Color(1, 0.8, 0.45, 0.9)
	elif camera_rig and camera_rig.is_locked():
		hint = "LOCKED · Tab to release"
		hint_color = Color(1, 0.6, 0.55, 0.8)
		var cam := camera_rig.camera
		var p := camera_rig.lock_target.global_position + Vector3.UP * 1.0
		draw_set_transform(Vector2.ZERO)
		if not cam.is_position_behind(p):
			var s := cam.unproject_position(p)
			var c := Color(1.0, 0.35, 0.3, 0.9)
			for i in 4:
				var a := TAU * i / 4.0 + PI / 4.0
				draw_arc(s, 56.0, a - 0.35, a + 0.35, 10, c, 4.0)
			draw_circle(s, 5.0, c)
		draw_set_transform(top_hud)
	draw_string(font, Vector2(0, 182), hint, HORIZONTAL_ALIGNMENT_CENTER, w, 18, hint_color)
	draw_set_transform(Vector2.ZERO)

	# Combat popups
	if camera_rig:
		var cam := camera_rig.camera
		for p in _popups:
			var world: Vector3 = p.pos + Vector3.UP * p.t * 0.8
			if cam.is_position_behind(world):
				continue
			var s := cam.unproject_position(world)
			var c: Color = p.color
			c.a = 1.0 - p.t / POPUP_TIME
			var fs := 34 if p.text.begins_with("-") else 30
			draw_string_outline(font, s + Vector2(-150, 0), p.text, HORIZONTAL_ALIGNMENT_CENTER, 300, fs, 6, Color(0, 0, 0, c.a * 0.7))
			draw_string(font, s + Vector2(-150, 0), p.text, HORIZONTAL_ALIGNMENT_CENTER, 300, fs, c)

	if aiming:
		_draw_crosshair()
	_draw_banner(font)
	var in_menu := session != null and session.phase in [SessionManager.Phase.SETUP, SessionManager.Phase.MATCH_END]
	if not in_menu:
		_draw_desktop_help(font)

	if show_debug and player:
		var text := "speed %.1f  state %s" % [player.horizontal_speed(), Fighter.State.keys()[player.state]]
		draw_string(font, Vector2(24, 200), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.5))


const DESKTOP_HELP := [
	"WASD move · Shift run · double-tap = dash",
	"LMB light · LMB+flick slash · hold LMB charge",
	"RMB guard / parry · Space jump (again in air: boost) · F aim mode",
	"Tab lock-on · Esc menu",
]


func _draw_desktop_help(font: Font) -> void:
	var y := size.y - 20.0 - DESKTOP_HELP.size() * 22.0
	for line in DESKTOP_HELP:
		draw_string(font, Vector2(20, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.45))
		y += 22.0


## Screen-centre crosshair for aim mode. The ring shows the weapon's spread.
func _draw_crosshair() -> void:
	var c := size * 0.5
	var col := Color(1, 1, 1, 0.9)
	var shadow := Color(0, 0, 0, 0.5)
	var gap := 7.0
	var arm := 14.0
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + d * gap, c + d * (gap + arm), shadow, 5.0)
		draw_line(c + d * gap, c + d * (gap + arm), col, 2.0)
	draw_circle(c, 2.0, col)
	if player and player.barrel.spread_deg > 0.0 and camera_rig:
		# Spread cone radius on screen at this FOV.
		var px := tan(deg_to_rad(player.barrel.spread_deg)) / tan(deg_to_rad(camera_rig.camera.fov * 0.5)) * size.y * 0.5
		draw_arc(c, maxf(px, gap + 2.0), 0, TAU, 32, Color(1, 1, 1, 0.35), 1.5)
	if player and player.ammo <= 0:
		draw_string(ThemeDB.fallback_font, c + Vector2(-60, 46), "NO AMMO", HORIZONTAL_ALIGNMENT_CENTER, 120, 18, Color(1, 0.4, 0.3, 0.9))


func _in_match() -> bool:
	return session != null and session.mode == SessionManager.Mode.MATCH \
		and session.phase != SessionManager.Phase.SETUP


## Round-win markers: one circle per round needed, filled when won.
func _draw_wins(pos: Vector2, wins: int, color: Color) -> void:
	if not _in_match():
		return
	for i in session.rounds_to_win:
		var c := pos + Vector2(i * 20 + 6, 0)
		if i < wins:
			draw_circle(c, 7, color)
		else:
			draw_arc(c, 7, 0, TAU, 20, Color(1, 1, 1, 0.4), 2.0)


## Big center text: round intro, countdown, K.O., results. Pops in, short ones fade out.
func _draw_banner(font: Font) -> void:
	if session == null or session.banner == "":
		return
	var text := session.banner
	var age := (Time.get_ticks_msec() - session.banner_set_ms) / 1000.0
	var alpha := 1.0
	if text == "FIGHT!" or text == "TRAINING":
		alpha = clampf(1.0 - (age - 0.6) / 0.3, 0.0, 1.0)
	if alpha <= 0.0:
		return
	var pop := 1.0 + 0.4 * clampf(1.0 - age / 0.15, 0.0, 1.0)
	var fs := 110 if text.length() <= 2 else 76
	var color := Color(1, 0.85, 0.3, alpha)
	match text:
		"K.O.", "ROUND LOST":
			color = Color(1, 0.4, 0.35, alpha)
		"ROUND WON", "FIGHT!":
			color = Color(0.5, 1, 0.6, alpha)
	var center := Vector2(size.x * 0.5, size.y * 0.32)
	draw_set_transform(center, 0.0, Vector2.ONE * pop)
	var half := size.x * 0.5
	draw_string_outline(font, Vector2(-half, fs * 0.35), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, 12, Color(0, 0, 0, 0.7 * alpha))
	draw_string(font, Vector2(-half, fs * 0.35), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, color)
	draw_set_transform(Vector2.ZERO)


## Pulsing red screen edges when the player is low on health.
func _draw_low_health_warning() -> void:
	if player == null or not player.is_alive() or player.health / player.max_health > 0.25:
		return
	var a := 0.18 + 0.12 * sin(Time.get_ticks_msec() / 1000.0 * 6.0)
	var c := Color(1, 0.1, 0.05, a)
	var t := 28.0
	draw_rect(Rect2(0, 0, size.x, t), c)
	draw_rect(Rect2(0, size.y - t, size.x, t), c)
	draw_rect(Rect2(0, 0, t, size.y), c)
	draw_rect(Rect2(size.x - t, 0, t, size.y), c)


func _loadout_text(f: Fighter) -> String:
	if f.sword == null or f.armor == null:
		return ""
	return "  ·  %s / %s" % [f.sword.display_name, f.armor.display_name]


func _bar(rect: Rect2, ratio: float, color: Color) -> void:
	draw_rect(rect, Color(0, 0, 0, 0.45))
	var fill := rect
	fill.size.x *= clampf(ratio, 0.0, 1.0)
	draw_rect(fill, color)
	draw_rect(rect, Color(1, 1, 1, 0.25), false, 1.5)
