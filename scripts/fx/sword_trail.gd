class_name SwordTrail
extends MeshInstance3D
## Glowing ribbon behind the blade during swings. Fed two points per frame (blade base and
## tip); keeps a short history and draws it as a fading strip.

@export var color := Color(0.4, 0.9, 1.0)
## How long a sample stays visible (seconds).
@export var lifetime := 0.14
@export var intensity := 0.8
var emitting := false

var _samples: Array = []  # [{ base: Vector3, tip: Vector3, t: float }]
var _time := 0.0
var _imesh := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _imesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	material_override = m


func push(base: Vector3, tip: Vector3) -> void:
	if emitting:
		_samples.append({ "base": base, "tip": tip, "t": _time })


func _process(delta: float) -> void:
	_time += delta
	while not _samples.is_empty() and _time - float(_samples[0].t) > lifetime:
		_samples.pop_front()
	_imesh.clear_surfaces()
	if _samples.size() < 2:
		return
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for s in _samples:
		var a := clampf(1.0 - (_time - float(s.t)) / lifetime, 0.0, 1.0) * intensity
		var c := color
		c.a = a * 0.15
		_imesh.surface_set_color(c)
		_imesh.surface_add_vertex(s.base)
		c.a = a
		_imesh.surface_set_color(c)
		_imesh.surface_add_vertex(s.tip)
	_imesh.surface_end()
