extends RefCounted

# Shared row icon helper for the code-built menus.
#
# The shop, recipe, upgrades, staff and areas menus all build their rows in
# code and each wants the same small glyph beside the row's label. The art
# lives in res://assets/ui/icons; this just turns a path into a sized TextureRect.
#
# Deliberately has no class_name: menus preload it and call RowIcon.make(),
# which keeps the dependency explicit and avoids a global class registration.

const DEFAULT_SIDE: int = 30

# A sized TextureRect for the icon at `path`, or null when there is no usable
# art. Callers add the result only when it is not null, so a catalog entry with
# a missing or broken icon path can never take a menu down with it.
static func make(path: String, side: int = DEFAULT_SIDE) -> TextureRect:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var texture: Texture2D = load(path)
	if texture == null:
		return null
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = texture
	icon.custom_minimum_size = Vector2(float(side), float(side))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Rows sit inside clickable panels and buttons; an icon must never eat one.
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon
