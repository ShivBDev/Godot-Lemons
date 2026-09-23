extends Node

signal profile_updated
signal weather_changed
signal area_changed(area_id: String)

# Core State Model
var username: String = "New Player"
var money: float = 100.00
var day_count: int = 1

# Active Day Inventory
var lemon_stock: int = 0
var sugar_stock: int = 0
var ice_stock: int = 0
var cup_stock: int = 0

# Recipe
var recipe_lemons: int = 4
var recipe_sugar: int = 4
var recipe_ice: int = 4
var sale_price: float = 1.00

# Weather: today's weather is what the running day uses, forecast is the
# preview for the next day to be played. Empty means "not rolled yet".
var weather: Dictionary = {}
var forecast: Dictionary = {}

# Lemon freshness is tracked as day-stamped crates, see Inventory. The counter
# above and this array are kept in step by add_stock(), consume_stock() and
# sync_lemon_lots(), so nothing else has to reason about both.
var lemon_lots: Array = []

# What the last night cost, so the day-end results panel can show it instead
# of the stock silently shrinking. Written by resolve_day_end(), read once when
# the results appear.
var last_ice_melted: int = 0
var last_lemons_spoiled: int = 0

# Upgrades: {upgrade_id: level}. All keys are optional.
var upgrade_levels: Dictionary = {}

# Which area the stand is set up in. Every level scene places the Stand on the
# same transform, so switching areas only swaps scenery and the rules below.
var current_area: String = AreaCatalog.DEFAULT_ID

# The two stadium team themes drawn for the current stadium day. Empty means
# the day has not been rolled yet, which reads as a plain crowd. Rolled once
# per stadium day, so the jerseys change every time you work the stadium.
var team_pair: Array = []

# What the last day's area fee cost, so the results panel can show it.
var last_area_fee: float = 0.0

func update_from_server_payload(profile_dict: Dictionary) -> void:
	if profile_dict.has("name"): username = profile_dict["name"]
	if profile_dict.has("money"): money = float(profile_dict["money"])
	if profile_dict.has("dayCount"): day_count = profile_dict["dayCount"]
	if profile_dict.has("lemonStock"): lemon_stock = profile_dict["lemonStock"]
	if profile_dict.has("sugarStock"): sugar_stock = profile_dict["sugarStock"]
	if profile_dict.has("iceStock"): ice_stock = profile_dict["iceStock"]
	if profile_dict.has("cupStock"): cup_stock = profile_dict["cupStock"]
	if profile_dict.has("recipeLemons"): recipe_lemons = profile_dict["recipeLemons"]
	if profile_dict.has("recipeSugar"): recipe_sugar = profile_dict["recipeSugar"]
	if profile_dict.has("recipeIce"): recipe_ice = profile_dict["recipeIce"]
	if profile_dict.has("salePrice"): sale_price = profile_dict["salePrice"]
	# Optional keys: absent on older saves, so each read is has()-guarded.
	if profile_dict.has("weather"): weather = Weather.sanitize(profile_dict["weather"])
	if profile_dict.has("forecast"): forecast = Weather.sanitize(profile_dict["forecast"])
	if profile_dict.has("upgradeLevels"): _read_upgrade_levels(profile_dict["upgradeLevels"])
	# Area choice and today's stadium teams. Both optional on older saves.
	if profile_dict.has("currentArea"):
		current_area = AreaCatalog.sanitize(str(profile_dict["currentArea"]))
	if profile_dict.has("teamPair"):
		team_pair = sanitize_team_pair(profile_dict["teamPair"])
	# Storage limits and lemon crates settle last. A save can carry more stock
	# than the stand now holds, so every counter is trimmed to fit, and any
	# crate that arrived without a matching counter is lined up before the UI
	# reads either of them.
	if profile_dict.has("lemonLots"):
		lemon_lots = Inventory.sanitize_lots(
			profile_dict["lemonLots"], Inventory.lemon_shelf_life(upgrade_levels), day_count)
	# A freshly loaded profile has not lived through a night yet.
	last_ice_melted = 0
	last_lemons_spoiled = 0
	_clamp_stocks()
	sync_lemon_lots()
	profile_updated.emit()
	weather_changed.emit()

func serialize_for_sync() -> Dictionary:
	return {
		"name": username,
		"state": {
			"money": money,
			"dayCount": day_count,
			"lemonStock": lemon_stock,
			"sugarStock": sugar_stock,
			"iceStock": ice_stock,
			"cupStock": cup_stock,
			"recipeLemons": recipe_lemons,
			"recipeSugar": recipe_sugar,
			"recipeIce": recipe_ice,
			"salePrice": sale_price,
			"weather": weather,
			"forecast": forecast,
			"lemonLots": lemon_lots,
			"upgradeLevels": upgrade_levels,
			"currentArea": current_area,
			"teamPair": team_pair
		}
	}

# --- Weather -------------------------------------------------------------

