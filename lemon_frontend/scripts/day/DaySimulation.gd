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

const CustomerScene: PackedScene = preload("res://scripts/day/Customer.tscn")
const QUEUE_SPACING: float = 0.9
# How far apart the two window lines sit, left and right of the counter.
const QUEUE_LANE_GAP: float = 1.6
const LEAVE_Z: float = -11.0

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
# Optional: a stale scene without this row still runs, it just reports no losses.
@onready var results_spoilage: Label = get_node_or_null("HUD/ResultsPanel/ResultsSpoilage")
# Optional too: names the area worked and what its operating fee came to.
@onready var results_area: Label = get_node_or_null("HUD/ResultsPanel/ResultsArea")
@onready var results_opinions: Label = get_node_or_null("HUD/ResultsPanel/ResultsOpinions")
@onready var results_popularity: Label = get_node_or_null("HUD/ResultsPanel/ResultsPopularity")
@onready var news_banner: Label = get_node_or_null("HUD/NewsBanner")
@onready var crew: Node3D = get_node_or_null("Stand/Crew")
# The player's name, painted on the stand sign on the line above the LEMONADE
# word. Optional: a scene without the label still runs, it just shows no name.
@onready var sign_user_label: Label3D = get_node_or_null("Stand/SignUserLabel")

func _ready() -> void:
	results_panel.visible = false
	$HUD/ResultsPanel/FinishDayButton.pressed.connect(_on_finish_day_pressed)
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
	_apply_effective_stats()
	# A stadium day draws its own pair of kits: the two colours the crowd can be
	# wearing today, re-rolled every time the stand is set up there.
	if PlayerData.current_area_id() == AreaCatalog.STADIUM:
		PlayerData.roll_team_pair()
	_refresh_level()
	# Re-read the stand, so moving or turning it in the editor lands on the next
	# day rather than only after a scene reload.
	_refresh_queue_anchor()
	_try_start_brewing()
	update_hud()
	_update_speed_button()
	_refresh_status_bar()

func _process(_delta: float) -> void:
	if not running:
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
	if serve_target != null:
		serve_remaining -= delta
		if serve_remaining <= 0.0:
			_finish_service()
	if serve_target_b != null:
		serve_remaining_b -= delta
		if serve_remaining_b <= 0.0:
			_finish_service_b()
	_update_queue_slots()
	_process_queue_front()
	update_hud()
	if day_remaining <= 0.0 and customers.is_empty() and serve_target == null and serve_target_b == null:
		_end_day()

# --- Area scenery ---------------------------------------------------------

# Instances the current area's level scene under LevelHolder, replacing whatever
# is already there. Called at boot and at the start of every day, so moving the
# stand to another area lands before the first customer walks in.
func _refresh_level() -> void:
	if level_holder == null or not is_instance_valid(level_holder):
		return
	var scene_path: String = AreaCatalog.level_scene_for(PlayerData.current_area_id())
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

# Moving the stand lands immediately, even mid-shop: the scenery swaps under the
# HUD so the player can see where they just set up. The day's numbers and the
# fee are read at start_day() and _end_day(), so they pick it up on their own.
func _on_area_changed(_area_id: String) -> void:
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
	var center: Vector3 = stand.global_position + facing * QUEUE_FRONT_OFFSET
	center.y = 0.0
	# Two starts, side by side in front of the counter. One line still uses
	# the left start; a hired server opens the right start beside it.
	_queue_front = center - side * (QUEUE_LANE_GAP * 0.5)
	_queue_front_b = center + side * (QUEUE_LANE_GAP * 0.5)

# Direction a customer faces while waiting at or being served at the counter:
# straight back at the stand, whichever way it was turned.
func get_queue_facing() -> Vector3:
	return -_queue_dir

# Back of the line, where the next arrival stops before the queue takes over.
func get_line_end_point() -> Vector3:
	return _queue_front + _queue_dir * (float(queue.size()) * QUEUE_SPACING)

func _server_hired() -> bool:
	return PlayerData.is_hired(StaffMember.STAFF_ID.server)

func get_line_end_point_b() -> Vector3:
	return _queue_front_b + _queue_dir * (float(queue_b.size()) * QUEUE_SPACING)

func get_line_end_z() -> float:
	return get_line_end_point().z

# Whether one cup could actually be handed over right now: the ice the recipe
# puts in a cup, plus either a cup already poured or a batch that can still be
# brewed. Ice is charged per cup, so a dry tray is a hard stop even with cups
# ready to pour.
func _can_serve_a_cup() -> bool:
	if PlayerData.ice_stock < PlayerData.recipe_ice:
		return false
	if cups_left > 0:
		return true
	return brewing or _can_brew()

