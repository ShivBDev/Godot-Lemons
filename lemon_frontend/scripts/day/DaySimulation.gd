extends Node3D
class_name DaySimulation

signal day_finished

@export var day_length: float = 120.0
@export var serve_time: float = 4.0
@export var brew_time: float = 8.0
@export var pitcher_capacity: int = 10
@export var spawn_min_interval: float = 4.0
@export var spawn_max_interval: float = 9.0
@export var spawn_stop_buffer: float = 25.0
@export var fast_forward_scale: float = 5.0

# Absolute floor for the upgrade-adjusted spawn interval. "advertising" and hot
# weather shorten the gap toward this, never below it.
@export var min_spawn_interval: float = 1.0
@export var max_spawn_interval: float = 4.0

const CustomerScene: PackedScene = preload("res://scenes/simulation_scenes/Customer.tscn")
const QUEUE_SPACING: float = 0.9
# How far apart the two window lines sit, left and right of the counter: one in
# front of the keeper, one in front of the hired server.
const QUEUE_LANE_GAP: float = 1.6
# How far a finished customer steps out sideways before walking off, so the
# way out never runs back down a lane.
const LANE_EXIT_STEP: float = 1.1
# How much closer to the counter the window spot sits than the head of the
# lane, so the customer being served and the next in line never share a spot.
const COUNTER_OFFSET: float = 0.55
# The next customer waits for the one just served to get this far from the
# window before stepping up, so the two never stand in one spot.
const COUNTER_CLEARANCE: float = 0.95
# Points of an arrival route closer than this to the front of the line are
# dropped when the route is walked back out: they sit beside the lanes.
const EXIT_SKIP_RADIUS: float = 3.0

# --- Crowd steering ------------------------------------------------------
# Everyone keeps a little personal space. Walkers are pushed away from anyone
# inside PERSONAL_SPACE, side-step whoever is ahead of them, and slow down to
# follow or yield; nobody is ever let closer than MIN_GAP centre to centre.
const PERSONAL_SPACE: float = 1.0
const MIN_GAP: float = 0.62
const STEER_LIMIT: float = 1.6

# --- Ambient crowd -------------------------------------------------------
# Passers-by walk the area's through-paths and never come to the stand. Their
# rate and head count scale with the area's own traffic, not with the day's
# demand, so the place looks lived in even when nobody wants lemonade.
const PASSBY_MIN_INTERVAL: float = 1.4
const PASSBY_MAX_INTERVAL: float = 3.4
const PASSBY_BASE_CAP: int = 8
const PASSBY_PREWARM: int = 7

# How far in front of the Stand node's origin the first customer stands. The
# counter sits 1.45 m down the stand's local -Z and the awning posts sit at
# 1.9 m, so 2.2 puts the front of the line just outside the posts rather than
# inside the counter.
const QUEUE_FRONT_OFFSET: float = 2.2
# Only used if the Stand node cannot be found, so the sim still has a sane line.
const APPROACH_Z: float = -2.0

# Weather art comes from the icon set in res://assets/ui/icons, preloaded so drawing a
# forecast never stalls on a disk read. Keyed by what kind_for_weather returns.
const WEATHER_ICONS: Dictionary = {
	"sun": preload("res://assets/ui/icons/sun.png"),
	"hot": preload("res://assets/ui/icons/hot.png"),
	"cold": preload("res://assets/ui/icons/cold.png"),
	"rain": preload("res://assets/ui/icons/rain.png"),
	"cloudy": preload("res://assets/ui/icons/cloudy.png"),
}

# Reaction art, shared with the badges that pop above customers' heads so the
# results card and the world can never disagree about what a face means. Each
# reject entry is [tally key, icon path, row label]; the keys are the
# RecipeOpinion.SKIP_* buckets, so a row, its icon and its count all come from
# the one tally and cannot drift apart.
const REJECT_ICONS: Array = [
	["wait", "res://assets/ui/icons/react_clock.svg", "Waited Too Long"],
	["queue", "res://assets/ui/icons/react_crowd.svg", "Line Too Long"],
	["price", "res://assets/ui/icons/react_price.svg", "Cost Too Much"],
	["stock", "res://assets/ui/icons/react_soldout.svg", "Sold Out"],
]
# [tally key, icon path, label]. The counts are read from the day tally.
const TASTE_ICONS: Array = [
	["loved", "res://assets/ui/icons/face_loved.svg", "Loved"],
	["neutral", "res://assets/ui/icons/face_neutral.svg", "Neutral"],
	["disliked", "res://assets/ui/icons/face_disliked.svg", "Disliked"],
]
# Results-card metrics. The card is one vertical list built in code, so a stale
# saved scene still gets the full layout instead of a mix of old and new.
const RESULT_ICON_SIZE: int = 26
const RESULT_FONT: int = 19
const RESULT_FONT_BIG: int = 23
# The area line at the head of the card, a size up from the body text.
const RESULT_HEADER_FONT: int = 30
# Fixed width for a reject reason's name, so every count lines up under the one
# above it however long the reason is.
const RESULT_REASON_WIDTH: int = 214
# Card frame. The card is a fixed width and CENTRED, and its height is fitted to
# whatever it is showing each day. Both matter: a fixed offset from a top-left
# anchor once pushed the card off the top of the screen, and a fixed tall height
# left a slab of dead space under the rows.
const RESULT_CARD_WIDTH: float = 620.0
const RESULT_CARD_MARGIN: float = 26.0
# Rows are HAND-PLACED at these heights rather than measured from their labels.
# A wrapping Label reports its minimum size from whatever width it has right
# now, so measuring the column before the card had been laid out read a 47
# character line as about 47 lines tall and stretched the card over the screen.
const RESULT_ROW_H: float = 34.0
const RESULT_ROW_H_TALL: float = 92.0
const RESULT_HEADER_H: float = 38.0
const RESULT_CARD_TOP_PAD: float = 26.0
const RESULT_CARD_BOTTOM_PAD: float = 78.0
const RESULT_TEXT_COLOR: Color = Color(0.16, 0.11, 0.06)
const RESULT_MUTED_COLOR: Color = Color(0.42, 0.34, 0.22)
const RESULT_LOSS_COLOR: Color = Color(0.72, 0.28, 0.16)
const RESULT_PROFIT_COLOR: Color = Color(0.15, 0.45, 0.20)

# Arrival routes live in AreaCatalog now, one set per area, so the crowd walks
# in from the right streets wherever the stand is set up. Every route in every
# area still converges on the pavement in front of the counter and none of them
# crosses the stand, so the queue geometry below carries across unchanged.
#
# The level scenery for the current area is instanced under LevelHolder, which
# every level scene contributes to: the stand itself never moves, so switching
# areas swaps the world around it without touching the queue or the camera.

var running: bool = false
var spawning: bool = false
var day_remaining: float = 0.0
var spawn_timer: float = 0.0
var time_scale: float = 1.0
var fast_forward: bool = false