# Always hand out usable weather: rolls defaults the first time it is needed
# so a fresh profile still has today's weather and a next-day forecast.
func ensure_weather_rolled() -> void:
	if weather.is_empty():
		weather = Weather.default_weather()
	if forecast.is_empty():
		forecast = Weather.roll()

func today_weather() -> Dictionary:
	ensure_weather_rolled()
	return Weather.sanitize(weather)

func next_forecast() -> Dictionary:
	ensure_weather_rolled()
	return Weather.sanitize(forecast)

func weather_label() -> String:
	return Weather.describe_weather(today_weather())

func forecast_label() -> String:
	return Weather.describe_weather(next_forecast())

# Called at day end: the forecast becomes today, and a new forecast is rolled.
func advance_weather() -> void:
	weather = next_forecast()
	forecast = Weather.roll()
	weather_changed.emit()

# --- Upgrades ------------------------------------------------------------

func get_upgrade_level(id: String) -> int:
	return UpgradeCatalog.level_of(upgrade_levels, id)

func set_upgrade_level(id: String, level: int) -> void:
	upgrade_levels[id] = clampi(level, 0, UpgradeCatalog.max_level_of(id))
	profile_updated.emit()

func upgrade_cost(id: String) -> float:
	return UpgradeCatalog.cost_for(id, get_upgrade_level(id))

func can_buy_upgrade(id: String) -> bool:
	if not UpgradeCatalog.has_def(id):
		return false
	if UpgradeCatalog.is_maxed(id, get_upgrade_level(id)):
		return false
	return money >= upgrade_cost(id)

# Purchase path for the (not yet built) shop UI. Effects are read by
# DaySimulation at start_day(), so a purchase lands the following day.
func buy_upgrade(id: String) -> bool:
	if not can_buy_upgrade(id):
		return false
	money -= upgrade_cost(id)
	set_upgrade_level(id, get_upgrade_level(id) + 1)
	# A storage or shelf-life upgrade must show up on the stocks the player is
	# looking at, not only on the ones bought afterwards.
	_clamp_stocks()
	extend_all_lots()
	profile_updated.emit()
	return true

# --- Storage limits ------------------------------------------------------

# How much of one stock the stand can hold, with storage upgrades applied.
func capacity_for(field: String) -> int:
	return Inventory.capacity_for(field, upgrade_levels)

# Current amount of one stock. Lemons report the crates actually on the shelf
# rather than the counter, which may briefly disagree after a server load.
func stock_of(field: String) -> int:
	if field == "lemon_stock":
		return lemon_lots_total()
	return int(self[field])

# Adds as much of quantity as fits and returns how many were accepted.
func add_stock(field: String, quantity: int) -> int:
	if quantity <= 0:
		return 0
	if field == "lemon_stock":
		var accepted: int = _add_lemon_lots(quantity)
		if accepted > 0:
			profile_updated.emit()
		return accepted
	var room: int = capacity_for(field) - int(self[field])
	var taken: int = clampi(quantity, 0, maxi(room, 0))
	if taken <= 0:
		return 0
	self[field] = int(self[field]) + taken
	profile_updated.emit()
	return taken

# Takes quantity off the shelf and reports whether all of it was there.
# Refuses the whole request when it cannot be filled, so a brew never half
# spends an ingredient.
func consume_stock(field: String, quantity: int) -> bool:
	if quantity <= 0:
		return true
	if field == "lemon_stock":
		if lemon_lots_total() < quantity:
			return false
		Inventory.consume_from_lots(lemon_lots, quantity)
		lemon_stock = lemon_lots_total()
		profile_updated.emit()
		return true
	if int(self[field]) < quantity:
		return false
	self[field] = int(self[field]) - quantity
	profile_updated.emit()
	return true

# Trims every stock down to what the stand can hold. Saves written before the
# storage limits existed can hold far more than the shelves fit.
func _clamp_stocks() -> void:
	for field in Inventory.CAPACITY_STATS.keys():
		self[field] = clampi(int(self[field]), 0, capacity_for(str(field)))

# --- Lemon freshness -----------------------------------------------------

func lemon_lots_total() -> int:
	return _total_lots(lemon_lots)

# Lines the crate list up with the single lemon_stock counter. Used when a save
# predates freshness tracking: the stock is kept as one crate that is still
# good, rather than spoiling on first load.
func sync_lemon_lots() -> void:
	lemon_lots = Inventory.refresh_lots(lemon_lots, _shelf_life(), day_count,
		capacity_for("lemon_stock"), lemon_stock)
	lemon_stock = lemon_lots_total()

# Ages every crate by one day without discarding stock for free: a crate past
# its date is thrown out, and only the stock above the capacity that frees is
# actually lost. Called when the day advances and whenever shelf life improves.
func extend_all_lots() -> void:
	lemon_lots = Inventory.refresh_lots(lemon_lots, _shelf_life(), day_count,
		capacity_for("lemon_stock"), lemon_stock)
	lemon_stock = lemon_lots_total()

