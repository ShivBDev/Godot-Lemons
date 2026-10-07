extends LineEdit

# Detect screen touch or mouse click
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		# Check if the click happened outside the LineEdit's global bounding box
		if not get_global_rect().has_point(event.position):
			release_focus()
