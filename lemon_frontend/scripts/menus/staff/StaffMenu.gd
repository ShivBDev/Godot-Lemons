extends Control

# Hire staff for the coming day. Each hire is a toggle: on means they work
# tomorrow and their wage comes out of the till when that day ends. Turning
# someone off before the day starts spends nothing.

const HINT_FONT: int = 15
const NOTICE_FONT: int = 15
const META_FONT: int = 16
const ROW_SEPARATION: int = 10
const RowIcon = preload("res://assets/ui/row_icon.gd")

const TITLE_COLOR := Color(0.16, 0.11, 0.06)
const BODY_COLOR := Color(0.29, 0.22, 0.13)
const WARN_COLOR := Color(0.55, 0.16, 0.10)
const ON_COLOR := Color(0.24, 0.42, 0.20)

var _money_label: Label
var _notice: Label
var _rows: Array = []

func _ready() -> void:
	_clear_placeholder_children()
	_build_ui()
	if not PlayerData.profile_updated.is_connected(_refresh):
		PlayerData.profile_updated.connect(_refresh)
	visibility_changed.connect(_on_visibility_changed)
	_refresh()

func _on_visibility_changed() -> void:
	if visible:
		_set_notice("")
		_refresh()

func _clear_placeholder_children() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

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

	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "Hire help for the next day. Wages come out of the till up front, the moment the day starts, and only for the people you left switched on. The server opens a second line. The advertiser walks the pavement and brings more people past."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.add_theme_font_size_override("font_size", HINT_FONT)
	hint.add_theme_color_override("font_color", BODY_COLOR)
	column.add_child(hint)

	_notice = Label.new()
	_notice.name = "Notice"
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notice.add_theme_font_size_override("font_size", NOTICE_FONT)
	_notice.add_theme_color_override("font_color", WARN_COLOR)
	column.add_child(_notice)
	column.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", ROW_SEPARATION)
	scroll.add_child(rows)
	for staffMember in StaffCatalog.all():
		rows.add_child(_build_row(staffMember))

func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Staff"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	header.add_child(title)
	_money_label = Label.new()
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money_label.add_theme_font_size_override("font_size", 20)
	_money_label.add_theme_color_override("font_color", TITLE_COLOR)
	header.add_child(_money_label)
	return header

func _build_row(staffMember: StaffMember) -> HBoxContainer:
	var id: StaffMember.STAFF_ID = staffMember.id
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var icon := RowIcon.make(staffMember.icon)
	if icon != null:
		row.add_child(icon)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_label := Label.new()
	name_label.text = staffMember.name
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", TITLE_COLOR)
	info.add_child(name_label)
	var blurb := Label.new()
	blurb.text = staffMember.blurb
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_font_size_override("font_size", META_FONT)
	blurb.add_theme_color_override("font_color", BODY_COLOR)
	info.add_child(blurb)
	var meta := Label.new()
	meta.add_theme_font_size_override("font_size", META_FONT)
	meta.add_theme_color_override("font_color", ON_COLOR)
	info.add_child(meta)
	var button := Button.new()
	button.custom_minimum_size = Vector2(120, 44)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(_on_toggle.bind(id))
	row.add_child(button)
	_rows.append({"id": id, "button": button, "meta": meta})
	return row

func _refresh() -> void:
	if _money_label == null:
		return
	_money_label.text = "Money: $%.2f" % PlayerData.money
	var wage: float = PlayerData.staff_daily_wage()
	for entry in _rows:
		var id: StaffMember.STAFF_ID = entry["id"]
		var hired: bool = PlayerData.is_hired(id)
		var button: Button = entry["button"]
		var meta: Label = entry["meta"]
		if button != null:
			button.text = "Hired" if hired else "Hire"
			# Locked only when taking someone on is what you cannot afford;
			# switching an existing hire off is always allowed.
			button.disabled = (not hired) and (not PlayerData.can_afford_hire(id))
		if meta != null:
			var cost: float = StaffCatalog.daily_cost(id)
			meta.text = "$%.2f / day - %s" % [cost, "on for tomorrow" if hired else "off"]
	if wage > 0.0:
		_set_notice("Tomorrow's wages if you leave them on: $%.2f." % wage)

func _on_toggle(id: StaffMember.STAFF_ID) -> void:
	# Taking someone on has to leave enough in the till to still start the day.
	if not PlayerData.is_hired(id) and not PlayerData.can_afford_hire(id):
		_set_notice("You cannot afford %s on top of today's costs." % StaffCatalog.name_of(id))
		return
	var now_hired: bool = PlayerData.toggle_hire(id)
	if now_hired:
		_set_notice("%s is hired. Their wage comes out up front when the day starts." % StaffCatalog.name_of(id))
	else:
		_set_notice("%s is off the roster." % StaffCatalog.name_of(id))
	_refresh()

func _set_notice(text: String) -> void:
	if _notice != null and is_instance_valid(_notice):
		_notice.text = text
