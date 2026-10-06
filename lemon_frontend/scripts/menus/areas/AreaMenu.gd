extends Control

# Pick where the stand is set up. One row per AreaCatalog entry: the crowd it
# brings, what those customers will pay, and what the pitch costs per day.
#
# Moving is a single PlayerData write. The day sim listens for area_changed and
# swaps the scenery, and the next day runs under the new numbers, so this menu
# never touches the 3D scene or the sim directly.

const HINT_FONT: int = 15
const NOTICE_FONT: int = 15
const META_FONT: int = 16
const ROW_SEPARATION: int = 10
const RowIcon = preload("res://assets/ui/row_icon.gd")

const TITLE_COLOR := Color(0.16, 0.11, 0.06)
const BODY_COLOR := Color(0.29, 0.22, 0.13)
const WARN_COLOR := Color(0.55, 0.16, 0.10)
const FREE_COLOR := Color(0.24, 0.42, 0.20)

var _money_label: Label
var _notice: Label
# One entry per area row: the move button, the three meta value labels, the
# popularity readout and its bar, and the stadium kits line.
# [{id, button, meta_traffic, meta_price, meta_fee, pop_label, pop_bar, teams}]
var _rows: Array = []

func _ready() -> void:
	_clear_placeholder_children()
	_build_ui()
	if not PlayerData.profile_updated.is_connected(_refresh):
		PlayerData.profile_updated.connect(_refresh)
	if not PlayerData.area_changed.is_connected(_on_area_changed):
		PlayerData.area_changed.connect(_on_area_changed)
	# Money and today's stadium kits both change while the menu is closed, so
	# re-read everything each time it is opened.
	visibility_changed.connect(_on_visibility_changed)
	_refresh()

func _on_visibility_changed() -> void:
	if visible:
		_set_notice("")
		_refresh()

func _on_area_changed(_area_id: MapArea.AreaID) -> void:
	_set_notice("")
	_refresh()

# The scene may ship hand-laid-out placeholder rows. Drop them so the generated
# list is the only thing on screen.
func _clear_placeholder_children() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

# --- UI construction -----------------------------------------------------

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.name = "Layout"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	column.add_child(_build_header())

	# Word wrap is load bearing: an unwrapped Label reports its whole text as
	# its minimum width, which stretches the row grid past the 700px panel.
	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "Where you set up changes who walks past and what they will pay. The neighbourhood is free to work. Downtown and the stadium bring far more customers and looser wallets, but charge a flat fee up front, every day you work there."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.add_theme_font_size_override("font_size", HINT_FONT)
	hint.add_theme_color_override("font_color", BODY_COLOR)
	column.add_child(hint)

	_notice = Label.new()
	_notice.name = "Notice"
	_notice.text = ""
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notice.add_theme_font_size_override("font_size", NOTICE_FONT)
	_notice.add_theme_color_override("font_color", WARN_COLOR)
	column.add_child(_notice)

	column.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", ROW_SEPARATION)
	scroll.add_child(rows)

	for area in AreaCatalog.all():
		rows.add_child(_build_row(area))

func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.name = "Header"

	var title := Label.new()
	title.name = "Title"
	title.text = "Areas"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	header.add_child(title)

	_money_label = Label.new()
	_money_label.name = "Money"
	_money_label.text = "Money: $0.00"
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_money_label.add_theme_font_size_override("font_size", 20)
	_money_label.add_theme_color_override("font_color", TITLE_COLOR)
	header.add_child(_money_label)

	return header

