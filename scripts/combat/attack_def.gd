class_name AttackDef
extends Resource
## One sword attack: timing, damage, hit area and sword pose.
## Sword presets (step 4) will provide their own sets of these.

@export var name := &"light"
@export var damage := 10.0
@export var stamina_cost := 12.0
## Phases in seconds: windup -> active (can hit) -> recovery.
@export var windup := 0.12
@export var active := 0.12
@export var recovery := 0.25
## Hit area: distance from the attacker's center and total arc width in front.
@export var reach := 2.7
@export var arc_deg := 110.0
## Forward speed during windup + active.
@export var lunge_speed := 3.0
@export var hitstun := 0.35
@export var knockback := 3.0
@export var guard_break := false
@export var parryable := true
## After this fraction of recovery, the next attack can start (combos).
@export_range(0.0, 1.0) var cancel_ratio := 0.4
## Defender's stamina cost when blocking = damage * this.
@export var block_stamina_mult := 1.2
## Brief freeze on impact, in seconds.
@export var hitstop := 0.06
## Sword pivot rotation (degrees) at the start and end of the active phase.
@export var pose_start := Vector3.ZERO
@export var pose_end := Vector3.ZERO


func total_time() -> float:
	return windup + active + recovery


static func from_dict(d: Dictionary) -> AttackDef:
	var a := AttackDef.new()
	for key in d:
		a.set(key, d[key])
	return a
