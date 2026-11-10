class_name Fighter
extends CharacterBody3D
## A combatant: movement, attacks, guard/parry, health and stamina.
## It doesn't know where its orders come from (touch input, AI, or later the network).
## Orders: move_input, wants_run, desired_yaw, guard_input, charge_input,
##         fire_input, aim_point, request_jump(), request_attack(name), request_dash(dir).

signal combat_event(text: String, color: Color)
signal got_hit(blocked: bool)
signal defeated
signal loadout_changed
signal aiming_changed(active: bool)
## For effects. kind: &"hit", &"block", &"parry", &"break". strength ≈ damage (parry: 20).
## source = the fighter who caused it (null for unknown).
signal impact(point: Vector3, kind: StringName, strength: float, source: Fighter)
signal dashed(direction: Vector3)
## Attack phase changes, for effects: 0 = windup started, 1 = blade live, 2 = follow-through.
signal attack_moment(attack: AttackDef, phase: int)
signal fired(muzzle: Vector3, direction: Vector3)

enum State { FREE, GUARD, CHARGE, ATTACK, DASH, STAGGER, DEAD }

@export_group("Movement")
## Top speeds (m/s). Armor overrides these.
@export var walk_speed := 2.2
@export var run_speed := 5.06
## m/s² gaining speed towards the stick direction.
@export var acceleration := 9.0
## m/s² shedding speed: stopping, or killing old momentum when changing direction.
@export var braking := 14.0
## m/s² steering while airborne: jumps mostly keep their momentum.
@export var air_acceleration := 3.0
## Attack lunges are a burst: they reach their speed almost at once.
@export var lunge_acceleration := 40.0
@export var stagger_friction := 12.0
## After a dash, speed is capped to this many times run speed, then braking takes over,
## so the dash eases out instead of stopping dead.
@export var dash_exit_speed_mult := 1.4
## 5.6 m/s ≈ 1.6 m jump (height scales with velocity²).
@export var jump_velocity := 5.6
@export var knockback_taken_mult := 1.0
## How fast the body turns to face desired_yaw. Higher = snappier.
@export var turn_sharpness := 11.0
@export var guard_move_mult := 0.4
## Charging a heavy plants you (low, wound-up stance).
@export var charge_move_mult := 0.0
@export var radius := 0.45

@export_group("Health & Stamina")
@export var max_health := 100.0
@export var max_stamina := 100.0
@export var stamina_regen := 35.0
@export var stamina_regen_delay := 0.7
@export var guard_regen_mult := 0.35
@export var run_stamina_per_sec := 10.0
@export var jump_stamina := 10.0

@export_group("Fuel")
@export var max_fuel := 100.0

@export_group("Defense")
@export var can_parry := true
@export var parry_window := 0.2
@export var parry_stamina := 5.0
## Share of damage that still gets through a block.
@export var block_damage_ratio := 0.1
## Attacks from within this angle of facing can be blocked/parried.
@export var guard_angle_deg := 100.0
@export var guard_break_stun := 0.9
@export var parried_stun := 1.0

@export_group("Attack")
@export var max_charge_time := 1.0

@export_group("Look")
@export var body_color := Color(0.25, 0.45, 0.3)

# --- Orders (written by the controller each tick) ---
## Desired movement direction in world space on the XZ plane (x, z). Length 0..1.
var move_input := Vector2.ZERO
var wants_run := false
## Yaw (radians) the body should face. 0 = facing -Z.
var desired_yaw := 0.0
var guard_input := false
var charge_input := false
## False during round intros / after a round ends: orders are ignored.
var controllable := true
var fire_input := false
## Manual aim mode (gun): planted, fires where the crosshair points. Toggle with toggle_aiming().
var aiming := false
## Player fighters can only fire while aiming; AI fighters fire from the hip.
var aim_required := false
## World point to shoot at.
var aim_point := Vector3.ZERO

