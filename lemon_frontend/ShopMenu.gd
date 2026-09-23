extends Control

# Shop menu.
#
# Rows are built in code so every ingredient shares one column grid: name and
# stock on the left, three pack buttons on the right. This mirrors the Upgrades
# menu, which keeps the two lists visually consistent.
#
# The scene node only supplies the 700x500 panel; everything inside is built
# here, and any hand-laid-out rows left in the scene are cleared first.

const ROW_SEPARATION: int = 8
const ROW_HEIGHT: int = 68
const PACK_BUTTON_SIZE: Vector2 = Vector2(104, 40)
const PACK_GAP: int = 10
const NAME_FONT: int = 20
const STOCK_FONT: int = 16
const PACK_FONT: int = 14
const HINT_FONT: int = 15
const NOTE_FONT: int = 14
const NOTICE_FONT: int = 15

# One entry per shop row. "field" is the PlayerData stock variable, and each
# pack is [quantity, price].
const ITEMS: Array = [
	{
		"name": "Lemons",
		"field": "lemon_stock",
		"packs": [[12, 4.50], [24, 7.50], [48, 12.50]],
	},
	{
		"name": "Sugar",
		"field": "sugar_stock",
		"packs": [[12, 4.80], [20, 7.00], [50, 15.00]],
	},
	{
		"name": "Ice",
		"field": "ice_stock",
		"packs": [[50, 1.00], [200, 3.00], [500, 5.50]],
	},
	{
		"name": "Cups",
		"field": "cup_stock",
		"packs": [[75, 1.00], [250, 2.50], [500, 4.50]],
	},
]

var _money_label: Label
var _notice: Label
# [{field: String, stock: Label, note: Label, packs: [{button, qty, price}]}]
var _rows: Array = []

func _ready() -> void:
	_clear_placeholder_children()
	_build_ui()
	if not PlayerData.profile_updated.is_connected(_refresh):
		PlayerData.profile_updated.connect(_refresh)
	# Money and stocks also change while the menu is closed, so re-read the
	# profile every time the menu is opened.
	visibility_changed.connect(_on_visibility_changed)
	_refresh()

func _on_visibility_changed() -> void:
	if visible:
		# Drop any notice from last time, so a stale "shelf is full" does not
		# greet the player after they bought storage.
		_set_notice("")
		_refresh()

# The scene ships the original hand-laid-out rows as placeholders. Drop them so
# the generated grid is the only thing on screen.
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

	# Word wrap is load bearing here, not decoration: an unwrapped Label reports
	# its whole text as its minimum width, which stretches the row grid wider
	# than the 700px panel and pushes the pack buttons off the right edge.
	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "The stand only holds so much of each ingredient. Ice melts overnight and lemons keep for a week, so buy storage and cooler upgrades in the Upgrades tab."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.add_theme_font_size_override("font_size", HINT_FONT)
	hint.add_theme_color_override("font_color", Color(0.29, 0.22, 0.13))
	column.add_child(hint)

	# Says why a purchase was turned down, or how much of a pack actually fit.
	# Empty most of the time, so it costs no room when nothing is wrong.
	_notice = Label.new()
	_notice.name = "Notice"
	_notice.text = ""
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notice.add_theme_font_size_override("font_size", NOTICE_FONT)
	_notice.add_theme_color_override("font_color", Color(0.55, 0.16, 0.10))
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

	for item in ITEMS:
		rows.add_child(_build_row(item))

func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.name = "Header"

	var title := Label.new()
	title.name = "Title"
	title.text = "Shop"
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

