class_name ResultPanel
extends Control
## End-of-match screen: VICTORY / DEFEAT / DRAW, score, REMATCH and SETUP.

signal rematch_pressed
signal setup_pressed


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func show_result(title: String, color: Color, score: String) -> void:
	for c in get_children():
		c.queue_free()

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.06, 0.75)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	var side := maxf(0.08, 0.5 - 380.0 / maxf(get_viewport_rect().size.x, 1.0))
	col.anchor_left = side
	col.anchor_right = 1.0 - side
	col.anchor_top = 0.3
	col.anchor_bottom = 0.85
	col.offset_left = 0
	col.offset_right = 0
	col.offset_top = 0
	col.offset_bottom = 0
	col.add_theme_constant_override("separation", 20)
	add_child(col)

	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 84)
	t.add_theme_color_override("font_color", color)
	t.add_theme_constant_override("outline_size", 10)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	col.add_child(t)

	var s := Label.new()
	s.text = score
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.add_theme_font_size_override("font_size", 46)
	col.add_child(s)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 60)
	col.add_child(spacer)

	col.add_child(_button("REMATCH", rematch_pressed, 100, 36))
	col.add_child(_button("SETUP", setup_pressed, 80, 28))
	visible = true


func _button(text: String, sig: Signal, height: float, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(func():
		visible = false
		sig.emit())
	return b
