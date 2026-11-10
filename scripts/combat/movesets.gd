class_name Movesets
## Attack sets. Keys match the attack names PlayerIntent sends.
##   light       tap
##   slash_left  swipe left  (blade sweeps right -> left)
##   slash_right swipe right (blade sweeps left -> right)
##   thrust      swipe up    (long lunging stab)
##   smash       swipe down  (overhead, slow, strong)
##   heavy       hold, then release (charged; full charge breaks guard)
## Pose yaw: negative = blade pointing to the fighter's right, positive = left.

const HEAVY_FULL_CHARGE_DAMAGE_MULT := 1.8


static func standard() -> Dictionary:
	var list := [
		{ name = &"light", damage = 8.0, stamina_cost = 12.0,
			windup = 0.12, active = 0.12, recovery = 0.26, reach = 2.7, arc_deg = 110.0,
			lunge_speed = 3.0, hitstun = 0.35, knockback = 2.5, cancel_ratio = 0.4,
			pose_start = Vector3(-90, -70, 0), pose_end = Vector3(-90, 70, 0) },
		{ name = &"slash_left", damage = 12.0, stamina_cost = 16.0,
			windup = 0.16, active = 0.14, recovery = 0.32, reach = 2.9, arc_deg = 160.0,
			lunge_speed = 4.0, hitstun = 0.45, knockback = 3.5,
			pose_start = Vector3(-90, -85, 0), pose_end = Vector3(-90, 85, 0) },
		{ name = &"slash_right", damage = 12.0, stamina_cost = 16.0,
			windup = 0.16, active = 0.14, recovery = 0.32, reach = 2.9, arc_deg = 160.0,
			lunge_speed = 4.0, hitstun = 0.45, knockback = 3.5,
			pose_start = Vector3(-90, 85, 0), pose_end = Vector3(-90, -85, 0) },
		{ name = &"thrust", damage = 13.0, stamina_cost = 16.0,
			windup = 0.18, active = 0.12, recovery = 0.35, reach = 3.6, arc_deg = 40.0,
			lunge_speed = 9.0, hitstun = 0.4, knockback = 5.0,
			pose_start = Vector3(-80, -10, 0), pose_end = Vector3(-92, 0, 0) },
		{ name = &"smash", damage = 18.0, stamina_cost = 22.0,
			windup = 0.32, active = 0.12, recovery = 0.45, reach = 3.0, arc_deg = 50.0,
			lunge_speed = 2.0, hitstun = 0.6, knockback = 2.0, hitstop = 0.09,
			pose_start = Vector3(40, 0, 0), pose_end = Vector3(-125, 0, 0) },
		{ name = &"heavy", damage = 18.0, stamina_cost = 26.0,
			windup = 0.08, active = 0.18, recovery = 0.5, reach = 3.1, arc_deg = 200.0,
			lunge_speed = 5.0, hitstun = 0.7, knockback = 7.0, hitstop = 0.12, cancel_ratio = 0.7,
			pose_start = Vector3(-90, -120, 0), pose_end = Vector3(-90, 150, 0) },
	]
	var set := {}
	for d in list:
		set[d.name] = AttackDef.from_dict(d)
	return set


## An attack launched out of a dash: faster windup, carries the dash speed, hits harder.
static func dash_boosted(base: AttackDef, dash_speed: float, damage_mult: float) -> AttackDef:
	var a := base.duplicate() as AttackDef
	a.damage = base.damage * damage_mult
	a.windup = base.windup * 0.6
	a.lunge_speed = maxf(base.lunge_speed, dash_speed * 0.6)
	a.knockback = base.knockback * 1.3
	return a


## A charged heavy attack. charge_ratio 0..1; full charge breaks guard.
static func charged(base: AttackDef, charge_ratio: float) -> AttackDef:
	var a := base.duplicate() as AttackDef
	a.damage = lerpf(base.damage, base.damage * HEAVY_FULL_CHARGE_DAMAGE_MULT, charge_ratio)
	a.guard_break = base.guard_break or charge_ratio >= 0.999
	return a
