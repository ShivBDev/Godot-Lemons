extends Control

# Shop menu.
#
# The rows live in the scene: one row per ingredient with its icon, stock
# readout, note and three pack buttons. This script only fills them from
# PlayerData, so adding a pack is a number in the table below.

# One entry per shop row. "field" is the PlayerData stock variable and also the
# scene row's name, and each pack is [quantity, price].
const ITEMS: Array = [
	{
		"name": "Lemons",
		"field": "lemon_stock",
		"icon": "res://assets/ui/icons/lemon.png",
		"packs": [[12, 8.50], [24, 16.50], [48, 31.50]],
	},
	{
		"name": "Sugar",
		"field": "sugar_stock",
		"icon": "res://assets/ui/icons/sugar.png",
		"packs": [[12, 9.50], [24, 17.50], [60, 32.50]],
	},
	{
		"name": "Ice",
		"field": "ice_stock",
		"icon": "res://assets/ui/icons/ice.png",
		"packs": [[50, 5.00], [200, 17.00], [500, 35.00]],
	},
	{
		"name": "Cups",
		"field": "cup_stock",
		"icon": "res://assets/ui/icons/cup.png",
		"packs": [[75, 7.00], [250, 18.50], [500, 34.50]],
	},
]

@onready var _money_label: Label = $Layout/Column/Header/Money
@onready var _notice: Label = $Layout/Column/Notice
@onready var _rows_box: VBoxContainer = $Layout/Column/Scroll/Rows

# [{field: String, stock: Label, note: Label, packs: [{button, qty, base}]}]
var _rows: Array = []
# One free rescue pack per ingredient per day: while the till cannot buy its way
# to one pitcher, the smallest pack of each missing ingredient is free, so a
# broken day can always be fixed without money. 0.00 is a legitimate price here,
# so this is a plain bool, not a price.
var _free_used: Dictionary = {}

func _ready() -> void:
	_build_rows()
	if not PlayerData.profile_updated.is_connected(_refresh):
		PlayerData.profile_updated.connect(_refresh)
	# A headline that re-prices the packs must redraw the rows the moment it
	# rolls, not only the next time the tab is opened.
	if not PlayerData.news_changed.is_connected(_refresh):
		PlayerData.news_changed.connect(_refresh)
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

# Binds the scene's rows to the pack table. The first pack built is the smallest
# one, and is the only one the rescue rule can hand over free.
func _build_rows() -> void:
	for item in ITEMS:
		var field: String = str(item.get("field", ""))
		var row: Control = _rows_box.get_node(str(item.get("name", "")))
		var packs: Array = []
		var buttons: Array = [row.get_node("Buy1"), row.get_node("Buy2"), row.get_node("Buy3")]
		var defs: Array = item.get("packs", [])
		for i in defs.size():
			var qty: int = int(defs[i][0])
			var base: float = float(defs[i][1])
			var buy: Button = buttons[i]
			buy.pressed.connect(_buy_item.bind(field, qty, base, i == 0))
			packs.append({"button": buy, "qty": qty, "base": base})
		_rows.append({
			"field": field,
			"stock": row.get_node("Info/Stock"),
			"note": row.get_node("Info/Note"),
			"packs": packs,
		})

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
		var pack_index: int = 0
		for pack in entry["packs"]:
			var button: Button = pack["button"]
			var qty: int = int(pack["qty"])
			# Only the smallest pack of an ingredient the day is short of can be
			# free, and only while the whole day is unreachable. Decided here so
			# the label and the click always agree.
			var free: bool = pack_index == 0 and _is_free_pack(field, qty)
			if button != null:
				# A free pack hands over the grant, not the pack size, so that is
				# the amount the shelf needs room for.
				var add_qty: int = _free_grant(field, qty) if free else qty
				# Locked as soon as THIS pack would overfill the shelf, not only
				# once the shelf is already full: a 48 pack is out of reach long
				# before 60 lemons are in stock. The row note reports the room
				# left, so a greyed out button is explained rather than a mystery.
				button.disabled = held + add_qty > cap
				if free:
					button.text = "Free %d\nRescue" % add_qty
				else:
					# Re-priced from the base on every refresh, so the row
					# always shows today's headline sale and nothing older.
					button.text = "Buy %d\n$%.2f" % [qty, _sale_price(field, float(pack["base"]))]
			pack_index += 1

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

