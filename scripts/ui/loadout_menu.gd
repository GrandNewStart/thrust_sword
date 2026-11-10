class_name LoadoutMenu
extends Control
## Training setup: sword + armor for each side, and the AI mode.
## Works while the game is paused.

signal confirmed

var player_sword := &"striker"
var player_armor := &"medium"
var opponent_sword := &"lancer"
var opponent_armor := &"medium"
var ai_mode := DummyBrain.Mode.SPAR
var mode := SessionManager.Mode.MATCH

var _desc_labels := {}  # side -> Label
## Landscape screens show YOU and OPPONENT side by side with shorter buttons.
var _wide := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open() -> void:
	_build()
	visible = true


func _build() -> void:
	for c in get_children():
		c.queue_free()

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.09, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var top_inset: float = SafeArea.insets(self).top
	var bottom_inset: float = SafeArea.insets(self).bottom
	var screen := get_viewport_rect().size
	_wide = screen.x > screen.y
	var max_w := 1100.0 if _wide else 760.0
	var side := int(maxf(28.0, (screen.x - max_w) * 0.5))
	margin.add_theme_constant_override("margin_left", side)
	margin.add_theme_constant_override("margin_right", side)
	margin.add_theme_constant_override("margin_top", int((20 if _wide else 40) + top_inset))
	margin.add_theme_constant_override("margin_bottom", int(30 + bottom_inset))
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8 if _wide else 14)
	margin.add_child(col)

	col.add_child(_label("SETUP", 34, Color(1, 1, 1)))
	col.add_child(_choice_row([SessionManager.Mode.MATCH, SessionManager.Mode.TRAINING],
		["MATCH  (best of 3)", "TRAINING"], mode, func(v): mode = v))
	if _wide:
		var sides := HBoxContainer.new()
		sides.add_theme_constant_override("separation", 32)
		col.add_child(sides)
		for spec in [[&"player", "YOU", Color(0.6, 1, 0.65)], [&"opponent", "OPPONENT", Color(1, 0.65, 0.6)]]:
			var c := VBoxContainer.new()
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			c.add_theme_constant_override("separation", 8)
			sides.add_child(c)
			_side(c, spec[0], spec[1], spec[2])
	else:
		_side(col, &"player", "YOU", Color(0.6, 1, 0.65))
		_side(col, &"opponent", "OPPONENT", Color(1, 0.65, 0.6))

	col.add_child(_label("OPPONENT AI", 22, Color(0.8, 0.85, 0.9)))
	var ai_ids: Array = []
	var ai_names: Array = []
	for m in DummyBrain.Mode.values():
		ai_ids.append(m)
		ai_names.append(DummyBrain.mode_name(m))
	col.add_child(_choice_row(ai_ids, ai_names, ai_mode, func(v): ai_mode = v))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)

	var fight := Button.new()
	fight.text = "FIGHT"
	fight.custom_minimum_size = Vector2(0, 70 if _wide else 110)
	fight.add_theme_font_size_override("font_size", 38)
	fight.focus_mode = Control.FOCUS_NONE
	var solid := StyleBoxFlat.new()
	solid.bg_color = Color(0.95, 0.5, 0.15)
	solid.set_corner_radius_all(12)
	var solid_hover := solid.duplicate() as StyleBoxFlat
	solid_hover.bg_color = Color(1.0, 0.6, 0.25)
	fight.add_theme_stylebox_override("normal", solid)
	fight.add_theme_stylebox_override("hover", solid_hover)
	fight.add_theme_stylebox_override("pressed", solid_hover)
	fight.add_theme_color_override("font_color", Color.WHITE)
	fight.add_theme_color_override("font_hover_color", Color.WHITE)
	fight.pressed.connect(_confirm)
	col.add_child(fight)


func _side(col: VBoxContainer, side: StringName, title: String, color: Color) -> void:
	col.add_child(_label(title, 26, color))
	var sword_names: Array = []
	for id in SwordDef.IDS:
		sword_names.append(SwordDef.by_id(id).display_name)
	var current_sword: StringName = player_sword if side == &"player" else opponent_sword
	col.add_child(_choice_row(SwordDef.IDS, sword_names, current_sword, func(v): _set_sword(side, v)))

	var desc := _label(SwordDef.by_id(current_sword).description, 17, Color(0.75, 0.8, 0.85))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(0, 50)
	col.add_child(desc)
	_desc_labels[side] = desc

	var armor_names: Array = []
	for id in ArmorDef.IDS:
		var a := ArmorDef.by_id(id)
		armor_names.append("%s\n%d HP · %s" % [a.display_name, a.max_health, a.tagline])
	var current_armor: StringName = player_armor if side == &"player" else opponent_armor
	col.add_child(_choice_row(ArmorDef.IDS, armor_names, current_armor, func(v): _set_armor(side, v)))


func _set_sword(side: StringName, id: StringName) -> void:
	if side == &"player":
		player_sword = id
	else:
		opponent_sword = id
	_desc_labels[side].text = SwordDef.by_id(id).description


func _set_armor(side: StringName, id: StringName) -> void:
	if side == &"player":
		player_armor = id
	else:
		opponent_armor = id


func _choice_row(ids: Array, names: Array, current: Variant, on_pick: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var group := ButtonGroup.new()
	for i in ids.size():
		var b := Button.new()
		b.text = names[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = ids[i] == current
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 54 if _wide else 76)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 22)
		_style_choice(b)
		var id = ids[i]
		b.pressed.connect(func(): on_pick.call(id))
		row.add_child(b)
	return row


## Selected = solid accent, unselected = dim outline, so the choice is obvious at a glance.
func _style_choice(b: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.14, 0.18)
	normal.border_color = Color(0.3, 0.34, 0.4)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(10)
	var selected := normal.duplicate() as StyleBoxFlat
	selected.bg_color = Color(0.15, 0.5, 0.85)
	selected.border_color = Color(0.55, 0.85, 1.0)
	selected.set_border_width_all(3)
	for state in ["normal", "hover", "focus"]:
		b.add_theme_stylebox_override(state, normal)
	for state in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, selected)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _confirm() -> void:
	visible = false
	confirmed.emit()