func on_customer_arrived(c) -> void:
	# Nobody joins the line when not even one cup could be served.
	if not _can_serve_a_cup():
		_reject_customer(c, "Out of stock!")
		return
	var use_b: bool = _server_hired() and _line_length(queue_b, serve_target_b) < _line_length(queue, serve_target)
	var line: Array = queue_b if use_b else queue
	var serving = serve_target_b if use_b else serve_target
	var line_len: int = _line_length(line, serving)
	if line_len > c.line_tolerance:
		_reject_customer(c, "Line too long!")
		return
	line.append(c)
	c.enter_queue()
	c.queue_lane = 1 if use_b else 0

func on_customer_gave_up(c) -> void:
	queue.erase(c)
	queue_b.erase(c)
	_reject_customer(c, "Gotta go!")

func _line_length(line: Array, serving) -> int:
	return line.size() + (1 if serving != null else 0)

func on_customer_finished(c) -> void:
	customers.erase(c)
	queue.erase(c)
	queue_b.erase(c)
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
	# _ready() rolls ideal_ice with the bias baked in.
	c.spawn(self, PlayerData.today_weather(), route)
	add_child(c)
	customers.append(c)

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

func _reject_customer(c, reason: String) -> void:
	rejected_count += 1
	if reject_reasons.has(reason):
		reject_reasons[reason] += 1
	else:
		reject_reasons[reason] = 1
	PlayerData.note_customer_skip(reason)
	c.reject(reason)

func _update_queue_slots() -> void:
	_write_slots(queue, _queue_front)
	_write_slots(queue_b, _queue_front_b)

func _write_slots(line: Array, front: Vector3) -> void:
	for i in line.size():
		var slot: Vector3 = front + _queue_dir * (float(i) * QUEUE_SPACING)
		slot.y = 0.0
		line[i].queue_slot_pos = slot
		line[i].queue_slot = slot.z
		line[i].queue_slot_x = slot.x

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
		if not _can_brew():
			var waiting = line[0]
			line.pop_front()
			_reject_customer(waiting, "Out of stock!")
		return
	var front = line[0]
	line.pop_front()
	if second:
		serve_target_b = front
		serve_remaining_b = eff_serve_time
	else:
		serve_target = front
		serve_remaining = eff_serve_time
	front.begin_service()

func _finish_service() -> void:
	var c = serve_target
	serve_target = null
	serve_remaining = 0.0
	if c == null or not is_instance_valid(c):
		return
	_resolve_sale(c)

func _finish_service_b() -> void:
	var c = serve_target_b
	serve_target_b = null
	serve_remaining_b = 0.0
	_resolve_sale(c)

func _resolve_sale(c) -> void:
	if c == null or not is_instance_valid(c):
		return
	# Ice is a per-cup cost: the recipe's ice count is what one cup holds, so a
	# tray that cannot fill the cup turns the customer away like an empty rack.
	if PlayerData.ice_stock < PlayerData.recipe_ice:
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
		# tally and what the customer says about it, so the bubble on screen and
		# the points behind it can never disagree. Nobody tastes before they
		# buy, so a recipe that misses the ideal costs popularity here instead
		# of costing the sale.
		var opinion: Dictionary = c.score_recipe()
		_record_opinion(opinion)
		c.buy(c.taste_reaction(opinion))
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
	if PlayerData.note_popularity_points(earned):
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
	GameNet.sync_user_data()
	_show_results()
	_refresh_status_bar()

func _show_results() -> void:
	results_revenue.text = "Revenue: $%.2f" % revenue
	results_cups.text = "Cups Sold: %d" % cups_sold
	results_served.text = "Customers Served: %d" % served_count
	results_rejected.text = "Customers Rejected: %d" % rejected_count
	# What the night cost, so melting and spoiling are visible on the summary
	# instead of silently shaving the stock down.
	if results_spoilage != null:
		results_spoilage.text = "Losses: %d ice melted, %d lemons spoiled" % [
			PlayerData.last_ice_melted, PlayerData.last_lemons_spoiled]
	# Which area was worked and what the pitch cost, so the fee is never a
	# silent deduction from the money total.
	if results_area != null:
		results_area.text = "%s - paid up front: $%.2f fee, $%.2f wages" % [
			PlayerData.current_area_name(), PlayerData.last_area_fee, PlayerData.last_staff_wage]
	if results_opinions != null:
		var lines: PackedStringArray = RecipeOpinion.summary_lines(PlayerData.opinion_totals)
		results_opinions.text = "\n".join(lines)
	if results_popularity != null:
		results_popularity.text = "Popularity %d (%d/%d pts) - %d loved, %d neutral today" % [
			PlayerData.popularity_level(), PlayerData.popularity_points(),
			PlayerData.popularity_goal(), loved_count, neutral_count]
	results_panel.visible = true

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
	var news_item: Dictionary = PlayerData.current_news()
	if NewsCatalog.effect_of(news_item) == NewsCatalog.EFFECTS_TRAFFIC \
			and NewsCatalog.applies_to_area(news_item, PlayerData.current_area_id()):
		eff_area_traffic *= NewsCatalog.value_of(news_item)
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
