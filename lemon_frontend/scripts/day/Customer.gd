extends Node3D
class_name Customer

# One person in the day sim. The same model serves three jobs:
#   - a customer: walks in, joins a lane, is served at the counter, walks off
#   - a passer-by (PASSBY): walks a through-path and never comes to the stand
#   - a puppet (PUPPET): driven by another script, e.g. the hired advertiser
#
# Movement is steered: DaySimulation._crowd_step() hands every walker a small
# avoidance vector and a speed factor each frame, so people step round each
# other and slow down behind someone instead of walking through them. People
# standing in a lane or at the counter are on rails and only act as obstacles.

enum State { SPAWN, WALK_TO_STAND, WAIT_IN_QUEUE, COUNTER, LEAVE, PASSBY, PUPPET }

const APPROACH_Z: float = -2.0

# The model's face sits on its local -Z side, so a rotation of PI is what
# points the face toward +Z.
const MODEL_FORWARD_YAW: float = PI
const TURN_SPEED: float = 9.0

# How close counts as "arrived" at a waypoint. Steered walkers use the wider
# radius: they are nudged off the exact line and would otherwise circle a
# corner they can never quite touch.
const WAYPOINT_EPSILON: float = 0.15
const STEERED_EPSILON: float = 0.5
# Farther than this from their lane slot, a queued customer is still walking up
# to join and is steered round the people already standing in line. Closer, it
# is shuffling along its own lane on rails.
const JOIN_STEER_DIST: float = 0.9
const COUNTER_EPSILON: float = 0.06
# How far a customer must walk away from the spot they started leaving from
# before their reaction badge appears. People sip as they stroll off, so the
# badge belongs out on the pavement rather than over the counter.
const REACTION_WALK_DIST: float = 1.5

# Taste spread around the area's base recipe, per ingredient: most of the crowd
# wants the base exactly, a third want one more or one less, and a rare few are
# two off. A player who finds the base recipe is loved by nearly everyone.
const IDEAL_EXACT_CHANCE: float = 0.6
const IDEAL_ONE_OFF_CHANCE: float = 0.35

# Outfit palettes. Shirt colour is rolled in HSV instead of being drawn from a
# list, so the crowd stays varied no matter how many customers spawn.
const SKIN_TONES: Array = [
	Color(0.99, 0.86, 0.73), Color(0.93, 0.77, 0.61), Color(0.80, 0.62, 0.45),
	Color(0.62, 0.44, 0.32), Color(0.45, 0.31, 0.22),
]
const HAIR_COLORS: Array = [
	Color(0.15, 0.11, 0.09), Color(0.36, 0.22, 0.13), Color(0.62, 0.44, 0.22),
	Color(0.87, 0.74, 0.44), Color(0.56, 0.20, 0.12), Color(0.32, 0.32, 0.36),
]
const PANTS_COLORS: Array = [
	Color(0.22, 0.27, 0.4), Color(0.35, 0.24, 0.17), Color(0.5, 0.5, 0.53),
	Color(0.25, 0.34, 0.28), Color(0.62, 0.5, 0.34), Color(0.4, 0.2, 0.24),
]
const SHOE_COLORS: Array = [
	Color(0.18, 0.16, 0.16), Color(0.42, 0.26, 0.16), Color(0.86, 0.86, 0.82),
	Color(0.55, 0.14, 0.14), Color(0.2, 0.3, 0.5),
]
const HAT_COLORS: Array = [
	Color(0.86, 0.3, 0.24), Color(0.25, 0.45, 0.7), Color(0.95, 0.86, 0.55),
	Color(0.35, 0.6, 0.35), Color(0.9, 0.9, 0.88), Color(0.5, 0.35, 0.6),
]