# --- State (read by visuals / HUD / AI) ---
var moveset: Dictionary = Movesets.standard()
var thruster: ThrusterDef = ThrusterDef.standard()
var barrel: BarrelDef = BarrelDef.machine_gun()
## Set by apply_loadout(); null = built-in defaults (used by tests).
var sword: SwordDef
var armor: ArmorDef
## Hits stronger than this crush the guard.
var block_limit := INF
var block_stamina_mult := 1.0
var damage_taken_mult := 1.0
var hitstun_taken_mult := 1.0
var state := State.FREE
var health := 0.0
var stamina := 0.0
var current_attack: AttackDef
var attack_time := 0.0
var charge_time := 0.0
var parry_timer := 0.0
var running := false
var fuel := 0.0
var ammo := 0
var dash_time := 0.0
var dash_dir := Vector3.ZERO
## Seconds since the last shot (for visuals).
var since_shot := 99.0

## Own random stream (weapon spread), independent of particles and other cosmetics.
var rng := RandomNumberGenerator.new()
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _jump_buffer := 0.0
var _buffered_attack := &""
var _attack_buffer := 0.0
var _hit_targets: Array[Fighter] = []
var _stun_time := 0.0
var _regen_wait := 0.0
var _hitstop := 0.0
var _prev_guard_input := false
## Light chain: index of the last light hit (0..2) and seconds since it finished.
var _light_step := -1
var _last_attack_phase := -1
var _since_light := 99.0
var _dash_request := Vector3.ZERO
var _dash_buffer := 0.0
var _dash_cooldown := 0.0
var _air_dashes := 0
var _air_time := 0.0
var _fire_cooldown := 0.0
var _fire_buffer := 0.0
var _empty_warned := false

const JUMP_BUFFER_TIME := 0.12
## After a light attack ends, another light within this time continues the chain.
const LIGHT_CHAIN_GRACE := 0.35
## Just after leaving the ground, a jump press still counts as a (buffered) jump, not a boost.
const AIRBORNE_GRACE := 0.05
const DASH_BUFFER_TIME := 0.15

const ATTACK_BUFFER_TIME := 0.3
const COLOR_DAMAGE := Color(1.0, 0.85, 0.8)
const COLOR_BLOCK := Color(0.5, 0.8, 1.0)
const COLOR_PARRY := Color(1.0, 0.85, 0.2)
const COLOR_BREAK := Color(1.0, 0.45, 0.15)


func _ready() -> void:
	desired_yaw = rotation.y
	health = max_health
	stamina = max_stamina
	fuel = max_fuel
	ammo = barrel.max_ammo


# ---------------------------------------------------------------- orders

## Enter / leave the manual aim mode. Only with a gun, standing (or guarding) on the ground.
func toggle_aiming() -> void:
	if aiming:
		set_aiming(false)
	elif barrel.has_gun() and is_on_floor() and (state == State.FREE or state == State.GUARD):
		set_aiming(true)


func set_aiming(value: bool) -> void:
	if aiming == value:
		return
	aiming = value
	aiming_changed.emit(value)


## On the ground: jump. In the air (with a flight-capable thruster): one-time vertical dash.
## Jumping out of aim mode is an escape: it leaves the mode first.
func request_jump() -> void:
	set_aiming(false)
	if not is_on_floor() and _air_time > AIRBORNE_GRACE and thruster.vertical:
		_dash_request = Vector3.UP
		_dash_buffer = DASH_BUFFER_TIME
	else:
		_jump_buffer = JUMP_BUFFER_TIME


func request_attack(attack_name: StringName) -> void:
	if aiming:
		return
	if moveset.has(attack_name):
		_buffered_attack = attack_name
		_attack_buffer = ATTACK_BUFFER_TIME


const BASE_JUMP_VELOCITY := 5.6


func apply_loadout(new_sword: SwordDef, new_armor: ArmorDef) -> void:
	sword = new_sword
	armor = new_armor
	moveset = sword.build_moveset()
	thruster = sword.thruster.duplicate()
	barrel = sword.barrel.duplicate()
	can_parry = sword.can_parry
	parry_window = sword.parry_window
	block_damage_ratio = sword.block_damage_ratio
	block_limit = sword.block_limit
	block_stamina_mult = sword.block_stamina_mult
	max_health = armor.max_health
	max_stamina = armor.max_stamina
	damage_taken_mult = armor.damage_taken_mult
	hitstun_taken_mult = armor.hitstun_taken_mult
	walk_speed = armor.walk_speed
	run_speed = armor.run_speed
	acceleration = armor.acceleration
	braking = armor.braking
	turn_sharpness = armor.turn_sharpness
	knockback_taken_mult = armor.knockback_taken_mult
	jump_velocity = BASE_JUMP_VELOCITY * armor.jump_mult
	health = max_health
	stamina = max_stamina
	fuel = max_fuel
	ammo = barrel.max_ammo
	loadout_changed.emit()