# Effective stats for the CURRENT day: base @export values run through
# PlayerData.upgrade_levels via UpgradeCatalog, plus today's weather on the
# spawn interval. Recomputed once at start_day(), so a purchase takes effect
# the next day.
var eff_pitcher_capacity: int = 10
var eff_brew_time: float = 8.0
var eff_serve_time: float = 4.0
var eff_spawn_min: float = 4.0
var eff_spawn_max: float = 9.0
# Area multipliers for the current day. Traffic shortens the gap between
# arrivals, and the price multiplier is how much the locals here will pay.
var eff_area_traffic: float = 1.0
var eff_price_mult: float = 1.0
# Ice the ice maker produces across one full day, and the fraction of a cube
# accrued so far today. Both stay at zero until the upgrade is bought.
var eff_ice_per_day: float = 0.0
var ice_made: float = 0.0

var cups_left: int = 0
var brewing: bool = false
var brew_remaining: float = 0.0
var serve_target = null
var serve_remaining: float = 0.0

var customers: Array = []
var queue: Array = []

# Where the line actually is. Derived from the Stand node rather than written
# down as numbers, so turning or moving the stand in the editor takes the queue
# with it instead of leaving customers standing inside the counter.
var _queue_front: Vector3 = Vector3(0.0, 0.0, APPROACH_Z)
var _queue_dir: Vector3 = Vector3(0.0, 0.0, -1.0)

var revenue: float = 0.0
var cups_sold: int = 0
var served_count: int = 0
var rejected_count: int = 0
var reject_reasons: Dictionary = {}
var perfect_cups: int = 0
var loved_count: int = 0
var neutral_count: int = 0
var disliked_count: int = 0
var opinion_lines: Array = []
# Second window. Null unless a server is hired for this day.
var serve_target_b = null
var serve_remaining_b: float = 0.0
var queue_b: Array = []
var _queue_front_b: Vector3 = Vector3(0.9, 0.0, APPROACH_Z)
var _queue_center: Vector3 = Vector3(0.0, 0.0, APPROACH_Z)
# Unit vector from lane A toward lane B, across the front of the counter.
var _lane_side: Vector3 = Vector3(1.0, 0.0, 0.0)
# The customer who last left each window, so the next one waits for them.
var _lane_leaver: Array = [null, null]

# Everyone walking about who no longer matters to the day: passers-by, and
# customers on their way out. Kept apart from `customers` so the day can end
# while the last buyer is still walking off up the street.
var walkers: Array = []
var _passby_timer: float = 0.0

@onready var stand: Node3D = get_node_or_null("Stand")
# The current area's scenery is instanced under this node and swapped for a
# different area's scene when the player moves the stand.
@onready var level_holder: Node3D = get_node_or_null("LevelHolder")
var loaded_level_scene: String = ""
@onready var time_label: Label = $HUD/TopBar/DayTimeLabel
@onready var top_bar: Panel = $HUD/TopBar
@onready var status_money_label: Label = $HUD/StatusBar/MoneyLabel
@onready var status_lemon_count: Label = $HUD/StatusBar/CountLemon
@onready var status_sugar_count: Label = $HUD/StatusBar/CountSugar
@onready var status_ice_count: Label = $HUD/StatusBar/CountIce
@onready var status_cup_count: Label = $HUD/StatusBar/CountCup
@onready var status_weather_icon: TextureRect = $HUD/StatusBar/WeatherIcon
@onready var status_forecast_icon: TextureRect = $HUD/StatusBar/ForecastIcon
@onready var status_weather_label: Label = $HUD/StatusBar/WeatherLabel
@onready var status_forecast_label: Label = $HUD/StatusBar/ForecastLabel
@onready var status_label: Label = $HUD/TopBar/StatusLabel
@onready var stock_label: Label = $HUD/TopBar/StockLabel
@onready var revenue_label: Label = $HUD/TopBar/RevenueLabel
@onready var results_panel: Control = $HUD/ResultsPanel
@onready var results_revenue: Label = $HUD/ResultsPanel/ResultsRevenue
@onready var results_cups: Label = $HUD/ResultsPanel/ResultsCups
@onready var results_served: Label = $HUD/ResultsPanel/ResultsServed
@onready var results_rejected: Label = $HUD/ResultsPanel/ResultsRejected
# The results card lists everything itself, in one column built at boot. The
# old hand-placed text rows are retired (hidden) but stay declared so a saved
# scene that still carries them loads and can be switched off.
@onready var results_spoilage: Label = get_node_or_null("HUD/ResultsPanel/ResultsSpoilage")
@onready var results_area: Label = get_node_or_null("HUD/ResultsPanel/ResultsArea")
@onready var results_opinions: Label = get_node_or_null("HUD/ResultsPanel/ResultsOpinions")
@onready var results_popularity: Label = get_node_or_null("HUD/ResultsPanel/ResultsPopularity")
# The card and the column every results row is added to, both built by
# _prepare_results_panel().
var _results_card: Panel = null
# A bare holder the rows are hand-placed inside, not a container: nothing about
# the card's layout is measured from its children.
var _results_body: Control = null
@onready var news_banner: Label = get_node_or_null("HUD/NewsBanner")
@onready var crew: Node3D = get_node_or_null("Stand/Crew")
# The player's name, painted on the stand sign on the line above the LEMONADE
# word. Optional: a scene without the label still runs, it just shows no name.
@onready var sign_user_label: Label3D = get_node_or_null("Stand/SignUserLabel")

func _ready() -> void:
	results_panel.visible = false
	# Wired BEFORE the card is built, because building it moves the button into
	# the card's own column and this path stops resolving afterwards.
	var finish_button: Button = get_node_or_null("HUD/ResultsPanel/FinishDayButton")
	if finish_button != null:
		finish_button.pressed.connect(_on_finish_day_pressed)
	_prepare_results_panel()
	var speed_button: Button = get_node_or_null("HUD/SpeedButton")
	if speed_button != null:
		speed_button.pressed.connect(_on_speed_button_pressed)
	if not PlayerData.profile_updated.is_connected(_refresh_status_bar):
		PlayerData.profile_updated.connect(_refresh_status_bar)
	if not PlayerData.weather_changed.is_connected(_refresh_status_bar):
		PlayerData.weather_changed.connect(_refresh_status_bar)
	if not PlayerData.area_changed.is_connected(_on_area_changed):
		PlayerData.area_changed.connect(_on_area_changed)
	_apply_effective_stats()
	_refresh_level()
	_refresh_queue_anchor()
	update_hud()
	_update_speed_button()
	_refresh_status_bar()

func is_running() -> bool:
	return running