# Area wardrobe palettes. Suits stay deliberately sober so the tie and the bag
# carry the colour, and the office crowd still reads as individuals.
const SUIT_COLORS: Array = [
	Color(0.16, 0.18, 0.24), Color(0.22, 0.22, 0.26), Color(0.30, 0.25, 0.22),
	Color(0.14, 0.16, 0.20), Color(0.27, 0.27, 0.32),
]
const TIE_COLORS: Array = [
	Color(0.72, 0.14, 0.18), Color(0.16, 0.32, 0.62), Color(0.85, 0.72, 0.20),
	Color(0.20, 0.45, 0.30), Color(0.55, 0.20, 0.55), Color(0.90, 0.90, 0.88),
]
const BRIEFCASE_COLORS: Array = [
	Color(0.30, 0.20, 0.14), Color(0.16, 0.14, 0.16), Color(0.38, 0.27, 0.18),
]

# Wardrobe shape choices. Hats have seven outcomes (one of them bare-headed),
# bottoms three cuts, and about half the crowd carries one accessory.
enum Hat { NONE, CAP_FORWARD, CAP_BACKWARD, SUN, BUCKET, BEANIE, HEADBAND }
enum Bottom { PANTS, SKIRT, SHORTS }
enum Extra { NONE, GLASSES, BACKPACK, APRON, BOW }

var sim
var state: State = State.SPAWN
# Set before add_child() to make this a passer-by or a puppet.
var puppet: bool = false

var ideal_lemons: int = 4
var ideal_sugar: int = 4
var ideal_ice: int = 4
# Weather shift applied to ideal_ice (hot days want a little more ice).
var ice_bias: int = 0
var max_price: float = 1.25
var line_tolerance: int = 3
var patience: float = 15.0
# Slot in the lane, written by the sim every frame.
var queue_slot_pos: Vector3 = Vector3(0.0, 0.0, APPROACH_Z)
# Spot at the counter window, written by the sim when service begins.
var counter_pos: Vector3 = Vector3(0.0, 0.0, APPROACH_Z)
var at_counter: bool = false
# Set by the sim while this customer has been called up to the window.
var at_window: bool = false
# 0 is the keeper's lane, 1 is the hired server's lane.
var queue_lane: int = 0
var reason: String = ""
var walk_speed: float = 1.4

# Crowd steering, written by DaySimulation._crowd_step() each frame.
var steer: Vector3 = Vector3.ZERO
var speed_factor: float = 1.0
# Unit direction of travel this frame, read back by the steering pass.
var travel_dir: Vector3 = Vector3.ZERO

# Arrival route (minus the final stand point), the leave route, or a
# passer-by's through-path, with the index of the next point.
var _waypoints: PackedVector3Array = PackedVector3Array()
var _waypoint_index: int = 0
var _leave_points: PackedVector3Array = PackedVector3Array()
var _leave_index: int = 0
# Where this customer's walk out began, and the badge waiting to appear once
# they are clear of it.
var _leave_start: Vector3 = Vector3.ZERO
var _pending_reaction: String = ""
var _bob_phase: float = 0.0
var _facing_yaw: float = MODEL_FORWARD_YAW

@onready var visuals: Node3D = $Visuals
@onready var body_mesh: MeshInstance3D = $Visuals/Body
@onready var pants_mesh: MeshInstance3D = $Visuals/Pants
@onready var shoe_left: MeshInstance3D = $Visuals/ShoeLeft
@onready var shoe_right: MeshInstance3D = $Visuals/ShoeRight
@onready var head_mesh: MeshInstance3D = $Visuals/Head
@onready var arm_left: MeshInstance3D = $Visuals/ArmLeft
@onready var arm_right: MeshInstance3D = $Visuals/ArmRight
@onready var hair_mesh: MeshInstance3D = $Visuals/HairCap
@onready var skirt: MeshInstance3D = $Visuals/Skirt
@onready var apron: MeshInstance3D = $Visuals/Apron
@onready var backpack: MeshInstance3D = $Visuals/Backpack
@onready var glasses: Node3D = $Visuals/Glasses
@onready var lens_left: MeshInstance3D = $Visuals/Glasses/LensLeft
@onready var lens_right: MeshInstance3D = $Visuals/Glasses/LensRight
@onready var bow: MeshInstance3D = $Visuals/Bow
# Area-only pieces: office wear for downtown, a jersey front for match day.
@onready var tie: MeshInstance3D = $Visuals/Tie
@onready var briefcase: MeshInstance3D = $Visuals/Briefcase
@onready var jersey_panel: MeshInstance3D = $Visuals/JerseyPanel
@onready var hat: Node3D = $Visuals/Hat
@onready var hat_brim: MeshInstance3D = $Visuals/Hat/Brim
@onready var hat_crown: MeshInstance3D = $Visuals/Hat/Crown
@onready var hat_sun_brim: MeshInstance3D = $Visuals/Hat/SunBrim
@onready var hat_bucket_crown: MeshInstance3D = $Visuals/Hat/BucketCrown
@onready var hat_bucket_brim: MeshInstance3D = $Visuals/Hat/BucketBrim
@onready var hat_beanie: MeshInstance3D = $Visuals/Hat/Beanie
@onready var hat_headband: MeshInstance3D = $Visuals/Hat/Headband

