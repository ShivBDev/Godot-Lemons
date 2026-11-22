extends Control

# Recipe menu.
#
# The layout lives in the scene: a row per recipe field, named after the
# PlayerData field it edits, with its icon, value readout and two step buttons.
# This script keeps those rows in step with the profile.

const MIX_ROWS: Array = [
	{"field": "recipe_lemons", "name": "Lemons", "min": 1.0, "max": 20.0, "step": 1.0, "money": false, "icon": "res://assets/ui/icons/lemon.png"},
	{"field": "recipe_sugar", "name": "Sugar", "min": 1.0, "max": 20.0, "step": 1.0, "money": false, "icon": "res://assets/ui/icons/sugar.png"},
]

const PRICE_ROWS: Array = [
	{"field": "recipe_ice", "name": "Ice Cubes", "min": 0.0, "max": 20.0, "step": 1.0, "money": false, "icon": "res://assets/ui/icons/ice.png"},
	{"field": "sale_price", "name": "Price per Cup", "min": 2.50, "max": 15.00, "step": 0.25, "money": true},
]

@onready var _money_label: Label = $Layout/Column/Header/Money
@onready var _rows_box: VBoxContainer = $Layout/Column/Scroll/Rows
var _rows: Array = []  # [{field: String, money: bool, value: Label}]

func _ready() -> void:
	_bind_rows()
	if not PlayerData.profile_updated.is_connected(_refresh):
		PlayerData.profile_updated.connect(_refresh)
	visibility_changed.connect(_on_visibility_changed)
	_refresh()

func _on_visibility_changed() -> void:
	if visible:
		_refresh()

func _bind_rows() -> void:
	for def in MIX_ROWS + PRICE_ROWS:
		var field: String = str(def.get("field", ""))
		var row: Control = _rows_box.get_node(field)
		var step: float = float(def.get("step", 1.0))
		var low: float = float(def.get("min", 0.0))
		var high: float = float(def.get("max", 1.0))
		var is_money: bool = bool(def.get("money", false))
		row.get_node("Decrease").pressed.connect(_step.bind(field, -step, low, high, is_money))
		row.get_node("Increase").pressed.connect(_step.bind(field, step, low, high, is_money))
		_rows.append({"field": field, "money": is_money, "value": row.get_node("Value")})

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