func start_day() -> void:
	if running:
		return
	# Manually save user setup, enable response requeue in case autosave was running
	print("Starting day, saving...")
	GameNet.sync_user_data(true)

	running = true
	# The pitch fee and the wages are paid up front, before the first customer
	# walks up, so the day can never end with the till in the red.
	PlayerData.pay_day_start_costs()
	spawning = true
	day_remaining = day_length
	spawn_timer = 2.0
	revenue = 0.0
	cups_sold = 0
	served_count = 0
	rejected_count = 0
	reject_reasons = {}
	perfect_cups = 0
	loved_count = 0
	neutral_count = 0
	disliked_count = 0
	opinion_lines = []
	serve_target_b = null
	serve_remaining_b = 0.0
	queue_b.clear()
	_lane_leaver = [null, null]
	PlayerData.reset_opinions()
	PlayerData.ensure_news()
	fast_forward = false
	time_scale = 1.0
	cups_left = 0
	ice_made = 0.0
	brewing = false
	brew_remaining = 0.0
	serve_target = null
	serve_remaining = 0.0
	for c in customers:
		if is_instance_valid(c):
			c.queue_free()
	customers.clear()
	queue.clear()
	results_panel.visible = false
	if PlayerData.current_area == MapArea.AreaID.Stadium:
		AreaCatalog.roll_new_team_themes()
	_apply_effective_stats()
	_refresh_level()
	# Re-read the stand, so moving or turning it in the editor lands on the next
	# day rather than only after a scene reload.
	_refresh_queue_anchor()
	_try_start_brewing()
	update_hud()
	_update_speed_button()
	_refresh_status_bar()

func _process(_delta: float) -> void:
	# The ambient crowd walks whether or not a day is running, so the street
	# looks lived in while the player shops too.
	_ambient_step(_delta * time_scale)
	if not running:
		_crowd_step()
		return
	var delta: float = _delta * time_scale
	day_remaining -= delta
	if day_remaining <= 0.0:
		day_remaining = 0.0
		spawning = false
	elif day_remaining <= spawn_stop_buffer:
		spawning = false
	if spawning:
		spawn_timer -= delta
		if spawn_timer <= 0.0:
			_spawn_customer()
			# Weather-scaled, upgrade-scaled gap between customers.
			spawn_timer = randf_range(eff_spawn_min, eff_spawn_max)
	# Passive ice: the ice maker runs while the day runs, so a full played day
	# hands over exactly eff_ice_per_day cubes, drip fed rather than in one lump.
	if eff_ice_per_day > 0.0:
		ice_made += eff_ice_per_day * (delta / maxf(day_length, 0.0001))
		var whole: int = int(floor(ice_made))
		if whole > 0:
			ice_made -= float(whole)
			var stored: int = PlayerData.add_stock("ice_stock", whole)
			if stored < whole:
				# The freezer is full: drop what will not fit instead of
				# banking it for a day when there is room again.
				ice_made = 0.0
	if brewing:
		brew_remaining -= delta
		if brew_remaining <= 0.0:
			brewing = false
			brew_remaining = 0.0
			cups_left = eff_pitcher_capacity
	# Service time only runs once the customer has actually stepped up to the
	# window, so nobody is served from halfway down the pavement.
	if serve_target != null:
		if not is_instance_valid(serve_target):
			serve_target = null
		elif serve_target.at_counter:
			serve_remaining -= delta
			if serve_remaining <= 0.0:
				_finish_service()
	if serve_target_b != null:
		if not is_instance_valid(serve_target_b):
			serve_target_b = null
		elif serve_target_b.at_counter:
			serve_remaining_b -= delta
			if serve_remaining_b <= 0.0:
				_finish_service_b()
	_update_queue_slots()
	_process_queue_front()
	_crowd_step()
	update_hud()
	# The bell has rung. Waiting for the last customers to finish strolling off
	# meant the results card turned up long after the clock ran out, so the day
	# now closes the moment the timer does: whoever is mid-service is served at
	# once, and the rest of the line is sent home without it counting against
	# them. The walkers keep drifting off behind the results card and are
	# cleared away when the next day starts.
	if day_remaining <= 0.0:
		_close_day()

# --- Area scenery ---------------------------------------------------------

# Instances the current area's level scene under LevelHolder, replacing whatever
# is already there. Called at boot and at the start of every day, so moving the
# stand to another area lands before the first customer walks in.
func _refresh_level() -> void:
	if level_holder == null or not is_instance_valid(level_holder):
		return
	var scene_path: String = AreaCatalog.get_area(PlayerData.current_area).level
	if scene_path.is_empty():
		return
	if scene_path == loaded_level_scene and level_holder.get_child_count() > 0:
		return
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_warning("[day] could not load area scene: %s" % scene_path)
		return
	# Swap the old scenery out before the new scene goes in, so the two never
	# overlap for a frame.
	for child in level_holder.get_children():
		level_holder.remove_child(child)
		child.queue_free()
	level_holder.add_child(packed.instantiate())
	loaded_level_scene = scene_path
	# New streets, new crowd: the old passers-by were walking the last area's
	# paths and would cut straight through the new scenery.
	_reset_passersby()

# Moving the stand lands immediately, even mid-shop: the scenery swaps under the
# HUD so the player can see where they just set up. The day's numbers and the
# fee are read at start_day() and _end_day(), so they pick it up on their own.
func _on_area_changed(_area_id: MapArea.AreaID) -> void:
	_apply_effective_stats()
	_refresh_level()
	_refresh_status_bar()

# --- Queue geometry --------------------------------------------------------

# Reads the Stand node once and turns its transform into the queue. The counter
# faces along the stand's local -Z, so that single axis gives both the direction
# the line runs and the direction customers face while they are being served.
func _refresh_queue_anchor() -> void:
	if stand == null or not is_instance_valid(stand):
		return
	var facing: Vector3 = -stand.global_transform.basis.z
	facing.y = 0.0
	if facing.length() < 0.0001:
		return
	facing = facing.normalized()
	_queue_dir = facing
	var side: Vector3 = stand.global_transform.basis.x
	side.y = 0.0
	if side.length() < 0.0001:
		side = Vector3(1.0, 0.0, 0.0)
	else:
		side = side.normalized()
	_lane_side = side
	var center: Vector3 = stand.global_position + facing * QUEUE_FRONT_OFFSET
	center.y = 0.0
	_queue_center = center
	# Two starts, side by side in front of the counter. Lane A is left of the
	# counter, lane B right; a hired server opens the right-hand one.
	_queue_front = center - side * (QUEUE_LANE_GAP * 0.5)
	_queue_front_b = center + side * (QUEUE_LANE_GAP * 0.5)

# Direction a customer faces while waiting at or being served at the counter:
# straight back at the stand, whichever way it was turned.
func get_queue_facing() -> Vector3:
	return -_queue_dir

# The point on the pavement the two lines open from, midway between the lanes.
func queue_center() -> Vector3:
	return _queue_center

func queue_lane_gap() -> float:
	return QUEUE_LANE_GAP

# Back of the line, where the next arrival stops before the queue takes over.
func get_line_end_point() -> Vector3:
	return _queue_front + _queue_dir * (float(queue.size()) * QUEUE_SPACING)

func _server_hired() -> bool:
	return PlayerData.is_hired(StaffMember.STAFF_ID.server)

