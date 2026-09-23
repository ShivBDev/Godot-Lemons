extends Control
class_name UiIcon

# Procedural icon drawing.
#
# Icons are drawn with Control._draw() instead of being loaded as image
# files. That keeps the whole set in one place, scales crisply to any size,
# and needs no import step.
#
# Usage: add a Control node with this script and set `kind`.
# Design space is a 48x48 box, scaled to fit whatever size the node has.

@export var kind: String = "lemon":
	set(value):
		kind = value
		queue_redraw()

# Palette, matching res://ui/theme.tres.
const WOOD_DARK := Color(0.36, 0.24, 0.15)
const WOOD_MID := Color(0.55, 0.38, 0.22)
const CREAM := Color(0.99, 0.965, 0.89)
const WHITE := Color(0.999, 0.985, 0.94)
const GREEN := Color(0.663, 0.808, 0.478)
const GREEN_DARK := Color(0.247, 0.353, 0.173)
const LEMON := Color(0.973, 0.859, 0.322)
const ICE := Color(0.749, 0.888, 0.949)
const ICE_EDGE := Color(0.29, 0.42, 0.48)
const ORANGE := Color(0.97, 0.62, 0.24)
const OUTLINE_W := 2.5

func _ready() -> void:
	# Icons sit on top of buttons and labels; they must never eat a click.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	var side: float = minf(size.x, size.y)
	if side <= 0.0:
		return
	var s: float = side / 48.0
	var off := Vector2((size.x - 48.0 * s) * 0.5, (size.y - 48.0 * s) * 0.5)
	draw_set_transform(off, 0.0, Vector2(s, s))
	match kind:
		"lemon": _draw_lemon()
		"sugar": _draw_sugar()
		"ice": _draw_ice()
		"cup": _draw_cup()
		"coin": _draw_coin()
		"recipe": _draw_recipe()
		"shop": _draw_shop()
		"upgrades": _draw_upgrades()
		"map": _draw_map()
		"settings": _draw_settings()
		"sun": _draw_sun(LEMON, false)
		"hot": _draw_sun(ORANGE, true)
		"cold": _draw_cold()
		"rain": _draw_rain()
		"cloudy": _draw_cloud()

# --- Drawing helpers -----------------------------------------------------

func _ellipse(cx: float, cy: float, rx: float, ry: float, n: int = 32) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a: float = TAU * float(i) / float(n)
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	return pts

func _shape(pts: PackedVector2Array, fill: Color, outline: Color = WOOD_DARK, w: float = OUTLINE_W) -> void:
	draw_colored_polygon(pts, fill)
	if w > 0.0:
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, outline, w, true)

func _box(r: Rect2, fill: Color, outline: Color = WOOD_DARK, w: float = OUTLINE_W) -> void:
	draw_rect(r, fill, true)
	if w > 0.0:
		draw_rect(r, outline, false, w)

func _line(a: Vector2, b: Vector2, c: Color = WOOD_DARK, w: float = OUTLINE_W) -> void:
	draw_line(a, b, c, w, true)

func _dot(c: Vector2, r: float, fill: Color, outline: Color = WOOD_DARK, w: float = OUTLINE_W) -> void:
	draw_circle(c, r, fill, true, -1.0, true)
	if w > 0.0:
		draw_arc(c, r, 0.0, TAU, 32, outline, w, true)

# --- Inventory ------------------------------------------------------------

func _draw_lemon() -> void:
	_shape(_ellipse(24.0, 27.0, 17.0, 14.0), LEMON)
	draw_colored_polygon(_ellipse(17.0, 22.0, 5.0, 3.5), Color(1.0, 0.953, 0.69, 0.85))
	_shape(PackedVector2Array([
		Vector2(24.0, 15.0), Vector2(26.0, 9.0), Vector2(32.0, 5.0),
		Vector2(35.0, 8.0), Vector2(30.0, 13.0), Vector2(25.0, 14.5),
	]), GREEN, GREEN_DARK, 2.0)

func _draw_sugar() -> void:
	_box(Rect2(6.0, 20.0, 21.0, 21.0), CREAM)
	_box(Rect2(21.0, 11.0, 21.0, 21.0), WHITE)
	_line(Vector2(10.0, 27.0), Vector2(23.0, 27.0), WOOD_MID, 1.8)
	_line(Vector2(25.0, 18.0), Vector2(38.0, 18.0), WOOD_MID, 1.8)

