class_name ArmorDef
extends Resource
## Suit armor: sets the pace of the fight (speed vs. toughness).

@export var id := &"medium"
@export var display_name := "Medium"
@export var max_health := 100.0
## Incoming damage is multiplied by this.
@export var damage_taken_mult := 1.0
## Walk / run speed multiplier.
@export var speed_mult := 1.0
## Stun duration multiplier when hit.
@export var hitstun_taken_mult := 1.0
@export var max_stamina := 100.0
## Visual bulk of the suit.
@export var body_scale := Vector3.ONE

const IDS: Array[StringName] = [&"light", &"medium", &"heavy"]


static func by_id(armor_id: StringName) -> ArmorDef:
	var a := ArmorDef.new()
	match armor_id:
		&"light":
			a.id = &"light"
			a.display_name = "Light"
			a.max_health = 85.0
			a.damage_taken_mult = 1.15
			a.speed_mult = 1.15
			a.hitstun_taken_mult = 1.1
			a.max_stamina = 110.0
			a.body_scale = Vector3(0.88, 1.0, 0.88)
		&"heavy":
			a.id = &"heavy"
			a.display_name = "Heavy"
			a.max_health = 140.0
			a.damage_taken_mult = 0.75
			a.speed_mult = 0.82
			a.hitstun_taken_mult = 0.75
			a.max_stamina = 90.0
			a.body_scale = Vector3(1.2, 1.05, 1.2)
	return a