func get_line_end_point_b() -> Vector3:
	return _queue_front_b + _queue_dir * (float(queue_b.size()) * QUEUE_SPACING)

func get_line_end_z() -> float:
	return get_line_end_point().z

# Whether one cup could actually be handed over right now: a cup on the rack,
# the ice the recipe puts in it, and either a cup already poured or a batch that
# can still be brewed. Any one of the three missing is a hard stop, so a dry
# tray or an empty cup shelf turns people away exactly like an empty jug.
func _can_serve_a_cup() -> bool:
	if PlayerData.ice_stock < PlayerData.recipe_ice:
		return false
	if PlayerData.cup_stock < 1:
		return false
	if cups_left > 0:
		return true
	return brewing or _can_brew()

func on_customer_arrived(c) -> void:
	# Nobody joins the line when not even one cup could be served.
	if not _can_serve_a_cup():
		_reject_customer(c, "Out of stock!")
		return
	# With two windows open the customer joins the shorter line and is told
	# which lane it is; with one window, the keeper's lane. Both lanes are
	# real queue arrays, so the two lines stand side by side and never merge.
	var use_b: bool = _server_hired() and _line_length(queue_b, serve_target_b) < _line_length(queue, serve_target)
	var line: Array = queue_b if use_b else queue
	var serving = serve_target_b if use_b else serve_target
	var line_len: int = _line_length(line, serving)
	if line_len > c.line_tolerance:
		_reject_customer(c, "Line too long!")
		return
	line.append(c)
	c.queue_lane = 1 if use_b else 0
	c.enter_queue()

func on_customer_gave_up(c) -> void:
	queue.erase(c)
	queue_b.erase(c)
	_reject_customer(c, "Gotta go!")

func _line_length(line: Array, serving) -> int:
	return line.size() + (1 if serving != null else 0)

# A customer who has reached the end of their leave route. They are already
# out of the queue by then; this only frees the model.
func on_customer_finished(c) -> void:
	walkers.erase(c)
	customers.erase(c)
	queue.erase(c)
	queue_b.erase(c)
	if is_instance_valid(c):
		c.queue_free()

# A passer-by finished their through-path.
func on_passerby_done(c) -> void:
	walkers.erase(c)
	if is_instance_valid(c):
		c.queue_free()

func _spawn_customer() -> void:
	PlayerData.note_customer_arrival()
	var c = CustomerScene.instantiate()
	# Routes come from the area, so the crowd walks in off the right streets
	# for wherever the stand is set up today.
	var area_routes: Array = PlayerData.area_routes()
	var route: PackedVector3Array = PackedVector3Array(area_routes[randi() % area_routes.size()])
	# Start on the route's first waypoint: the customer is already walking in
	# from the edge of the block rather than appearing in front of the stand.
	c.position = route[0]
	# Weather is handed over before the customer enters the tree, because
	# _ready() rolls the ideals with the weather bias baked in.
	c.spawn(self, PlayerData.today_weather(), route)
	add_child(c)
	customers.append(c)

# --- Ambient crowd -------------------------------------------------------
# People who are not customers: they walk a through-path end to end and are
# freed. They make the block look lived in, and because the steering pass knows
# about them they also part around the queue instead of cutting through it.

func _reset_passersby() -> void:
	for w in walkers:
		if is_instance_valid(w):
			w.queue_free()
	walkers.clear()
	_passby_timer = 0.0
	for i in PASSBY_PREWARM:
		_spawn_passerby(true)

func _ambient_step(delta: float) -> void:
	# Seeded once so the streets are already busy the moment the scene opens,
	# rather than filling up over the first few seconds.
	_passby_timer -= delta
	if _passby_timer <= 0.0:
		_spawn_passerby(false)
		_passby_timer = randf_range(PASSBY_MIN_INTERVAL, PASSBY_MAX_INTERVAL)

func _spawn_passerby(spread_out: bool) -> void:
	var paths: Array = PlayerData.area_passby_paths()
	if paths.is_empty():
		return
	var path: PackedVector3Array = PackedVector3Array(paths[randi() % paths.size()])
	if path.size() < 2:
		return
	# A prewarmed walker starts partway along so the first wave is spread over
	# the whole street instead of stepping off the same corner together.
	if spread_out and randf() < 0.6:
		var start: int = randi_range(1, path.size() - 1)
		_spawn_walker(path, start)
		return
	# Alternate the direction so paths are used both ways.
	if randf() < 0.5:
		var reversed_path := PackedVector3Array(path)
		reversed_path.reverse()
		_spawn_walker(reversed_path, 0)
	else:
		_spawn_walker(path, 0)

func _spawn_walker(path: PackedVector3Array, start_index: int) -> void:
	var p = CustomerScene.instantiate()
	p.position = path[start_index]
	p.spawn_passerby(self, path, start_index)
	add_child(p)
	walkers.append(p)

# --- Crowd steering ------------------------------------------------------
# One pass each frame gives every walker a push away from whoever is too close
# and a speed factor that drops to zero behind someone ahead. Queued people and
# counter people are on rails, so they only ever act as obstacles.

func _crowd_step() -> void:
	var movers: Array = []
	for c in customers:
		if is_instance_valid(c) and c.is_steered():
			movers.append(c)
	for w in walkers:
		if is_instance_valid(w):
			movers.append(w)
	# Anyone standing still matters as an obstacle: queued people, people at
	# the counter, and any walker that is not currently moving.
	var solids: Array = []
	for c in customers:
		if is_instance_valid(c) and not c.is_steered():
			solids.append(c)
	for w in walkers:
		if is_instance_valid(w) and not w.is_steered():
			solids.append(w)
	for m in movers:
		var push := Vector3.ZERO
		var slow: float = 1.0
		for o in solids:
			var d: Vector3 = m.position - o.position
			d.y = 0.0
			var dist: float = d.length()
			if dist < 0.0001:
				# Exactly overlapped: shove apart on a stable axis so the two
				# never stay pinned on the same spot.
				push += Vector3(1.0, 0.0, 0.0)
				continue
			if dist < PERSONAL_SPACE:
				var away: Vector3 = d / dist
				var strength: float = (PERSONAL_SPACE - dist) / PERSONAL_SPACE
				push += away * strength
				# Nearer than MIN_GAP is more than a nudge: yield to a stop.
				if dist < MIN_GAP:
					slow = minf(slow, clampf(dist / MIN_GAP, 0.0, 1.0))
		for o in movers:
			if o == m:
				continue
			var d: Vector3 = m.position - o.position
			d.y = 0.0
			var dist: float = d.length()
			if dist >= 0.0001 and dist < PERSONAL_SPACE:
				var away: Vector3 = d / dist
				var strength: float = (PERSONAL_SPACE - dist) / PERSONAL_SPACE
				push += away * strength * 0.6
		# Fade out if too many pushes stack up, so nobody snaps around.
		if push.length() > STEER_LIMIT:
			push = push.normalized() * STEER_LIMIT
		m.steer = push
		m.speed_factor = slow