## Dash along a world-space direction on the XZ plane.
func request_dash(world_dir: Vector2) -> void:
	set_aiming(false)  # dashing out of aim mode is an escape
	if world_dir.length() < 0.01:
		world_dir = Vector2(forward().x, forward().z)
	_dash_request = Vector3(world_dir.x, 0.0, world_dir.y).normalized()
	_dash_buffer = DASH_BUFFER_TIME


func _ignore_orders() -> void:
	move_input = Vector2.ZERO
	wants_run = false
	guard_input = false
	charge_input = false
	fire_input = false
	_buffered_attack = &""
	_dash_buffer = 0.0
	_fire_buffer = 0.0
	_jump_buffer = 0.0
	if state == State.CHARGE:
		state = State.FREE  # drop the charge instead of releasing it


## A trigger press. Semi-automatic guns fire once per press; automatic ones fire
## at least one shot even if the press is shorter than a frame.
func request_fire() -> void:
	_fire_buffer = 0.15


## Returns false if already full.
func add_fuel(amount: float) -> bool:
	if fuel >= max_fuel:
		return false
	fuel = minf(max_fuel, fuel + amount)
	return true


## Refill a share of max ammo. Returns false if full or the sword has no gun.
func add_ammo(ratio: float) -> bool:
	if not barrel.has_gun() or ammo >= barrel.max_ammo:
		return false
	ammo = mini(barrel.max_ammo, ammo + maxi(1, ceili(barrel.max_ammo * ratio)))
	_empty_warned = false
	return true


func reset_to(pos: Vector3, yaw: float) -> void:
	global_position = pos
	rotation.y = yaw
	desired_yaw = yaw
	velocity = Vector3.ZERO
	health = max_health
	stamina = max_stamina
	fuel = max_fuel
	ammo = barrel.max_ammo
	state = State.FREE
	current_attack = null
	_buffered_attack = &""
	_dash_buffer = 0.0
	_fire_buffer = 0.0
	_jump_buffer = 0.0
	_dash_cooldown = 0.0
	_light_step = -1
	set_aiming(false)
	_hitstop = 0.0
	_stun_time = 0.0
	parry_timer = 0.0


# ---------------------------------------------------------------- queries

func is_alive() -> bool:
	return state != State.DEAD


func is_running() -> bool:
	return running


func is_thrusting() -> bool:
	return state == State.DASH


func is_vertical_dash() -> bool:
	return state == State.DASH and dash_dir.y > 0.9


func forward() -> Vector3:
	return Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func charge_ratio() -> float:
	return clampf(charge_time / max_charge_time, 0.0, 1.0)


## 0 = windup, 1 = active, 2 = recovery. -1 when not attacking.
func attack_phase() -> int:
	if state != State.ATTACK or current_attack == null:
		return -1
	if attack_time < current_attack.windup:
		return 0
	if attack_time < current_attack.windup + current_attack.active:
		return 1
	return 2


# ---------------------------------------------------------------- tick

func _physics_process(delta: float) -> void:
	if _hitstop > 0.0:
		_hitstop -= delta
		return
	if not controllable:
		_ignore_orders()
	# Leave aim mode when it no longer makes sense: hit, stunned, attacking, guarding, no gun.
	if aiming and (not controllable or state != State.FREE or guard_input or not barrel.has_gun()):
		set_aiming(false)

	_update_timers(delta)
	_update_state(delta)
	_update_firing()
	_update_movement(delta)
	_prev_guard_input = guard_input


func _update_timers(delta: float) -> void:
	_jump_buffer -= delta
	parry_timer -= delta
	_attack_buffer -= delta
	if _attack_buffer <= 0.0:
		_buffered_attack = &""
	if state != State.ATTACK:
		_since_light += delta
	_dash_buffer -= delta
	_dash_cooldown -= delta
	_fire_cooldown -= delta
	_fire_buffer -= delta
	since_shot += delta

	if _regen_wait > 0.0:
		_regen_wait -= delta
	elif state != State.DEAD:
		var rate := stamina_regen * (guard_regen_mult if state == State.GUARD else 1.0)
		stamina = minf(max_stamina, stamina + rate * delta)


