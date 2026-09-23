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
const LEAVE_Z: float = -11.0

# How far in front of the Stand node's origin the first customer stands. The
# counter sits 1.45 m down the stand's local -Z and the awning posts sit at
# 1.9 m, so 2.2 puts the front of the line just outside the posts rather than
# inside the counter.
const QUEUE_FRONT_OFFSET: float = 2.2
# Only used if the Stand node cannot be found, so the sim still has a sane line.
const APPROACH_Z: float = -2.0

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
@onready var status_weather_icon: Control = $HUD/StatusBar/WeatherIcon
@onready var status_forecast_icon: Control = $HUD/StatusBar/ForecastIcon
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
	spawning = true
	day_remaining = day_length
	spawn_timer = 2.0
	revenue = 0.0
	cups_sold = 0
	served_count = 0
	rejected_count = 0
	reject_reasons = {}
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
	_update_queue_slots()
	_process_queue_front()
	update_hud()
	if day_remaining <= 0.0 and customers.is_empty() and serve_target == null:
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
	_queue_front = stand.global_position + facing * QUEUE_FRONT_OFFSET
	_queue_front.y = 0.0

# Direction a customer faces while waiting at or being served at the counter:
# straight back at the stand, whichever way it was turned.
func get_queue_facing() -> Vector3:
	return -_queue_dir

# Back of the line, where the next arrival stops before the queue takes over.
func get_line_end_point() -> Vector3:
	return _queue_front + _queue_dir * (float(queue.size()) * QUEUE_SPACING)

func get_line_end_z() -> float:
	return get_line_end_point().z

func on_customer_arrived(c) -> void:
	if cups_left == 0 and not brewing and not _can_brew():
		_reject_customer(c, "Out of stock!")
		return
	var line_len: int = queue.size() + (1 if serve_target != null else 0)
	if line_len > c.line_tolerance:
		_reject_customer(c, "Line too long!")
		return
	queue.append(c)
	c.enter_queue()

func on_customer_gave_up(c) -> void:
	queue.erase(c)
	_reject_customer(c, "Gotta go!")

func on_customer_finished(c) -> void:
	customers.erase(c)
	queue.erase(c)
	c.queue_free()

func _spawn_customer() -> void:
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

func _can_brew() -> bool:
	return PlayerData.lemon_stock >= PlayerData.recipe_lemons \
		and PlayerData.sugar_stock >= PlayerData.recipe_sugar \
		and PlayerData.ice_stock >= PlayerData.recipe_ice

func _try_start_brewing() -> void:
	if brewing:
		return
	if cups_left > 0:
		return
	if not _can_brew():
		return
	# consume_stock() refuses a partial spend and takes lemons from the crate
	# closest to going off first, so a stale crate is used before fresh fruit.
	# _can_brew() above already checked all three, so these are all-or-nothing.
	if not PlayerData.consume_stock("lemon_stock", PlayerData.recipe_lemons):
		return
	if not PlayerData.consume_stock("sugar_stock", PlayerData.recipe_sugar):
		return
	if not PlayerData.consume_stock("ice_stock", PlayerData.recipe_ice):
		return
	brewing = true
	brew_remaining = eff_brew_time

func _reject_customer(c, reason: String) -> void:
	rejected_count += 1
	if reject_reasons.has(reason):
		reject_reasons[reason] += 1
	else:
		reject_reasons[reason] = 1
	c.reject(reason)

func _update_queue_slots() -> void:
	for i in queue.size():
		# Slots step back from the counter along the stand's own facing, so a
		# turned stand drags the whole line with it.
		var slot: Vector3 = _queue_front + _queue_dir * (float(i) * QUEUE_SPACING)
		queue[i].queue_slot = slot.z
		queue[i].queue_slot_x = slot.x

func _process_queue_front() -> void:
	if queue.is_empty():
		return
	if serve_target != null:
		return
	if brewing:
		return
	if cups_left <= 0:
		if not _can_brew():
			var front = queue[0]
			queue.pop_front()
			_reject_customer(front, "Out of stock!")
		return
	var front = queue[0]
	queue.pop_front()
	serve_target = front
	serve_remaining = eff_serve_time
	front.begin_service()

func _finish_service() -> void:
	var c = serve_target
	serve_target = null
	serve_remaining = 0.0
	if c == null or not is_instance_valid(c):
		return
	if c.evaluate_purchase():
		cups_left -= 1
		cups_sold += 1
		# A cup always sells for exactly the price set in the recipe menu. The
		# area never inflates the till: it only decides which customers will
		# pay that price, through their own ceiling in evaluate_purchase().
		revenue += PlayerData.sale_price
		served_count += 1
		PlayerData.cup_stock = maxi(0, PlayerData.cup_stock - 1)
		c.buy()
		if cups_left <= 0:
			_try_start_brewing()
	else:
		_reject_customer(c, c.reason)

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
	# Operating fee for the area just worked, charged whether or not the day
	# went well. The neighbourhood is free; the city and the stadium rent the
	# pitch, and the stadium rents it dearly.
	var area_fee: float = PlayerData.area_daily_fee()
	PlayerData.last_area_fee = area_fee
	PlayerData.money -= area_fee
	# Pay out the part of a cube the day happened to end on, so a full played
	# day always yields the ice maker's whole output.
	_flush_ice_maker()
	# PlayerData owns the between-days bookkeeping: ice melts over night, lemon
	# crates age, and the day counter and the weather roll forward.
	PlayerData.resolve_day_end()
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
		results_area.text = "%s - fee $%.2f" % [PlayerData.current_area_name(), PlayerData.last_area_fee]
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
	eff_area_traffic = PlayerData.area_traffic()
	eff_price_mult = PlayerData.area_price_multiplier()
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
	_set_icon(status_weather_icon, UiIcon.kind_for_weather(int(today["temp"]), bool(today["raining"])))
	_set_icon(status_forecast_icon, UiIcon.kind_for_weather(int(tomorrow["temp"]), bool(tomorrow["raining"])))
	status_weather_label.text = "Today %s" % PlayerData.weather_label()
	status_forecast_label.text = "Tomorrow %s" % PlayerData.forecast_label()
	# The day bar only carries live numbers while a day is running.
	if top_bar != null:
		top_bar.visible = running

# Points a UiIcon node at a different drawing kind, skipping a redraw when the
# icon is already showing the right thing. get/set keeps this optional-safe if
# an icon node is ever missing from a stale scene.
func _set_icon(node: Control, icon_kind: String) -> void:
	if node == null or not is_instance_valid(node):
		return
	if str(node.get("kind")) == icon_kind:
		return
	node.set("kind", icon_kind)
