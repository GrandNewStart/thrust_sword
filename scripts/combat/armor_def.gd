class_name ArmorDef
extends Resource
## Suit armor: sets the pace and weight of the fight.
## Heavier suits are tougher but slower to get moving, slower to stop and turn,
## jump lower and get shoved around less.

@export var id := &"medium"
@export var display_name := "Medium"
## Short description for the setup menu.
@export var tagline := "Balanced"
@export var max_health := 100.0
## Incoming damage is multiplied by this.
@export var damage_taken_mult := 1.0
@export var hitstun_taken_mult := 1.0
@export var max_stamina := 100.0

@export_group("Movement")
## Top speeds in m/s.
@export var walk_speed := 2.2
@export var run_speed := 5.06
## m/s² when speeding up towards the stick direction.
@export var acceleration := 9.0
## m/s² when slowing down, or shedding momentum while changing direction.
@export var braking := 14.0
## How fast the body turns to face where you look (higher = snappier).
@export var turn_sharpness := 11.0
@export var knockback_taken_mult := 1.0
@export var jump_mult := 1.0

## Visual bulk of the suit.
@export var body_scale := Vector3.ONE

const IDS: Array[StringName] = [&"light", &"medium", &"heavy"]


static func by_id(armor_id: StringName) -> ArmorDef:
	var a := ArmorDef.new()
	match armor_id:
		&"light":
			a.id = &"light"
			a.display_name = "Light"
			a.tagline = "Fast, nimble"
			a.max_health = 85.0
			a.damage_taken_mult = 1.15
			a.hitstun_taken_mult = 1.1
			a.max_stamina = 110.0
			a.walk_speed = 2.64
			a.run_speed = 6.05
			a.acceleration = 14.0
			a.braking = 20.0
			a.turn_sharpness = 14.0
			a.knockback_taken_mult = 1.2
			a.jump_mult = 1.05
			a.body_scale = Vector3(0.88, 1.0, 0.88)
		&"heavy":
			a.id = &"heavy"
			a.display_name = "Heavy"
			a.tagline = "Slow, unstoppable"
			a.max_health = 140.0
			a.damage_taken_mult = 0.75
			a.hitstun_taken_mult = 0.75
			a.max_stamina = 90.0
			a.walk_speed = 1.76
			a.run_speed = 3.74
			a.acceleration = 4.0
			a.braking = 6.0
			a.turn_sharpness = 7.0
			a.knockback_taken_mult = 0.65
			a.jump_mult = 0.85
			a.body_scale = Vector3(1.2, 1.05, 1.2)
	return a
