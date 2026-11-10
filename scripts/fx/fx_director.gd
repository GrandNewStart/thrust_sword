class_name FxDirector
extends Node
## Turns gameplay events into effects. World effects (sparks, flashes, dust) play for every
## fighter; screen effects (shake, blur, vignette, aberration) only for things involving the
## player, so the screen doesn't jump around because of the AI.

@export var player: Fighter
@export var camera_rig: FighterCamera
@export var screen_fx: ScreenFx
## Effects spawn under this node (the level).
@export var world: Node

const COLORS := {
	&"hit": Color(1.0, 0.62, 0.28),
	&"block": Color(0.45, 0.78, 1.0),
	&"parry": Color(1.0, 0.86, 0.3),
	&"break": Color(1.0, 0.42, 0.12),
}


func _ready() -> void:
	add_to_group("fx")
	if world == null:
		world = get_parent()
	for node in get_tree().get_nodes_in_group("fighters"):
		var f := node as Fighter
		if f:
			f.impact.connect(_on_impact.bind(f))
			f.dashed.connect(_on_dashed.bind(f))
			f.fired.connect(_on_fired.bind(f))
			f.attack_moment.connect(_on_attack_moment.bind(f))


func _on_impact(point: Vector3, kind: StringName, strength: float, source: Fighter, victim: Fighter) -> void:
	var color: Color = COLORS.get(kind, Color.WHITE)
	var spray := point - (victim.global_position + Vector3.UP * 1.25)
	match kind:
		&"hit":
			Fx.burst(world, point, spray, color, int(clampf(16.0 + strength * 1.4, 12, 50)), 7.0 + strength * 0.25, 0.13)
			Fx.flare(world, point, color, 1.3 + strength * 0.04, 0.12)
			Fx.flash(world, point, color, 3.0 + strength * 0.1, 4.0, 0.12)
		&"block":
			Fx.burst(world, point, spray, color, 20, 8.0, 0.1, 0.25, 70.0)
			Fx.flare(world, point, color, 1.1, 0.1)
			Fx.flash(world, point, color, 2.5, 3.5, 0.1)
		&"parry":
			Fx.burst(world, point, spray, color, 60, 13.0, 0.16, 0.45, 80.0)
			Fx.burst(world, point, Vector3.UP, Color(1, 1, 1), 24, 6.0, 0.2, 0.25, 180.0, 0.0)
			Fx.flare(world, point, color, 3.0, 0.25)
			Fx.flash(world, point, color, 8.0, 6.0, 0.22)
		&"break":
			Fx.burst(world, point, spray, color, 45, 11.0, 0.15, 0.4, 75.0)
			Fx.flare(world, point, color, 2.2, 0.18)
			Fx.flash(world, point, color, 6.0, 5.0, 0.18)

	if camera_rig == null or player == null:
		return
	if victim == player:
		match kind:
			&"hit":
				camera_rig.add_trauma(0.28 + strength * 0.02)
				screen_fx.kick_vignette(0.55 + strength * 0.02)
				screen_fx.kick_aberration(0.6)
			&"block":
				camera_rig.add_trauma(0.14)
			&"break":
				camera_rig.add_trauma(0.5)
				screen_fx.kick_aberration(0.9)
			&"parry":  # we parried
				camera_rig.add_trauma(0.22)
				screen_fx.kick_aberration(0.45)
	elif source == player:
		match kind:
			&"hit":
				camera_rig.add_trauma(0.08 + strength * 0.012)
				if strength >= 20.0:
					screen_fx.kick_aberration(0.4)
			&"block":
				camera_rig.add_trauma(0.07)
			&"break":
				camera_rig.add_trauma(0.32)
			&"parry":  # we got parried
				camera_rig.add_trauma(0.3)
				screen_fx.kick_aberration(0.55)


## Charging (player): vibration, zoom-in, focus blur and edge darkening grow with the charge.
const CHARGE_SHAKE := Vector2(0.012, 0.09)  # intensity at start -> full
const CHARGE_ZOOM := -5.0  # degrees at full charge
const CHARGE_BLUR := 0.06
const CHARGE_DARKEN := 0.55

const AIM_DARKEN := 0.3

var _was_full := false
var _last_state := -1