# Called by DaySimulation BEFORE the customer enters the tree, so today's
# weather is already known when _ready() rolls the recipe ideals. The route's
# last point is the front of the line; it is dropped, because walking to the
# front and then back down the line to a slot is what used to march arrivals
# straight through the people already queueing. The sim picks a lane and the
# customer walks to the back of it instead.
func spawn(sim_ref, weather_ref, route_points: PackedVector3Array = PackedVector3Array()) -> void:
	sim = sim_ref
	_waypoints = route_points.duplicate()
	if _waypoints.size() > 1 and sim != null and is_instance_valid(sim):
		var front: Vector3 = sim.queue_center()
		var last: Vector3 = _waypoints[_waypoints.size() - 1]
		if Vector2(last.x - front.x, last.z - front.z).length() < 1.2:
			_waypoints.remove_at(_waypoints.size() - 1)
	_waypoint_index = 0
	ice_bias = _ice_bias_for(weather_ref)

# A passer-by: walks the path from start_index onward, then the sim frees it.
func spawn_passerby(sim_ref, path: PackedVector3Array, start_index: int = 0) -> void:
	sim = sim_ref
	puppet = false
	_waypoints = path
	_waypoint_index = clampi(start_index, 0, maxi(0, path.size() - 1))
	state = State.PASSBY

func _ice_bias_for(weather_ref) -> int:
	if typeof(weather_ref) == TYPE_DICTIONARY:
		return Weather.ice_bias_for(weather_ref)
	return 0

func _ready() -> void:
	_randomize_outfit()
	walk_speed = randf_range(1.15, 1.55)
	if puppet:
		state = State.PUPPET
		return
	if state == State.PASSBY:
		_face_toward_next(true)
		return
	_roll_ideals()
	_apply_news_to_ideals()
	# Price ceiling scales with the area, today's headline, and how well known
	# the stand is here. The till still charges the recipe price.
	max_price = randf_range(0.75, 2.5) * _area_price_mult() * _news_price_mult() * PlayerData.popularity_price()
	line_tolerance = randi_range(1, 5) + PlayerData.popularity_line() + _news_line_bonus()
	patience = randf_range(8.0, 25.0) * PlayerData.popularity_patience() * _news_patience_mult()
	_face_toward_next(true)

# The area's crowd shares one base recipe; each customer is a tight roll
# around it, then the weather nudges the ice and the headline nudges the rest.
func _roll_ideals() -> void:
	var area: MapArea = AreaCatalog.get_area(PlayerData.current_area)
	var base_l: int = 4
	var base_s: int = 4
	var base_i: int = 4
	if area != null:
		base_l = area.base_lemons
		base_s = area.base_sugar
		base_i = area.base_ice
	ideal_lemons = maxi(0, base_l + roll_offset())
	ideal_sugar = maxi(0, base_s + roll_offset())
	ideal_ice = maxi(0, base_i + roll_offset() + ice_bias)