func _draw_ice() -> void:
	_shape(PackedVector2Array([
		Vector2(10.0, 16.0), Vector2(24.0, 9.0), Vector2(38.0, 16.0),
		Vector2(38.0, 32.0), Vector2(24.0, 39.0), Vector2(10.0, 32.0),
	]), ICE, ICE_EDGE)
	_line(Vector2(10.0, 16.0), Vector2(24.0, 23.0), ICE_EDGE, 2.0)
	_line(Vector2(38.0, 16.0), Vector2(24.0, 23.0), ICE_EDGE, 2.0)
	_line(Vector2(24.0, 23.0), Vector2(24.0, 39.0), ICE_EDGE, 2.0)
	_line(Vector2(14.0, 19.0), Vector2(21.0, 22.5), Color(1, 1, 1, 0.8), 2.4)

func _draw_cup() -> void:
	_shape(PackedVector2Array([
		Vector2(12.0, 16.0), Vector2(36.0, 16.0), Vector2(33.0, 39.0),
		Vector2(15.0, 39.0),
	]), Color(1.0, 0.953, 0.69))
	_box(Rect2(9.0, 10.0, 30.0, 6.0), CREAM)
	_box(Rect2(27.0, 3.0, 4.0, 21.0), ORANGE, WOOD_DARK, 2.0)
	_line(Vector2(15.0, 23.0), Vector2(33.0, 23.0), WOOD_MID, 1.8)

# --- Menu bar -------------------------------------------------------------

func _draw_coin() -> void:
	_dot(Vector2(24.0, 24.0), 16.0, LEMON)
	_dot(Vector2(24.0, 24.0), 10.5, Color(0.988, 0.933, 0.616), WOOD_MID, 1.6)
	_line(Vector2(24.0, 15.0), Vector2(24.0, 33.0), WOOD_MID, 2.6)
	_line(Vector2(20.0, 19.0), Vector2(28.0, 19.0), WOOD_MID, 2.2)
	_line(Vector2(20.0, 29.0), Vector2(28.0, 29.0), WOOD_MID, 2.2)

func _draw_recipe() -> void:
	_box(Rect2(9.0, 5.0, 24.0, 38.0), CREAM)
	for y in [15.0, 22.0, 29.0]:
		_line(Vector2(14.0, y), Vector2(28.0, y), WOOD_MID, 2.2)
	_line(Vector2(14.0, 35.0), Vector2(23.0, 35.0), WOOD_MID, 2.2)

func _draw_shop() -> void:
	_shape(PackedVector2Array([
		Vector2(6.0, 17.0), Vector2(42.0, 17.0), Vector2(37.0, 41.0),
		Vector2(11.0, 41.0),
	]), Color(0.91, 0.784, 0.478))
	draw_arc(Vector2(24.0, 17.0), 9.0, PI, TAU, 24, WOOD_DARK, 2.5, true)
	_line(Vector2(16.0, 24.0), Vector2(32.0, 24.0), WOOD_MID, 2.0)

func _draw_upgrades() -> void:
	_shape(PackedVector2Array([
		Vector2(24.0, 5.0), Vector2(40.0, 21.0), Vector2(31.0, 21.0),
		Vector2(31.0, 33.0), Vector2(17.0, 33.0), Vector2(17.0, 21.0),
		Vector2(8.0, 21.0),
	]), GREEN, GREEN_DARK)
	_line(Vector2(9.0, 41.0), Vector2(39.0, 41.0), WOOD_DARK, 3.0)

# Folded map with a route and a marked spot, for the Areas tab.
func _draw_map() -> void:
	_shape(PackedVector2Array([
		Vector2(7.0, 12.0), Vector2(19.0, 8.0), Vector2(31.0, 13.0),
		Vector2(43.0, 9.0), Vector2(43.0, 39.0), Vector2(31.0, 43.0),
		Vector2(19.0, 38.0), Vector2(7.0, 42.0),
	]), CREAM)
	_line(Vector2(19.0, 8.0), Vector2(19.0, 38.0), WOOD_MID, 1.8)
	_line(Vector2(31.0, 13.0), Vector2(31.0, 43.0), WOOD_MID, 1.8)
	_line(Vector2(12.0, 32.0), Vector2(37.0, 21.0), GREEN_DARK, 2.2)
	_dot(Vector2(24.0, 26.0), 4.0, LEMON)

