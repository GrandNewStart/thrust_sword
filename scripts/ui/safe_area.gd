class_name SafeArea
## Screen insets (notch / Dynamic Island, home bar) in a Control's coordinates.
## Zero on desktop.


static func insets(c: Control) -> Dictionary:
	var result := { "top": 0.0, "bottom": 0.0, "left": 0.0, "right": 0.0 }
	if not OS.has_feature("mobile"):
		return result
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0.0 or win.y <= 0.0:
		return result
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var scale := c.get_viewport_rect().size / win
	result.top = safe.position.y * scale.y
	result.bottom = (win.y - safe.end.y) * scale.y
	result.left = safe.position.x * scale.x
	result.right = (win.x - safe.end.x) * scale.x
	return result
