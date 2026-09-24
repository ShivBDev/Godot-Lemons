extends RefCounted
class_name UpgradeCatalog

# Data-driven upgrade catalog. Adding an upgrade means adding ONE entry to
# UPGRADES below - no other file needs to change. UpgradesMenu draws one row
# per entry and inserts a heading whenever "group" changes.
#
# Entry shape:
#   id          : String  - stable key, also used as the save key
#   name        : String  - display name
#   description : String  - one-line shop text
#   group       : String  - heading the row sits under in the upgrades menu
#   max_level   : int     - highest purchasable level
#   base_cost   : float   - cost of level 0 -> 1
#   cost_growth : float   - multiplier applied per already-owned level
#   effects     : Array of effects, each:
#       stat      : String  - one of the stat names listed below
#       mode      : "add" | "multiply"
#       per_level : float - amount added, or factor applied, per level
#       min_value : float - lower bound for the resulting stat value
#
# Stat names read by the game:
#   pitcher_capacity  DaySimulation   cups brewed per pitcher
#   brew_time         DaySimulation   seconds to brew a pitcher
#   serve_time        DaySimulation   seconds to serve one customer
#   spawn_interval    DaySimulation   multiplier on the gap between customers
#   ice_per_day       Inventory       ice cubes passively made per day
#   ice_melt_save     Inventory       0..1 share of overnight ice melt avoided
#   lemon_shelf_life  Inventory       days a fresh lemon crate stays good
#   *_capacity        Inventory       storage limit per ingredient
# Capacity stats are paired with a stock field by Inventory.FIELD_TO_CAPACITY_STAT.

# The upgrade that owns the passive ice machine. Inventory reads this to know
# that ice production is zero until the machine has actually been bought.
const ICE_MAKER_ID: String = "ice_maker"

const UPGRADES: Array = [
	# --- The stand --------------------------------------------------------
	{
		"id": "bigger_pitcher",
		"icon": "res://assets/ui/icons/up_bigger_pitcher.png",
		"name": "Bigger Pitcher",
		"group": "The Stand",
		"description": "Brew a larger batch: +6 cups per pitcher per level.",
		"max_level": 8,
		"base_cost": 35.0,
		"cost_growth": 1.45,
		"effects": [
			{"stat": "pitcher_capacity", "mode": "add", "per_level": 6.0, "min_value": 10.0}
		]
	},
	{
		"id": "faster_brewing",
		"icon": "res://assets/ui/icons/up_faster_brewing.png",
		"name": "Faster Brewing",
		"group": "The Stand",
		"description": "Better equipment cuts brewing time by 12 percent per level.",
		"max_level": 7,
		"base_cost": 40.0,
		"cost_growth": 1.5,
		"effects": [
			{"stat": "brew_time", "mode": "multiply", "per_level": 0.88, "min_value": 1.0}
		]
	},
	{
		"id": "faster_serving",
		"icon": "res://assets/ui/icons/up_faster_serving.png",
		"name": "Faster Serving",
		"group": "The Stand",
		"description": "Sharper hands cut serving time by 12 percent per level.",
		"max_level": 7,
		"base_cost": 35.0,
		"cost_growth": 1.5,
		"effects": [
			{"stat": "serve_time", "mode": "multiply", "per_level": 0.88, "min_value": 0.5}
		]
	},
	{
		"id": "advertising",
		"icon": "res://assets/ui/icons/up_advertising.png",
		"name": "Advertising",
		"group": "The Stand",
		"description": "Flyers and a louder sign bring more customers: 8 percent shorter gaps.",
		"max_level": 8,
		"base_cost": 45.0,
		"cost_growth": 1.42,
		"effects": [
			{"stat": "spawn_interval", "mode": "multiply", "per_level": 0.92, "min_value": 1.5}
		]
	},

	# --- Storage ----------------------------------------------------------
	# The stand only holds so much of each ingredient; these raise the limits.
	{
		"id": "extra_shelving",
		"icon": "res://assets/ui/icons/up_extra_shelving.png",
		"name": "Extra Shelving",
		"group": "Storage",
		"description": "More shelf space for fruit: +25 lemons of storage per level.",
		"max_level": 8,
		"base_cost": 28.0,
		"cost_growth": 1.38,
		"effects": [
			{"stat": "lemon_capacity", "mode": "add", "per_level": 25.0, "min_value": 60.0}
		]
	},
	{
		"id": "bigger_sugar_bins",
		"icon": "res://assets/ui/icons/up_bigger_sugar_bins.png",
		"name": "Bigger Sugar Bins",
		"group": "Storage",
		"description": "Sealed bins hold more sweetener: +25 sugar of storage per level.",
		"max_level": 8,
		"base_cost": 24.0,
		"cost_growth": 1.38,
		"effects": [
			{"stat": "sugar_capacity", "mode": "add", "per_level": 25.0, "min_value": 60.0}
		]
	},
	{
		"id": "chest_freezer",
		"icon": "res://assets/ui/icons/up_chest_freezer.png",
		"name": "Chest Freezer",
		"group": "Storage",
		"description": "A deep freezer for ice: +80 ice of storage per level.",
		"max_level": 8,
		"base_cost": 36.0,
		"cost_growth": 1.38,
		"effects": [
			{"stat": "ice_capacity", "mode": "add", "per_level": 80.0, "min_value": 200.0}
		]
	},
	{
		"id": "cup_racking",
		"icon": "res://assets/ui/icons/up_cup_racking.png",
		"name": "Cup Racking",
		"group": "Storage",
		"description": "Stacked racking for cups: +100 cups of storage per level.",
		"max_level": 8,
		"base_cost": 22.0,
		"cost_growth": 1.38,
		"effects": [
			{"stat": "cup_capacity", "mode": "add", "per_level": 100.0, "min_value": 300.0}
		]
	},

	# --- Supplies ---------------------------------------------------------
	# Ice and lemons go off on their own, so these are the counter-measures.
	{
		"id": "insulated_ice_chest",
		"icon": "res://assets/ui/icons/up_insulated_ice_chest.png",
		"name": "Insulated Ice Chest",
		"group": "Supplies",
		"description": "A better icebox loses 8 percent less ice to overnight melt per level.",
		"max_level": 7,
		"base_cost": 55.0,
		"cost_growth": 1.48,
		"effects": [
			{"stat": "ice_melt_save", "mode": "add", "per_level": 0.08, "min_value": 0.0}
		]
	},
	{
		"id": "ice_maker",
		"icon": "res://assets/ui/icons/up_ice_maker.png",
		"name": "Ice Maker",
		"group": "Supplies",
		"description": "A slow machine makes ice over each day: 40 at level 1, plus 12 per level.",
		"max_level": 8,
		"base_cost": 90.0,
		"cost_growth": 1.42,
		"effects": [
			{"stat": "ice_per_day", "mode": "add", "per_level": 12.0, "min_value": 0.0}
		]
	},
	{
		"id": "walk_in_cooler",
		"icon": "res://assets/ui/icons/up_walk_in_cooler.png",
		"name": "Walk-in Cooler",
		"group": "Supplies",
		"description": "Refrigeration keeps lemons fresh for 28 days instead of 7, including the fruit already on the shelf.",
		"max_level": 1,
		"base_cost": 450.0,
		"cost_growth": 1.0,
		"effects": [
			{"stat": "lemon_shelf_life", "mode": "add", "per_level": 21.0, "min_value": 7.0}
		]
	},
]