func _build_row(area: MapArea) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Area_" + area.id_str
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 10)
	panel.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	pad.add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	column.add_child(head)

	var icon := RowIcon.make(area.icon)
	if icon != null:
		head.add_child(icon)

	var title := Label.new()
	title.text = area.name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	head.add_child(title)

	var fee: float = area.daily_fee
	var fee_label := Label.new()
	fee_label.name = "Fee"
	fee_label.text = "Free" if fee <= 0.0 else "$%.2f / day" % fee
	fee_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fee_label.add_theme_font_size_override("font_size", 18)
	fee_label.add_theme_color_override("font_color", FREE_COLOR if fee <= 0.0 else WARN_COLOR)
	head.add_child(fee_label)

	var blurb := Label.new()
	blurb.text = area.blurb
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blurb.add_theme_font_size_override("font_size", HINT_FONT)
	blurb.add_theme_color_override("font_color", BODY_COLOR)
	column.add_child(blurb)

	# Foot traffic and price tolerance are reported as words, never as the
	# multipliers behind them: those are balance numbers, and Low / Medium /
	# High is what the choice actually comes down to at the stand.
	var meta := HBoxContainer.new()
	meta.name = "Meta"
	meta.add_theme_constant_override("separation", 18)
	column.add_child(meta)

	var meta_traffic := _add_meta_stat(meta, "Foot traffic:")
	var meta_price := _add_meta_stat(meta, "Willing to pay:")
	var meta_fee := _add_meta_stat(meta, "Fee:")

	# How well known the stand is in THIS area. Popularity is tracked per
	# area, so this bar is that area's own reputation rather than the one the
	# player is currently standing in.
	var pop_box := VBoxContainer.new()
	pop_box.name = "Popularity"
	pop_box.add_theme_constant_override("separation", 2)
	column.add_child(pop_box)

	var pop_label := Label.new()
	pop_label.name = "PopularityLabel"
	pop_label.add_theme_font_size_override("font_size", META_FONT)
	pop_label.add_theme_color_override("font_color", BODY_COLOR)
	pop_box.add_child(pop_label)

	var pop_bar := ProgressBar.new()
	pop_bar.name = "PopularityBar"
	pop_bar.custom_minimum_size = Vector2(0, 14)
	pop_bar.show_percentage = false
	pop_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pop_bar.max_value = 1.0
	pop_bar.value = 0.0
	pop_bar.add_theme_stylebox_override("background", _bar_style(BAR_BG_COLOR, BAR_BORDER_COLOR))
	pop_bar.add_theme_stylebox_override("fill", _bar_style(BAR_FILL_COLOR, BAR_BORDER_COLOR))
	pop_box.add_child(pop_bar)

	var move := Button.new()
	move.name = "Move"
	move.custom_minimum_size = Vector2(0, 44)
	move.text = "Move Here"
	move.pressed.connect(_on_move_pressed.bind(area.id))
	column.add_child(move)

	_rows.append({
		"id": area.id_str,
		"button": move,
		"meta_traffic": meta_traffic,
		"meta_price": meta_price,
		"meta_fee": meta_fee,
		"pop_label": pop_label,
		"pop_bar": pop_bar,
		#"teams": teams,
	})
	return panel

# --- Refresh -------------------------------------------------------------

func _refresh() -> void:
	if _money_label != null and is_instance_valid(_money_label):
		_money_label.text = "Money: $%.2f" % PlayerData.money
	var currentArea: String = MapArea.ID2Str(PlayerData.current_area)
	for row in _rows:
		var id: String = str(row["id"])
		var rowArea: MapArea = AreaCatalog.get_area(MapArea.Str2ID(id))
		var traffic: float = rowArea.traffic
		var price_mult: float = rowArea.price_tolerance
		var fee: float = rowArea.daily_fee
		_set_tier_label(row["meta_traffic"], _tier_for(traffic, TRAFFIC_LOW_MAX, TRAFFIC_MED_MAX))
		_set_tier_label(row["meta_price"], _tier_for(price_mult, PRICE_LOW_MAX, PRICE_MED_MAX))
		var fee_value: Label = row["meta_fee"]
		if fee_value != null and is_instance_valid(fee_value):
			fee_value.text = "free" if fee <= 0.0 else "$%.2f" % fee
			fee_value.add_theme_color_override("font_color", FREE_COLOR if fee <= 0.0 else WARN_COLOR)
		_refresh_popularity(row, rowArea.id)
		var button: Button = row["button"]
		if button == null or not is_instance_valid(button):
			continue
		if id == currentArea:
			button.text = "Working Here"
			button.disabled = true
		else:
			button.text = "Move Here" if fee <= 0.0 else "Move Here  ($%.2f / day)" % fee
			# Locked when the new fee plus the wages already on the books would
			# not fit in the till, so a move can never make the day unstartable.
			button.disabled = not PlayerData.can_afford_area(rowArea.id)

