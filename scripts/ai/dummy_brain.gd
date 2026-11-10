class_name DummyBrain
extends Node
## Training partner. Controls a Fighter through the same orders the player uses.
## Modes:
##   IDLE   — stands still
##   BLOCK  — always guards
##   ATTACK — walks in and attacks relentlessly
##   SPAR   — fights properly: spacing, reactions (guard / parry / dodge) with a human-like
##            delay, punishes recovery, dash attacks, guns, stamina and fuel management.

enum Mode { IDLE, BLOCK, ATTACK, SPAR }

@export var fighter: Fighter
@export var target: Fighter
@export var mode := Mode.IDLE

@export_group("Attack mode")
@export var attack_range := 2.6
@export var attack_interval := Vector2(1.0, 1.8)

@export_group("Spar mode")
## Seconds before reacting to an attack it sees coming.
@export var reaction_time := 0.22
@export_range(0, 1) var parry_chance := 0.35
@export_range(0, 1) var guard_chance := 0.4
@export_range(0, 1) var dodge_chance := 0.2
@export var preferred_range := 4.5
## Average seconds between attack attempts in neutral.
@export var attack_tempo := 1.6

var _cooldown := 1.0
var _charging := 0.0
var _burst := 0.0

# Spar state
var _seen_attack: AttackDef
var _react_in := 0.0
var _plan := &""
var _guard_hold := 0.0
var _strafe_sign := 1.0
var _strafe_switch := 2.0
var _combo_left := 0
var _dash_attack_pending := 0.0
var _retreat := 0.0
var _was_hit := false

const ATTACKS := [&"light", &"light", &"slash_left", &"slash_right", &"smash", &"thrust"]


func _ready() -> void:
	process_physics_priority = -10  # give orders before the fighters tick
	if fighter:
		fighter.got_hit.connect(func(blocked: bool): _was_hit = not blocked)


static func mode_name(m: Mode) -> String:
	return ["IDLE", "BLOCK", "ATTACK", "SPAR"][m]


func _physics_process(delta: float) -> void:
	if fighter == null or target == null:
		return
	fighter.move_input = Vector2.ZERO
	fighter.wants_run = false
	fighter.guard_input = false
	fighter.charge_input = false
	fighter.fire_input = false
	fighter.thrust_input = false
	fighter.aim_point = target.global_position + Vector3.UP
	if not fighter.is_alive() or not target.is_alive():
		return

	var to := target.global_position - fighter.global_position
	to.y = 0.0
	if mode != Mode.IDLE:
		fighter.desired_yaw = FighterCamera.yaw_towards(to)

	match mode:
		Mode.BLOCK:
			fighter.guard_input = true
		Mode.ATTACK:
			_attack_mode(to, delta)
		Mode.SPAR:
			_spar(to, delta)


# ---------------------------------------------------------------- ATTACK mode

func _attack_mode(to: Vector3, delta: float) -> void:
	var dist := to.length()
	if dist > attack_range:
		var dir := to.normalized()
		fighter.move_input = Vector2(dir.x, dir.z)
		fighter.wants_run = dist > 8.0
		# Close distance with a dash now and then; shoot a burst at range.
		if dist > 7.0 and fighter.fuel > 30.0 and randf() < delta * 0.6:
			fighter.request_dash(Vector2(dir.x, dir.z))
		if dist > 6.0 and fighter.ammo > 0:
			_burst = maxf(_burst, 0.0)
			if _burst <= 0.0 and randf() < delta * 0.4:
				_burst = 0.6
				fighter.request_fire()
	if _burst > 0.0:
		_burst -= delta
		fighter.fire_input = true

	if _charging > 0.0:
		_charging -= delta
		fighter.charge_input = _charging > 0.0
		return

	_cooldown -= delta
	if _cooldown <= 0.0 and dist <= attack_range + 0.4 and fighter.state == Fighter.State.FREE:
		_cooldown = randf_range(attack_interval.x, attack_interval.y)
		if randf() < 0.15:
			_charging = randf_range(0.5, 1.1)  # charged heavy
			fighter.charge_input = true
		else:
			fighter.request_attack(ATTACKS.pick_random())