# Every definition, in catalog order.
static func all() -> Array:
	return UPGRADES

# One definition, or an empty Dictionary when the id is unknown.
# Safe on old saves that reference an upgrade removed from the catalog.
static func get_def(id: String) -> Dictionary:
	for def in UPGRADES:
		if str(def.get("id", "")) == id:
			return def
	return {}

static func has_def(id: String) -> bool:
	return not get_def(id).is_empty()

static func max_level_of(id: String) -> int:
	var def: Dictionary = get_def(id)
	if def.is_empty():
		return 0
	return int(def.get("max_level", 0))

# Cost of buying the level AFTER the given (already owned) level.
static func cost_for(id: String, level: int) -> float:
	var def: Dictionary = get_def(id)
	if def.is_empty():
		return 0.0
	var owned: int = clampi(level, 0, max_level_of(id))
	return float(def.get("base_cost", 0.0)) * pow(float(def.get("cost_growth", 1.0)), float(owned))

static func is_maxed(id: String, level: int) -> bool:
	var def: Dictionary = get_def(id)
	if def.is_empty():
		return true
	return level >= int(def.get("max_level", 0))

# Reads a level out of a saved {id: level} dictionary without ever erroring.
static func level_of(levels: Variant, id: String) -> int:
	if typeof(levels) != TYPE_DICTIONARY:
		return 0
	var d: Dictionary = levels
	if not d.has(id):
		return 0
	var raw: Variant = d[id]
	if not (raw is float or raw is int):
		return 0
	return clampi(roundi(float(raw)), 0, max_level_of(id))

# Walks every definition effect that contributes to stat_name and returns the
# final value, clamped to the effect floor (min_value) for that stat.
static func stat_value(stat_name: String, base_value: float, levels: Dictionary) -> float:
	var value: float = base_value
	var has_floor: bool = false
	var floor_value: float = 0.0
	for def in UPGRADES:
		var id: String = str(def.get("id", ""))
		var level: int = level_of(levels, id)
		if level <= 0:
			continue
		var effects: Array = def.get("effects", [])
		for effect in effects:
			if str(effect.get("stat", "")) != stat_name:
				continue
			var per_level: float = float(effect.get("per_level", 1.0))
			var mode: String = str(effect.get("mode", "add"))
			if mode == "multiply":
				value *= pow(per_level, float(level))
			else:
				value += per_level * float(level)
			var min_value: float = float(effect.get("min_value", 0.0))
			if mode == "multiply" and min_value > 0.0:
				floor_value = maxf(floor_value, min_value) if has_floor else min_value
				has_floor = true
	if has_floor:
		value = maxf(value, floor_value)
	return value

# Convenience wrappers for the four sim stats.
static func effective_pitcher_capacity(base_value: float, levels: Dictionary) -> int:
	return int(round(maxf(1.0, stat_value("pitcher_capacity", base_value, levels))))

static func effective_brew_time(base_value: float, levels: Dictionary) -> float:
	return maxf(0.1, stat_value("brew_time", base_value, levels))

static func effective_serve_time(base_value: float, levels: Dictionary) -> float:
	return maxf(0.05, stat_value("serve_time", base_value, levels))

static func effective_spawn_interval(base_value: float, levels: Dictionary) -> float:
	return maxf(0.2, stat_value("spawn_interval", base_value, levels))

# Storage limits are read through Inventory, which owns the field/stat pairing
# and the base values, so there is no separate wrapper for them here.
