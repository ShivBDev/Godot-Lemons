extends RefCounted
class_name AreaCatalog

# Where the stand can be set up. ONE entry per area: the level scene the day
# sim swaps in, the numbers the day reads, the arrival routes the crowd walks,
# and the wardrobe they wear. Adding an area means adding one entry here.
#
# Entry shape:
#   id            : String - stable key, also the save key
#   name          : String - display name
#   blurb         : String - one line for the areas menu
#   level_scene   : String - res:// level scene instanced under LevelHolder
#   traffic       : float  - multiplier on arrivals (1.0 = neighbourhood pace)
#   price_mult    : float  - multiplier on every customer's price ceiling
#   daily_fee     : float  - charged once at day end for working there
#   attire        : String - wardrobe theme handed to Customer
#   routes        : Array  - arrival waypoint lists (Array of Vector3)
#
# The stand itself never moves: every level scene places the Stand on the same
# transform, so the queue geometry, the routes and the camera framing all carry
# across areas unchanged.

const NEIGHBORHOOD := "neighborhood"
const CITY := "city"
const STADIUM := "stadium"
const DEFAULT_ID := NEIGHBORHOOD

# Wardrobe themes. Neighbourhood keeps the original mixed crowd.
const ATTIRE_SUBURBAN := "suburban"
const ATTIRE_CITY := "city"
const ATTIRE_STADIUM := "stadium"

# Stadium team themes. Two different ones are drawn for each stadium day and
# worn by the crowd, so the colours on the jerseys change every day you work
# the stadium. Add a theme and it joins the rotation.
const TEAM_THEMES: Array = [
	{"name": "Crimson", "primary": Color(0.76, 0.13, 0.16), "secondary": Color(0.95, 0.94, 0.90)},
	{"name": "Royals", "primary": Color(0.13, 0.28, 0.66), "secondary": Color(0.94, 0.75, 0.20)},
	{"name": "Timber", "primary": Color(0.12, 0.42, 0.22), "secondary": Color(0.94, 0.95, 0.92)},
	{"name": "Knights", "primary": Color(0.13, 0.13, 0.16), "secondary": Color(0.80, 0.82, 0.85)},
	{"name": "Embers", "primary": Color(0.92, 0.44, 0.10), "secondary": Color(0.11, 0.18, 0.38)},
	{"name": "Violets", "primary": Color(0.40, 0.18, 0.58), "secondary": Color(0.10, 0.60, 0.58)},
	{"name": "Mariners", "primary": Color(0.55, 0.14, 0.20), "secondary": Color(0.58, 0.78, 0.90)},
	{"name": "Wasps", "primary": Color(0.93, 0.78, 0.15), "secondary": Color(0.14, 0.14, 0.16)},
]

# --- Arrival routes --------------------------------------------------------
# Each is an ordered list of XZ waypoints walked before the customer may join
# the line. Waypoint y is always 0: reaching the queue is a flat translation.

# Both the neighbourhood and the city sit on the same street grid, so they
# share these four proven routes.
const ROUTE_SIDEWALK: Array = [
	Vector3(-2.0, 0.0, -50.0),
	Vector3(-2.0, 0.0, -8.0),
	Vector3(-1.4, 0.0, -4.2),
	Vector3(0.3, 0.0, -3.5),
]
const ROUTE_NEIGHBOURHOOD: Array = [
	Vector3(-2.0, 0.0, 30.0),
	Vector3(-2.0, 0.0, 1.0),
	Vector3(-1.0, 0.0, -1.0),
	Vector3(0.3, 0.0, -3.5),
]
const ROUTE_CROSSWALK: Array = [
	Vector3(-10.75, 0.0, 40.0),
	Vector3(-10.75, 0.0, 12.0),
	Vector3(-10.75, 0.0, 6.0),
	Vector3(-3.0, 0.0, 6.0),
	Vector3(-1.6, 0.0, 1.0),
	Vector3(0.3, 0.0, -3.5),
]
const ROUTE_CORNER: Array = [
	Vector3(54.0, 0.0, 10.0),
	Vector3(7.0, 0.0, 10.0),
	Vector3(3.4, 0.0, 5.0),
	Vector3(3.4, 0.0, 0.5),
	Vector3(0.3, 0.0, 0.5),
	Vector3(0.3, 0.0, -3.5),
]
# City only: in off the far end of the avenue and down the pavement.
const ROUTE_AVENUE: Array = [
	Vector3(-2.0, 0.0, 74.0),
	Vector3(-2.0, 0.0, 30.0),
	Vector3(-2.0, 0.0, 2.0),
	Vector3(-1.2, 0.0, -1.0),
	Vector3(0.3, 0.0, -3.5),
]

const ROUTES_SUBURBAN: Array = [ROUTE_SIDEWALK, ROUTE_NEIGHBOURHOOD, ROUTE_CROSSWALK, ROUTE_CORNER]
const ROUTES_CITY: Array = [ROUTE_SIDEWALK, ROUTE_AVENUE, ROUTE_CROSSWALK, ROUTE_CORNER, ROUTE_NEIGHBOURHOOD]