static func roll_offset() -> int:
	var r: float = randf()
	if r < IDEAL_EXACT_CHANCE:
		return 0
	var magnitude: int = 1 if r < IDEAL_EXACT_CHANCE + IDEAL_ONE_OFF_CHANCE else 2
	return magnitude if randf() < 0.5 else -magnitude

# --- Outfit ---------------------------------------------------------------

func _randomize_outfit() -> void:
	var skin: Color = SKIN_TONES[randi() % SKIN_TONES.size()]
	var hair: Color = HAIR_COLORS[randi() % HAIR_COLORS.size()]
	var shirt: Color = Color.from_hsv(randf(), randf_range(0.35, 0.75), randf_range(0.75, 0.98))
	# Reset the area-only pieces first, so a reused instance can never keep the
	# wardrobe it was wearing somewhere else.
	tie.visible = false
	briefcase.visible = false
	jersey_panel.visible = false
	_tint(body_mesh, shirt)
	_tint(head_mesh, skin)
	_tint(arm_left, skin)
	_tint(arm_right, skin)
	_tint(hair_mesh, hair)
	_randomize_bottom(skin)
	var shoe: Color = SHOE_COLORS[randi() % SHOE_COLORS.size()]
	_tint(shoe_left, shoe)
	_tint(shoe_right, shoe)
	_randomize_hat()
	_randomize_extra()
	# Then let the area dress whoever it wants to over the top. The
	# neighbourhood leaves the mixed crowd above exactly as it was. A puppet is
	# staff, so it keeps the plain outfit its owner gives it.
	if puppet:
		return
	match PlayerData.area_attire():
		MapArea.Attire.City:
			_dress_city()
		MapArea.Attire.Stadium:
			_dress_stadium()

# --- Bottoms --------------------------------------------------------------

func _randomize_bottom(skin: Color) -> void:
	skirt.visible = false
	pants_mesh.scale = Vector3.ONE
	match _roll_bottom():
		Bottom.SKIRT:
			_tint(pants_mesh, skin)
			_tint(skirt, Color.from_hsv(randf(), randf_range(0.3, 0.8), randf_range(0.55, 0.95)))
			skirt.visible = true
		Bottom.SHORTS:
			_tint(pants_mesh, skin)
			pants_mesh.scale = Vector3(1.0, 0.62, 1.0)
		_:
			_tint(pants_mesh, PANTS_COLORS[randi() % PANTS_COLORS.size()])

func _roll_bottom() -> int:
	var roll: float = randf()
	if roll < 0.55:
		return Bottom.PANTS
	if roll < 0.85:
		return Bottom.SKIRT
	return Bottom.SHORTS

# --- Hat ------------------------------------------------------------------

func _randomize_hat() -> void:
	hat.visible = false
	hat_brim.visible = false
	hat_crown.visible = false
	hat_sun_brim.visible = false
	hat_bucket_crown.visible = false
	hat_bucket_brim.visible = false
	hat_beanie.visible = false
	hat_headband.visible = false
	hat_brim.scale = Vector3.ONE
	hat_brim.position = Vector3(0.0, 1.44, 0.0)
	hat_brim.rotation.y = 0.0
	var style: int = _roll_hat()
	if style == Hat.NONE:
		return
	hat.visible = true
	var hat_color: Color = HAT_COLORS[randi() % HAT_COLORS.size()]
	match style:
		Hat.CAP_FORWARD:
			hat_brim.visible = true
			hat_crown.visible = true
			hat_brim.scale = Vector3(0.72, 1.0, 0.72)
		Hat.CAP_BACKWARD:
			hat_brim.visible = true
			hat_crown.visible = true
			hat_brim.scale = Vector3(0.72, 1.0, 0.72)
			hat_brim.position.z = 0.19
			hat_brim.rotation.y = PI
		Hat.SUN:
			hat_sun_brim.visible = true
			hat_crown.visible = true
		Hat.BUCKET:
			hat_bucket_crown.visible = true
			hat_bucket_brim.visible = true
		Hat.BEANIE:
			hat_beanie.visible = true
		Hat.HEADBAND:
			hat_headband.visible = true
	_tint(hat_crown, hat_color)
	_tint(hat_brim, hat_color)
	_tint(hat_sun_brim, hat_color)
	_tint(hat_bucket_crown, hat_color)
	_tint(hat_bucket_brim, hat_color)
	_tint(hat_beanie, hat_color)
	_tint(hat_headband, hat_color)

