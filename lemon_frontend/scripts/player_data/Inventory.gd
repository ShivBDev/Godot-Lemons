extends RefCounted
class_name Inventory

# One home for every rule about stand supplies: how much fits on the stand,
# what melts overnight, and how long lemons stay usable.
#
# DaySimulation, ShopMenu, UpgradesMenu and PlayerData all read these numbers
# from here, so a balance tweak is a one-line edit instead of a hunt through
# three files.
#
# Lemons are tracked twice in PlayerData on purpose:
#   - lemon_stock: the plain counter every UI reads
#   - lemon_lots:  an array of crates, each {"count", "expires", "life"} where
#     "expires" is the absolute day number the crate is no longer good on and
#     "life" is the shelf life it was packed under. A crate added on day 3 with
#     a 7 day shelf life is usable on days 3..9. PlayerData keeps the counter
#     and the crates in step; brewing always eats the crate closest to going
#     off first.
#
# "life" is what makes the walk-in cooler work exactly once. Extending a crate
# raises its expiry by the DIFFERENCE between the old and new shelf life and
# then records the new life, so running the freshness pass every day cannot
# push a crate's expiry out forever.

# --- Base storage limits -------------------------------------------------
# Every counter is capped. UpgradeCatalog sells the Storage upgrades that
# raise these, one per ingredient.
const BASE_LEMON_CAPACITY: int = 60
const BASE_SUGAR_CAPACITY: int = 60
const BASE_ICE_CAPACITY: int = 200
const BASE_CUP_CAPACITY: int = 300

# --- Ice -----------------------------------------------------------------
# Ice melts overnight: any stock above ICE_KEEP_FLOOR loses ICE_MELT_RATE of
# itself, scaled by how warm the day was. A small holding never melts, so a
# player who keeps only a handful is not punished, and the insulated ice
# chest shaves the loss down per level.
const ICE_KEEP_FLOOR: int = 10
const ICE_MELT_RATE: float = 0.20
const ICE_PER_DAY_BASE: float = 28.0

# --- Lemons --------------------------------------------------------------
# A crate bought today is good for LEMON_SHELF_LIFE_DAYS days. The walk-in
# cooler upgrade adds to that.
const LEMON_SHELF_LIFE_DAYS: int = 7

# Stock field name -> the capacity stat that raises its limit.
const CAPACITY_STATS: Dictionary = {
	"lemon_stock": "lemon_capacity",
	"sugar_stock": "sugar_capacity",
	"ice_stock": "ice_capacity",
	"cup_stock": "cup_capacity",
}

const FIELD_TO_BASE_CAPACITY: Dictionary = {
	"lemon_stock": BASE_LEMON_CAPACITY,
	"sugar_stock": BASE_SUGAR_CAPACITY,
	"ice_stock": BASE_ICE_CAPACITY,
	"cup_stock": BASE_CUP_CAPACITY,
}

# --- Capacities ----------------------------------------------------------

# Storage limit for one ingredient, upgrades included. Unknown fields give 0.
static func capacity_for(field: String, levels: Dictionary) -> int:
	if not FIELD_TO_BASE_CAPACITY.has(field):
		return 0
	var stat: String = str(CAPACITY_STATS[field])
	var base: float = float(FIELD_TO_BASE_CAPACITY[field])
	var value: float = UpgradeCatalog.stat_value(stat, base, levels)
	return maxi(1, int(round(value)))

# Space left on the stand for one ingredient.
static func room_for(field: String, current: int, levels: Dictionary) -> int:
	return maxi(0, capacity_for(field, levels) - maxi(0, current))

# --- The pitcher floor ---------------------------------------------------
# The floor is the least a day can open with and still sell something: the
# lemons and sugar for one batch, plus the ice for ONE cup. Ice is charged to
# the cup that is sold rather than to the batch, so a single cup's worth is
# the honest minimum. Cups are deliberately NOT here, because an empty cup
# rack never stops a sale being recorded, so it is not a soft lock.
const PITCHER_FIELDS: Array = ["lemon_stock", "sugar_stock", "ice_stock"]

# Single-word lowercase name for a stock field, for messages.
static func field_label(field: String) -> String:
	match field:
		"lemon_stock":
			return "lemons"
		"sugar_stock":
			return "sugar"
		"ice_stock":
			return "ice"
		"cup_stock":
			return "cups"
	return field

# What the floor asks of one stock field, read from the recipe: a batch's
# lemons and sugar, and for ice the amount ONE cup holds, since ice is spent
# per cup. Anything else needs nothing, so cup_stock asks for zero.
static func pitcher_amount(field: String, recipe_lemons: int, recipe_sugar: int,
		recipe_ice: int) -> int:
	match field:
		"lemon_stock":
			return maxi(0, recipe_lemons)
		"sugar_stock":
			return maxi(0, recipe_sugar)
		"ice_stock":
			return maxi(0, recipe_ice)
	return 0