# Stadium: the concourse is the whole world, so the crowd comes in from the
# turnstiles and the parking lots instead of along a street.
const ROUTE_GATE: Array = [
	Vector3(-2.0, 0.0, -44.0),
	Vector3(-2.0, 0.0, -22.0),
	Vector3(-1.4, 0.0, -6.0),
	Vector3(0.3, 0.0, -3.5),
]
const ROUTE_CONCOURSE: Array = [
	Vector3(5.0, 0.0, 40.0),
	Vector3(4.4, 0.0, 26.0),
	Vector3(0.6, 0.0, 12.0),
	Vector3(0.3, 0.0, -3.5),
]
const ROUTE_TAILGATE: Array = [
	Vector3(4.5, 0.0, 58.0),
	Vector3(3.4, 0.0, 40.0),
	Vector3(4.5, 0.0, 16.0),
	Vector3(1.6, 0.0, 4.0),
	Vector3(0.3, 0.0, -3.5),
]
const ROUTE_CORNER_LOT: Array = [
	Vector3(46.0, 0.0, -30.0),
	Vector3(30.0, 0.0, -30.0),
	Vector3(12.0, 0.0, -22.0),
	Vector3(2.0, 0.0, -10.0),
	Vector3(0.3, 0.0, -3.5),
]
const ROUTE_HOME_END: Array = [
	Vector3(-8.0, 0.0, 40.0),
	Vector3(-6.0, 0.0, 20.0),
	Vector3(0.0, 0.0, 8.0),
	Vector3(0.3, 0.0, -3.5),
]

const ROUTES_STADIUM: Array = [ROUTE_GATE, ROUTE_CONCOURSE, ROUTE_TAILGATE, ROUTE_CORNER_LOT, ROUTE_HOME_END]

# --- The areas -------------------------------------------------------------

const AREAS: Array = [
	{
		"id": NEIGHBORHOOD,
		"name": "The Neighborhood",
		"blurb": "The quiet residential block. Free to work, steady foot traffic, and the locals know what a cup is worth.",
		"level_scene": "res://scenes/neighborhood.tscn",
		"traffic": 1.0,
		"price_mult": 1.0,
		"daily_fee": 0.0,
		"attire": ATTIRE_SUBURBAN,
		"routes": ROUTES_SUBURBAN,
	},
	{
		"id": CITY,
		"name": "Downtown",
		"blurb": "Office towers and a busy avenue. More people walking past, and they will pay a little more for a cold cup.",
		"level_scene": "res://scenes/city.tscn",
		"traffic": 1.35,
		"price_mult": 1.5,
		"daily_fee": 20.0,
		"attire": ATTIRE_CITY,
		"routes": ROUTES_CITY,
	},
	{
		"id": STADIUM,
		"name": "The Stadium",
		"blurb": "A full concourse on match day. The biggest crowds and the loosest wallets, with the steepest fee to match.",
		"level_scene": "res://scenes/stadium.tscn",
		"traffic": 2.0,
		"price_mult": 2.2,
		"daily_fee": 60.0,
		"attire": ATTIRE_STADIUM,
		"routes": ROUTES_STADIUM,
	},
]

# --- Lookups ---------------------------------------------------------------

static func all() -> Array:
	return AREAS

static func get_area(id: String) -> Dictionary:
	for area in AREAS:
		if str(area.get("id", "")) == id:
			return area
	return {}

static func has_area(id: String) -> bool:
	return not get_area(id).is_empty()

# Unknown ids (an old save, a typo) fall back to the neighbourhood rather than
# leaving the stand in limbo with no level.
static func sanitize(id: String) -> String:
	if has_area(id):
		return id
	return DEFAULT_ID

static func name_for(id: String) -> String:
	var area: Dictionary = get_area(sanitize(id))
	return str(area.get("name", DEFAULT_ID))

static func blurb_for(id: String) -> String:
	var area: Dictionary = get_area(sanitize(id))
	return str(area.get("blurb", ""))

static func level_scene_for(id: String) -> String:
	var area: Dictionary = get_area(sanitize(id))
	return str(area.get("level_scene", ""))

static func traffic_for(id: String) -> float:
	var area: Dictionary = get_area(sanitize(id))
	return maxf(0.05, float(area.get("traffic", 1.0)))

static func price_multiplier_for(id: String) -> float:
	var area: Dictionary = get_area(sanitize(id))
	return maxf(0.1, float(area.get("price_mult", 1.0)))

static func daily_fee_for(id: String) -> float:
	var area: Dictionary = get_area(sanitize(id))
	return maxf(0.0, float(area.get("daily_fee", 0.0)))

static func attire_for(id: String) -> String:
	var area: Dictionary = get_area(sanitize(id))
	return str(area.get("attire", ATTIRE_SUBURBAN))

static func routes_for(id: String) -> Array:
	var area: Dictionary = get_area(sanitize(id))
	var routes: Array = area.get("routes", [])
	if routes.is_empty():
		return ROUTES_SUBURBAN
	return routes

# --- Stadium teams ---------------------------------------------------------

# Two different team themes for one stadium day. Called at the start of each
# stadium day, so the crowd's colours are re-rolled every time.
static func roll_team_pair() -> Array:
	var count: int = TEAM_THEMES.size()
	if count == 0:
		return []
	if count == 1:
		return [TEAM_THEMES[0]]
	var first: int = randi() % count
	var second: int = randi() % count
	while second == first:
		second = randi() % count
	return [TEAM_THEMES[first], TEAM_THEMES[second]]