func _roll_hat() -> int:
	var roll: float = randf()
	if roll < 0.28:
		return Hat.NONE
	if roll < 0.48:
		return Hat.CAP_FORWARD
	if roll < 0.60:
		return Hat.CAP_BACKWARD
	if roll < 0.72:
		return Hat.SUN
	if roll < 0.84:
		return Hat.BUCKET
	if roll < 0.93:
		return Hat.BEANIE
	return Hat.HEADBAND

# --- Accessories ----------------------------------------------------------

func _randomize_extra() -> void:
	glasses.visible = false
	backpack.visible = false
	apron.visible = false
	bow.visible = false
	match _roll_extra():
		Extra.GLASSES:
			_tint(lens_left, Color(0.1, 0.1, 0.12))
			_tint(lens_right, Color(0.1, 0.1, 0.12))
			glasses.visible = true
		Extra.BACKPACK:
			_tint(backpack, Color.from_hsv(randf(), randf_range(0.4, 0.85), randf_range(0.4, 0.8)))
			backpack.visible = true
		Extra.APRON:
			_tint(apron, Color.from_hsv(randf(), 0.12, randf_range(0.85, 0.99)))
			apron.visible = true
		Extra.BOW:
			_tint(bow, Color.from_hsv(randf(), randf_range(0.5, 0.9), randf_range(0.6, 0.95)))
			bow.visible = true

func _roll_extra() -> int:
	var roll: float = randf()
	if roll < 0.5:
		return Extra.NONE
	if roll < 0.65:
		return Extra.GLASSES
	if roll < 0.78:
		return Extra.BACKPACK
	if roll < 0.9:
		return Extra.APRON
	return Extra.BOW

# --- Area wardrobe --------------------------------------------------------

func _area_price_mult() -> float:
	if sim != null and is_instance_valid(sim):
		return maxf(0.1, sim.eff_price_mult)
	return 1.0

func _dress_city() -> void:
	if randf() > 0.5:
		return
	var jacket: Color = SUIT_COLORS[randi() % SUIT_COLORS.size()]
	_tint(body_mesh, jacket)
	_tint(pants_mesh, jacket)
	_tint(arm_left, jacket)
	_tint(arm_right, jacket)
	skirt.visible = false
	pants_mesh.scale = Vector3.ONE
	var dress_shoe: Color = Color(0.12, 0.11, 0.13)
	_tint(shoe_left, dress_shoe)
	_tint(shoe_right, dress_shoe)
	_tint(tie, TIE_COLORS[randi() % TIE_COLORS.size()])
	tie.visible = true
	if randf() < 0.7:
		backpack.visible = false
		_tint(briefcase, BRIEFCASE_COLORS[randi() % BRIEFCASE_COLORS.size()])
		briefcase.visible = true

func _dress_stadium() -> void:
	if randf() > 0.8:
		return
	var themes: Array[Dictionary] = AreaCatalog.get_team_theme()
	var theme: Dictionary = themes[randi() % themes.size()]
	var primary: Color = theme.get("primary", Color(0.8, 0.8, 0.8))
	var secondary: Color = theme.get("secondary", Color(0.15, 0.15, 0.15))
	_tint(body_mesh, primary)
	_tint(pants_mesh, primary.darkened(0.25))
	_tint(arm_left, primary)
	_tint(arm_right, primary)
	skirt.visible = false
	pants_mesh.scale = Vector3.ONE
	_tint(jersey_panel, secondary)
	jersey_panel.visible = true
	if randf() < 0.55:
		hat.visible = true
		hat_brim.visible = true
		hat_crown.visible = true
		hat_brim.scale = Vector3(0.72, 1.0, 0.72)
		hat_brim.position = Vector3(0.0, 1.44, 0.0)
		hat_brim.rotation.y = 0.0
		_tint(hat_crown, primary)
		_tint(hat_brim, secondary)