# A batch eats lemons and sugar. Ice is deliberately NOT here: the recipe's
# ice count is what one CUP holds, and it is spent when that cup is sold, so a
# batch can be brewed with a dry tray and it is the sale that refuses.
func _can_brew() -> bool:
	return PlayerData.lemon_stock >= PlayerData.recipe_lemons \
		and PlayerData.sugar_stock >= PlayerData.recipe_sugar

func _try_start_brewing() -> void:
	if brewing:
		return
	if cups_left > 0:
		return
	if not _can_brew():
		return
	# consume_stock() refuses a partial spend and takes lemons from the crate
	# closest to going off first, so a stale crate is used before fresh fruit.
	# _can_brew() above already checked both, so these are all-or-nothing.
	if not PlayerData.consume_stock("lemon_stock", PlayerData.recipe_lemons):
		return
	if not PlayerData.consume_stock("sugar_stock", PlayerData.recipe_sugar):
		return
	brewing = true
	brew_remaining = eff_brew_time

# --- Reactions ------------------------------------------------------------

# Pops a badge above a customer's head. It is parented to the sim and runs on
# real time, so it survives fast forward and the customer being freed mid-float.
func spawn_reaction(c, kind: String) -> void:
	if c == null or not is_instance_valid(c) or kind.is_empty():
		return
	var badge = ReactionIcon.make(kind)
	if badge == null:
		return
	add_child(badge)
	# Hand over the person, not a fixed spot: the badge rides above their head
	# as they walk off, which is where the sip actually happens.
	badge.follow(c)

# --- Leaving --------------------------------------------------------------

# The way out for a customer. Someone who was standing in a lane steps out
# sideways first, clear of the line, and then retraces the route they came in
# on, so the way out never crosses the people still queueing. Anyone turned
# away out on the pavement just carries on past the stand.
func leave_route_for(c, from_line: bool) -> PackedVector3Array:
	var route := PackedVector3Array()
	if c == null or not is_instance_valid(c):
		return route
	var here: Vector3 = Vector3(c.position.x, 0.0, c.position.z)
	if from_line:
		# Step out to the outer edge of the queue, away from the other lane.
		var outward: Vector3 = _lane_side if c.queue_lane == 0 else -_lane_side
		route.append(here + outward * LANE_EXIT_STEP)
	var arrival: PackedVector3Array = c.arrival_route()
	for i in range(arrival.size() - 1, -1, -1):
		var p: Vector3 = arrival[i]
		if here.distance_to(p) < EXIT_SKIP_RADIUS:
			continue
		if not route.is_empty() and route[route.size() - 1].distance_to(p) < 0.05:
			continue
		route.append(p)
	if route.size() < 2:
		# Nothing usable to retrace: head away from the stand, and the sim frees
		# them once they are out of shot.
		route.append(here - _queue_dir * 14.0)
	return route

func _reject_customer(c, reason: String) -> void:
	rejected_count += 1
	if reject_reasons.has(reason):
		reject_reasons[reason] += 1
	else:
		reject_reasons[reason] = 1
	PlayerData.note_customer_skip(reason)
	c.reject(reason)

# Writes each lane's queue slots, then decides who, if anyone, is standing at
# each window this frame.
func _update_queue_slots() -> void:
	_write_slots(queue, _queue_front)
	_write_slots(queue_b, _queue_front_b)
	_age_lane_leavers()
	for lane_line in [queue, queue_b]:
		for x in lane_line:
			if is_instance_valid(x):
				x.at_window = false
	_assign_window(queue, serve_target, _queue_front, 0)
	_assign_window(queue_b, serve_target_b, _queue_front_b, 1)

func _write_slots(line: Array, front: Vector3) -> void:
	for i in line.size():
		if not is_instance_valid(line[i]):
			continue
		var slot: Vector3 = front + _queue_dir * (float(i) * QUEUE_SPACING)
		slot.y = 0.0
		line[i].queue_slot_pos = slot

# Whoever the window belongs to: the customer being served, or, with the window
# free, the head of the line. The head only steps up once the last customer has
# walked COUNTER_CLEARANCE away, which is what stops the two sharing a spot.
func _assign_window(line: Array, serving, window_pos: Vector3, lane: int) -> void:
	if serving != null and is_instance_valid(serving):
		_place_at_window(serving, window_pos)
		return
	var leaver = _lane_leaver[lane]
	if leaver != null and is_instance_valid(leaver) \
			and leaver.position.distance_to(window_pos) < COUNTER_CLEARANCE:
		return
	if line.is_empty():
		return
	var head = line[0]
	if not is_instance_valid(head):
		return
	_place_at_window(head, window_pos)

func _place_at_window(walker, window_pos: Vector3) -> void:
	if walker.counter_pos.distance_to(window_pos) > 0.0001:
		walker.counter_pos = window_pos
		walker.at_counter = false
	walker.at_window = true

# Drops each lane's leaver once it has stepped clear, so the next customer is
# allowed to take the window.
func _age_lane_leavers() -> void:
	for i in 2:
		var leaver = _lane_leaver[i]
		if leaver == null or not is_instance_valid(leaver):
			_lane_leaver[i] = null
			continue
		var win: Vector3 = _queue_front_b if i == 1 else _queue_front
		if leaver.position.distance_to(win) >= COUNTER_CLEARANCE:
			_lane_leaver[i] = null

func _process_queue_front() -> void:
	_serve_from(queue, false)
	if _server_hired():
		_serve_from(queue_b, true)

func _serve_from(line: Array, second: bool) -> void:
	if line.is_empty():
		return
	if second and serve_target_b != null:
		return
	if not second and serve_target != null:
		return
	if brewing:
		return
	if cups_left <= 0:
		# An empty jug is only fatal when another batch cannot be brewed.
		if not _can_brew():
			var waiting = line[0]
			line.pop_front()
			_reject_customer(waiting, "Out of stock!")
		return
	var front = line[0]
	line.pop_front()
	var window: Vector3 = _queue_front_b if second else _queue_front
	if second:
		serve_target_b = front
		serve_remaining_b = eff_serve_time
	else:
		serve_target = front
		serve_remaining = eff_serve_time
	front.begin_service(window)

func _finish_service() -> void:
	_end_service(serve_target, 0)

func _finish_service_b() -> void:
	_end_service(serve_target_b, 1)

func _end_service(c, lane: int) -> void:
	if lane == 1:
		serve_target_b = null
		serve_remaining_b = 0.0
	else:
		serve_target = null
		serve_remaining = 0.0
	if c == null or not is_instance_valid(c):
		return
	# Remember who just left this window: the next customer waits for them to
	# step clear before taking the spot.
	_lane_leaver[lane] = c
	_resolve_sale(c, lane)