func _on_move_pressed(id: MapArea.AreaID) -> void:
	if not AreaCatalog.has_area(id):
		_set_notice("That location is not available.")
		return
	if id == PlayerData.current_area:
		return
	var area: MapArea = AreaCatalog.get_area(id)
	var fee: float = area.daily_fee
	# Moving has to leave enough in the till to still start the day.
	if not PlayerData.can_afford_area(id):
		_set_notice("You cannot afford to set up in %s yet: $%.2f a day plus wages." % [
			area.name, fee])
		return
	PlayerData.set_area(id)
	if fee > 0.0:
		_set_notice("Set up in %s. The $%.2f fee comes out up front when the day starts." % [
			area.name, fee])
	else:
		_set_notice("Set up in %s. No fee to work here." % area.name)

func _set_notice(text: String) -> void:
	if _notice != null and is_instance_valid(_notice):
		_notice.text = text

# --- Presentation helpers ------------------------------------------------

# Foot traffic and price tolerance are shown as words, never as multipliers.
# The exact figures are balance internals living in AreaCatalog; a shopper only
# needs to read the tier, and the word carries its own colour.
const TRAFFIC_LOW_MAX: float = 1.15
const TRAFFIC_MED_MAX: float = 1.60
const PRICE_LOW_MAX: float = 1.25
const PRICE_MED_MAX: float = 1.80

const TIER_LOW := "Low"
const TIER_MEDIUM := "Medium"
const TIER_HIGH := "High"

const TIER_LOW_COLOR := Color(0.45, 0.38, 0.30)
const TIER_MEDIUM_COLOR := Color(0.72, 0.47, 0.08)
const TIER_HIGH_COLOR := Color(0.20, 0.47, 0.22)

const BAR_BG_COLOR := Color(1.0, 0.973, 0.882, 0.85)
const BAR_BORDER_COLOR := Color(0.784, 0.631, 0.396, 1.0)
const BAR_FILL_COLOR := Color(0.663, 0.808, 0.478, 1.0)

# One "name: value" pair inside the meta row, so the value can carry its own
# colour without repainting the whole line.
func _add_meta_stat(parent: HBoxContainer, prefix: String) -> Label:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)

	var name_label := Label.new()
	name_label.text = prefix
	name_label.add_theme_font_size_override("font_size", META_FONT)
	name_label.add_theme_color_override("font_color", BODY_COLOR)
	box.add_child(name_label)

	var value := Label.new()
	value.add_theme_font_size_override("font_size", META_FONT)
	value.add_theme_color_override("font_color", BODY_COLOR)
	box.add_child(value)
	return value

func _tier_for(value: float, low_max: float, med_max: float) -> String:
	if value < low_max:
		return TIER_LOW
	if value < med_max:
		return TIER_MEDIUM
	return TIER_HIGH

func _tier_color(tier: String) -> Color:
	if tier == TIER_HIGH:
		return TIER_HIGH_COLOR
	if tier == TIER_MEDIUM:
		return TIER_MEDIUM_COLOR
	return TIER_LOW_COLOR

func _set_tier_label(label: Label, tier: String) -> void:
	if label == null or not is_instance_valid(label):
		return
	label.text = tier
	label.add_theme_color_override("font_color", _tier_color(tier))

func _bar_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	return style

# Fills one row's popularity bar with THAT area's own reputation. Popularity is
# tracked per area, so the bar reads how well known the stand is wherever the
# row points, not where the stand happens to be standing. The bar measures
# progress toward the next rank, so a maxed area shows full rather than empty,
# and the label above it carries the rank itself.
func _refresh_popularity(row: Dictionary, id: MapArea.AreaID) -> void:
	var label: Label = row["pop_label"]
	if label == null or not is_instance_valid(label):
		return
	var level: int = PlayerData.popularity_level(id)
	var points: int = PlayerData.popularity_points(id)
	var goal: int = PlayerData.popularity_goal(id)
	var bar: ProgressBar = row["pop_bar"]
	if level >= Popularity.MAX_RANK or goal <= 0:
		label.text = "Popularity  Rank %d / %d  -  top of this area" % [level, Popularity.MAX_RANK]
		if bar != null and is_instance_valid(bar):
			bar.max_value = 1.0
			bar.value = 1.0
		return
	label.text = "Popularity  Rank %d / %d  -  %d / %d points to next" % [
		level, Popularity.MAX_RANK, points, goal]
	if bar != null and is_instance_valid(bar):
		bar.max_value = float(goal)
		bar.value = float(clampi(points, 0, goal))