func _tint(node: MeshInstance3D, color: Color) -> void:
	if node == null:
		return
	var mat: StandardMaterial3D = node.material_override.duplicate()
	mat.albedo_color = color
	node.material_override = mat

# Recolours the shirt and trousers, for staff that wear a uniform.
func set_uniform(shirt: Color, trousers: Color) -> void:
	_tint(body_mesh, shirt)
	_tint(pants_mesh, trousers)
	pants_mesh.scale = Vector3.ONE
	skirt.visible = false

# --- Movement -------------------------------------------------------------

func _process(_delta: float) -> void:
	var delta: float = _delta * _sim_time_scale()
	match state:
		State.SPAWN:
			state = State.WALK_TO_STAND
		State.WALK_TO_STAND:
			_bob(delta, true)
			if _walk_list(_waypoints, delta, true):
				# Set the state before notifying the sim: an arrival rejection
				# flips this customer straight to LEAVE.
				state = State.WAIT_IN_QUEUE
				if sim != null:
					sim.on_customer_arrived(self)
		State.WAIT_IN_QUEUE:
			if at_window:
				# Called up to the window: step onto the counter spot, then hold
				# there facing the stand and wait to be served. The sim only
				# calls the head of the line up once the window is clear, so
				# nobody walks into the customer still being served.
				if not at_counter:
					_bob(delta, true)
					if _step_toward(counter_pos, delta, false, COUNTER_EPSILON):
						at_counter = true
				else:
					_bob(delta, false)
					travel_dir = Vector3.ZERO
					_face_travel(_counter_facing(), delta)
			else:
				# Still in line: walk to this customer's slot in the lane. While
				# the slot is far away the walk is steered, so it goes round the
				# people already standing there instead of through them.
				var to_slot := Vector3(queue_slot_pos.x - position.x, 0.0, queue_slot_pos.z - position.z)
				var slot_dist: float = to_slot.length()
				if slot_dist > JOIN_STEER_DIST:
					_bob(delta, true)
					_step_toward(queue_slot_pos, delta, true, WAYPOINT_EPSILON)
				elif slot_dist > 0.0005:
					_bob(delta, true)
					_step_toward(queue_slot_pos, delta, false, 0.0005)
				else:
					_bob(delta, false)
					travel_dir = Vector3.ZERO
					_face_travel(_counter_facing(), delta)
			patience -= delta
			if patience <= 0.0 and sim != null:
				sim.on_customer_gave_up(self)
		State.COUNTER:
			if not at_counter:
				_bob(delta, true)
				if _step_toward(counter_pos, delta, false, COUNTER_EPSILON):
					at_counter = true
			else:
				_bob(delta, false)
				travel_dir = Vector3.ZERO
				_face_travel(_counter_facing(), delta)
		State.LEAVE:
			_bob(delta, true)
			# Badges appear out here, once they are walking off: not while they
			# are still standing at the stand.
			_update_pending_reaction()
			if _walk_list(_leave_points, delta, true):
				if sim != null:
					sim.on_customer_finished(self)
				else:
					queue_free()
		State.PASSBY:
			_bob(delta, true)
			if _walk_list(_waypoints, delta, true):
				if sim != null:
					sim.on_passerby_done(self)
				else:
					queue_free()
		State.PUPPET:
			pass

# Walks the active list (arrival route, leave route or through-path). Returns
# true once the last point is reached.
func _walk_list(points: PackedVector3Array, delta: float, steered: bool) -> bool:
	var index: int = _leave_index if state == State.LEAVE else _waypoint_index
	if index >= points.size():
		return true
	var last: bool = index == points.size() - 1
	var eps: float = WAYPOINT_EPSILON if (last or not steered) else STEERED_EPSILON
	if _step_toward(points[index], delta, steered, eps):
		index += 1
	if state == State.LEAVE:
		_leave_index = index
	else:
		_waypoint_index = index
	return index >= points.size()