func _resolve_sale(c, lane: int) -> void:
	if c == null or not is_instance_valid(c):
		return
	# Every cup needs ice and a cup of its own. Running out of either turns the
	# customer away exactly like an empty rack, and the cup is only struck off
	# the shelf once the sale is actually made.
	if PlayerData.ice_stock < PlayerData.recipe_ice or PlayerData.cup_stock < 1:
		_reject_customer(c, "Out of stock!")
		return
	if c.evaluate_purchase():
		cups_left -= 1
		cups_sold += 1
		revenue += PlayerData.sale_price
		served_count += 1
		PlayerData.cup_stock = maxi(0, PlayerData.cup_stock - 1)
		# The ice this cup is made of leaves the tray with the cup.
		PlayerData.consume_stock("ice_stock", PlayerData.recipe_ice)
		PlayerData.note_sale(PlayerData.sale_price)
		# The cup is scored once, and that one score drives both the popularity
		# tally and the reaction above the customer's head, so the badge on
		# screen and the points behind it can never disagree. Nobody tastes
		# before they buy, so a recipe that misses the ideal costs popularity
		# here instead of costing the sale.
		var opinion: Dictionary = c.score_recipe()
		_record_opinion(opinion)
		c.buy(str(opinion.get("verdict", RecipeOpinion.NEUTRAL)))
		if cups_left <= 0:
			_try_start_brewing()
	else:
		_reject_customer(c, c.reason)

func _record_opinion(opinion: Dictionary) -> void:
	PlayerData.note_opinion(opinion)
	var band: String = str(opinion.get("band", RecipeOpinion.NEUTRAL))
	if band == RecipeOpinion.LOVE:
		loved_count += 1
	elif band == RecipeOpinion.DISLIKE:
		disliked_count += 1
	else:
		neutral_count += 1
	var earned: int = Popularity.points_for_verdict(str(opinion.get("verdict", opinion.get("band", RecipeOpinion.NEUTRAL))))
	if bool(opinion.get("perfect", false)):
		perfect_cups += 1
	if PlayerData.note_popularity_points(earned, PlayerData.current_area):
		opinion_lines.append("Popularity up")
	var note: String = RecipeOpinion.summary_line(opinion)
	if not note.is_empty():
		opinion_lines.append(note)

# Pays out the fraction of a cube the day happened to end on, so a full played
# day yields the ice maker's whole output instead of stopping one cube short.
func _flush_ice_maker() -> void:
	if ice_made < 1.0:
		ice_made = 0.0
		return
	var whole: int = int(floor(ice_made))
	ice_made = 0.0
	PlayerData.add_stock("ice_stock", whole)

# Closes the day out promptly. Anyone mid-service is paid out at once, and
# everyone still standing in a line is sent home through the ordinary leave
# walk without it counting as a rejection, so the results card appears the
# moment the clock runs out instead of waiting on half the street to disperse.
func _close_day() -> void:
	if not running:
		return
	if serve_target != null:
		_finish_service()
	if serve_target_b != null:
		_finish_service_b()
	for c in customers.duplicate():
		if is_instance_valid(c):
			c.dismiss_out()
	_end_day()

func _end_day() -> void:
	running = false
	spawning = false
	fast_forward = false
	time_scale = 1.0
	_update_speed_button()
	PlayerData.money += revenue
	# The pitch fee and the wages were already taken at start_day(), so day end
	# only settles the stock and the calendar.
	_flush_ice_maker()
	# Tomorrow's headline is rolled and folded into tomorrow's forecast BEFORE
	# the calendar rolls over. resolve_day_end() then promotes that forecast to
	# today, so the headline lands on the day the ticker promised instead of
	# the one after it.
	PlayerData.roll_next_news()
	PlayerData.apply_news_to_forecast()
	PlayerData.resolve_day_end()
	# One career-stat entry per played day, filed against the area it was
	# worked in and weighed against the best day so far.
	PlayerData.note_day_finished(revenue, cups_sold)
	PlayerData.profile_updated.emit()
	print("Day Finished, saving...")
	GameNet.sync_user_data()
	_show_results()
	_refresh_status_bar()

# The day's books, top to bottom: where the stand was and what it cost up
# front, what it took, what it really made, what the night ate, how many people
# were served or turned away (and why, as icon rows), and how the crowd felt
# about the recipe. The prose the old card buried this under lives on the Stats
# panel instead.
func _show_results() -> void:
	_clear_results_body()
	if _results_body == null:
		results_panel.visible = true
		return
	# Profit is what the day actually made once the fee and the wages taken at
	# start_day() are off it, so the headline figure is the honest one.
	var profit: float = revenue - PlayerData.last_area_fee - PlayerData.last_staff_wage
	# Rows are placed one after another at a known height and the card's height
	# is the running total of them. Nothing here measures a label.
	var y: float = RESULT_CARD_TOP_PAD
	_add_result_row(y, _result_line(AreaCatalog.get_area(PlayerData.current_area).name, RESULT_TEXT_COLOR, RESULT_HEADER_FONT), RESULT_HEADER_H)
	y += RESULT_HEADER_H
	_add_result_row(y, _result_line("Upfront Cost: Area Fee ($%.2f), Staff ($%.2f)" % [
		PlayerData.last_area_fee, PlayerData.last_staff_wage], RESULT_MUTED_COLOR, RESULT_FONT))
	y += RESULT_ROW_H
	_add_result_row(y, _result_line("Revenue: $%.2f" % revenue, RESULT_TEXT_COLOR, RESULT_FONT))
	y += RESULT_ROW_H
	_add_result_row(y, _result_line("Profit: $%.2f" % profit, RESULT_PROFIT_COLOR, RESULT_FONT_BIG))
	y += RESULT_ROW_H
	_add_result_row(y, _result_line("Losses: %d ice melted, %d lemons spoiled" % [
		PlayerData.last_ice_melted, PlayerData.last_lemons_spoiled], RESULT_LOSS_COLOR, RESULT_FONT))
	y += RESULT_ROW_H
	_add_result_row(y, _served_row())
	y += RESULT_ROW_H
	# One row per reason a customer walked away, read from the same SKIP_*
	# buckets the tally counts, so a row's icon, label and number can never
	# disagree. A reason nobody hit still shows, at zero.
	var skips: Dictionary = PlayerData.opinion_totals.get("skips", {})
	for entry in REJECT_ICONS:
		_add_result_row(y, _reject_row(str(entry[2]), str(entry[1]), int(skips.get(str(entry[0]), 0))))
		y += RESULT_ROW_H
	_add_result_row(y, _result_line("Recipe:", RESULT_TEXT_COLOR, RESULT_FONT))
	y += RESULT_ROW_H
	_add_result_row(y, _taste_row(), RESULT_ROW_H_TALL)
	y += RESULT_ROW_H_TALL
	_fit_results_card(y + RESULT_CARD_BOTTOM_PAD)
	results_panel.visible = true

