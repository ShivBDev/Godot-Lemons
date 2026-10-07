extends Node

signal profile_updated
signal weather_changed
signal area_changed(area_id: MapArea.AreaID)
signal news_changed

# Core State Model
var username: String = "New Player"
# Money can never go below zero. Over-committing -- an area fee or a wage the
# till could not cover -- floors at zero instead of carrying debt, so a free
# day in the neighbourhood is always playable. The setter is the one choke
# point, so a server load, a purchase and a charge all land on the same floor.
var money: float = 100.00:
	set(value):
		money = maxf(0.0, value)
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
var current_area: MapArea.AreaID = MapArea.AreaID.Neighborhood
	#set(value):
		#var emit: bool = current_area != value
		#current_area = value
		#if emit: area_changed.emit()

# What the last day's area fee cost, so the results panel can show it.
var last_area_fee: float = 0.0

# Per-area popularity. {area_id: {level, points}}. A loved cup is 3 points
# and a neutral cup is 1. The next rank always costs more, and a busier area
# costs more still. "perfects" is the old save key and is read as points.
var popularity: Dictionary = {}

# Staff hired for the coming day. {worker_id: true}. Wages are charged once
# when that day ends, and only for whoever was still toggled on.
var hired_staff: Dictionary = {}
var last_staff_wage: float = 0.0

# The headline that applies to the CURRENT day. Rolled at day end, consumed when
# that day starts, then replaced. Empty means "roll one on first open".
var news_id: String = ""

# Running taste tallies for the day that just ended, so the results panel can
# show how the crowd felt. Reset by DaySimulation at start_day().
var opinion_totals: Dictionary = {}

# Lifetime career stats, shown in the Settings menu's stats panel. Plain
# numbers and one nested count per area id, so the whole block rides the save
# round trip as JSON. Every key is optional on load: _ensure_stats() fills in
# whatever an older save did not carry.
var stats: Dictionary = {}

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
	# Loose on the way in too, so a headline-pushed day is still that day after
	# a reload instead of snapping back into the usual 55-105 band.
	if profile_dict.has("weather"): weather = Weather.sanitize_loose(profile_dict["weather"])
	if profile_dict.has("forecast"): forecast = Weather.sanitize_loose(profile_dict["forecast"])
	# Storage limits and lemon crates settle last. A save can carry more stock
	# than the stand now holds, so every counter is trimmed to fit, and any
	# crate that arrived without a matching counter is lined up before the UI
	# reads either of them.
	if profile_dict.has("lemonLots"):
		lemon_lots = Inventory.sanitize_lots(
			profile_dict["lemonLots"], Inventory.lemon_shelf_life(upgrade_levels), day_count)
	if profile_dict.has("upgradeLevels"): _read_upgrade_levels(profile_dict["upgradeLevels"])
	# Area choice and today's stadium teams. Both optional on older saves.
	if profile_dict.has("currentArea"):
		current_area = MapArea.Str2ID(profile_dict["currentArea"])
	#if profile_dict.has("teamPair"):
		#team_pair = sanitize_team_pair(profile_dict["teamPair"])
	if profile_dict.has("popularity"):
		popularity = _read_popularity(profile_dict["popularity"])
	if profile_dict.has("hiredStaff"):
		hired_staff = _read_hired(profile_dict["hiredStaff"])
	if profile_dict.has("newsId"): news_id = profile_dict["newsId"]
	if profile_dict.has("stats"):
		stats = _read_stats(profile_dict["stats"])
	# A freshly loaded profile has not lived through a night yet.
	last_ice_melted = 0
	last_lemons_spoiled = 0
	_clamp_stocks()
	sync_lemon_lots()
	profile_updated.emit()
	weather_changed.emit()
	news_changed.emit()
	area_changed.emit(current_area)

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
			"currentArea": MapArea.ID2Str(current_area),
			"popularity": popularity,
			"hiredStaff": hired_staff,
			"newsId": news_id,
			"stats": stats
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

# Read loose, not clamped: tomorrow's headline can push the temperature past
# the normal 55-105 roll, and the value the sim and the HUD act on has to be
# the one the headline promised.
func today_weather() -> Dictionary:
	ensure_weather_rolled()
	return Weather.sanitize_loose(weather)

func next_forecast() -> Dictionary:
	ensure_weather_rolled()
	return Weather.sanitize_loose(forecast)

func weather_label() -> String:
	return Weather.describe_weather(today_weather())

func forecast_label() -> String:
	return Weather.describe_weather(next_forecast())