func _build_row(item: Dictionary) -> HBoxContainer:
	var field: String = str(item.get("field", ""))

	var row := HBoxContainer.new()
	row.name = str(item.get("name", "Item"))
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.add_theme_constant_override("separation", PACK_GAP)

	var info := VBoxContainer.new()
	info.name = "Info"
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 0)
	row.add_child(info)

	var row_name := Label.new()
	row_name.name = "Name"
	row_name.text = str(item.get("name", ""))
	row_name.add_theme_font_size_override("font_size", NAME_FONT)
	row_name.add_theme_color_override("font_color", Color(0.16, 0.11, 0.06))
	info.add_child(row_name)

	var stock := Label.new()
	stock.name = "Stock"
	stock.text = "In stock: 0"
	stock.add_theme_font_size_override("font_size", STOCK_FONT)
	stock.add_theme_color_override("font_color", Color(0.36, 0.28, 0.17))
	info.add_child(stock)

	# Side effects live here: how long the fruit keeps, what tonight will melt.
	var note := Label.new()
	note.name = "Note"
	note.text = ""
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.add_theme_font_size_override("font_size", NOTE_FONT)
	note.add_theme_color_override("font_color", Color(0.45, 0.33, 0.19))
	info.add_child(note)

	var packs: Array = []
	for pack in item.get("packs", []):
		var qty: int = int(pack[0])
		var price: float = float(pack[1])
		var buy := Button.new()
		buy.name = "Buy%d" % qty
		buy.custom_minimum_size = PACK_BUTTON_SIZE
		buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		buy.add_theme_font_size_override("font_size", PACK_FONT)
		buy.text = "Buy %d\n$%.2f" % [qty, price]
		buy.pressed.connect(_buy_item.bind(field, qty, price))
		row.add_child(buy)
		packs.append({"button": buy, "qty": qty, "price": price})

	_rows.append({"field": field, "stock": stock, "note": note, "packs": packs})

	return row

# --- State -> UI ---------------------------------------------------------

func _refresh() -> void:
	if _money_label == null:
		return
	_money_label.text = "Money: $%.2f" % PlayerData.money
	for entry in _rows:
		var field: String = str(entry["field"])
		var cap: int = PlayerData.capacity_for(field)
		var held: int = PlayerData.stock_of(field)
		var stock: Label = entry["stock"]
		if stock != null:
			# Read against the limit, so storage upgrades are visible here too.
			stock.text = "In stock: %d / %d" % [held, cap]
		var note: Label = entry["note"]
		if note != null:
			note.text = _note_for(field, held, cap)
		for pack in entry["packs"]:
			var button: Button = pack["button"]
			if button != null:
				# Locked as soon as THIS pack would overfill the shelf, not only
				# once the shelf is already full: a 48 pack is out of reach long
				# before 60 lemons are in stock. The row note reports the room
				# left, so a greyed out button is explained rather than a mystery.
				button.disabled = held + int(pack["qty"]) > cap

# The line under each row: what the night will cost, and how much room is left
# for another pack. Room earns its place here because the pack buttons lock the
# moment a pack would not fit, so this is what explains a greyed out button.
func _note_for(field: String, held: int, cap: int) -> String:
	var parts: Array = []
	if field == "lemon_stock":
		if held <= 0:
			parts.append("Nothing on the shelf.")
		else:
			var days: int = Inventory.days_left(PlayerData.lemon_lots, PlayerData.day_count)
			parts.append("Oldest crate keeps %d more day%s." % [days, "" if days == 1 else "s"])
	if field == "ice_stock" and held > 0:
		var melt: int = Inventory.ice_melted(held,
			Inventory.melt_save(PlayerData.upgrade_levels), PlayerData.today_weather())
		if melt <= 0:
			parts.append("Too small a holding to melt.")
		else:
			parts.append("Tonight will melt about %d." % melt)
	var room: int = maxi(0, cap - held)
	if room <= 0:
		parts.append("The shelf is full. Buy more storage in Upgrades.")
	else:
		parts.append("Room for %d more." % room)
	return " ".join(parts)

func _label_for(field: String) -> String:
	for item in ITEMS:
		if str(item.get("field", "")) == field:
			return str(item.get("name", field))
	return field

func _set_notice(text: String) -> void:
	if _notice != null and is_instance_valid(_notice):
		_notice.text = text

# --- Input ---------------------------------------------------------------

# Purchases go through PlayerData.add_stock(), which only accepts what fits on
# the stand. A pack that does not fit is refused outright and nothing is
# charged for it, so money can never buy stock the shelves cannot hold.
func _buy_item(field: String, quantity: int, price: float) -> void:
	if price > PlayerData.money:
		_set_notice("Not enough money for that pack.")
		return
	var accepted: int = PlayerData.add_stock(field, quantity)
	if accepted <= 0:
		_set_notice("No room left for %s. Buy more storage in Upgrades." % _label_for(field))
		return
	PlayerData.money -= price
	if accepted < quantity:
		_set_notice("Only %d of %d fit on the shelf, so the rest stayed at the store."
			% [accepted, quantity])
	else:
		_set_notice("%d %s added." % [accepted, _label_for(field).to_lower()])
	PlayerData.profile_updated.emit()