func _update_state(delta: float) -> void:
	if _dash_buffer > 0.0 and _can_dash():
		_start_dash()

	match state:
		State.FREE, State.GUARD:
			var guard_pressed := guard_input and not _prev_guard_input
			if guard_pressed and can_parry:
				parry_timer = parry_window
				_spend_stamina(parry_stamina)
			state = State.GUARD if guard_input else State.FREE

			if charge_input and stamina > 0.0:
				state = State.CHARGE
				charge_time = 0.0
			elif _buffered_attack != &"" and stamina > 0.0:
				_start_attack(_resolve_attack(_buffered_attack))

		State.CHARGE:
			charge_time = minf(charge_time + delta, max_charge_time)
			if not charge_input:
				_start_attack(Movesets.charged(moveset[&"heavy"], charge_ratio()))

		State.ATTACK:
			attack_time += delta
			var a := current_attack
			var phase := attack_phase()
			if phase != _last_attack_phase and phase >= 0:
				_last_attack_phase = phase
				attack_moment.emit(a, phase)
			if attack_phase() == 1:
				_check_hits()
			if attack_time >= a.total_time():
				state = State.FREE
				current_attack = null
			elif attack_phase() == 2 and _buffered_attack != &"" and stamina > 0.0:
				var recovery_done := (attack_time - a.windup - a.active) / a.recovery
				if recovery_done >= a.cancel_ratio:
					_start_attack(_resolve_attack(_buffered_attack))

		State.DASH:
			dash_time += delta
			var t := thruster
			if _buffered_attack != &"" and stamina > 0.0 and t.dash_attack == ThrusterDef.DashAttack.DURING:
				_start_dash_attack()
			elif dash_time >= (t.vertical_dash_duration if dash_dir.y > 0.9 else t.dash_duration):
				state = State.FREE
				_dash_cooldown = t.dash_cooldown
				_ease_out_of_dash()
				if _buffered_attack != &"" and stamina > 0.0 and t.dash_attack == ThrusterDef.DashAttack.AFTER:
					_start_dash_attack()

		State.STAGGER:
			_stun_time -= delta
			if _stun_time <= 0.0:
				state = State.FREE


## Momentum-preserving steering. Speed along the wanted direction builds up at `accel`;
## any other momentum (going the wrong way, sideways after a turn, or above the target speed)
## bleeds off at `brake`. Sharp turns therefore carve an arc, and reversals skid first.
static func _steer(v: Vector3, target: Vector3, accel: float, brake: float, delta: float) -> Vector3:
	if target.length() < 0.01:
		return v.move_toward(Vector3.ZERO, brake * delta)
	var dir := target.normalized()
	var want := target.length()
	var along := v.dot(dir)
	var side := (v - dir * along).move_toward(Vector3.ZERO, brake * delta)
	if along < 0.0:
		along = minf(along + brake * delta, 0.0)  # still sliding backwards: brake first
	elif along < want:
		along = minf(along + accel * delta, want)
	else:
		along = maxf(along - brake * delta, want)
	return dir * along + side


func _ease_out_of_dash() -> void:
	if dash_dir.y > 0.9:
		velocity.y = minf(velocity.y, thruster.vertical_dash_speed * 0.4)  # keeps rising briefly
		return
	var h := Vector2(velocity.x, velocity.z).limit_length(run_speed * dash_exit_speed_mult)
	velocity.x = h.x
	velocity.z = h.y