# Called at day end: the forecast becomes today, and a new forecast is rolled.
# Promoted loose so a headline's pushed temperature survives into the day it was
# announced for instead of being clamped back into the usual range.
func advance_weather() -> void:
	weather = Weather.sanitize_loose(forecast)
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
	var cost: float = upgrade_cost(id)
	money -= cost
	note_spend(cost)
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

# --- The pitcher floor ---------------------------------------------------
# The fewest ingredients a day can open with: one pitcher's worth of lemons,
# sugar and ice. The Start Day button is blocked on this, and the Shop hands
# out a free rescue pack of anything the player is BOTH short of AND unable to
# pay for, so a broke stand can always be dug out of the hole.

# Every stock the pitcher floor reads, in one dictionary. Lemons report the
# crates actually on the shelf, not the counter.
func pitcher_stocks() -> Dictionary:
	return {
		"lemon_stock": stock_of("lemon_stock"),
		"sugar_stock": sugar_stock,
		"ice_stock": ice_stock,
		"cup_stock": cup_stock,
	}

# Cups are part of the floor: every cup sold uses one, and nothing can be sold
# without one. Inventory.PITCHER_FIELDS covers the three ingredients; the cup is
# added here so every caller (Start Day lock, shortfall text, Shop rescue packs)
# reads the same list.
const CUPS_PER_SALE: int = 1

func pitcher_fields() -> Array:
	var fields: Array = Inventory.PITCHER_FIELDS.duplicate()
	if not fields.has("cup_stock"):
		fields.append("cup_stock")
	return fields

# How much of each pitcher ingredient is missing, keyed by stock field. Empty
# means the stand can open.
func pitcher_shortfall() -> Dictionary:
	var short: Dictionary = Inventory.pitcher_shortfall(pitcher_stocks(), recipe_lemons, recipe_sugar, recipe_ice)
	if cup_stock < CUPS_PER_SALE:
		short["cup_stock"] = CUPS_PER_SALE - cup_stock
	return short

# What one pitcher needs of one field: a batch of lemons and sugar, one cup's
# ice, and one cup to pour it into.
func pitcher_need(field: String) -> int:
	if field == "cup_stock":
		return CUPS_PER_SALE
	return Inventory.pitcher_amount(field, recipe_lemons, recipe_sugar, recipe_ice)

func can_brew_pitcher() -> bool:
	return pitcher_shortfall().is_empty()

# Readable shortfall for the locked Start Day line, e.g. "4 lemons, 2 sugar".
func pitcher_shortfall_text() -> String:
	var short: Dictionary = pitcher_shortfall()
	var parts: Array = []
	for field in pitcher_fields():
		var key: String = str(field)
		if short.has(key):
			parts.append("%d %s" % [int(short[key]), Inventory.field_label(key)])
	return ", ".join(parts)

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

# Moves the stand to another area. Returns true when it actually changed, so
# callers can tell a real move from tapping the area already in use.
func set_area(targetArea: MapArea.AreaID) -> bool:
	if targetArea == current_area:
		return false
	# A move has to leave the day startable, so a fee the till cannot cover is
	# refused here as well as in the areas menu.
	if not can_afford_area(targetArea):
		return false
	current_area = targetArea
	profile_updated.emit()
	area_changed.emit(current_area)
	return true

# Every customer's price ceiling is scaled by the area, so downtown and the
# stadium tolerate what the neighbourhood would flatly refuse.
func area_price_multiplier() -> float:
	return AreaCatalog.get_area(current_area).price_tolerance

func area_traffic() -> float:
	return AreaCatalog.get_area(current_area).traffic

func area_daily_fee() -> float:
	return AreaCatalog.get_area(current_area).daily_fee

func area_attire() -> MapArea.Attire:
	return AreaCatalog.get_area(current_area).attire

func area_routes() -> Array:
	return AreaCatalog.get_area(current_area).route

# Through-paths the ambient crowd walks: people crossing the block who are
# never coming to the stand.
func area_passby_paths() -> Array:
	return AreaCatalog.get_area(current_area).passby_paths

# --- Popularity ----------------------------------------------------------

func popularity_level(area_id: MapArea.AreaID) -> int:
	return int(_popularity_entry(area_id).get("level", 0))

func popularity_points(area_id: MapArea.AreaID) -> int:
	var entry: Dictionary = _popularity_entry(area_id)
	if entry.has("points"):
		return int(entry.get("points", 0))
	return int(entry.get("perfects", 0))

func popularity_perfects(area_id: MapArea.AreaID) -> int:
	return popularity_points(area_id)