# How much of each pitcher ingredient the given stocks are short of one
# pitcher, keyed by stock field. Empty means the stand can brew.
static func pitcher_shortfall(stocks: Dictionary, recipe_lemons: int,
		recipe_sugar: int, recipe_ice: int) -> Dictionary:
	var short: Dictionary = {}
	for field in PITCHER_FIELDS:
		var key: String = str(field)
		var need: int = pitcher_amount(key, recipe_lemons, recipe_sugar, recipe_ice)
		var have: int = int(stocks.get(key, 0))
		if have < need:
			short[key] = need - have
	return short

# True when the stocks hold enough for one pitcher.
static func can_brew_pitcher(stocks: Dictionary, recipe_lemons: int,
		recipe_sugar: int, recipe_ice: int) -> bool:
	return pitcher_shortfall(stocks, recipe_lemons, recipe_sugar, recipe_ice).is_empty()

# --- Ice -----------------------------------------------------------------

# Share of the overnight melt the player has bought off, 0.0 to 0.9.
static func melt_save(levels: Dictionary) -> float:
	return clampf(UpgradeCatalog.stat_value("ice_melt_save", 0.0, levels), 0.0, 0.9)

# Cubes one full day of ice making produces. Zero until the ice maker itself is
# owned: ICE_PER_DAY_BASE is that machine's level 1 output, so it must never be
# handed out to a stand that never bought one.
static func ice_per_day(levels: Dictionary) -> float:
	if UpgradeCatalog.level_of(levels, UpgradeCatalog.ICE_MAKER_ID) <= 0:
		return 0.0
	return maxf(0.0, UpgradeCatalog.stat_value("ice_per_day", ICE_PER_DAY_BASE, levels))

# How much faster ice goes in warm weather. A hot spell hurts an uninsulated
# stock, a cold snap keeps it, and rain cools things off.
static func ice_melt_multiplier(weather: Dictionary) -> float:
	var w: Dictionary = Weather.sanitize(weather)
	var temp: int = int(w["temp"])
	var mult: float = 1.0
	if temp >= 95:
		mult = 2.0
	elif temp >= 85:
		mult = 1.5
	elif temp >= 70:
		mult = 1.0
	elif temp >= 60:
		mult = 0.75
	else:
		mult = 0.5
	if bool(w["raining"]):
		mult *= 0.85
	return mult

# Cubes lost over one night for a given stock. Takes the already-resolved save
# share so callers read the upgrade levels exactly once.
static func ice_melted(stock: int, melt_save_value: float, weather: Dictionary) -> int:
	if stock <= ICE_KEEP_FLOOR:
		return 0
	var save: float = clampf(melt_save_value, 0.0, 0.9)
	var rate: float = ICE_MELT_RATE * ice_melt_multiplier(weather)
	var melted: float = float(stock) * rate * (1.0 - save)
	return clampi(roundi(melted), 0, stock)

# Ice left the next morning: whatever survived the melt, trimmed to what the
# freezer still holds.
static func ice_after_night(stock: int, capacity: int, melt_save_value: float,
		weather: Dictionary) -> int:
	var left: int = maxi(0, stock - ice_melted(stock, melt_save_value, weather))
	return clampi(left, 0, maxi(1, capacity))

# --- Lemons --------------------------------------------------------------

static func lemon_shelf_life(levels: Dictionary) -> int:
	var value: float = UpgradeCatalog.stat_value("lemon_shelf_life",
		float(LEMON_SHELF_LIFE_DAYS), levels)
	return maxi(1, int(round(value)))

# --- Lemon crates --------------------------------------------------------

static func lots_total(lots: Array) -> int:
	var total: int = 0
	for lot in lots:
		total += maxi(0, int(lot.get("count", 0)))
	return total

# Adds a crate packed today that expires shelf_life days from ref_day, merging
# into an existing crate that shares its expiry so the list stays short.
static func add_to_lots(lots: Array, amount: int, ref_day: int, shelf_life: int) -> void:
	if amount <= 0:
		return
	var life: int = maxi(1, shelf_life)
	var expires: int = ref_day + life
	for lot in lots:
		if int(lot.get("expires", 0)) == expires and int(lot.get("life", 0)) == life:
			lot["count"] = int(lot.get("count", 0)) + amount
			return
	lots.append({"count": amount, "expires": expires, "life": life})

