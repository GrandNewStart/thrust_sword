class_name BarrelDef
extends Resource
## Sword barrel component: the secondary (ranged) attack.

enum Kind { NONE, MACHINE_GUN, ROCKET }

@export var kind := Kind.NONE
@export var max_ammo := 0
@export var damage := 0.0
## Seconds between shots.
@export var fire_interval := 0.1
## Hold to keep firing (true) or one shot per press (false).
@export var automatic := false
@export var projectile_speed := 60.0
@export var spread_deg := 0.0
## Explosion radius; 0 = no explosion.
@export var splash_radius := 0.0
@export var hitstun := 0.0
@export var knockback := 0.0
## Defender's stamina cost when blocking one shot.
@export var block_stamina := 0.0
## Hits cancel the target's charged attack.
@export var interrupts_charge := false
## Backward push on the shooter per shot.
@export var recoil := 0.0
@export var hitstop := 0.0


func has_gun() -> bool:
	return kind != Kind.NONE


static func none() -> BarrelDef:
	return BarrelDef.new()


static func machine_gun() -> BarrelDef:
	var b := BarrelDef.new()
	b.kind = Kind.MACHINE_GUN
	b.max_ammo = 60
	b.damage = 2.5
	b.fire_interval = 0.09
	b.automatic = true
	b.projectile_speed = 70.0
	b.spread_deg = 2.5
	b.knockback = 0.3
	b.block_stamina = 1.5
	b.interrupts_charge = true
	return b


static func rocket() -> BarrelDef:
	var b := BarrelDef.new()
	b.kind = Kind.ROCKET
	b.max_ammo = 4
	b.damage = 16.0
	b.fire_interval = 0.9
	b.automatic = false
	b.projectile_speed = 28.0
	b.splash_radius = 2.5
	b.hitstun = 0.5
	b.knockback = 7.0
	b.block_stamina = 25.0
	b.recoil = 4.0
	b.hitstop = 0.05
	return b
