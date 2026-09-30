extends Control

# Recipe menu.
#
# Built in code as one scrollable list of rows, matching the Upgrades and Shop
# menus: name on the left, current value in the middle, - and + on the right.
# Every row shares the same column grid, so the list stays even as the numbers
# change width.
#
# The scene node only supplies the 700x500 panel; everything inside is built
# here, and any hand-laid-out rows left in the scene are cleared first.

const ROW_SEPARATION: int = 8
const ROW_HEIGHT: int = 58
const VALUE_WIDTH: int = 76
const STEP_BUTTON_SIZE: Vector2 = Vector2(64, 42)
const NAME_FONT: int = 20
const VALUE_FONT: int = 20
const STEP_FONT: int = 24
const SECTION_FONT: int = 17
const HINT_FONT: int = 15

const RowIcon = preload("res://assets/ui/row_icon.gd")
const ROW_ICON_SIZE: int = 34

# Stepper rows for the pitcher mix. "money" rows step in cents and print with
# two decimals; the others are whole units.
const MIX_ROWS: Array = [
	{"field": "recipe_lemons", "name": "Lemons", "min": 1.0, "max": 20.0, "step": 1.0, "money": false, "icon": "res://assets/ui/icons/lemon.png"},
	{"field": "recipe_sugar", "name": "Sugar", "min": 1.0, "max": 20.0, "step": 1.0, "money": false, "icon": "res://assets/ui/icons/sugar.png"},
]

const PRICE_ROWS: Array = [
	{"field": "recipe_ice", "name": "Ice Cubes", "min": 0.0, "max": 20.0, "step": 1.0, "money": false, "icon": "res://assets/ui/icons/ice.png"},
	{"field": "sale_price", "name": "Price per Cup", "min": 0.10, "max": 5.00, "step": 0.10, "money": true},
]

var _money_label: Label
var _rows: Array = []  # [{field: String, money: bool, value: Label}]

func _ready() -> void:
	_clear_placeholder_children()
	_build_ui()
	if not PlayerData.profile_updated.is_connected(_refresh):
		PlayerData.profile_updated.connect(_refresh)
	visibility_changed.connect(_on_visibility_changed)
	_refresh()

func _on_visibility_changed() -> void:
	if visible:
		_refresh()

# The scene ships the original hand-laid-out rows as placeholders. Drop them so
# the generated list is the only thing on screen.
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

	# Wrapped so a longer hint can never widen the panel past the steppers.
	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "How much fruit and sugar goes into each pitcher, and what you charge per cup."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.add_theme_font_size_override("font_size", HINT_FONT)
	hint.add_theme_color_override("font_color", Color(0.29, 0.22, 0.13))
	column.add_child(hint)

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

	rows.add_child(_build_section("Per Pitcher"))
	for def in MIX_ROWS:
		rows.add_child(_build_row(def))

	rows.add_child(_build_section("Per Cup"))
	for def in PRICE_ROWS:
		rows.add_child(_build_row(def))

func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.name = "Header"

	var title := Label.new()
	title.name = "Title"
	title.text = "Recipe"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.16, 0.11, 0.06))
	header.add_child(title)

	_money_label = Label.new()
	_money_label.name = "Money"
	_money_label.text = "Money: $0.00"
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_money_label.add_theme_font_size_override("font_size", 20)
	_money_label.add_theme_color_override("font_color", Color(0.16, 0.11, 0.06))
	header.add_child(_money_label)

	return header

func _build_section(text: String) -> Label:
	var section := Label.new()
	section.name = "Section"
	section.text = text
	section.add_theme_font_size_override("font_size", SECTION_FONT)
	section.add_theme_color_override("font_color", Color(0.45, 0.33, 0.19))
	return section

func _build_row(def: Dictionary) -> HBoxContainer:
	var field: String = str(def.get("field", ""))
	var is_money: bool = bool(def.get("money", false))

	var row := HBoxContainer.new()
	row.name = field
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.add_theme_constant_override("separation", 10)

	# Rows without art (the price row) still get a spacer of the same width, so
	# every name in the list starts at the same x and the grid stays even.
	var icon: Control = RowIcon.make(str(def.get("icon", "")), ROW_ICON_SIZE)
	if icon == null:
		icon = Control.new()
		icon.name = "IconSpacer"
		icon.custom_minimum_size = Vector2(float(ROW_ICON_SIZE), 0.0)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var row_name := Label.new()
	row_name.name = "Name"
	row_name.text = str(def.get("name", ""))
	row_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row_name.add_theme_font_size_override("font_size", NAME_FONT)
	row_name.add_theme_color_override("font_color", Color(0.16, 0.11, 0.06))
	row.add_child(row_name)

	var value := Label.new()
	value.name = "Value"
	value.text = "0"
	value.custom_minimum_size = Vector2(VALUE_WIDTH, 0)
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", VALUE_FONT)
	value.add_theme_color_override("font_color", Color(0.16, 0.11, 0.06))
	row.add_child(value)

	var down := Button.new()
	down.name = "Decrease"
	down.custom_minimum_size = STEP_BUTTON_SIZE
	down.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	down.add_theme_font_size_override("font_size", STEP_FONT)
	down.text = "-"
	down.pressed.connect(_step.bind(field, -float(def.get("step", 1.0)),
		float(def.get("min", 0.0)), float(def.get("max", 1.0)), is_money))
	row.add_child(down)

	var up := Button.new()
	up.name = "Increase"
	up.custom_minimum_size = STEP_BUTTON_SIZE
	up.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	up.add_theme_font_size_override("font_size", STEP_FONT)
	up.text = "+"
	up.pressed.connect(_step.bind(field, float(def.get("step", 1.0)),
		float(def.get("min", 0.0)), float(def.get("max", 1.0)), is_money))
	row.add_child(up)

	_rows.append({"field": field, "money": is_money, "value": value})
	return row

# --- State -> UI ---------------------------------------------------------

func _refresh() -> void:
	if _money_label == null:
		return
	_money_label.text = "Money: $%.2f" % PlayerData.money
	for entry in _rows:
		var label: Label = entry["value"]
		if label == null:
			continue
		if bool(entry["money"]):
			label.text = "$%.2f" % float(PlayerData[entry["field"]])
		else:
			label.text = str(int(PlayerData[entry["field"]]))

# --- Input ---------------------------------------------------------------

func _step(field: String, delta: float, min_value: float, max_value: float, is_money: bool) -> void:
	var current: float = float(PlayerData[field])
	var new_value: float = clampf(current + delta, min_value, max_value)
	if is_money:
		new_value = snappedf(new_value, 0.01)
	if is_equal_approx(current, new_value):
		return
	# profile_updated refreshes the row, so the label never drifts from state.
	if is_money:
		PlayerData[field] = new_value
	else:
		PlayerData[field] = int(round(new_value))
	PlayerData.profile_updated.emit()