func _shelf_life() -> int:
	return Inventory.lemon_shelf_life(upgrade_levels)

func _total_lots(lots: Array) -> int:
	var total: int = 0
	for lot in lots:
		total += int(lot.get("count", 0))
	return total

func _add_lemon_lots(quantity: int) -> int:
	var room: int = capacity_for("lemon_stock") - lemon_lots_total()
	var taken: int = clampi(quantity, 0, maxi(room, 0))
	if taken <= 0:
		return 0
	Inventory.add_to_lots(lemon_lots, taken, day_count, _shelf_life())
	lemon_stock = lemon_lots_total()
	return taken

# --- Day end -------------------------------------------------------------

# Settles everything that happens between one day and the next, in the order
# that matters. Called once by DaySimulation when a played day ends, so the ice
# the ice maker delivered during that day is already on the shelf before the
# night's melt is worked out on it.
func resolve_day_end() -> void:
	var settled_day: int = day_count
	var weather_today: Dictionary = today_weather()
	var ice_before: int = ice_stock
	var lemons_before: int = lemon_stock
	# Night falls on the day that was just played and the weather it had, so a
	# crate bought on day 3 with a 7 day shelf life stays good through day 9.
	ice_stock = Inventory.ice_after_night(ice_stock, capacity_for("ice_stock"),
		Inventory.melt_save(upgrade_levels), weather_today)
	last_ice_melted = maxi(0, ice_before - ice_stock)
	day_count += 1
	extend_all_lots()
	last_lemons_spoiled = maxi(0, lemons_before - lemon_stock)
	# Promote tomorrow's forecast to today and roll a fresh one, so the idle
	# HUD always previews the next day to be played.
	advance_weather()
	print("[day] day %d settled: ice %d -> %d (melted %d), lemons %d -> %d (spoiled %d, %d crates)" % [
		settled_day, ice_before, ice_stock, last_ice_melted,
		lemons_before, lemon_stock, last_lemons_spoiled, lemon_lots.size()])
	profile_updated.emit()

func _read_upgrade_levels(raw: Variant) -> void:
	if typeof(raw) != TYPE_DICTIONARY:
		return
	var stored: Dictionary = raw
	for key in stored.keys():
		var id: String = str(key)
		if not UpgradeCatalog.has_def(id):
			continue
		upgrade_levels[id] = UpgradeCatalog.level_of(stored, id)

# --- Areas ---------------------------------------------------------------

func current_area_id() -> String:
	return AreaCatalog.sanitize(current_area)

func current_area_name() -> String:
	return AreaCatalog.name_for(current_area)

# Moves the stand to another area. Returns true when it actually changed, so
# callers can tell a real move from tapping the area already in use.
func set_area(id: String) -> bool:
	var target: String = AreaCatalog.sanitize(id)
	if target == current_area:
		return false
	current_area = target
	# A different area is a different crowd. Walking into the stadium rolls a
	# fresh pair of team colours for the day; leaving clears them again.
	if target == AreaCatalog.STADIUM:
		roll_team_pair()
	else:
		team_pair = []
	profile_updated.emit()
	area_changed.emit(current_area)
	return true

# Every customer's price ceiling is scaled by the area, so downtown and the
# stadium tolerate what the neighbourhood would flatly refuse.
func area_price_multiplier() -> float:
	return AreaCatalog.price_multiplier_for(current_area)

func area_traffic() -> float:
	return AreaCatalog.traffic_for(current_area)

func area_daily_fee() -> float:
	return AreaCatalog.daily_fee_for(current_area)

func area_attire() -> String:
	return AreaCatalog.attire_for(current_area)

func area_routes() -> Array:
	return AreaCatalog.routes_for(current_area)

func roll_team_pair() -> void:
	team_pair = AreaCatalog.roll_team_pair()

func has_team_pair() -> bool:
	return team_pair.size() >= 2

# A saved pair only needs to carry the team names: the colours are looked back
# up in the catalog, so a round trip through the server cannot mangle them.
func sanitize_team_pair(raw: Variant) -> Array:
	if typeof(raw) != TYPE_ARRAY:
		return []
	var stored: Array = raw
	if stored.is_empty():
		return []
	var names: Array = []
	for entry in stored:
		if typeof(entry) == TYPE_DICTIONARY:
			var stored_name: String = str(entry.get("name", ""))
			if not stored_name.is_empty():
				names.append(stored_name)
		elif typeof(entry) == TYPE_STRING:
			names.append(str(entry))
	var pair: Array = []
	for theme in AreaCatalog.TEAM_THEMES:
		if pair.size() >= 2:
			break
		if names.has(str(theme.get("name", ""))):
			pair.append(theme)
	if pair.size() >= 2:
		return pair
	# Nothing usable came back: draw a fresh pair rather than leave the crowd
	# wearing half a colour scheme.
	return AreaCatalog.roll_team_pair()