func _draw_settings() -> void:
	_dot(Vector2(24.0, 24.0), 7.0, CREAM)
	for i in 8:
		var a: float = TAU * float(i) / 8.0
		var d := Vector2(cos(a), sin(a))
		_line(Vector2(24.0, 24.0) + d * 12.0, Vector2(24.0, 24.0) + d * 19.0, WOOD_DARK, 3.0)

# --- Weather --------------------------------------------------------------

func _draw_sun(base: Color, strong: bool) -> void:
	_dot(Vector2(24.0, 24.0), 11.0, base)
	var n: int = 12 if strong else 8
	var inner: float = 15.0
	var outer: float = 21.0 if strong else 19.0
	for i in n:
		var a: float = TAU * float(i) / float(n)
		var d := Vector2(cos(a), sin(a))
		_line(Vector2(24.0, 24.0) + d * inner, Vector2(24.0, 24.0) + d * outer, base, 3.0)

func _draw_cold() -> void:
	for i in 6:
		var a: float = TAU * float(i) / 6.0
		var d := Vector2(cos(a), sin(a))
		_line(Vector2(24.0, 24.0), Vector2(24.0, 24.0) + d * 17.0, ICE_EDGE, 3.0)
	_dot(Vector2(24.0, 24.0), 4.0, WHITE, ICE_EDGE, 2.0)

func _draw_cloud() -> void:
	draw_circle(Vector2(17.0, 24.0), 9.0, WHITE, true, -1.0, true)
	draw_circle(Vector2(26.0, 21.0), 11.0, WHITE, true, -1.0, true)
	draw_circle(Vector2(34.0, 25.0), 8.0, WHITE, true, -1.0, true)
	draw_rect(Rect2(9.0, 25.0, 33.0, 9.0), WHITE, true)
	draw_arc(Vector2(17.0, 24.0), 9.0, PI, TAU, 20, WOOD_DARK, 2.5, true)
	draw_arc(Vector2(26.0, 21.0), 11.0, PI, TAU, 24, WOOD_DARK, 2.5, true)
	draw_arc(Vector2(34.0, 25.0), 8.0, PI, TAU, 18, WOOD_DARK, 2.5, true)
	_line(Vector2(9.0, 25.0), Vector2(9.0, 34.0), WOOD_DARK, 2.5)
	_line(Vector2(42.0, 25.0), Vector2(42.0, 34.0), WOOD_DARK, 2.5)
	_line(Vector2(9.0, 34.0), Vector2(42.0, 34.0), WOOD_DARK, 2.5)

func _draw_rain() -> void:
	draw_circle(Vector2(17.0, 19.0), 9.0, WHITE, true, -1.0, true)
	draw_circle(Vector2(26.0, 16.0), 11.0, WHITE, true, -1.0, true)
	draw_circle(Vector2(34.0, 20.0), 8.0, WHITE, true, -1.0, true)
	draw_rect(Rect2(9.0, 20.0, 33.0, 8.0), WHITE, true)
	draw_arc(Vector2(17.0, 19.0), 9.0, PI, TAU, 20, WOOD_DARK, 2.5, true)
	draw_arc(Vector2(26.0, 16.0), 11.0, PI, TAU, 24, WOOD_DARK, 2.5, true)
	draw_arc(Vector2(34.0, 20.0), 8.0, PI, TAU, 18, WOOD_DARK, 2.5, true)
	_line(Vector2(9.0, 20.0), Vector2(9.0, 28.0), WOOD_DARK, 2.5)
	_line(Vector2(42.0, 20.0), Vector2(42.0, 28.0), WOOD_DARK, 2.5)
	_line(Vector2(9.0, 28.0), Vector2(42.0, 28.0), WOOD_DARK, 2.5)
	for x in [15.0, 24.0, 33.0]:
		_line(Vector2(x, 33.0), Vector2(x - 2.0, 42.0), ICE_EDGE, 3.0)

# --- Shared helpers -------------------------------------------------------

# Which weather icon suits a weather dictionary.
static func kind_for_weather(temp: int, raining: bool) -> String:
	if raining:
		return "rain"
	if temp >= 90:
		return "hot"
	if temp <= 60:
		return "cold"
	return "sun"