# ---------------------------------------------------------------- SPAR mode

func _spar(to: Vector3, delta: float) -> void:
	var me := fighter
	var foe := target
	var dist := to.length()
	var dir := to.normalized() if dist > 0.01 else -me.forward()
	var side := Vector3(-dir.z, 0.0, dir.x) * _strafe_sign

	# 1. React to incoming melee attacks.
	_watch_attacks(dist)
	if _plan != &"" and _seen_attack:
		_react_in -= delta
		if _react_in <= 0.0:
			_execute_plan(dir, side)

	# Incoming fire: sometimes raise guard.
	if foe.since_shot < 0.1 and dist > 4.0 and _guard_hold <= 0.0 and randf() < guard_chance * 0.15:
		_guard_hold = 0.5

	# Got hit: once able to act again, often turtle up to break the combo.
	if _was_hit and me.state == Fighter.State.FREE:
		_was_hit = false
		if randf() < guard_chance + 0.2:
			_guard_hold = randf_range(0.4, 0.8)

	# Standing in the foe's range: fast attacks can't be reacted to, so anticipate.
	var foe_reach: float = foe.moveset[&"light"].reach + 0.6
	if dist <= foe_reach and me.state == Fighter.State.FREE and _guard_hold <= 0.0 \
			and randf() < delta * 2.0 * guard_chance:
		_guard_hold = randf_range(0.35, 0.7)

	if _guard_hold > 0.0:
		_guard_hold -= delta
		# Keep the guard up while an attack string is still coming.
		if foe.state == Fighter.State.ATTACK:
			_guard_hold = maxf(_guard_hold, 0.1)
		me.guard_input = true
		me.move_input = Vector2(-dir.x, -dir.z) * 0.3
		return

	# Charging a heavy: hold it, then let go.
	if _charging > 0.0:
		_charging -= delta
		me.charge_input = _charging > 0.0
		return

	# 2. Combos: keep pressing while the current attack is in recovery.
	if _combo_left > 0 and me.state == Fighter.State.ATTACK and me.attack_phase() == 2:
		me.request_attack([&"light", &"slash_left", &"slash_right"].pick_random())
		_combo_left -= 1

	# Dash attack: attack shortly after a dash starts.
	if _dash_attack_pending > 0.0:
		_dash_attack_pending -= delta
		if me.state == Fighter.State.DASH and _dash_attack_pending <= 0.0:
			me.request_attack([&"light", &"thrust"].pick_random())

	if me.state != Fighter.State.FREE:
		return

	var reach: float = me.moveset[&"light"].reach

	# 3. Punish: foe is stunned or stuck in recovery and close.
	var foe_open := foe.state == Fighter.State.STAGGER or foe.attack_phase() == 2
	if foe_open and dist <= reach + 0.8 and me.stamina > 15.0:
		var stunned := foe.state == Fighter.State.STAGGER
		me.request_attack(&"smash" if stunned and randf() < 0.4 else &"light")
		_combo_left = randi_range(0, 2) if stunned else 0
		return

	# 4. Out of breath: back off and recover.
	if me.stamina < 25.0:
		_retreat = 1.0
	if _retreat > 0.0:
		_retreat -= delta
		me.move_input = _flat(-dir * 0.8 + side * 0.6)
		return

	# 5. Low fuel: go grab a pack when it's safe-ish.
	if me.fuel < 25.0 and dist > 6.0:
		var pack := _nearest_pack()
		if pack:
			var to_pack := pack.global_position - me.global_position
			to_pack.y = 0.0
			me.move_input = _flat(to_pack.normalized())
			me.wants_run = true
			return

	# 6. Neutral: close in / keep spacing and circle, poke with the gun, look for an opening.
	_strafe_switch -= delta
	if _strafe_switch <= 0.0:
		_strafe_switch = randf_range(1.2, 3.0)
		_strafe_sign = -_strafe_sign

	if dist > 12.0:
		me.move_input = _flat(dir)
		me.wants_run = true
		if me.fuel > 40.0 and randf() < delta * 0.5:
			me.request_dash(_flat(dir))
	elif dist > preferred_range + 1.0:
		me.move_input = _flat(dir * 0.8 + side * 0.4)
	elif dist < preferred_range - 1.5:
		me.move_input = _flat(-dir * 0.6 + side * 0.6)
	else:
		me.move_input = _flat(side * 0.8)

	if me.barrel.has_gun() and me.ammo > 0 and dist > 6.0:
		if me.barrel.automatic:
			if _burst <= 0.0 and randf() < delta * 0.5:
				_burst = 0.5
			if _burst > 0.0:
				_burst -= delta
				me.fire_input = true
		elif randf() < delta * 0.35:
			me.request_fire()

	_cooldown -= delta
	if _cooldown > 0.0 or me.stamina < 40.0:
		return
	_cooldown = randf_range(attack_tempo * 0.6, attack_tempo * 1.4)
	_start_offense(dist, reach, dir)


