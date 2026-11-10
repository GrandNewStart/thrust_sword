class_name Projectile
extends Node3D
## A bullet or rocket. Moves by raycasting each tick so fast shots never pass through targets.

const LIFETIME := 2.5
const COLLISION_MASK := 1 | 2  # environment + fighters

var shooter: Fighter
var barrel: BarrelDef
var velocity := Vector3.ZERO
var _age := 0.0


static func spawn(parent: Node, from: Fighter, def: BarrelDef, pos: Vector3, vel: Vector3) -> Projectile:
	var p := Projectile.new()
	p.add_to_group("projectiles")
	p.shooter = from
	p.barrel = def
	p.velocity = vel
	parent.add_child(p)
	p.global_position = pos
	p.look_at(pos + vel, Vector3.UP if absf(vel.normalized().y) < 0.99 else Vector3.FORWARD)
	p._build_mesh()
	return p


func _build_mesh() -> void:
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if barrel.kind == BarrelDef.Kind.ROCKET:
		var m := CapsuleMesh.new()
		m.radius = 0.14
		m.height = 0.7
		mi.mesh = m
		mi.rotation_degrees.x = 90  # capsule axis along flight direction
		mat.albedo_color = Color(1.0, 0.5, 0.15)
	else:
		var m := BoxMesh.new()
		m.size = Vector3(0.05, 0.05, 0.9)
		mi.mesh = m
		mat.albedo_color = Color(1.0, 0.9, 0.5)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME:
		queue_free()
		return

	var from := global_position
	var to := from + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, to, COLLISION_MASK)
	if is_instance_valid(shooter):
		query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = to
		return

	var point: Vector3 = hit.position
	var target := hit.collider as Fighter
	if barrel.splash_radius > 0.0:
		_explode(point, target)
	elif target and is_instance_valid(shooter):
		target.receive_projectile(shooter, barrel, barrel.damage, from)
	queue_free()


func _explode(point: Vector3, direct: Fighter) -> void:
	for node in get_tree().get_nodes_in_group("fighters"):
		var f := node as Fighter
		if f == null or f == shooter or not f.is_alive():
			continue
		var center := f.global_position + Vector3.UP * 0.9
		var dist := center.distance_to(point)
		if f != direct and dist > barrel.splash_radius + f.radius:
			continue
		# Full damage on a direct hit, down to half at the edge of the blast.
		var falloff := 1.0 if f == direct else lerpf(1.0, 0.5, clampf(dist / barrel.splash_radius, 0.0, 1.0))
		if is_instance_valid(shooter):
			f.receive_projectile(shooter, barrel, barrel.damage * falloff, point)
	Explosion.spawn(get_parent(), point, barrel.splash_radius)


class Explosion:
	extends MeshInstance3D
	var _t := 0.0
	var _radius := 1.0
	var _mat: StandardMaterial3D

	static func spawn(parent: Node, pos: Vector3, radius: float) -> void:
		var e := Explosion.new()
		e._radius = radius
		var m := SphereMesh.new()
		m.radius = 1.0
		m.height = 2.0
		e.mesh = m
		e._mat = StandardMaterial3D.new()
		e._mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		e._mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		e._mat.albedo_color = Color(1.0, 0.6, 0.2, 0.8)
		e.material_override = e._mat
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(e)
		e.global_position = pos

	func _process(delta: float) -> void:
		_t += delta / 0.3
		scale = Vector3.ONE * lerpf(0.3, 1.0, minf(_t, 1.0)) * _radius
		_mat.albedo_color.a = 0.8 * (1.0 - _t)
		if _t >= 1.0:
			queue_free()
