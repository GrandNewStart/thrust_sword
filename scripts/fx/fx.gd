class_name Fx
## One-shot visual effects: particle bursts, light flashes, dust. Each cleans itself up.
## CPU particles (no shader compile hitches, fine on mobile).

static var _glow_mat: StandardMaterial3D
static var _smoke_mat: StandardMaterial3D
static var _fade: Gradient
static var _ring_tex: GradientTexture2D


## Sparks / embers: additive, round, fading. `dir` = main spray direction.
static func burst(parent: Node, pos: Vector3, dir: Vector3, color: Color, amount: int,
		speed: float, size := 0.06, lifetime := 0.35, spread := 55.0, gravity := 9.8) -> void:
	var p := _particles(amount, lifetime, size, _glow())
	p.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed * 0.45
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -gravity, 0)
	p.damping_min = 2.0
	p.damping_max = 6.0
	p.color = color
	_launch(parent, p, pos, lifetime)


## A bright glow that pops at a point and fades fast (impact flare, muzzle flash):
## a coloured halo plus a hot white core.
static func flare(parent: Node, pos: Vector3, color: Color, size: float, duration := 0.12) -> void:
	_flare_sprite(parent, pos, color, size, duration * 1.2)
	_flare_sprite(parent, pos, Color(1, 1, 1, 0.9), size * 0.45, duration)


static func _flare_sprite(parent: Node, pos: Vector3, color: Color, size: float, duration: float) -> void:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mi.mesh = quad
	var m := _glow().duplicate() as StandardMaterial3D
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = false
	m.albedo_color = color
	m.no_depth_test = true  # reads even when partly behind a body
	m.render_priority = 1
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * size * 0.7
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(mi.queue_free)


## An expanding ring that fades out. Flat on the ground by default; `normal` tilts it
## (e.g. Vector3.UP for a ground slam, the fighter's up axis for a spin wave at waist height).
static func shockwave(parent: Node, pos: Vector3, color: Color, radius: float, duration := 0.3, normal := Vector3.UP) -> void:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)  # diameter 2 at scale 1 -> scale = radius
	quad.orientation = PlaneMesh.FACE_Y
	mi.mesh = quad
	var m := _glow().duplicate() as StandardMaterial3D
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	m.vertex_color_use_as_albedo = false
	m.albedo_texture = _ring()
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	var up := normal.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	mi.global_basis = Basis(side, up, side.cross(up))
	mi.scale = Vector3.ONE * radius * 0.15
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, duration).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


static func _ring() -> GradientTexture2D:
	if _ring_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.72, 0.86, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.15), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		_ring_tex = GradientTexture2D.new()
		_ring_tex.gradient = g
		_ring_tex.fill = GradientTexture2D.FILL_RADIAL
		_ring_tex.fill_from = Vector2(0.5, 0.5)
		_ring_tex.fill_to = Vector2(1.0, 0.5)
		_ring_tex.width = 128
		_ring_tex.height = 128
	return _ring_tex


## Soft grey puffs that drift up (dash take-off, explosions).
static func dust(parent: Node, pos: Vector3, dir: Vector3, amount := 20, size := 0.55) -> void:
	var p := _particles(amount, 0.6, size, _smoke())
	p.direction = (dir.normalized() + Vector3.UP * 0.3).normalized() if dir.length() > 0.01 else Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, 0.6, 0)
	p.damping_min = 3.0
	p.damping_max = 5.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.color = Color(0.72, 0.74, 0.8, 0.6)
	_launch(parent, p, pos, 0.6)


## A short-lived point light (impact flash, muzzle flash, explosion).
static func flash(parent: Node, pos: Vector3, color: Color, energy: float, light_range: float, duration: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = false
	parent.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, duration).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)


## Continuous smoke trail (for rockets). Parent it to the moving object.
static func smoke_trail(parent: Node3D) -> CPUParticles3D:
	var p := _particles(24, 0.5, 0.18, _smoke())
	p.one_shot = false
	p.explosiveness = 0.0
	p.local_coords = false
	p.spread = 12.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.8
	p.gravity = Vector3(0, 0.5, 0)
	p.color = Color(0.75, 0.75, 0.8, 0.45)
	parent.add_child(p)
	p.restart()
	p.emitting = true
	return p


static func _particles(amount: int, lifetime: float, size: float, mat: Material) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	# Particles default to emitting: they'd fire at the origin the moment they enter the tree,
	# before we move them. Start switched off; _launch / smoke_trail turn them on in place.
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = maxi(1, amount)
	p.lifetime = lifetime
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = mat
	p.mesh = quad
	p.color_ramp = _fade_ramp()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func _launch(parent: Node, p: CPUParticles3D, pos: Vector3, lifetime: float) -> void:
	parent.add_child(p)
	p.global_position = pos
	p.restart()  # emit from where it is now
	p.emitting = true
	p.get_tree().create_timer(lifetime + 0.3).timeout.connect(p.queue_free)


static func _fade_ramp() -> Gradient:
	if _fade == null:
		_fade = Gradient.new()
		_fade.set_color(0, Color(1, 1, 1, 1))
		_fade.set_color(1, Color(1, 1, 1, 0))
	return _fade


static func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	return t


static func _glow() -> StandardMaterial3D:
	if _glow_mat == null:
		_glow_mat = _base_mat()
		_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return _glow_mat


static func _smoke() -> StandardMaterial3D:
	if _smoke_mat == null:
		_smoke_mat = _base_mat()
	return _smoke_mat


static func _base_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = _soft_dot()
	m.no_depth_test = false
	return m