func _update_movement(delta: float) -> void:
	if is_on_floor():
		_air_time = 0.0
		_air_dashes = 0
	else:
		_air_time += delta
		if state != State.DASH:
			velocity.y -= _gravity * delta

	var can_jump := state == State.FREE or state == State.GUARD
	if _jump_buffer > 0.0 and is_on_floor() and can_jump and stamina > 0.0:
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_spend_stamina(jump_stamina)

	running = false
	var target := Vector3.ZERO
	var dir := Vector3(move_input.x, 0.0, move_input.y)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)

	match state:
		State.FREE:
			var gunning := fire_input and barrel.automatic and ammo > 0
			running = wants_run and stamina > 0.0 and move_input.length() > 0.1 and not gunning and not aiming
			target = Vector3.ZERO if aiming else dir * (run_speed if running else walk_speed)
			if running:
				_spend_stamina(run_stamina_per_sec * delta)
		State.GUARD:
			target = dir * walk_speed * guard_move_mult
		State.CHARGE:
			target = dir * walk_speed * charge_move_mult
		State.ATTACK:
			if attack_phase() <= 1:
				target = forward() * current_attack.lunge_speed

	match state:
		State.DASH:
			if is_vertical_dash():
				velocity.y = thruster.vertical_dash_speed  # keeps its horizontal momentum
			else:
				horizontal = dash_dir * thruster.dash_speed
				velocity.y = 0.0
		State.ATTACK when attack_phase() <= 1:
			horizontal = horizontal.move_toward(target, lunge_acceleration * delta)
		State.STAGGER, State.DEAD:
			horizontal = horizontal.move_toward(Vector3.ZERO, stagger_friction * delta)
		_:
			if is_on_floor():
				horizontal = _steer(horizontal, target, acceleration, braking, delta)
			else:
				horizontal = horizontal.move_toward(target, air_acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	var turn := 0.0
	match state:
		State.FREE, State.GUARD, State.CHARGE, State.DASH:
			turn = turn_sharpness
		State.ATTACK:
			if attack_phase() == 0:
				turn = turn_sharpness * 0.5  # can still aim during windup, then committed
	if turn > 0.0:
		rotation.y = lerp_angle(rotation.y, desired_yaw, 1.0 - exp(-turn * delta))

	move_and_slide()


# ---------------------------------------------------------------- combat

func _can_dash() -> bool:
	if fuel <= 0.0 or stamina <= 0.0 or _dash_cooldown > 0.0:
		return false
	if not is_on_floor() and _air_dashes >= thruster.air_dash_limit:
		return false
	match state:
		State.FREE, State.GUARD, State.CHARGE:
			return true
		State.ATTACK:
			# Dash-cancel out of recovery, same window as combos.
			if attack_phase() == 2:
				var a := current_attack
				return (attack_time - a.windup - a.active) / a.recovery >= a.cancel_ratio
	return false


func _start_dash() -> void:
	_dash_buffer = 0.0
	if not is_on_floor():
		_air_dashes += 1
	var vertical := _dash_request.y > 0.9
	fuel = maxf(0.0, fuel - (thruster.vertical_dash_fuel if vertical else thruster.dash_fuel))
	_spend_stamina(thruster.dash_stamina)
	dash_dir = _dash_request
	dash_time = 0.0
	dashed.emit(dash_dir)
	current_attack = null
	state = State.DASH


func _start_dash_attack() -> void:
	var t := thruster
	_dash_cooldown = t.dash_cooldown
	_start_attack(Movesets.dash_boosted(_resolve_attack(_buffered_attack), t.dash_speed, t.dash_attack_damage_mult))


func _update_firing() -> void:
	if not barrel.has_gun():
		return
	if aim_required and not aiming:
		_fire_buffer = 0.0
		return
	var pressed := _fire_buffer > 0.0
	var wants := pressed or (barrel.automatic and fire_input)
	if not wants or (state != State.FREE and state != State.DASH):
		return
	if _fire_cooldown > 0.0:
		return
	_fire_buffer = 0.0
	if ammo <= 0:
		if not _empty_warned:
			_empty_warned = true
			combat_event.emit("NO AMMO", COLOR_BREAK)
		return

	ammo -= 1
	_fire_cooldown = barrel.fire_interval
	since_shot = 0.0
	var muzzle := muzzle_position()
	var dir := (aim_point - muzzle).normalized() if aim_point.distance_to(muzzle) > 1.0 else forward()
	if barrel.spread_deg > 0.0:
		var spread := deg_to_rad(barrel.spread_deg)
		dir = dir.rotated(Vector3.UP, rng.randf_range(-spread, spread))
		var side := dir.cross(Vector3.UP).normalized()
		if side.length() > 0.1:
			dir = dir.rotated(side, rng.randf_range(-spread, spread))
	Projectile.spawn(get_parent(), self, barrel, muzzle, dir * barrel.projectile_speed)
	fired.emit(muzzle, dir)
	if barrel.recoil > 0.0:
		velocity -= Vector3(dir.x, 0.0, dir.z).normalized() * barrel.recoil


func muzzle_position() -> Vector3:
	var right := Vector3(cos(rotation.y), 0.0, -sin(rotation.y))
	return global_position + Vector3.UP * 1.3 + forward() * 0.9 + right * 0.5


## Hit by a bullet or explosion. from_pos = where it came from (for guard direction).
func receive_projectile(shooter: Fighter, b: BarrelDef, damage: float, from_pos: Vector3) -> void:
	if not is_alive():
		return
	var to_source := from_pos - global_position
	to_source.y = 0.0
	var away := -to_source.normalized() if to_source.length() > 0.01 else -forward()
	var in_front := to_source.length() < 0.01 or rad_to_deg(forward().angle_to(to_source)) <= guard_angle_deg

	var point := _impact_point(to_source)
	if in_front and state == State.GUARD and damage > block_limit:
		_crush_guard(null, damage, b.block_stamina, b.hitstop)
		impact.emit(point, &"break", damage, shooter)
		return

	if in_front and state == State.GUARD:
		_spend_stamina(b.block_stamina * block_stamina_mult)
		_take_damage(damage * block_damage_ratio)
		got_hit.emit(true)
		impact.emit(point, &"block" if stamina > 0.0 else &"break", damage, shooter)
		if not is_alive():
			return
		if stamina <= 0.0:
			_stagger(guard_break_stun)
			combat_event.emit("GUARD BREAK", COLOR_BREAK)
		elif damage >= 5.0:
			combat_event.emit("BLOCK", COLOR_BLOCK)
		return

	_take_damage(damage)
	got_hit.emit(false)
	impact.emit(point, &"hit", damage, shooter)
	if damage >= 5.0:
		combat_event.emit("-%d" % roundi(damage * damage_taken_mult), COLOR_DAMAGE)
	if b.hitstop > 0.0:
		_apply_hitstop(b.hitstop)
	if not is_alive():
		return
	velocity += away * b.knockback * knockback_taken_mult
	if b.hitstun > 0.0:
		_stagger(b.hitstun * hitstun_taken_mult)
	elif b.interrupts_charge and state == State.CHARGE:
		_stagger(0.3)
		combat_event.emit("INTERRUPT", COLOR_BREAK)


## "light" means "the next hit of the light chain": swing left → swing right → poke.
## The chain continues if the previous hit is still recovering or ended moments ago.
func _resolve_attack(attack_name: StringName) -> AttackDef:
	if attack_name != &"light":
		_light_step = -1  # any other attack breaks the chain
		return moveset[attack_name]
	var chaining := _light_step >= 0 and (_since_light <= LIGHT_CHAIN_GRACE
		or (state == State.ATTACK and current_attack and Movesets.LIGHT_CHAIN.has(current_attack.name)))
	var step := (_light_step + 1) % Movesets.LIGHT_CHAIN.size() if chaining else 0
	_light_step = step
	_since_light = 0.0
	return moveset[Movesets.LIGHT_CHAIN[step]]


func light_chain_step() -> int:
	return _light_step


func _start_attack(a: AttackDef) -> void:
	_spend_stamina(a.stamina_cost)
	current_attack = a
	attack_time = 0.0
	_hit_targets.clear()
	_buffered_attack = &""
	state = State.ATTACK
	_last_attack_phase = 0
	attack_moment.emit(a, 0)


func _check_hits() -> void:
	var a := current_attack
	var fwd := forward()
	for node in get_tree().get_nodes_in_group("fighters"):
		var f := node as Fighter
		if f == null or f == self or not f.is_alive() or _hit_targets.has(f):
			continue
		var to := f.global_position - global_position
		if absf(to.y) > 2.0:
			continue
		var flat := Vector3(to.x, 0.0, to.z)
		var dist := flat.length()
		if dist - f.radius > a.reach:
			continue
		var point_blank := dist < radius + f.radius + 0.3
		if not point_blank and rad_to_deg(fwd.angle_to(flat)) > a.arc_deg * 0.5:
			continue
		_hit_targets.append(f)
		f.receive_hit(self, a)


func receive_hit(attacker: Fighter, a: AttackDef) -> void:
	if not is_alive():
		return
	var to_attacker := attacker.global_position - global_position
	to_attacker.y = 0.0
	var away := -to_attacker.normalized() if to_attacker.length() > 0.01 else -forward()
	var in_front := to_attacker.length() < 0.01 or rad_to_deg(forward().angle_to(to_attacker)) <= guard_angle_deg
	var point := _impact_point(to_attacker)

	# Parry: guard pressed just before the hit.
	if in_front and parry_timer > 0.0 and a.parryable:
		parry_timer = 0.0
		attacker.get_parried()
		_apply_hitstop(0.12)
		attacker._apply_hitstop(0.12)
		combat_event.emit("PARRY!", COLOR_PARRY)
		impact.emit(point, &"parry", 20.0, attacker)
		return

	# Too strong for this blade: the guard is crushed.
	if in_front and state == State.GUARD and not a.guard_break and a.damage > block_limit:
		_crush_guard(attacker, a.damage, a.damage * a.block_stamina_mult, a.hitstop)
		impact.emit(point, &"break", a.damage, attacker)
		return

	# Block.
	if in_front and state == State.GUARD and not a.guard_break:
		_spend_stamina(a.damage * a.block_stamina_mult * block_stamina_mult)
		_take_damage(a.damage * block_damage_ratio)
		_apply_hitstop(a.hitstop * 0.7)
		attacker._apply_hitstop(a.hitstop * 0.7)
		got_hit.emit(true)
		impact.emit(point, &"block" if stamina > 0.0 else &"break", a.damage, attacker)
		if not is_alive():
			return
		if stamina <= 0.0:
			_stagger(guard_break_stun)
			combat_event.emit("GUARD BREAK", COLOR_BREAK)
		else:
			velocity += away * a.knockback * 0.5 * knockback_taken_mult
			combat_event.emit("BLOCK", COLOR_BLOCK)
		return

	# Clean hit.
	var broke := in_front and state == State.GUARD and a.guard_break
	if broke:
		combat_event.emit("GUARD BREAK", COLOR_BREAK)
	_take_damage(a.damage)
	_apply_hitstop(a.hitstop)
	attacker._apply_hitstop(a.hitstop)
	got_hit.emit(false)
	impact.emit(point, &"break" if broke else &"hit", a.damage, attacker)
	combat_event.emit("-%d" % roundi(a.damage * damage_taken_mult), COLOR_DAMAGE)
	if is_alive():
		_stagger(a.hitstun * hitstun_taken_mult)
		velocity += away * a.knockback * knockback_taken_mult


## Guard held but the hit is too strong for the blade: half damage + short stagger.
func _crush_guard(attacker: Fighter, damage: float, stamina_cost: float, hitstop: float) -> void:
	_spend_stamina(stamina_cost * block_stamina_mult)
	_take_damage(damage * 0.5)
	_apply_hitstop(hitstop)
	if attacker:
		attacker._apply_hitstop(hitstop)
	got_hit.emit(false)
	combat_event.emit("GUARD BREAK", COLOR_BREAK)
	if is_alive():
		_stagger(0.45)


## Where a blow lands: chest height, on the side facing the source.
func _impact_point(to_source: Vector3) -> Vector3:
	var dir := to_source.normalized() if to_source.length() > 0.01 else forward()
	return global_position + Vector3.UP * 1.25 + dir * radius * 0.9


func get_parried() -> void:
	_stagger(parried_stun)


func _stagger(duration: float) -> void:
	_light_step = -1
	state = State.STAGGER
	_stun_time = duration
	current_attack = null
	_buffered_attack = &""


func _take_damage(amount: float) -> void:
	health = maxf(0.0, health - amount * damage_taken_mult)
	if health <= 0.0 and state != State.DEAD:
		state = State.DEAD
		current_attack = null
		combat_event.emit("K.O.", COLOR_BREAK)
		defeated.emit()


func _spend_stamina(amount: float) -> void:
	stamina = maxf(0.0, stamina - amount)
	_regen_wait = stamina_regen_delay


func _apply_hitstop(duration: float) -> void:
	_hitstop = maxf(_hitstop, duration)