## Motion blur that lasts as long as the player moves fast: mild while running (ramping in
## between walk and run speed), heavy for the whole dash; it fades out after a dash.
func _process(_delta: float) -> void:
	if player == null or screen_fx == null:
		return
	var target := 0.0
	if player.state == Fighter.State.DASH:
		target = screen_fx.dash_blur
	elif player.state == Fighter.State.FREE and player.is_on_floor():
		var speed := player.horizontal_speed()
		target = screen_fx.run_blur * clampf(inverse_lerp(player.walk_speed * 1.1, player.run_speed * 0.95, speed), 0.0, 1.0)
	if player.state != Fighter.State.DASH and screen_fx.held_blur > maxf(screen_fx.run_blur, CHARGE_BLUR) * 1.5:
		screen_fx.kick_blur(screen_fx.held_blur)  # dash just ended: let it fade instead of cutting

	var charging := player.state == Fighter.State.CHARGE
	var r := player.charge_ratio() if charging else 0.0
	if charging:
		target = maxf(target, CHARGE_BLUR * r)
		if r >= 1.0 and not _was_full:  # fully charged: a ping you can feel
			camera_rig.add_trauma(0.2)
			screen_fx.kick_aberration(0.35)
			Fx.flare(world, player.global_position + Vector3.UP * 1.3, Color(1.0, 0.9, 0.6), 1.6, 0.18)
	_was_full = charging and r >= 1.0
	camera_rig.hold_shake(lerpf(CHARGE_SHAKE.x, CHARGE_SHAKE.y, r * r) if charging else 0.0)
	camera_rig.hold_fov(CHARGE_ZOOM * r if charging else 0.0)
	var darken := CHARGE_DARKEN * r if charging else 0.0
	if player.aiming:
		darken = maxf(darken, AIM_DARKEN)  # focus on the crosshair
	screen_fx.hold_darken(darken)
	screen_fx.hold_blur(target)

	# Release: the charged swing bursts out.
	if _last_state == Fighter.State.CHARGE and player.state == Fighter.State.ATTACK:
		camera_rig.add_trauma(0.18 + 0.15 * float(player.current_attack and player.current_attack.guard_break))
		camera_rig.kick_fov(6.0)
		screen_fx.kick_blur(0.1)
	_last_state = player.state


func _on_dashed(direction: Vector3, f: Fighter) -> void:
	var feet := f.global_position + Vector3.UP * 0.15
	if f.is_on_floor() or direction.y > 0.9:
		Fx.dust(world, feet, -direction if direction.y < 0.9 else Vector3.DOWN)
	if f == player and camera_rig:
		camera_rig.add_trauma(0.07)
		camera_rig.kick_fov(9.0)
		screen_fx.kick_blur(screen_fx.dash_blur * 0.6)  # instant hit; the hold below takes over


func _on_fired(muzzle: Vector3, direction: Vector3, f: Fighter) -> void:
	var rocket := f.barrel.kind == BarrelDef.Kind.ROCKET
	Fx.flash(world, muzzle + direction * 0.3, Color(1.0, 0.8, 0.5), 5.0 if rocket else 2.5, 3.5, 0.06 if not rocket else 0.12)
	Fx.flare(world, muzzle + direction * 0.25, Color(1.0, 0.8, 0.45), 0.9 if rocket else 0.45, 0.06)
	Fx.burst(world, muzzle + direction * 0.2, direction, Color(1.0, 0.85, 0.55), 14 if rocket else 5, 9.0, 0.05, 0.15, 25.0, 0.0)
	if rocket:
		Fx.dust(world, muzzle - direction * 0.6, -direction, 16, 0.5)  # backblast
		Fx.flare(world, muzzle + direction * 0.4, Color(1.0, 0.7, 0.35), 1.6, 0.12)
	else:
		# Brass casings flicked out to the right.
		var right := direction.cross(Vector3.UP).normalized()
		Fx.burst(world, muzzle - direction * 0.5, right + Vector3.UP * 0.8, Color(0.95, 0.75, 0.3), 1, 3.5, 0.05, 0.6, 15.0, 9.8)
	if f == player and camera_rig:
		camera_rig.add_trauma(0.16 if rocket else 0.025)


