extends Panel

# Scrolling headline for the day about to be played. Hidden while a day is
# running, because the news is a shopping-time preview, not a live overlay.

const SCROLL_SPEED: float = 70.0

@onready var _label: Label = $Headline
var _offset: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not PlayerData.news_changed.is_connected(_refresh):
		PlayerData.news_changed.connect(_refresh)
	_refresh()

func _process(delta: float) -> void:
	var running: bool = false
	var sim: Node = get_node_or_null("../DaySimulator/SubViewport/DaySimulation")
	if sim != null and sim.has_method("is_running"):
		running = bool(sim.call("is_running"))
	visible = not running
	if not visible or _label == null:
		return
	_offset -= SCROLL_SPEED * delta
	var width: float = maxf(size.x, 200.0)
	if _offset < -_label.size.x - 40.0:
		_offset = width
	_label.position = Vector2(_offset, 8.0)

func _refresh() -> void:
	if _label == null:
		return
	_label.text = NewsCatalog.headline(PlayerData.current_news())
	_offset = size.x if size.x > 0.0 else 700.0
