class_name ThrusterDef
extends Resource
## Sword thruster component: dashes and vertical thrust.

enum DashAttack {
	NONE,    ## attacking waits until the dash is fully over
	AFTER,   ## an attack queued during the dash fires the instant it ends, with dash momentum
	DURING,  ## attacks can start mid-dash, carrying its momentum
}

@export var dash_speed := 14.0
@export var dash_duration := 0.22
@export var dash_fuel := 12.0
@export var dash_stamina := 8.0
@export var dash_cooldown := 0.2
## Dashes allowed before touching the ground again.
@export var air_dash_limit := 2
@export var dash_attack := DashAttack.DURING
@export var dash_attack_damage_mult := 1.25

@export var vertical := true
## Upward acceleration on top of cancelling gravity.
## Vertical dash: press jump again while airborne for a one-time upward boost.
## Shares the air-dash limit with horizontal air dashes.
@export var vertical_dash_speed := 10.0
@export var vertical_dash_duration := 0.22
@export var vertical_dash_fuel := 12.0


static func standard() -> ThrusterDef:
	return ThrusterDef.new()