# Adds one element to the card at an absolute y, inset equally from both sides,
# with an explicit rect. No container lays these out and nothing is measured,
# which is what keeps the card's height honest.
func _add_result_row(top: float, content: Control, height: float = RESULT_ROW_H) -> void:
	if _results_body == null or content == null:
		return
	content.anchor_left = 0.0
	content.anchor_right = 1.0
	content.anchor_top = 0.0
	content.anchor_bottom = 0.0
	content.offset_left = RESULT_CARD_MARGIN
	content.offset_right = -RESULT_CARD_MARGIN
	content.offset_top = top
	content.offset_bottom = top + height
	_results_body.add_child(content)

# Centres the card on a height that was worked out from the rows themselves.
func _fit_results_card(height: float) -> void:
	if _results_card == null:
		return
	_results_card.offset_top = -height * 0.5
	_results_card.offset_bottom = height * 0.5

# Clears the previous day's rows out of the column. The Finish Day button lives
# in the same column so it always sits under the last row, and it is tagged so
# this pass leaves it alone.
func _clear_results_body() -> void:
	if _results_body == null or not is_instance_valid(_results_body):
		return
	for child in _results_body.get_children():
		if child.has_meta("card_keeper"):
			continue
		_results_body.remove_child(child)
		child.queue_free()

# A plain, single-line label in the card. It never wraps and never expands: a
# wrapping Label reports its minimum size from whatever width it currently has,
# so a squeezed one collapses into a one-character-wide ribbon of text.
func _result_line(text: String, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

# "Customers Served: 20      Customers Rejected: 2" on one row: the two totals
# belong together, and a second full row would waste the width. Neither label
# expands or wraps, so the pair can never be squeezed into a vertical column.
func _served_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 24)
	var served: Label = _result_line("Customers Served: %d" % served_count, RESULT_TEXT_COLOR, RESULT_FONT)
	served.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(served)
	row.add_child(_result_line("Customers Rejected: %d" % rejected_count, RESULT_TEXT_COLOR, RESULT_FONT))
	return row

# "Waited Too Long [clock] : 1". The reason name sits in a fixed-width column so
# every count lines up under the one above it.
func _reject_row(name: String, icon_path: String, count: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	# The name sits in a fixed-width column so every count below it lines up.
	var name_label: Label = _result_line(name, RESULT_TEXT_COLOR, RESULT_FONT)
	name_label.custom_minimum_size = Vector2(RESULT_REASON_WIDTH, 0)
	row.add_child(name_label)
	var icon: TextureRect = _icon(icon_path, RESULT_ICON_SIZE)
	if icon != null:
		row.add_child(icon)
	row.add_child(_result_line(": %d" % count, RESULT_TEXT_COLOR, RESULT_FONT))
	return row

# Recipe verdicts as three columns: the count and the face on top, the word
# underneath. The same faces the badges over customers' heads use.
func _taste_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 0)
	var totals: Dictionary = PlayerData.opinion_totals
	for entry in TASTE_ICONS:
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_theme_constant_override("separation", 2)
		var top := HBoxContainer.new()
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.alignment = BoxContainer.ALIGNMENT_CENTER
		top.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		top.add_theme_constant_override("separation", 6)
		top.add_child(_result_line("%d" % int(totals.get(str(entry[0]), 0)), RESULT_TEXT_COLOR, RESULT_FONT_BIG))
		var icon: TextureRect = _icon(str(entry[1]), RESULT_ICON_SIZE)
		if icon != null:
			top.add_child(icon)
		column.add_child(top)
		var caption: Label = _result_line(str(entry[2]), RESULT_MUTED_COLOR, RESULT_FONT)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(caption)
		row.add_child(column)
	return row

