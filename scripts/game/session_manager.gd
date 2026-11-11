class_name SessionManager
extends Node
## Runs a play session.
##   MATCH    — best-of-3 rounds with a timer, intro countdown, K.O. slow-mo, results screen.
##   TRAINING — endless; fighters reset a moment after a K.O.
## Loadouts, AI mode and session mode come from the SETUP menu.

signal phase_changed

enum Mode { MATCH, TRAINING }
enum Phase { SETUP, INTRO, FIGHT, ROUND_END, MATCH_END }
enum Outcome { NONE, PLAYER, OPPONENT, DRAW }

@export var player: Fighter
@export var opponent: Fighter
@export var brain: DummyBrain
@export var camera_rig: FighterCamera
@export var menu: LoadoutMenu
@export var result_panel: ResultPanel
## Turns player input on/off around menus.
@export var player_controller: PlayerController
## Open the SETUP menu on launch. Tests turn this off: training mode with built-in default stats.
@export var auto_start := true

@export_group("Match rules")
@export var round_time := 75.0
@export var rounds_to_win := 2
## Draw rounds don't count; the match ends after this many rounds regardless.
@export var max_rounds := 5
@export var training_reset_delay := 2.5

var mode := Mode.TRAINING
var phase := Phase.FIGHT
var round_number := 0
var player_wins := 0
var opponent_wins := 0
var time_left := 0.0
var last_round_outcome := Outcome.NONE
## Big center text for the HUD, and when it was set (real time, ms).
var banner := ""
var banner_set_ms := 0

var _player_start: Transform3D
var _opponent_start: Transform3D
var _flow := 0  # bumped on every restart so stale timers do nothing


func _ready() -> void:
	_player_start = player.global_transform
	_opponent_start = opponent.global_transform
	player.defeated.connect(_on_defeated)
	opponent.defeated.connect(_on_defeated)
	menu.confirmed.connect(_on_setup_confirmed)
	result_panel.rematch_pressed.connect(start_match)
	result_panel.setup_pressed.connect(open_setup)
	if auto_start:
		apply_setup()
		open_setup.call_deferred()


# ---------------------------------------------------------------- setup

func _unhandled_input(event: InputEvent) -> void:
	# Desktop: Esc opens the setup menu (and releases the mouse).
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if phase != Phase.SETUP:
			open_setup()


func _set_input(value: bool) -> void:
	player_controller.set_input_enabled(value)


func open_setup() -> void:
	_flow += 1
	Engine.time_scale = 1.0
	result_panel.visible = false
	_set_input(false)
	_set_phase(Phase.SETUP)
	get_tree().paused = true
	menu.open()


func _on_setup_confirmed() -> void:
	get_tree().paused = false
	_set_input(true)
	apply_setup()
	mode = menu.mode
	if mode == Mode.MATCH:
		start_match()
	else:
		start_training()


func apply_setup() -> void:
	player.apply_loadout(SwordDef.by_id(menu.player_sword), ArmorDef.by_id(menu.player_armor))
	opponent.apply_loadout(SwordDef.by_id(menu.opponent_sword), ArmorDef.by_id(menu.opponent_armor))
	brain.mode = menu.ai_mode


# ---------------------------------------------------------------- training

func start_training() -> void:
	_flow += 1
	mode = Mode.TRAINING
	result_panel.visible = false
	_set_input(true)
	reset_fighters()
	_set_controllable(true)
	_show_banner("TRAINING")
	_set_phase(Phase.FIGHT)


# ---------------------------------------------------------------- match

func start_match() -> void:
	_flow += 1
	mode = Mode.MATCH
	result_panel.visible = false
	_set_input(true)
	player_wins = 0
	opponent_wins = 0
	round_number = 0
	_next_round()


func _next_round() -> void:
	var flow := _flow
	round_number += 1
	last_round_outcome = Outcome.NONE
	reset_fighters()
	time_left = round_time
	_set_controllable(false)
	_set_phase(Phase.INTRO)

	_show_banner("ROUND %d" % round_number if round_number < max_rounds else "FINAL ROUND")
	if not await _wait(1.1, flow):
		return
	for n in ["3", "2", "1"]:
		_show_banner(n)
		if not await _wait(0.5, flow):
			return
	_show_banner("FIGHT!")
	_set_controllable(true)
	_set_phase(Phase.FIGHT)