func _sale_price(field: String, base_price: float) -> float:
	return base_price * NewsCatalog.sale_multiplier(PlayerData.current_news(), field)

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
func _buy_item(field: String, quantity: int, base_price: float, can_be_free: bool = false) -> void:
	# The rescue pack, and nothing but. While the till cannot buy its way to one
	# pitcher, the smallest pack of a short ingredient comes free; every other
	# case -- the same pack once the day is affordable, a bigger pack, a row
	# that is not short -- is an ordinary paid purchase. Wanting extra stock is
	# never blocked by the rescue rule.
	if can_be_free and _is_free_pack(field, quantity):
		_take_free_pack(field, quantity)
		return
	# Priced at the click, from the base, so the charge is always the sale the
	# button is showing at that moment rather than the one it showed yesterday.
	var price: float = _sale_price(field, base_price)
	if price > PlayerData.money:
		_set_notice("Not enough money for that pack.")
		return
	var accepted: int = PlayerData.add_stock(field, quantity)
	if accepted <= 0:
		_set_notice("No room left for %s. Buy more storage in Upgrades." % _label_for(field))
		return
	# The button already shows this pack's price with today's sale on it, so the
	# till is charged exactly what was shown and the spend total records the
	# same figure.
	PlayerData.money -= price
	PlayerData.note_spend(price)
	if accepted < quantity:
		_set_notice("Only %d of %d fit on the shelf, so the rest stayed at the store."
			% [accepted, quantity])
	else:
		_set_notice("%d %s added." % [accepted, _label_for(field).to_lower()])
	PlayerData.profile_updated.emit()

# --- Rescue packs --------------------------------------------------------

# True while this pack is the free way back into the day: the till cannot buy
# its way to one pitcher, this ingredient is below that floor, the free pack has
# not been taken today, and this is the smallest pack on the row. A stand that
# can afford its ingredients buys them like anyone else.
func _is_free_pack(field: String, quantity: int) -> bool:
	# Stamp reads rather than a bare flag, so the allowance refills by itself
	# when the day rolls over and nothing has to reset it.
	if int(_free_used.get(field, 0)) == PlayerData.day_count:
		return false
	var need: int = maxi(1, PlayerData.pitcher_need(field))
	if need <= 0 or PlayerData.stock_of(field) >= need:
		return false
	# Only the smallest pack, so the rescue is the cheapest route to a pitcher
	# rather than a free big crate.
	if quantity > _smallest_pack(field):
		return false
	return not _can_afford_pitcher_materials()

# Size of the cheapest pack on an ingredient's row.
func _smallest_pack(field: String) -> int:
	for item in ITEMS:
		if str(item.get("field", "")) == field:
			var smallest: int = 0
			for pack in item.get("packs", []):
				var qty: int = int(pack[0])
				if smallest == 0 or qty < smallest:
					smallest = qty
			return smallest
	return 0

# How much a rescue pack actually delivers: the pack's own size, or enough of
# the shortfall to reach the pitcher floor when the pack alone is smaller than
# it. A recipe can call for more lemons or sugar than the smallest pack holds,
# and leaving a broke player one crate short is the very soft lock this fixes.
func _free_grant(field: String, quantity: int) -> int:
	var need: int = maxi(0, PlayerData.pitcher_need(field))
	return maxi(quantity, need - PlayerData.stock_of(field))

# Hands over the rescue pack through PlayerData.add_stock(), the same door a
# paid pack uses, so it can never push a shelf past its limit.
func _take_free_pack(field: String, quantity: int) -> void:
	var grant: int = _free_grant(field, quantity)
	var accepted: int = PlayerData.add_stock(field, grant)
	_free_used[field] = PlayerData.day_count
	if accepted <= 0:
		_set_notice("The %s shelf is already full, so no free pack was needed." % _label_for(field).to_lower())
	elif accepted < grant:
		_set_notice("Free pack: only %d of %d fit, and nothing was charged." % [accepted, grant])
	else:
		_set_notice("Free %s pack: %d added, no charge." % [_label_for(field).to_lower(), accepted])
	PlayerData.profile_updated.emit()

# True when the till covers the cheapest pack of every ingredient the stand is
# short of for one pitcher. Prices are read here, where the packs live, so a
# rescue pack can never be handed to a player who could simply have paid.
func _can_afford_pitcher_materials() -> bool:
	var cost: float = 0.0
	for field in PlayerData.pitcher_fields():
		var key: String = str(field)
		var need: int = PlayerData.pitcher_need(key)
		if need <= 0 or PlayerData.stock_of(key) >= need:
			continue
		cost += _cheapest_pack_price(key)
	return PlayerData.money >= cost

# Sale-adjusted price of the cheapest pack on an ingredient's row.
func _cheapest_pack_price(field: String) -> float:
	for item in ITEMS:
		if str(item.get("field", "")) != field:
			continue
		var best: float = -1.0
		for pack in item.get("packs", []):
			var price: float = _sale_price(field, float(pack[1]))
			if best < 0.0 or price < best:
				best = price
		return maxf(0.0, best)
	return 0.0