func popularity_goal(area_id: MapArea.AreaID) -> int:
	return Popularity.cups_to_next(area_id, popularity_level(area_id))

# Opinion points in the area being worked. A loved cup is 3, a neutral cup
# is 1, a dislike is 0. Returns true when the points also raised a rank.
func note_popularity_points(earned: int, area_id: MapArea.AreaID) -> bool:
	if earned <= 0:
		return false
	var entry: Dictionary = _popularity_entry(area_id)
	var level: int = int(entry.get("level", 0))
	var points: int = popularity_points(area_id) + earned
	var leveled: bool = false
	while level < Popularity.MAX_RANK and points >= Popularity.points_needed(area_id, level):
		points -= Popularity.points_needed(area_id, level)
		level += 1
		leveled = true
	popularity[MapArea.ID2Str(area_id)] = {"level": level, "points": points}
	return leveled

func note_perfect_cup(area_id: MapArea.AreaID) -> bool:
	return note_popularity_points(Popularity.POINTS_LOVE, area_id)

func popularity_traffic() -> float:
	return Popularity.traffic_bonus(popularity_level(current_area))

func popularity_price() -> float:
	return Popularity.price_bonus(popularity_level(current_area))

func popularity_patience() -> float:
	return Popularity.patience_bonus(popularity_level(current_area))

func popularity_line() -> int:
	return Popularity.line_bonus(popularity_level(current_area))

func _popularity_entry(area_id: MapArea.AreaID) -> Dictionary:
	var id: String = MapArea.ID2Str(area_id)
	var raw: Variant = popularity.get(id, {})
	if typeof(raw) != TYPE_DICTIONARY:
		return {"level": 0, "perfects": 0}
	return raw