# A square icon for a card row, aspect kept, or null if the art is missing.
func _icon(path: String, size: int) -> TextureRect:
	var texture: Texture2D = _reaction_texture(path)
	if texture == null:
		return null
	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(size, size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return icon

# Loads and caches one of the reaction icons for the results rows.
var _result_icon_cache: Dictionary = {}

func _reaction_texture(path: String) -> Texture2D:
	if _result_icon_cache.has(path):
		return _result_icon_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_result_icon_cache[path] = tex
	return tex

# The card builds one vertical list of its own and retires the old hand-placed
# text rows, so a stale saved scene still gets the full layout instead of a mix
# of the two. The column sits inside the card's Panel, inset to clear the title
# at the top and the Finish Day button at the bottom.
func _prepare_results_panel() -> void:
	# The card is drawn from scratch in _show_results(), so the scene's old title
	# and text rows are retired here instead of sitting above the new layout.
	var title: Label = get_node_or_null("HUD/ResultsPanel/TitleLabel")
	if title != null:
		title.visible = false
	for stale in [results_revenue, results_cups, results_served, results_rejected,
			results_spoilage, results_area, results_opinions, results_popularity]:
		if stale != null and is_instance_valid(stale):
			stale.visible = false
	# The whole overlay is taken over from code, so nothing about the layout
	# depends on what the saved scene happens to say: full-screen dim, one
	# centred card, one column of rows.
	results_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop: ColorRect = get_node_or_null("HUD/ResultsPanel/Backdrop")
	if backdrop != null:
		backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		backdrop.color = Color(0, 0, 0, 0.55)
	_results_card = get_node_or_null("HUD/ResultsPanel/Panel")
	if _results_card == null:
		return
	# Centre the card. Anchors are set rather than trusted, because the scene's
	# Panel uses a top-left layout mode, and its offsets then place the card
	# ABOVE the top of the screen instead of in the middle of it.
	_results_card.anchor_left = 0.5
	_results_card.anchor_top = 0.5
	_results_card.anchor_right = 0.5
	_results_card.anchor_bottom = 0.5
	_results_card.offset_left = -RESULT_CARD_WIDTH * 0.5
	_results_card.offset_right = RESULT_CARD_WIDTH * 0.5
	# A placeholder height until the first day ends and _fit_results_card() sets
	# the real one.
	_results_card.offset_top = -RESULT_ROW_H * 2.0
	_results_card.offset_bottom = RESULT_ROW_H * 2.0
	# Drop a body left over from an earlier load, so the card can never end up
	# with two sets of rows stacked on top of each other.
	var stale_body: Node = _results_card.get_node_or_null("Rows")
	if stale_body != null:
		_results_card.remove_child(stale_body)
		stale_body.queue_free()
	# A bare holder: every row is placed inside it at an absolute y, so nothing
	# here needs a container to lay out, and nothing is ever measured.
	_results_body = Control.new()
	_results_body.name = "Rows"
	_results_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_results_body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_results_card.add_child(_results_body)
	# The button is pinned to the card's own bottom edge, below the last row.
	var finish: Button = get_node_or_null("HUD/ResultsPanel/FinishDayButton")
	if finish != null:
		var old_parent: Node = finish.get_parent()
		if old_parent != null and old_parent != _results_card:
			old_parent.remove_child(finish)
			_results_card.add_child(finish)
		finish.set_meta("card_keeper", true)
		finish.anchor_left = 0.5
		finish.anchor_right = 0.5
		finish.anchor_top = 1.0
		finish.anchor_bottom = 1.0
		finish.offset_left = -110.0
		finish.offset_right = 110.0
		finish.offset_top = -66.0
		finish.offset_bottom = -16.0

func _on_finish_day_pressed() -> void:
	results_panel.visible = false
	day_finished.emit()

func _on_speed_button_pressed() -> void:
	toggle_fast_forward()

func toggle_fast_forward() -> void:
	set_fast_forward(not fast_forward)

func set_fast_forward(enabled: bool) -> void:
	fast_forward = enabled
	time_scale = fast_forward_scale if fast_forward else 1.0
	_update_speed_button()

func is_fast_forward() -> bool:
	return fast_forward

func _update_speed_button() -> void:
	var btn: Button = get_node_or_null("HUD/SpeedButton")
	if btn == null:
		return
	btn.visible = running
	btn.disabled = not running
	if fast_forward:
		btn.text = "Fast Forward ON"
	else:
		btn.text = "Fast Forward x%d" % int(fast_forward_scale)

func update_hud() -> void:
	if time_label == null:
		return
	time_label.text = "Day Time: %.1fs" % day_remaining
	revenue_label.text = "Revenue: $%.2f" % revenue
	if brewing:
		status_label.text = "Brewing... %.1fs" % brew_remaining
	elif PlayerData.ice_stock < PlayerData.recipe_ice:
		status_label.text = "Out of ice"
	elif cups_left > 0:
		status_label.text = "%d cups ready" % cups_left
	elif _can_brew():
		status_label.text = "Brewing..."
	else:
		status_label.text = "Out of stock"
	stock_label.text = "Stock L:%d/%d S:%d/%d I:%d/%d C:%d/%d" % [
		PlayerData.lemon_stock, PlayerData.capacity_for("lemon_stock"),
		PlayerData.sugar_stock, PlayerData.capacity_for("sugar_stock"),
		PlayerData.ice_stock, PlayerData.capacity_for("ice_stock"),
		PlayerData.cup_stock, PlayerData.capacity_for("cup_stock"),
	]
	_refresh_status_bar()

# --- Effective stats -----------------------------------------------------

# Folds PlayerData.upgrade_levels and today's weather into the day's numbers.
# Runs once at start_day(), so a purchase bought while shopping -- or a new
# day's weather -- applies from the next day onward.
func _apply_effective_stats() -> void:
	var levels: Dictionary = PlayerData.upgrade_levels
	eff_pitcher_capacity = UpgradeCatalog.effective_pitcher_capacity(float(pitcher_capacity), levels)
	eff_brew_time = UpgradeCatalog.effective_brew_time(brew_time, levels)
	eff_serve_time = UpgradeCatalog.effective_serve_time(serve_time, levels)
	eff_ice_per_day = Inventory.ice_per_day(levels)
	# The catalog describes a multiplier on the base interval; weather then
	# divides it (hot = shorter gap = more traffic, rain = longer gap).
	var interval_scale: float = UpgradeCatalog.stat_value("spawn_interval", 1.0, levels)
	# Area foot traffic multiplies demand, so the stadium stays busy on a quiet
	# day and the neighbourhood stays calm on a hot one. The area's price
	# multiplier goes to the crowd only: it raises the ceiling a customer will
	# pay, and never the price the cup actually sells for.
	eff_area_traffic = PlayerData.area_traffic() * PlayerData.popularity_traffic()
	if PlayerData.is_hired(StaffMember.STAFF_ID.advertiser):
		eff_area_traffic *= StaffCatalog.AD_TRAFFIC
	var news_item: NewsItem = NewsCatalog.get_item(PlayerData.current_news())
	if news_item.effects == NewsItem.EffectTarget.traffic \
			and NewsCatalog.applies_to_area(news_item.newsId, PlayerData.current_area):
		eff_area_traffic *= news_item.value
	eff_price_mult = PlayerData.area_price_multiplier() * PlayerData.popularity_price()
	var demand: float = Weather.demand_for(PlayerData.today_weather()) * eff_area_traffic
	if demand <= 0.0:
		demand = 1.0
	eff_spawn_min = maxf(min_spawn_interval, spawn_min_interval * interval_scale / demand)
	eff_spawn_max = clampf(spawn_max_interval * interval_scale / demand, eff_spawn_min, max_spawn_interval)

# --- Status bar ----------------------------------------------------------

# Always-on top strip: money, inventory, today's weather and tomorrow's
# forecast. Visible while shopping and while a day runs.
func _refresh_status_bar() -> void:
	if not is_inside_tree() or status_money_label == null:
		return
	PlayerData.ensure_weather_rolled()
	# The sign shows the player's name. This method already listens to
	# profile_updated, which is what a rename emits, so the board follows along.
	if sign_user_label != null:
		sign_user_label.text = PlayerData.username
	status_money_label.text = "Money: $%.2f" % PlayerData.money
	# One icon + number per ingredient, so the strip reads at a glance.
	# Count over capacity, so the strip shows both what is on the stand and how
	# much more will fit there.
	status_lemon_count.text = "%d/%d" % [PlayerData.lemon_stock, PlayerData.capacity_for("lemon_stock")]
	status_sugar_count.text = "%d/%d" % [PlayerData.sugar_stock, PlayerData.capacity_for("sugar_stock")]
	status_ice_count.text = "%d/%d" % [PlayerData.ice_stock, PlayerData.capacity_for("ice_stock")]
	status_cup_count.text = "%d/%d" % [PlayerData.cup_stock, PlayerData.capacity_for("cup_stock")]
	var today: Dictionary = PlayerData.today_weather()
	var tomorrow: Dictionary = PlayerData.next_forecast()
	_set_weather_icon(status_weather_icon, kind_for_weather(int(today["temp"]), bool(today["raining"])))
	_set_weather_icon(status_forecast_icon, kind_for_weather(int(tomorrow["temp"]), bool(tomorrow["raining"])))
	# Icon, day word and temperature only. The icon already says which sky it
	# is, so repeating "warm sunny" beside it just crowds the strip.
	status_weather_label.text = "Today %dF" % int(today["temp"])
	status_forecast_label.text = "Tomorrow %dF" % int(tomorrow["temp"])
	# The day bar only carries live numbers while a day is running.
	if top_bar != null:
		top_bar.visible = running

# Which icon suits a weather dictionary. Rain wins over temperature, and the
# mild middle band is plain sun.
static func kind_for_weather(temp: int, raining: bool) -> String:
	if raining:
		return "rain"
	if temp >= 90:
		return "hot"
	if temp <= 60:
		return "cold"
	return "sun"

# Swaps a status-bar weather icon onto the texture for its kind, skipping a
# reload when the icon is already showing the right art. Optional-safe: a stale
# scene without the node just goes without an icon.
func _set_weather_icon(node: TextureRect, icon_kind: String) -> void:
	if node == null or not is_instance_valid(node):
		return
	var texture: Texture2D = WEATHER_ICONS.get(icon_kind)
	if texture == null or node.texture == texture:
		return
	node.texture = texture
