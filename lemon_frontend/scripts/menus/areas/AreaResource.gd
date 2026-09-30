extends Resource
class_name MapArea

# Where the stand can be set up. ONE entry per area: the level scene the day
# sim swaps in, the numbers the day reads, the arrival routes the crowd walks,
# and the wardrobe they wear. Adding an area means adding one entry here.
#
# Entry shape:
#   id            : String - stable key, also the save key
#   icon          : String - area menu icon
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

enum AreaID { Neighborhood, City, Stadium }
static func ID2Str(id: AreaID) -> String: return AreaID.keys()[id]
static func Str2ID(name: String) -> AreaID: return AreaID.get(name, AreaID.Neighborhood)
enum Attire { Suburban, City, Stadium }
enum Routes { Suburban, City, Stadium }

@export var id: AreaID = AreaID.Neighborhood
var id_str: String:
	get: return ID2Str(id)
@export_file var icon: String = ""
@export var name: String = ""
@export_multiline var blurb: String = ""
@export_file var level: String = ""
@export var traffic: float = 1.0
@export var price_tolerance: float = 1.0
@export var daily_fee: float = 0.0
@export var attire: Attire = Attire.Suburban
@export var routeID: Routes = Routes.Suburban
var route : Array :
	get:
		match route:
			Routes.Suburban: return ROUTES_SUBURBAN
			Routes.City: return ROUTES_CITY
			Routes.Stadium: return ROUTES_STADIUM
			_: return ROUTES_SUBURBAN

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
