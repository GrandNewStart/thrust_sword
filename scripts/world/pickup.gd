@tool
class_name Pickup
extends Area3D
## Fuel or ammo pack. Refills a fighter who touches it (unless already full),
## then respawns after a delay.

enum Kind { FUEL, AMMO }

@export var kind := Kind.FUEL:
	set(v):
		kind = v
		if is_inside_tree():
			_build()
## FUEL: fuel points. AMMO: share of max ammo (0..1).
@export var amount := 50.0
@export var respawn_time := 15.0

var available := true
var _generation := 0  # ignores respawn timers from before a reset
var _visual: Node3D
var _t := 0.0


func _ready() -> void:
	_build()
	if Engine.is_editor_hint():
		return
	add_to_group("pickups")
	collision_layer = 0
	collision_mask = 2  # fighters
	monitorable = false


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.0
	col.shape = shape
	col.position.y = 0.8
	add_child(col)

	_visual = Node3D.new()
	add_child(_visual)
	var color := Color(1.0, 0.55, 0.15) if kind == Kind.FUEL else Color(0.3, 0.85, 1.0)

	var mi := MeshInstance3D.new()
	if kind == Kind.FUEL:
		var m := CylinderMesh.new()
		m.top_radius = 0.28
		m.bottom_radius = 0.28
		m.height = 0.7
		mi.mesh = m
	else:
		var m := BoxMesh.new()
		m.size = Vector3(0.6, 0.4, 0.4)
		mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.2
	mi.material_override = mat
	mi.position.y = 0.9
	_visual.add_child(mi)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.75
	torus.outer_radius = 0.85
	ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = color
	ring.material_override = ring_mat
	ring.position.y = 0.05
	add_child(ring)


func _process(delta: float) -> void:
	if _visual == null:
		return
	_t += delta
	_visual.rotation.y = _t * 1.5
	_visual.position.y = sin(_t * 2.0) * 0.12


# Polling (instead of body_entered) also catches a fighter who was already standing here
# when they became able to use it, e.g. after spending fuel.
func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not available or not monitoring:
		return
	for body in get_overlapping_bodies():
		if body is Fighter and (body as Fighter).is_alive():
			_try_give(body)
			if not available:
				return


func _try_give(f: Fighter) -> void:
	var used := f.add_fuel(amount) if kind == Kind.FUEL else f.add_ammo(amount)
	if used:
		f.combat_event.emit("+FUEL" if kind == Kind.FUEL else "+AMMO", Color(1.0, 0.75, 0.3) if kind == Kind.FUEL else Color(0.4, 0.9, 1.0))
		_set_available(false)
		var gen := _generation
		get_tree().create_timer(respawn_time).timeout.connect(func():
			if gen == _generation:
				_set_available(true))


## Back to available, e.g. at the start of a round.
func reset_pickup() -> void:
	_generation += 1
	_set_available(true)


func _set_available(value: bool) -> void:
	available = value
	_visual.visible = value
	set_deferred("monitoring", value)