func _read_popularity(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var stored: Dictionary = raw
	var clean: Dictionary = {}
	for key in stored.keys():
		var id: MapArea.AreaID = MapArea.Str2ID(str(key))
		var entry: Variant = stored[key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var stored_points: int = int(entry.get("points", entry.get("perfects", 0)))
		clean[id] = {
			"level": clampi(int(entry.get("level", 0)), 0, Popularity.MAX_RANK),
			"points": maxi(0, stored_points),
		}
	return clean

# --- Staff ---------------------------------------------------------------

func is_hired(id: StaffMember.STAFF_ID) -> bool:
	return bool(hired_staff.get(id, false))

func toggle_hire(id: StaffMember.STAFF_ID) -> bool:
	if not StaffCatalog.has_worker(id):
		return false
	var now_on: bool = not is_hired(id)
	# Taking someone on must leave the day startable, so the same check the
	# menu makes is enforced here too.
	if now_on and not can_afford_hire(id):
		return false
	if now_on:
		hired_staff[id] = true
	else:
		hired_staff.erase(id)
	profile_updated.emit()
	return now_on

func staff_daily_wage() -> float:
	var total: float = 0.0
	for id in hired_staff.keys():
		if bool(hired_staff[id]):
			total += StaffCatalog.daily_cost(id)
	return total

func charge_staff_wages() -> float:
	last_staff_wage = staff_daily_wage()
	# Only what the till could actually pay is recorded as spend, so the
	# zero floor cannot make the career total claim money it never paid out.
	note_spend(minf(last_staff_wage, money))
	money = maxf(0.0, money - last_staff_wage)
	return last_staff_wage

# --- Day costs -----------------------------------------------------------

# What setting up for the day costs before a single cup is sold: the pitch
# fee for the current area plus a day's wage for everyone left switched on.
# Charged once, up front, by pay_day_start_costs().
func day_start_cost() -> float:
	return area_daily_fee() + staff_daily_wage()

# The day can only start while the till covers both the fee and the wages.
# This is what locks the Start Day button out.
func can_afford_day_start() -> bool:
	return money >= day_start_cost()

# A day also needs something to sell: one pitcher's worth of lemons, sugar and
# ice on the shelf. The Shop's free rescue packs close this gap, so the two
# together mean a day can always be reached without a soft lock.
func can_start_day() -> bool:
	return can_afford_day_start() and can_brew_pitcher()

# Takes the day's costs out of the till up front and records them for the
# results panel. Money is floored at zero, so a day can never open in debt.
func pay_day_start_costs() -> float:
	last_area_fee = area_daily_fee()
	last_staff_wage = staff_daily_wage()
	var total: float = last_area_fee + last_staff_wage
	# The fee and the wages are the day's biggest spend, and only the part the
	# till could cover counts, for the same reason as a wage charge.
	note_spend(minf(total, money))
	money = maxf(0.0, money - total)
	profile_updated.emit()
	return total

# A new hire has to leave the day startable, so the fee, the wages already on
# the books and this one all have to fit in the till together. Turning someone
# off is always allowed.
func can_afford_hire(id: StaffMember.STAFF_ID) -> bool:
	if not StaffCatalog.has_worker(id):
		return false
	if is_hired(id):
		return true
	return money >= day_start_cost() + StaffCatalog.daily_cost(id)

# Moving has to leave the day startable too: the new pitch fee plus the wages
# already promised.
func can_afford_area(id: MapArea.AreaID) -> bool:
	if not AreaCatalog.has_area(id):
		return false
	return money >= AreaCatalog.get_area(id).daily_fee + staff_daily_wage()

func _read_hired(raw_data: Variant) -> Dictionary:
	if typeof(raw_data) != TYPE_DICTIONARY:
		return {}
	var stored_data: Dictionary = raw_data
	var cleaned_data: Dictionary = {}
	for key in stored_data.keys():
		var id: StaffMember.STAFF_ID = int(key) as StaffMember.STAFF_ID
		if StaffCatalog.has_worker(id):
			if bool(stored_data[key]): cleaned_data[id] = true
			else: cleaned_data[id] = false
	return cleaned_data

# --- News ----------------------------------------------------------------

func ensure_news() -> void:
	if news_id.is_empty():
		news_id = NewsCatalog.roll()
		# The first headline of a session has no finished day behind it to have
		# been folded in at day end, and the day it applies to is the one
		# already sitting in `weather`, so fold it in there.
		if _fold_news_weather(news_id, weather):
			weather_changed.emit()
		news_changed.emit()

func current_news() -> String:
	ensure_news()
	return news_id

func roll_next_news() -> void:
	news_id = NewsCatalog.roll()
	news_changed.emit()

# Folds the current headline into tomorrow's forecast. DaySimulation calls this
# at day end BEFORE the calendar rolls over, so resolve_day_end() promotes the
# finished forecast to today: the headline lands on the day the ticker promised
# rather than on the one after it.
func apply_news_to_forecast() -> void:
	if _fold_news_weather(current_news(), forecast):
		weather_changed.emit()

# The one place a headline's weather is written into a day. Returns true when
# the headline was a weather story and the target changed.
func _fold_news_weather(news: String, target: Dictionary) -> bool:
	if news.is_empty():
		return false
	var newsItem: NewsItem = NewsCatalog.get_item(news)
	if newsItem == null:
		return false
	# A hot or cold headline is a promise about the temperature, so it is SET
	# outside the usual band rather than added to whatever the forecast rolled:
	# +18 on top of a 60F roll was only 78F, which is not a heat wave.
	var push: int = newsItem.weather_push
	if newsItem.effects == NewsItem.EffectTarget.temp:
		push = 1 if newsItem.value >= 0.0 else -1
	if push > 0:
		target["temp"] = Weather.headline_hot_temp()
		target["raining"] = false
		return true
	if push < 0:
		target["temp"] = Weather.headline_cold_temp()
		return true
	if newsItem.effects == NewsItem.EffectTarget.rain:
		target["raining"] = newsItem.value >= 0.5
		return true
	return false

# --- Career stats --------------------------------------------------------

# Days, sales and spend across the whole save, plus the best single day's
# takings. Read only by the Settings panel; every number is a plain int or
# float so it round trips through the save like the rest of the profile.
func note_day_finished(day_revenue: float, cups: int) -> void:
	_ensure_stats()
	stats["days_total"] = int(stats["days_total"]) + 1
	var by_area: Dictionary = stats["days_by_area"]
	var id: String = MapArea.ID2Str(current_area)
	by_area[id] = int(by_area.get(id, 0)) + 1
	# A best day is judged on money, and the cup count is what made it.
	if day_revenue > float(stats["best_day_money"]):
		stats["best_day_money"] = day_revenue
		stats["best_day_cups"] = cups
		stats["best_day_day"] = day_count

func note_sale(amount: float) -> void:
	_ensure_stats()
	stats["cups_sold"] = int(stats["cups_sold"]) + 1
	stats["sales_money"] = float(stats["sales_money"]) + amount

# Money leaving the till: shop packs, upgrades, the area fee, wages.
func note_spend(amount: float) -> void:
	if amount <= 0.0:
		return
	_ensure_stats()
	stats["spend_money"] = float(stats["spend_money"]) + amount

# The Settings panel's stat block, one formatted line per fact. Formatting
# lives here so the panel stays a plain list of labels, and a save that is
# missing a key still shows a full block.
func stats_lines() -> PackedStringArray:
	_ensure_stats()
	var out := PackedStringArray()
	out.append("Days played: %d" % int(stats["days_total"]))
	# One line per fact keeps the block inside a fixed-height panel however
	# many areas are ever added: the per-area counts share a single row.
	out.append("By area: %s" % _area_days_line())
	out.append("Total sales: %d cups  |  $%.2f" % [int(stats["cups_sold"]), float(stats["sales_money"])])
	out.append("Total spent: $%.2f" % float(stats["spend_money"]))
	if int(stats["best_day_day"]) <= 0:
		out.append("Best day: none yet")
	else:
		out.append("Best day: $%.2f  |  %d cups (day %d)" % [
			float(stats["best_day_money"]), int(stats["best_day_cups"]), int(stats["best_day_day"])])
	return out

# "The Neighborhood: 4 | Downtown: 2 | The Stadium: 1". Every area in the
# catalog is named, including ones never worked, so the breakdown always reads
# as a complete picture.
func _area_days_line() -> String:
	var parts := PackedStringArray()
	for area: MapArea in AreaCatalog.all():
		parts.append("%s: %d" % [area.name, stats_days_by_area(area.id)])
	return " | ".join(parts)

func stats_days_by_area(id: MapArea.AreaID) -> int:
	_ensure_stats()
	var by_area: Dictionary = stats["days_by_area"]
	return int(by_area.get(MapArea.ID2Str(id), 0))

func stats_days_total() -> int:
	_ensure_stats()
	return int(stats["days_total"])

# Fills in any key a save from before stats existed would be missing, so the
# panel and the note_* calls can all read the dictionary without guarding.
func _ensure_stats() -> void:
	if not stats.has("days_total"):
		stats["days_total"] = 0
	if typeof(stats.get("days_by_area")) != TYPE_DICTIONARY:
		stats["days_by_area"] = {}
	if not stats.has("cups_sold"):
		stats["cups_sold"] = 0
	if not stats.has("sales_money"):
		stats["sales_money"] = 0.0
	if not stats.has("spend_money"):
		stats["spend_money"] = 0.0
	if not stats.has("best_day_money"):
		stats["best_day_money"] = 0.0
	if not stats.has("best_day_cups"):
		stats["best_day_cups"] = 0
	if not stats.has("best_day_day"):
		stats["best_day_day"] = 0

func _read_stats(raw: Variant) -> Dictionary:
	var blank: Dictionary = {
		"days_total": 0,
		"days_by_area": {},
		"cups_sold": 0,
		"sales_money": 0.0,
		"spend_money": 0.0,
		"best_day_money": 0.0,
		"best_day_cups": 0,
		"best_day_day": 0,
	}
	if typeof(raw) != TYPE_DICTIONARY:
		return blank
	var stored: Dictionary = raw
	blank["days_total"] = maxi(0, int(stored.get("days_total", 0)))
	blank["cups_sold"] = maxi(0, int(stored.get("cups_sold", 0)))
	blank["sales_money"] = maxf(0.0, float(stored.get("sales_money", 0.0)))
	blank["spend_money"] = maxf(0.0, float(stored.get("spend_money", 0.0)))
	blank["best_day_money"] = maxf(0.0, float(stored.get("best_day_money", 0.0)))
	blank["best_day_cups"] = maxi(0, int(stored.get("best_day_cups", 0)))
	blank["best_day_day"] = maxi(0, int(stored.get("best_day_day", 0)))
	var by_area: Dictionary = {}
	var stored_areas: Variant = stored.get("days_by_area", {})
	if typeof(stored_areas) == TYPE_DICTIONARY:
		var areas: Dictionary = stored_areas
		for key in areas.keys():
			by_area[key] = maxi(0, int(areas[key]))
	blank["days_by_area"] = by_area
	return blank

# --- Opinions ------------------------------------------------------------

func reset_opinions() -> void:
	opinion_totals = RecipeOpinion.empty_totals()

func note_opinion(opinion: Dictionary) -> void:
	if opinion_totals.is_empty():
		opinion_totals = RecipeOpinion.empty_totals()
	RecipeOpinion.add_totals(opinion_totals, opinion)

func note_customer_arrival() -> void:
	if opinion_totals.is_empty():
		opinion_totals = RecipeOpinion.empty_totals()
	RecipeOpinion.note_arrival(opinion_totals)

func note_customer_skip(reason: String) -> void:
	if opinion_totals.is_empty():
		opinion_totals = RecipeOpinion.empty_totals()
	RecipeOpinion.note_skip(opinion_totals, reason)