func _start_offense(dist: float, reach: float, dir: Vector3) -> void:
	var me := fighter
	var dash_attack_ok := me.thruster.dash_attack != ThrusterDef.DashAttack.NONE
	if dist <= reach + 0.2:
		if randf() < 0.2:
			_charging = randf_range(0.4, 1.0)
			me.charge_input = true
		else:
			me.request_attack([&"light", &"light", &"slash_left", &"slash_right", &"smash"].pick_random())
			_combo_left = randi_range(0, 2)
	elif dist <= 7.0 and dash_attack_ok and me.fuel > 15.0:
		me.request_dash(_flat(dir))
		_dash_attack_pending = 0.06
	elif dist <= reach + 1.5:
		me.request_attack(&"thrust")


## Notice a new attack from the foe and decide how to answer it.
func _watch_attacks(dist: float) -> void:
	var foe := target
	if foe.state != Fighter.State.ATTACK or foe.current_attack == null:
		_seen_attack = null
		_plan = &""
		return
	if foe.current_attack == _seen_attack:
		return
	_seen_attack = foe.current_attack
	_plan = &""
	var a := _seen_attack
	var lunge := a.lunge_speed * (a.windup + a.active)
	if dist > a.reach + lunge + 1.0:
		return  # not a threat
	_react_in = reaction_time * randf_range(0.8, 1.3)
	var roll := randf()
	if fighter.can_parry and roll < parry_chance:
		_plan = &"parry"
	elif roll < parry_chance + guard_chance:
		_plan = &"guard"
	elif roll < parry_chance + guard_chance + dodge_chance and fighter.fuel > 10.0:
		_plan = &"dodge"


func _execute_plan(dir: Vector3, side: Vector3) -> void:
	var a := _seen_attack
	var foe := target
	match _plan:
		&"parry":
			# Press guard just before the hit lands.
			var time_to_hit := a.windup - foe.attack_time
			if time_to_hit <= fighter.parry_window * 0.6:
				_guard_hold = 0.35  # stays up as a block if the timing was off
				_plan = &""
		&"guard":
			_guard_hold = maxf(0.2, a.total_time() - foe.attack_time)
			_plan = &""
		&"dodge":
			fighter.request_dash(_flat(-dir * 0.5 + side))
			_plan = &""


func _nearest_pack() -> Pickup:
	var best: Pickup = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("pickups"):
		var p := node as Pickup
		if p and p.available and p.kind == Pickup.Kind.FUEL:
			var d := p.global_position.distance_to(fighter.global_position)
			if d < best_d:
				best = p
				best_d = d
	return best


static func _flat(v: Vector3) -> Vector2:
	var f := Vector2(v.x, v.z)
	return f.normalized() * minf(f.length(), 1.0) if f.length() > 0.01 else Vector2.ZERO