# One step toward target. Steered walkers blend in the crowd-avoidance vector
# and slow down behind whoever is in the way; on-rails walkers go straight.
# Returns true when the target is reached.
func _step_toward(target: Vector3, delta: float, steered: bool, epsilon: float) -> bool:
	var to := Vector3(target.x - position.x, 0.0, target.z - position.z)
	var dist: float = to.length()
	var speed: float = walk_speed * (speed_factor if steered else 1.0)
	var step: float = speed * delta
	if dist <= maxf(epsilon, 0.0001) or (not steered and dist <= step):
		if not steered:
			position.x = target.x
			position.z = target.z
		return true
	var dir: Vector3 = to / dist
	if steered and steer.length_squared() > 0.000001:
		var mixed: Vector3 = dir + steer
		if mixed.length_squared() > 0.000001:
			dir = mixed.normalized()
	travel_dir = dir
	_face_travel(dir, delta)
	position.x += dir.x * step
	position.z += dir.z * step
	return false

# True while this person picks a way through the crowd. Anyone standing in a
# lane slot or at the counter holds position and is only an obstacle.
func is_steered() -> bool:
	match state:
		State.WALK_TO_STAND, State.LEAVE, State.PASSBY:
			return true
		State.WAIT_IN_QUEUE:
			return position.distance_to(queue_slot_pos) > JOIN_STEER_DIST
	return false

func _face_toward_next(instant: bool) -> void:
	if _waypoint_index >= _waypoints.size():
		return
	var target: Vector3 = _waypoints[_waypoint_index]
	var travel := Vector3(target.x - position.x, 0.0, target.z - position.z)
	if travel.length_squared() < 0.0001:
		return
	_facing_yaw = atan2(-travel.x, -travel.z)
	if instant:
		rotation.y = _facing_yaw

# Turns the model toward the direction it is travelling. The face sits on the
# model's local -Z side, so the yaw for a travel direction d is atan2(-d.x, -d.z).
func _face_travel(travel: Vector3, delta: float) -> void:
	if absf(travel.x) < 0.0001 and absf(travel.z) < 0.0001:
		return
	var target: float = atan2(-travel.x, -travel.z)
	_facing_yaw = lerp_angle(_facing_yaw, target, clampf(delta * TURN_SPEED, 0.0, 1.0))
	rotation.y = _facing_yaw

func _counter_facing() -> Vector3:
	if sim != null and is_instance_valid(sim):
		return sim.get_queue_facing()
	return Vector3(0.0, 0.0, 1.0)

func _sim_time_scale() -> float:
	if sim != null and is_instance_valid(sim):
		return sim.time_scale
	return 1.0

func _bob(delta: float, walking: bool) -> void:
	_bob_phase += delta * 7.0
	if not walking:
		visuals.position.y = sin(_bob_phase) * 0.012
		visuals.rotation.z = 0.0
	else:
		visuals.position.y = absf(sin(_bob_phase)) * 0.045
		visuals.rotation.z = sin(_bob_phase) * 0.045

# --- Puppet ---------------------------------------------------------------
# Lets another script walk this model with the crowd's own gait: the same bob,
# the same turn speed, the same facing rule.

func puppet_walk(delta: float, travel: Vector3) -> void:
	_bob(delta, travel.length_squared() > 0.000001)
	_face_travel(travel, delta)

# --- Sim callbacks --------------------------------------------------------

# Queues the badge instead of showing it on the spot. The sim pops it above
# this customer once they have walked clear of the window (see
# _update_pending_reaction): people drink as they stroll off, they do not pose
# at the counter, and a badge over the counter is lost in the serving scrum.
func show_reaction(kind: String) -> void:
	if kind.is_empty():
		return
	_pending_reaction = kind

# Fires the queued badge as soon as this customer is far enough past the spot
# they started leaving from. Runs every frame of the walk out and does nothing
# once the badge has gone off.
func _update_pending_reaction() -> void:
	if _pending_reaction.is_empty():
		return
	if position.distance_to(_leave_start) < REACTION_WALK_DIST:
		return
	var kind: String = _pending_reaction
	_pending_reaction = ""
	if sim != null and is_instance_valid(sim):
		sim.spawn_reaction(self, kind)

