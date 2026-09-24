extends Control

# Upgrades menu.
#
# The scene hands this Control the 700x500 menu area. Everything inside is
# built in code because the content is data-driven: one row is generated per
# UpgradeCatalog entry, grouped under the entry's "group" heading. Adding an
# upgrade to the catalog adds it here, and a new group name adds a heading.
#
# State lives in PlayerData (upgrade_levels). A purchase is a plain
# PlayerData.buy_upgrade() call; DaySimulation and PlayerData read the new
# levels, so a purchase lands on the next day.

const ROW_SEPARATION: int = 12
const BUY_BUTTON_SIZE: Vector2 = Vector2(150, 52)
const SECTION_FONT: int = 19
const RowIcon = preload("res://assets/ui/row_icon.gd")

var _moneyLabel: Label
var _rowsBox: VBoxContainer
var _rowIds: Array[String] = []
var _rowLevels: Dictionary = {}  # upgrade id -> Label (level readout)
var _rowButtons: Dictionary = {}  # upgrade id -> Button (buy)

func _ready() -> void:
	_build_ui()
	if not PlayerData.profile_updated.is_connected(_refresh):
		PlayerData.profile_updated.connect(_refresh)
	# Money can also change while the menu is closed (shop, day results),
	# so re-read the profile every time the menu is opened.
	visibility_changed.connect(_on_visibility_changed)
	_refresh()

func _on_visibility_changed() -> void:
	if visible:
		_refresh()

# --- UI construction -----------------------------------------------------

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.name = "Layout"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	column.add_child(_build_header())

	# Wrapped for the same reason as the shop hint: an unwrapped line sets the
	# panel's minimum width and would push the buy buttons off the edge.
	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "Buy an upgrade to raise its level. Most apply from the next day; storage and cooler upgrades apply straight away."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.12, 0.18, 0.12))
	column.add_child(hint)

	column.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_rowsBox = VBoxContainer.new()
	_rowsBox.name = "Rows"
	_rowsBox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rowsBox.add_theme_constant_override("separation", ROW_SEPARATION)
	scroll.add_child(_rowsBox)

	_build_rows()

func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.name = "Title"
	title.text = "Upgrades"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0, 0, 0))
	header.add_child(title)

	_moneyLabel = Label.new()
	_moneyLabel.name = "Money"
	_moneyLabel.text = "Money: $0.00"
	_moneyLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_moneyLabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_moneyLabel.add_theme_font_size_override("font_size", 24)
	_moneyLabel.add_theme_color_override("font_color", Color(0, 0, 0))
	header.add_child(_moneyLabel)

	return header

func _build_rows() -> void:
	var first_in_group: bool = true
	var current_group: String = ""
	for def in UpgradeCatalog.all():
		var id: String = str(def.get("id", ""))
		if id == "":
			continue
		# A new heading replaces the separator, so each group reads as one
		# block rather than a flat list of eleven rows.
		var group: String = str(def.get("group", ""))
		if group != current_group:
			current_group = group
			first_in_group = true
			if group != "":
				_rowsBox.add_child(_build_section(group))
		if not first_in_group:
			_rowsBox.add_child(HSeparator.new())
		first_in_group = false
		_rowIds.append(id)
		_rowsBox.add_child(_build_row(def))

func _build_section(text: String) -> Label:
	var section := Label.new()
	section.name = "Section"
	section.text = text
	section.add_theme_font_size_override("font_size", SECTION_FONT)
	section.add_theme_color_override("font_color", Color(0.45, 0.33, 0.19))
	return section

func _build_row(def: Dictionary) -> HBoxContainer:
	var id: String = str(def.get("id", ""))

	var row := HBoxContainer.new()
	row.name = id
	row.add_theme_constant_override("separation", 28)

	var icon := RowIcon.make(str(def.get("icon", "")))
	if icon != null:
		row.add_child(icon)

	var info := VBoxContainer.new()
	info.name = "Info"
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)

	var rowName := Label.new()
	rowName.name = "Name"
	rowName.text = str(def.get("name", id))
	rowName.add_theme_font_size_override("font_size", 22)
	rowName.add_theme_color_override("font_color", Color(0, 0, 0))
	info.add_child(rowName)

	var level := Label.new()
	level.name = "Level"
	level.text = "Level 0"
	level.add_theme_font_size_override("font_size", 16)
	level.add_theme_color_override("font_color", Color(0.15, 0.25, 0.15))
	info.add_child(level)
	_rowLevels[id] = level

	var description := Label.new()
	description.name = "Description"
	description.text = str(def.get("description", ""))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", 16)
	description.add_theme_color_override("font_color", Color(0.15, 0.25, 0.15))
	info.add_child(description)

	var buy := Button.new()
	buy.name = "Buy"
	buy.custom_minimum_size = BUY_BUTTON_SIZE
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.add_theme_font_size_override("font_size", 18)
	buy.pressed.connect(_on_buy_pressed.bind(id))
	row.add_child(buy)
	_rowButtons[id] = buy

	return row

# --- State -> UI ---------------------------------------------------------

func _refresh() -> void:
	if _moneyLabel == null:
		return
	_moneyLabel.text = "Money: $%.2f" % PlayerData.money
	for id in _rowIds:
		_refresh_row(id)

func _refresh_row(id: String) -> void:
	var levelLabel: Label = _rowLevels.get(id)
	var buy: Button = _rowButtons.get(id)
	if levelLabel == null or buy == null:
		return
	var level: int = PlayerData.get_upgrade_level(id)
	var maxLevel: int = UpgradeCatalog.max_level_of(id)
	levelLabel.text = "Level %d / %d" % [level, maxLevel]
	if maxLevel > 0 and level >= maxLevel:
		buy.text = "MAX"
		buy.disabled = true
		return
	var cost: float = PlayerData.upgrade_cost(id)
	buy.text = "$%.2f" % cost
	buy.disabled = PlayerData.money < cost

# --- Input ---------------------------------------------------------------

func _on_buy_pressed(id: String) -> void:
	# buy_upgrade() emits profile_updated on success, which refreshes the rows.
	PlayerData.buy_upgrade(id)