func _physics_process(delta: float) -> void:
	if mode == Mode.MATCH and phase == Phase.FIGHT:
		time_left = maxf(0.0, time_left - delta)
		if time_left <= 0.0:
			_end_round(true)


func _on_defeated() -> void:
	if mode == Mode.TRAINING:
		var flow := _flow
		if await _wait(training_reset_delay, flow):
			reset_fighters()
	elif phase == Phase.FIGHT:
		_end_round(false)


func _end_round(timeout: bool) -> void:
	var flow := _flow
	_set_phase(Phase.ROUND_END)

	var outcome := Outcome.DRAW
	if timeout:
		var p := player.health / player.max_health
		var o := opponent.health / opponent.max_health
		if absf(p - o) > 0.001:
			outcome = Outcome.PLAYER if p > o else Outcome.OPPONENT
	elif player.is_alive() != opponent.is_alive():
		outcome = Outcome.PLAYER if player.is_alive() else Outcome.OPPONENT
	last_round_outcome = outcome
	match outcome:
		Outcome.PLAYER:
			player_wins += 1
		Outcome.OPPONENT:
			opponent_wins += 1

	if timeout:
		_set_controllable(false)
		_show_banner("TIME")
		if not await _wait(1.2, flow):
			return
	else:
		# K.O.: brief slow motion, then freeze.
		_show_banner("K.O.")
		Engine.time_scale = 0.3
		if not await _wait(1.0, flow):
			return
		Engine.time_scale = 1.0
		_set_controllable(false)

	match outcome:
		Outcome.PLAYER:
			_show_banner("ROUND WON")
		Outcome.OPPONENT:
			_show_banner("ROUND LOST")
		_:
			_show_banner("DRAW")
	if not await _wait(1.6, flow):
		return

	var decided := player_wins >= rounds_to_win or opponent_wins >= rounds_to_win
	if decided or round_number >= max_rounds:
		_end_match()
	else:
		_next_round()


func _end_match() -> void:
	_set_phase(Phase.MATCH_END)
	_show_banner("")
	_set_input(false)
	var title := "DRAW"
	var color := Color(0.85, 0.85, 0.9)
	if player_wins > opponent_wins:
		title = "VICTORY"
		color = Color(0.5, 1.0, 0.6)
	elif opponent_wins > player_wins:
		title = "DEFEAT"
		color = Color(1.0, 0.45, 0.4)
	result_panel.show_result(title, color, "%d  –  %d" % [player_wins, opponent_wins])


func match_result() -> Outcome:
	if phase != Phase.MATCH_END:
		return Outcome.NONE
	if player_wins == opponent_wins:
		return Outcome.DRAW
	return Outcome.PLAYER if player_wins > opponent_wins else Outcome.OPPONENT


# ---------------------------------------------------------------- helpers

func reset_fighters() -> void:
	Engine.time_scale = 1.0
	player.reset_to(_player_start.origin, _player_start.basis.get_euler().y)
	opponent.reset_to(_opponent_start.origin, _opponent_start.basis.get_euler().y)
	if camera_rig and not camera_rig.is_locked():
		camera_rig.yaw = player.rotation.y
	for node in get_tree().get_nodes_in_group("projectiles"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("pickups"):
		(node as Pickup).reset_pickup()


func _set_controllable(value: bool) -> void:
	player.controllable = value
	opponent.controllable = value


func _set_phase(p: Phase) -> void:
	phase = p
	phase_changed.emit()


func _show_banner(text: String) -> void:
	banner = text
	banner_set_ms = Time.get_ticks_msec()


## Waits in real time (unaffected by slow motion). Returns false if the session restarted meanwhile.
func _wait(seconds: float, flow: int) -> bool:
	await get_tree().create_timer(seconds, true, false, true).timeout
	return flow == _flow
