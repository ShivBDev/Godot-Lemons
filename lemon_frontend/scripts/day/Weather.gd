extends RefCounted
class_name Weather

# Weather model for the day simulation.
# This is a stateless helper: PlayerData owns the saved weather values and
# DaySimulation decides when a day rolls over.

enum Season { Summer, Fall, Winter, Spring }

const DAYS_PER_SEASON: int = 30
const TEMP_MIN: int = 55
const TEMP_MAX: int = 105
const RAIN_CHANCE: float = 0.28
const RAIN_DEMAND_MULT: float = 0.55
const HOT_TEMP: float = 100.0
const COLD_TEMP: float = 55.0
const DEMAND_AT_COLD: float = 0.6
const DEMAND_AT_HOT: float = 1.4

# The calendar repeats summer -> fall -> winter -> spring every 120 days. It
# is derived from the day number, so an old save needs no new field to know
# which season it is in.
static func season_for_day(day: int) -> Season:
	var index: int = (maxi(1, day) - 1) / DAYS_PER_SEASON
	return index % 4

static func season_name(season: Season) -> String:
	return ["Summer", "Fall", "Winter", "Spring"][season]

# How often a day brings precipitation. Winter is 60 percent wetter than the
# base rate, spring 40 percent. Summer and fall keep the original odds.
static func rain_chance_for(season: Season) -> float:
	match season:
		Season.Winter:
			return minf(1.0, RAIN_CHANCE * 1.6)
		Season.Spring:
			return minf(1.0, RAIN_CHANCE * 1.4)
	return RAIN_CHANCE

# Seasonal temperature bands. Summer keeps the measured 55-105 range the game
# has always used; the other seasons are cooler, which is what makes winter
# precipitation read as snow rather than rain.
static func temp_range_for(season: Season) -> Vector2i:
	match season:
		Season.Fall:
			return Vector2i(45, 85)
		Season.Winter:
			# 30F is the loose clamp's floor, so a winter roll never snaps on
			# the way back out of the save.
			return Vector2i(30, 55)
		Season.Spring:
			return Vector2i(50, 90)
	return Vector2i(TEMP_MIN, TEMP_MAX)

# Rolls a fresh day of weather for the given game day.
static func roll_for_day(day: int) -> Dictionary:
	var season: Season = season_for_day(day)
	var band: Vector2i = temp_range_for(season)
	return {
		"temp": randi_range(band.x, band.y),
		"raining": randf() < rain_chance_for(season),
	}

# Kept for callers that do not care which day it is (today, in summer).
static func roll() -> Dictionary:
	return roll_for_day(1)

# Fallback used when a save has no weather stored yet.
static func default_weather() -> Dictionary:
	return {"temp": 75, "raining": false}

# Accepts anything (including data from an older save) and returns a valid
# weather dictionary. Never throws.
static func sanitize(data: Variant) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return default_weather()
	var d: Dictionary = data
	var temp_v: Variant = d.get("temp", 75)
	var raining_v: Variant = d.get("raining", false)
	var temp: int = TEMP_MIN
	if temp_v is float or temp_v is int:
		temp = roundi(float(temp_v))
	return {
		"temp": clampi(temp, TEMP_MIN, TEMP_MAX),
		"raining": bool(raining_v),
	}

# News can push a day outside the usual roll. Same shape as sanitize(), but
# the temperature is allowed past TEMP_MIN / TEMP_MAX.
static func sanitize_loose(data: Variant) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return default_weather()
	var d: Dictionary = data
	var temp_v: Variant = d.get("temp", 75)
	var temp: int = 75
	if temp_v is float or temp_v is int:
		temp = roundi(float(temp_v))
	return {
		"temp": clampi(temp, 30, 120),
		"raining": bool(d.get("raining", false)),
	}

# Short comfort word so the status bar reads like a forecast strip.
static func comfort_word(temp: int) -> String:
	if temp >= 90:
		return "Hot"
	if temp >= 75:
		return "Warm"
	if temp >= 60:
		return "Mild"
	return "Cold"

# Example: "82F Warm Sunny" / "61F Mild Rainy".
static func describe(temp: int, raining: bool) -> String:
	var sky: String = "Rainy" if raining else "Sunny"
	return "%dF %s %s" % [temp, comfort_word(temp), sky]

static func describe_weather(weather: Dictionary) -> String:
	# Loose, so a headline-pushed temperature reads the same here as it does on
	# the status strip.
	var w: Dictionary = sanitize_loose(weather)
	return describe(int(w["temp"]), bool(w["raining"]))

# Hotter means more thirsty customers; rain keeps people home.
static func demand_multiplier(temp: int, raining: bool) -> float:
	var t: float = clampf(float(temp), COLD_TEMP, HOT_TEMP)
	var ratio: float = (t - COLD_TEMP) / (HOT_TEMP - COLD_TEMP)
	var mult: float = lerpf(DEMAND_AT_COLD, DEMAND_AT_HOT, clampf(ratio, 0.0, 1.0))
	if raining:
		mult *= RAIN_DEMAND_MULT
	return clampf(mult, 0.2, 1.8)

static func demand_for(weather: Dictionary) -> float:
	var w: Dictionary = sanitize(weather)
	return demand_multiplier(int(w["temp"]), bool(w["raining"]))

# Hot days push customers toward a little more ice, cold days a little less.
# Deliberately small: about -2 at the usual low, +2 at the usual high, and up
# to 3 either way on a headline day outside that band. Rain takes one more off.
# The area's base recipe stays the anchor; the weather is a nudge.
static func ice_bias(temp: int, raining: bool) -> int:
	var bias: float = (float(temp) - 80.0) / 12.5
	if raining:
		bias -= 1.0
	return int(round(clampf(bias, -3.0, 3.0)))

# Loose, so a heat wave's pushed temperature really does ask for more ice.
static func ice_bias_for(weather: Dictionary) -> int:
	var w: Dictionary = sanitize_loose(weather)
	return ice_bias(int(w["temp"]), bool(w["raining"]))

# --- Headline weather ------------------------------------------------------
# A hot headline ALWAYS lands above the usual high and a cold one ALWAYS below
# the usual low, whatever the forecast rolled. Within the loose 30-120 band.
const HEADLINE_HOT_MIN: int = TEMP_MAX + 3
const HEADLINE_HOT_MAX: int = TEMP_MAX + 12
const HEADLINE_COLD_MIN: int = TEMP_MIN - 15
const HEADLINE_COLD_MAX: int = TEMP_MIN - 3

static func headline_hot_temp() -> int:
	return randi_range(HEADLINE_HOT_MIN, HEADLINE_HOT_MAX)

static func headline_cold_temp() -> int:
	return randi_range(HEADLINE_COLD_MIN, HEADLINE_COLD_MAX)
