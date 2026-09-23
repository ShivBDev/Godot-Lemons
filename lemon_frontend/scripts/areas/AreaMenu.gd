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

const TITLE_COLOR := Color(0.16, 0.11, 0.06)
const BODY_COLOR := Color(0.29, 0.22, 0.13)
const WARN_COLOR := Color(0.55, 0.16, 0.10)
const FREE_COLOR := Color(0.24, 0.42, 0.20)

var _money_label: Label
var _notice: Label
# [{id: String, button: Button, meta: Label, teams: Label}]
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

func _on_area_changed(_area_id: String) -> void:
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
	hint.text = "Where you set up changes who walks past and what they will pay. The neighbourhood is free to work. Downtown and the stadium bring far more customers and looser wallets, but charge a flat fee at the end of every day you work there."
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

func _build_row(area: Dictionary) -> PanelContainer:
	var id: String = str(area.get("id", ""))
	var panel := PanelContainer.new()
	panel.name = "Area_" + id
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 10)
	panel.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	pad.add_child(column)

	var head := HBoxContainer.new()
	column.add_child(head)

	var title := Label.new()
	title.text = str(area.get("name", ""))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	head.add_child(title)

	var fee: float = float(area.get("daily_fee", 0.0))
	var fee_label := Label.new()
	fee_label.name = "Fee"
	fee_label.text = "Free" if fee <= 0.0 else "$%.2f / day" % fee
	fee_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fee_label.add_theme_font_size_override("font_size", 18)
	fee_label.add_theme_color_override("font_color", FREE_COLOR if fee <= 0.0 else WARN_COLOR)
	head.add_child(fee_label)

	var blurb := Label.new()
	blurb.text = str(area.get("blurb", ""))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blurb.add_theme_font_size_override("font_size", HINT_FONT)
	blurb.add_theme_color_override("font_color", BODY_COLOR)
	column.add_child(blurb)

	var meta := Label.new()
	meta.name = "Meta"
	meta.add_theme_font_size_override("font_size", META_FONT)
	meta.add_theme_color_override("font_color", BODY_COLOR)
	column.add_child(meta)

	# Stadium only: the two kits the crowd is wearing today.
	var teams := Label.new()
	teams.name = "Teams"
	teams.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	teams.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	teams.add_theme_font_size_override("font_size", META_FONT)
	teams.add_theme_color_override("font_color", BODY_COLOR)
	teams.visible = false
	column.add_child(teams)

	var move := Button.new()
	move.name = "Move"
	move.custom_minimum_size = Vector2(0, 44)
	move.text = "Move Here"
	move.pressed.connect(_on_move_pressed.bind(id))
	column.add_child(move)

	_rows.append({"id": id, "button": move, "meta": meta, "teams": teams})
	return panel

# --- Refresh -------------------------------------------------------------

func _refresh() -> void:
	if _money_label != null and is_instance_valid(_money_label):
		_money_label.text = "Money: $%.2f" % PlayerData.money
	var current: String = PlayerData.current_area_id()
	for row in _rows:
		var id: String = str(row["id"])
		var traffic: float = AreaCatalog.traffic_for(id)
		var price_mult: float = AreaCatalog.price_multiplier_for(id)
		var fee: float = AreaCatalog.daily_fee_for(id)
		var meta: Label = row["meta"]
		if meta != null and is_instance_valid(meta):
			meta.text = "Foot traffic x%.2f   -   Willing to pay x%.2f   -   Fee %s" % [
				traffic, price_mult, "free" if fee <= 0.0 else "$%.2f" % fee]
		_refresh_teams(row["teams"], id, current)
		var button: Button = row["button"]
		if button == null or not is_instance_valid(button):
			continue
		if id == current:
			button.text = "Working Here"
			button.disabled = true
		else:
			button.text = "Move Here" if fee <= 0.0 else "Move Here  ($%.2f / day)" % fee
			button.disabled = false

func _refresh_teams(label: Label, id: String, current: String) -> void:
	if label == null or not is_instance_valid(label):
		return
	if id != AreaCatalog.STADIUM or id != current:
		label.visible = false
		return
	var names: PackedStringArray = PackedStringArray()
	for theme in PlayerData.team_pair:
		if typeof(theme) == TYPE_DICTIONARY:
			names.append(str(theme.get("name", "")))
	if names.is_empty():
		label.text = "Today's kits are drawn when the day starts."
	else:
		label.text = "Today's kits: %s" % " vs ".join(names)
	label.visible = true

func _on_move_pressed(id: String) -> void:
	if not AreaCatalog.has_area(id):
		_set_notice("That location is not available.")
		return
	if id == PlayerData.current_area_id():
		return
	var fee: float = AreaCatalog.daily_fee_for(id)
	PlayerData.set_area(id)
	if fee > 0.0:
		_set_notice("Set up in %s. The $%.2f fee comes out when the day ends." % [
			AreaCatalog.name_for(id), fee])
	else:
		_set_notice("Set up in %s. No fee to work here." % AreaCatalog.name_for(id))

func _set_notice(text: String) -> void:
	if _notice != null and is_instance_valid(_notice):
		_notice.text = text