# The day is over and this person never got a cup: walk them off exactly like
# anyone else, but without it being counted as a rejection. Used by the sim
# when the clock runs out, so the line does not have to be watched out.
func dismiss_out() -> void:
	if state == State.LEAVE:
		return
	_pending_reaction = ""
	_start_leave()

func enter_queue() -> void:
	state = State.WAIT_IN_QUEUE

func begin_service(spot: Vector3) -> void:
	counter_pos = spot
	at_counter = false
	state = State.COUNTER

# A served customer reacts with the cup's verdict (love / neutral / dislike),
# the same score the popularity tally used.
func buy(verdict: String) -> void:
	show_reaction(verdict)
	_start_leave()

func reject(reason_text: String) -> void:
	reason = reason_text
	show_reaction(ReactionIcon.kind_for_reason(reason_text))
	_start_leave()

func _start_leave() -> void:
	var from_line: bool = state == State.COUNTER or (state == State.WAIT_IN_QUEUE \
		and position.distance_to(queue_slot_pos) <= JOIN_STEER_DIST)
	state = State.LEAVE
	at_counter = false
	at_window = false
	_leave_index = 0
	# The walk out starts here, and the queued badge measures its distance.
	_leave_start = Vector3(position.x, 0.0, position.z)
	if sim != null and is_instance_valid(sim):
		_leave_points = sim.leave_route_for(self, from_line)
	if _leave_points.is_empty():
		_leave_points = PackedVector3Array([position + Vector3(0.0, 0.0, -12.0)])

# The approach this customer walked, for the sim to build a way back out.
func arrival_route() -> PackedVector3Array:
	return _waypoints

func score_recipe() -> Dictionary:
	var opinion: Dictionary = RecipeOpinion.score(
		PlayerData.recipe_lemons, PlayerData.recipe_sugar, PlayerData.recipe_ice,
		ideal_lemons, ideal_sugar, ideal_ice)
	opinion["band"] = str(opinion.get("verdict", RecipeOpinion.NEUTRAL))
	return opinion

# Only the price can stop a sale. Nobody tastes a cup before they buy it, so a
# recipe that misses this customer's ideal is still sold, and the miss is scored
# afterwards by the sim, where it costs popularity instead of costing the sale.
func evaluate_purchase() -> bool:
	if PlayerData.sale_price > max_price:
		reason = "Too expensive!"
		return false
	return true

func _apply_news_to_ideals() -> void:
	var shift: Dictionary = NewsCatalog.recipe_shift(PlayerData.current_news())
	if shift.is_empty():
		return
	if not NewsCatalog.applies_to_area(PlayerData.current_news(), PlayerData.current_area):
		return
	ideal_lemons = clampi(ideal_lemons + int(shift.get("lemons", 0)), 0, 12)
	ideal_sugar = clampi(ideal_sugar + int(shift.get("sugar", 0)), 0, 12)
	ideal_ice = clampi(ideal_ice + int(shift.get("ice", 0)), 0, 16)

func _news_for_here() -> NewsItem:
	var newsItem: NewsItem = NewsCatalog.get_item(PlayerData.current_news())
	if newsItem == null or not NewsCatalog.applies_to_area(newsItem.newsId, PlayerData.current_area):
		return null
	return newsItem

func _news_price_mult() -> float:
	var item: NewsItem = _news_for_here()
	if item == null or item.effects != NewsItem.EffectTarget.price:
		return 1.0
	return maxf(0.5, item.value)

func _news_patience_mult() -> float:
	var item: NewsItem = _news_for_here()
	if item == null or item.effects != NewsItem.EffectTarget.patience:
		return 1.0
	return maxf(0.4, item.value)

func _news_line_bonus() -> int:
	var item: NewsItem = _news_for_here()
	if item == null or item.effects != NewsItem.EffectTarget.line:
		return 0
	return int(round(item.value))
