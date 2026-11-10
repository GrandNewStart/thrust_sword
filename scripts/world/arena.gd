@tool
extends Node3D
## Large open arena with a grid floor, boundary walls and a few obstacles.
## Built in code so it's easy to tune; also shows in the editor.

@export var arena_size := 120.0:
	set(v):
		arena_size = v
		_rebuild()
@export var wall_height := 8.0

## [center on the floor, size]
const OBSTACLES := [
	[Vector3(14, 0, -12), Vector3(4, 3, 4)],
	[Vector3(-18, 0, -20), Vector3(3, 6, 3)],
	[Vector3(-10, 0, 14), Vector3(8, 1.5, 3)],
	[Vector3(22, 0, 18), Vector3(3, 8, 3)],
	[Vector3(-30, 0, -2), Vector3(5, 2.5, 5)],
	[Vector3(4, 0, -32), Vector3(10, 4, 2)],
	[Vector3(32, 0, -28), Vector3(4, 4, 4)],
]


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for c in get_children():
		remove_child(c)
		c.queue_free()

	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = load("res://shaders/grid.gdshader")
	_add_box(Vector3(0, -0.5, 0), Vector3(arena_size, 1, arena_size), floor_mat)

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.12, 0.14, 0.18)
	wall_mat.metallic = 0.6
	wall_mat.roughness = 0.4
	var h := arena_size * 0.5
	var y := wall_height * 0.5
	_add_box(Vector3(0, y, -h), Vector3(arena_size, wall_height, 1), wall_mat)
	_add_box(Vector3(0, y, h), Vector3(arena_size, wall_height, 1), wall_mat)
	_add_box(Vector3(-h, y, 0), Vector3(1, wall_height, arena_size), wall_mat)
	_add_box(Vector3(h, y, 0), Vector3(1, wall_height, arena_size), wall_mat)

	var block_mat := StandardMaterial3D.new()
	block_mat.albedo_color = Color(0.32, 0.36, 0.42)
	block_mat.metallic = 0.5
	block_mat.roughness = 0.45
	for o in OBSTACLES:
		var s: Vector3 = o[1]
		_add_box(o[0] + Vector3(0, s.y * 0.5, 0), s, block_mat)


func _add_box(center: Vector3, box_size: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 0

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	col.shape = shape
	body.add_child(col)

	var mesh_inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box_size
	mesh.material = mat
	mesh_inst.mesh = mesh
	body.add_child(mesh_inst)

	add_child(body)