# Eats the shortest-dated crates first so nothing spoils while newer fruit
# sits untouched. Silent when there is not enough stock; callers check first.
static func consume_from_lots(lots: Array, amount: int) -> int:
	var remaining: int = maxi(0, amount)
	var taken: int = 0
	while remaining > 0:
		var idx: int = _soonest_index(lots)
		if idx < 0:
			break
		var have: int = maxi(0, int(lots[idx].get("count", 0)))
		var take: int = mini(have, remaining)
		remaining -= take
		taken += take
		if have - take <= 0:
			lots.remove_at(idx)
		else:
			lots[idx]["count"] = have - take
	return taken

# Index of the crate closest to going off, or -1 when nothing is left.
static func _soonest_index(lots: Array) -> int:
	var best: int = -1
	var best_expires: int = 0
	for i in lots.size():
		if int(lots[i].get("count", 0)) <= 0:
			continue
		var expires: int = int(lots[i].get("expires", 0))
		if best < 0 or expires < best_expires:
			best = i
			best_expires = expires
	return best

# Validates crates from a save file or the server. A crate that arrives with
# no expiry is treated as packed today, and one with no recorded life is taken
# to have been packed under the current shelf life, so an older save never
# gets a retroactive cooler bonus. Never throws.
static func sanitize_lots(raw: Variant, shelf_life: int = LEMON_SHELF_LIFE_DAYS,
		ref_day: int = 1) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	var current: int = maxi(1, shelf_life)
	for entry in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var count: int = int(entry.get("count", 0))
		if count <= 0:
			continue
		var expires: int = int(entry.get("expires", 0))
		if expires <= ref_day:
			expires = ref_day + current
		var life: int = int(entry.get("life", 0))
		if life <= 0:
			life = mini(current, maxi(1, expires - ref_day))
		out.append({"count": count, "expires": expires, "life": life})
	return out

# The freshness pass, run on load and again whenever the day moves on or the
# shelf life improves. Throws out crates that are past their date, grants the
# crates still good the DIFFERENCE a better cooler bought them (once, because
# the crate records the life it was packed under), trims the pile down to the
# space that actually exists, and back-fills one fresh crate when a legacy
# save has a lemon counter but no crates at all. Returns the new crate list.
static func refresh_lots(lots: Variant, shelf_life: int, ref_day: int, capacity: int,
		fallback_stock: int = -1) -> Array:
	var working: Array = sanitize_lots(lots, shelf_life, ref_day)
	var life: int = maxi(1, shelf_life)

	# A better cooler also rescues the fruit already on the shelf: a crate gets
	# the extra days it was packed without, then remembers the new life so the
	# next pass over it is a no-op.
	for lot in working:
		var packed: int = maxi(1, int(lot.get("life", life)))
		if packed < life:
			lot["expires"] = mini(int(lot["expires"]) + (life - packed), ref_day + life)
			lot["life"] = life

	# Nothing usable but a counter says there is fruit: treat it as one fresh
	# crate rather than spoiling stock the player already owned.
	if working.is_empty() and fallback_stock > 0:
		working.append({"count": fallback_stock, "expires": ref_day + life, "life": life})

	# Cull the least useful crates first when the shelves no longer fit it all.
	var total: int = lots_total(working)
	var cap: int = maxi(1, capacity)
	while total > cap:
		var idx: int = _soonest_index(working)
		if idx < 0:
			break
		var over: int = total - cap
		var have: int = maxi(0, int(working[idx].get("count", 0)))
		var drop: int = mini(have, over)
		total -= drop
		if have - drop <= 0:
			working.remove_at(idx)
		else:
			working[idx]["count"] = have - drop

	return _merge_same_expiry(working)

# Folds crates that expire on the same day into one, so the list stays short.
static func _merge_same_expiry(lots: Array) -> Array:
	var out: Array = []
	for lot in lots:
		var count: int = int(lot.get("count", 0))
		if count <= 0:
			continue
		var expires: int = int(lot.get("expires", 0))
		var life: int = int(lot.get("life", 0))
		var merged: bool = false
		for kept in out:
			if int(kept["expires"]) == expires and int(kept["life"]) == life:
				kept["count"] = int(kept["count"]) + count
				merged = true
				break
		if not merged:
			out.append({"count": count, "expires": expires, "life": life})
	return out

# Days until the shortest-dated crate is past its date. 0 means the shelf is
# empty, which is what the shop shows.
static func days_left(lots: Array, ref_day: int) -> int:
	var best: int = 0
	for lot in lots:
		if int(lot.get("count", 0)) <= 0:
			continue
		var left: int = maxi(0, int(lot.get("expires", 0)) - ref_day)
		if best == 0 or left < best:
			best = left
	return best