## Per-attack signatures, timed to the attack's phases.
func _on_attack_moment(a: AttackDef, phase: int, f: Fighter) -> void:
	var visual := f.get_node_or_null("Visual") as FighterVisual
	var accent := visual.accent_color() if visual else Color(0.4, 0.9, 1.0)
	var tip := visual.blade_tip_position() if visual else f.global_position + f.forward() * 2.0
	var mine := f == player and camera_rig != null
	match a.name:
		&"light", &"light_2":
			if phase == 1 and mine:  # camera rolls with the swing
				camera_rig.kick_roll(0.025 if a.name == &"light" else -0.025)
		&"light_3":  # poke: an air ring pierced at the tip
			if phase == 1:
				Fx.shockwave(world, tip, accent, 0.9, 0.18, f.forward())
				Fx.flare(world, tip, accent, 0.9, 0.1)
				if mine:
					camera_rig.kick_fov(3.5)
					camera_rig.add_trauma(0.04)
					screen_fx.kick_blur(0.05)
		&"slash_left", &"slash_right":
			if phase == 1 and mine:
				camera_rig.kick_roll(0.045 if a.name == &"slash_left" else -0.045)
				camera_rig.add_trauma(0.05)
				screen_fx.kick_blur(0.035)
		&"thrust":  # thruster-driven lunge
			if phase == 0:
				Fx.dust(world, f.global_position + Vector3.UP * 0.15, -f.forward(), 14, 0.45)
			elif phase == 1:
				Fx.shockwave(world, tip, accent, 1.2, 0.2, f.forward())
				Fx.flare(world, tip, accent, 1.1, 0.12)
				if mine:
					camera_rig.kick_fov(6.0)
					camera_rig.add_trauma(0.06)
					screen_fx.kick_blur(0.1)
		&"smash":  # the blade slams the ground, hit or miss
			if phase == 2:
				var ground := Vector3(tip.x, f.global_position.y + 0.06, tip.z)
				Fx.shockwave(world, ground, accent, 3.0, 0.35)
				Fx.shockwave(world, ground, Color(1.0, 0.85, 0.6), 1.8, 0.22)
				Fx.dust(world, ground, Vector3.UP, 26, 0.75)
				Fx.burst(world, ground, Vector3.UP, Color(1.0, 0.75, 0.45), 26, 7.0, 0.1, 0.4, 70.0)
				Fx.flash(world, ground + Vector3.UP * 0.3, accent, 4.0, 5.0, 0.2)
				if mine:
					camera_rig.add_trauma(0.42)  # your own slam: full force
				else:
					_shake_near(ground, 0.42, 10.0)
		&"heavy":  # the spin sends a wave outwards at waist height
			if phase == 1:
				var waist := f.global_position + Vector3.UP * 1.1
				Fx.shockwave(world, waist, accent, 3.6, 0.3, f.global_basis.y)
				Fx.shockwave(world, f.global_position + Vector3.UP * 0.06, accent, 2.6, 0.35)
				if mine:
					camera_rig.add_trauma(0.12)


## Shake the player's camera when something heavy happens nearby (whoever caused it).
func _shake_near(point: Vector3, strength: float, falloff_distance: float) -> void:
	if camera_rig == null or player == null:
		return
	var t := clampf(1.0 - player.global_position.distance_to(point) / falloff_distance, 0.0, 1.0)
	if t > 0.0:
		camera_rig.add_trauma(strength * t)


## Called by projectiles (group "fx") when a bullet hits a wall or the floor.
func bullet_impact(point: Vector3, normal: Vector3) -> void:
	Fx.burst(world, point, normal, Color(1.0, 0.8, 0.5), 7, 6.0, 0.06, 0.2, 50.0)
	Fx.dust(world, point, normal, 4, 0.25)
	Fx.flare(world, point, Color(1.0, 0.8, 0.5), 0.35, 0.06)


## Called by projectiles (group "fx") when a rocket explodes.
func explosion(point: Vector3, radius: float) -> void:
	Fx.burst(world, point, Vector3.UP, Color(1.0, 0.55, 0.15), 60, 12.0, 0.12, 0.5, 180.0, 4.0)
	Fx.burst(world, point, Vector3.UP, Color(1.0, 0.9, 0.6), 25, 6.0, 0.2, 0.25, 180.0, 0.0)
	Fx.dust(world, point, Vector3.UP, 22, 0.6)
	Fx.flash(world, point, Color(1.0, 0.6, 0.25), 9.0, radius * 3.0, 0.3)
	Fx.flare(world, point, Color(1.0, 0.7, 0.35), radius * 1.8, 0.25)
	if camera_rig and player:
		var d := player.global_position.distance_to(point)
		var t := clampf(1.0 - d / 15.0, 0.0, 1.0)
		if t > 0.0:
			camera_rig.add_trauma(0.6 * t)
			screen_fx.kick_aberration(0.5 * t)
