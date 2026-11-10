class_name SwordDef
extends Resource
## A complete sword: shared base frame + components.
##   Blade  — swing damage / speed / reach, how much it can block, look
##   Core   — parry support
##   Thruster, Barrel — see ThrusterDef / BarrelDef
## The PoC has three presets; a customization screen can later mix components freely.

@export var id := &"lancer"
@export var display_name := "Lancer"
@export_multiline var description := ""

@export_group("Blade")
@export var damage_mult := 1.0
## > 1 = faster swings (all attack timings are divided by this).
@export var speed_mult := 1.0
@export var reach_add := 0.0
@export var stamina_mult := 1.0
@export var hitstun_mult := 1.0
## Attacks from the moveset that always break guard.
@export var guard_break_moves: Array[StringName] = []
## Hits stronger than this crush the guard (half damage + short stagger).
@export var block_limit := 20.0
## Share of damage that gets through a successful block.
@export var block_damage_ratio := 0.1
## Multiplier on the stamina a block costs.
@export var block_stamina_mult := 1.0
@export var blade_size := Vector3(0.12, 2.1, 0.45)
@export var blade_color := Color(0.78, 0.8, 0.85)

@export_group("Core")
@export var can_parry := true
@export var parry_window := 0.2

@export_group("Components")
@export var thruster: ThrusterDef
@export var barrel: BarrelDef


func build_moveset() -> Dictionary:
	var set := Movesets.standard()
	for key in set:
		var a: AttackDef = set[key]
		a.damage *= damage_mult
		a.windup /= speed_mult
		a.active /= speed_mult
		a.recovery /= speed_mult
		a.reach += reach_add
		a.stamina_cost *= stamina_mult
		a.hitstun *= hitstun_mult
		a.knockback *= lerpf(1.0, damage_mult, 0.5)
		a.guard_break = a.guard_break or guard_break_moves.has(key)
	return set


const IDS: Array[StringName] = [&"striker", &"breaker", &"lancer"]


static func by_id(sword_id: StringName) -> SwordDef:
	match sword_id:
		&"striker":
			return striker()
		&"breaker":
			return breaker()
	return lancer()


## Mobility: light fast blade, long dashes, flies, attacks mid-dash, machine gun.
static func striker() -> SwordDef:
	var s := SwordDef.new()
	s.id = &"striker"
	s.display_name = "Striker"
	s.description = "Fast & mobile. Long dashes, flight, attack mid-dash. Machine gun. Small guard."
	s.damage_mult = 0.8
	s.speed_mult = 1.25
	s.reach_add = -0.2
	s.stamina_mult = 0.85
	s.block_limit = 14.0
	s.block_damage_ratio = 0.15
	s.block_stamina_mult = 1.2
	s.blade_size = Vector3(0.08, 1.75, 0.32)
	s.blade_color = Color(0.7, 0.85, 0.95)
	s.can_parry = true
	s.parry_window = 0.22
	var t := ThrusterDef.new()
	t.dash_speed = 16.8
	t.dash_duration = 0.26
	t.dash_fuel = 9.0
	t.dash_cooldown = 0.15
	t.air_dash_limit = 3
	t.dash_attack = ThrusterDef.DashAttack.DURING
	t.vertical = true
	t.vertical_dash_speed = 12.0
	t.vertical_dash_fuel = 9.0
	s.thruster = t
	s.barrel = BarrelDef.machine_gun()
	return s


## Power: huge slow blade that blocks almost anything; heavy hits break guard. No gun, no parry.
static func breaker() -> SwordDef:
	var s := SwordDef.new()
	s.id = &"breaker"
	s.display_name = "Breaker"
	s.description = "Huge & slow. Crushing hits, heavy/smash break guard. Blocks almost anything. No gun, no parry."
	s.damage_mult = 1.45
	s.speed_mult = 0.78
	s.reach_add = 0.5
	s.stamina_mult = 1.25
	s.hitstun_mult = 1.2
	s.guard_break_moves = [&"heavy", &"smash"]
	s.block_limit = 999.0
	s.block_damage_ratio = 0.05
	s.block_stamina_mult = 0.6
	s.blade_size = Vector3(0.2, 2.6, 0.75)
	s.blade_color = Color(0.55, 0.57, 0.62)
	s.can_parry = false
	var t := ThrusterDef.new()
	t.dash_speed = 11.9
	t.dash_duration = 0.16
	t.dash_fuel = 14.0
	t.dash_cooldown = 0.3
	t.air_dash_limit = 1
	t.dash_attack = ThrusterDef.DashAttack.NONE
	t.vertical = false
	s.thruster = t
	s.barrel = BarrelDef.none()
	return s


## Balanced: medium blade, attacks right after a dash, rockets.
static func lancer() -> SwordDef:
	var s := SwordDef.new()
	s.id = &"lancer"
	s.display_name = "Lancer"
	s.description = "Balanced. Attack straight out of a dash. Rockets: few, strong, explosive."
	s.reach_add = 0.3
	s.block_limit = 20.0
	s.blade_size = Vector3(0.12, 2.1, 0.45)
	s.can_parry = true
	s.parry_window = 0.2
	var t := ThrusterDef.new()
	t.dash_attack = ThrusterDef.DashAttack.AFTER
	s.thruster = t
	s.barrel = BarrelDef.rocket()
	return s
