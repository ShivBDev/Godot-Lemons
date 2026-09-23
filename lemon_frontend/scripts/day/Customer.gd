extends Node3D
class_name Customer

enum State { SPAWN, WALK_TO_STAND, WAIT_IN_QUEUE, COUNTER, LEAVE }

const APPROACH_Z: float = -2.0
const LEAVE_Z: float = -11.0
const BUBBLE_DURATION: float = 2.5

# The model's face sits on its local -Z side, so a rotation of PI is what
# points the face toward +Z. Customers walk from -Z up toward the stand at +Z,
# so without that half turn they travel backwards with their face toward the
# camera.
const MODEL_FORWARD_YAW: float = PI
const TURN_SPEED: float = 9.0

# How close counts as "arrived" at a route waypoint. Snapping inside this
# radius keeps a customer from orbiting a corner it can never quite hit.
const WAYPOINT_EPSILON: float = 0.15

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

# Wardrobe shape choices. Colour alone used to carry the crowd; these give it
# real silhouettes instead. Hats have seven outcomes (one of them bare-headed),
# bottoms three cuts, and about half the crowd carries one accessory.
enum Hat { NONE, CAP_FORWARD, CAP_BACKWARD, SUN, BUCKET, BEANIE, HEADBAND }
enum Bottom { PANTS, SKIRT, SHORTS }
enum Extra { NONE, GLASSES, BACKPACK, APRON, BOW }

var sim
var state: State = State.SPAWN

var ideal_lemons: int = 4
var ideal_sugar: int = 4
var ideal_ice: int = 4
# Weather shift applied to ideal_ice (hot days want more ice, cold days less).
var ice_bias: int = 0
var max_price: float = 1.25
var line_tolerance: int = 3
var patience: float = 15.0
var queue_slot: float = APPROACH_Z
var queue_slot_x: float = 0.0
var reason: String = ""
var walk_speed: float = 1.4

var _walk_target_z: float = APPROACH_Z
# Ordered route to walk before joining the queue, plus how far along it we are.
# An empty list means the caller handed over no route, and spawn() falls back to
# a single waypoint straight in front of the line.
var _waypoints: PackedVector3Array = PackedVector3Array()
var _waypoint_index: int = 0
var _bob_phase: float = 0.0
var _bubble_timer: float = 0.0
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
@onready var bubble: Label3D = $Bubble

func setup(sim_ref) -> void:
	sim = sim_ref
	_walk_target_z = sim.get_line_end_z()

# Called by DaySimulation BEFORE the customer enters the tree, so today's
# weather is already known when _ready() rolls the recipe ideals. route_points
# is the ordered waypoint list for the arrival route this customer was given.
func spawn(sim_ref, weather_ref, route_points: PackedVector3Array = PackedVector3Array()) -> void:
	sim = sim_ref
	if sim != null:
		_walk_target_z = sim.get_line_end_z()
	_waypoints = route_points
	if _waypoints.is_empty():
		# No route handed over: fall back to one leg ending at the back of the
		# line, wherever the stand has been moved to.
		var end_point: Vector3 = Vector3(position.x, 0.0, _walk_target_z)
		if sim != null and is_instance_valid(sim):
			end_point = sim.get_line_end_point()
		_waypoints.append(end_point)
	_waypoint_index = 0
	ice_bias = _ice_bias_for(weather_ref)

func _ice_bias_for(weather_ref) -> int:
	if typeof(weather_ref) == TYPE_DICTIONARY:
		return Weather.ice_bias_for(weather_ref)
	return 0

func _ready() -> void:
	ideal_lemons = randi_range(2, 7)
	ideal_sugar = randi_range(1, 6)
	# Hotter weather shifts the ideal ice up, colder weather shifts it down.
	ideal_ice = maxi(0, randi_range(0, 8) + ice_bias)
	# Price ceiling scales with the area: downtown and the stadium will pay for
	# the same cup what the neighbourhood would flatly refuse.
	max_price = randf_range(0.75, 2.5) * _area_price_mult()
	line_tolerance = randi_range(1, 5)
	patience = randf_range(8.0, 25.0)
	walk_speed = randf_range(1.1, 1.6)
	_randomize_outfit()
	# Spawn already facing the stand so nobody starts a step backwards.
	_facing_yaw = MODEL_FORWARD_YAW
	rotation.y = _facing_yaw
	bubble.visible = false

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
	# neighbourhood leaves the mixed crowd above exactly as it was.
	match _wardrobe_theme():
		AreaCatalog.ATTIRE_CITY:
			_dress_city()
		AreaCatalog.ATTIRE_STADIUM:
			_dress_stadium()

# --- Bottoms --------------------------------------------------------------

func _randomize_bottom(skin: Color) -> void:
	# Reset to the default silhouette before rolling, so a reused instance can
	# never keep a previous customer's shape.
	skirt.visible = false
	pants_mesh.scale = Vector3.ONE
	match _roll_bottom():
		Bottom.SKIRT:
			# Bare legs under a flared skirt: the leg block takes skin tone.
			_tint(pants_mesh, skin)
			_tint(skirt, Color.from_hsv(randf(), randf_range(0.3, 0.8), randf_range(0.55, 0.95)))
			skirt.visible = true
		Bottom.SHORTS:
			# Shorter leg block, so more bare leg shows above the shoes.
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
	# Reset every silhouette, then light up exactly the one this customer wears.
	# The whole Hat node stays hidden when the roll comes up bare-headed.
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
			# Brim pushed round to the back of the head.
			hat_brim.visible = true
			hat_crown.visible = true
			hat_brim.scale = Vector3(0.72, 1.0, 0.72)
			hat_brim.position.z = 0.19
			hat_brim.rotation.y = PI
		Hat.SUN:
			# Wide floppy brim sharing the cap crown.
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
			# Aprons read as work wear, so they stay near-white.
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

# Which wardrobe the area hands out, read from wherever the stand is set up.
func _wardrobe_theme() -> String:
	return PlayerData.area_attire()

# The area's price multiplier, read off the running day so it matches the
# traffic the sim is spawning with. Falls back to 1.0 outside a day.
func _area_price_mult() -> float:
	if sim != null and is_instance_valid(sim):
		return maxf(0.1, sim.eff_price_mult)
	return 1.0

# Downtown: about half the crowd is on the way to or from an office, in a suit
# with a tie and often a briefcase.
func _dress_city() -> void:
	if randf() > 0.5:
		return
	var jacket: Color = SUIT_COLORS[randi() % SUIT_COLORS.size()]
	# Jacket and trousers match, and the arms become sleeves rather than bare
	# skin, which is what makes the silhouette read as a suit.
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
		# Briefcase in hand instead of a backpack on the back.
		backpack.visible = false
		_tint(briefcase, BRIEFCASE_COLORS[randi() % BRIEFCASE_COLORS.size()])
		briefcase.visible = true

# Match day: most of the crowd backs one of the two kits drawn for today, so
# the concourse reads as two blocks of colour instead of a random crowd.
func _dress_stadium() -> void:
	if not PlayerData.has_team_pair():
		return
	if randf() > 0.8:
		return
	var theme: Dictionary = PlayerData.team_pair[randi() % 2]
	var primary: Color = theme.get("primary", Color(0.8, 0.8, 0.8))
	var secondary: Color = theme.get("secondary", Color(0.15, 0.15, 0.15))
	_tint(body_mesh, primary)
	_tint(pants_mesh, primary.darkened(0.25))
	_tint(arm_left, primary)
	_tint(arm_right, primary)
	skirt.visible = false
	pants_mesh.scale = Vector3.ONE
	# Two-tone front panel, so the shirt reads as a jersey and not a plain tee.
	_tint(jersey_panel, secondary)
	jersey_panel.visible = true
	if randf() < 0.55:
		# Club cap: the existing cap silhouette in the team's colours.
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

# --- Movement -------------------------------------------------------------

func _process(_delta: float) -> void:
	# Movement, patience and all sim timers follow the sim's speed multiplier.
	# Bubble text stays on real time so reject reasons remain readable at 5x.
	var delta: float = _delta * _sim_time_scale()
	if _bubble_timer > 0.0:
		_bubble_timer -= _delta
		if _bubble_timer <= 0.0:
			bubble.visible = false
	match state:
		State.SPAWN:
			state = State.WALK_TO_STAND
		State.WALK_TO_STAND:
			_bob(delta)
			if _walk_route(delta):
				# Set the state before notifying the sim: an on_customer_arrived
				# rejection flips this customer straight to LEAVE.
				state = State.WAIT_IN_QUEUE
				if sim != null:
					sim.on_customer_arrived(self)
		State.WAIT_IN_QUEUE:
			_bob(delta)
			var to_slot := Vector3(queue_slot_x - position.x, 0.0, queue_slot - position.z)
			var slot_dist: float = to_slot.length()
			if slot_dist > 0.0005:
				# Shuffling along the line: keep facing where we are going. The
				# slot x closes any sideways offset left over from the route.
				_face_travel(to_slot, delta)
				var dir: Vector3 = to_slot / slot_dist
				var step: float = minf(walk_speed * delta, slot_dist)
				position.x += dir.x * step
				position.z += dir.z * step
			else:
				# Settled in line: look at the stand.
				_face_travel(_counter_facing(), delta)
			patience -= delta
			if patience <= 0.0:
				if sim != null:
					sim.on_customer_gave_up(self)
		State.COUNTER:
			_bob(delta)
			_face_travel(_counter_facing(), delta)
		State.LEAVE:
			_bob(delta)
			_face_travel(Vector3(0.0, 0.0, -1.0), delta)
			position.z = move_toward(position.z, LEAVE_Z, walk_speed * delta)
			if position.z <= LEAVE_Z:
				if sim != null:
					sim.on_customer_finished(self)

# Advances one step along the arrival route. Returns true once the last
# waypoint is behind us, which is the moment this customer may ask for a place
# in the line.
func _walk_route(delta: float) -> bool:
	if _waypoint_index >= _waypoints.size():
		return true
	var target: Vector3 = _waypoints[_waypoint_index]
	var to_target := Vector3(target.x - position.x, 0.0, target.z - position.z)
	var dist: float = to_target.length()
	var step: float = walk_speed * delta
	if dist > 0.0001:
		_face_travel(to_target, delta)
	if dist <= maxf(step, WAYPOINT_EPSILON):
		# Close enough: snap onto the corner and take the next leg.
		position.x = target.x
		position.z = target.z
		_waypoint_index += 1
		return _waypoint_index >= _waypoints.size()
	var dir: Vector3 = to_target / dist
	position.x += dir.x * step
	position.z += dir.z * step
	return false

# Turns the model toward the direction it is travelling. The face sits on the
# model's local -Z side, so the yaw for a travel direction d is
# atan2(-d.x, -d.z): that gives PI for straight +Z travel and 0 for -Z, which
# is the old MODEL_FORWARD_YAW behaviour plus a real turn around corners.
func _face_travel(travel: Vector3, delta: float) -> void:
	if absf(travel.x) < 0.0001 and absf(travel.z) < 0.0001:
		return
	var target: float = atan2(-travel.x, -travel.z)
	_facing_yaw = lerp_angle(_facing_yaw, target, clampf(delta * TURN_SPEED, 0.0, 1.0))
	rotation.y = _facing_yaw

# Direction to face while standing at the counter. The sim owns this because it
# is derived from the Stand node's transform: turn the stand and the customers
# turn with it instead of staring at where the counter used to be.
func _counter_facing() -> Vector3:
	if sim != null and is_instance_valid(sim):
		return sim.get_queue_facing()
	return Vector3(0.0, 0.0, 1.0)

func _sim_time_scale() -> float:
	if sim != null and is_instance_valid(sim):
		return sim.time_scale
	return 1.0

func _bob(delta: float) -> void:
	_bob_phase += delta * 7.0
	if state == State.WAIT_IN_QUEUE or state == State.COUNTER:
		visuals.position.y = sin(_bob_phase) * 0.012
		visuals.rotation.z = 0.0
	else:
		visuals.position.y = absf(sin(_bob_phase)) * 0.045
		visuals.rotation.z = sin(_bob_phase) * 0.045

# --- Sim callbacks --------------------------------------------------------

func show_bubble(text: String) -> void:
	bubble.text = text
	bubble.visible = true
	_bubble_timer = BUBBLE_DURATION

func enter_queue() -> void:
	state = State.WAIT_IN_QUEUE

func begin_service() -> void:
	state = State.COUNTER

func buy() -> void:
	show_bubble("Yum!")
	state = State.LEAVE

func reject(reason_text: String) -> void:
	reason = reason_text
	show_bubble(reason_text)
	state = State.LEAVE

func evaluate_purchase() -> bool:
	if PlayerData.sale_price > max_price:
		reason = "Too expensive!"
		return false
	var d_lemons: float = absf(float(PlayerData.recipe_lemons) - float(ideal_lemons)) / 5.0
	var d_sugar: float = absf(float(PlayerData.recipe_sugar) - float(ideal_sugar)) / 5.0
	var d_ice: float = absf(float(PlayerData.recipe_ice) - float(ideal_ice)) / 8.0
	var taste: float = 1.0 - (d_lemons + d_sugar + d_ice) / 3.0
	if taste < 0.45:
		if PlayerData.recipe_lemons > ideal_lemons + 1:
			reason = "Too sour!"
		elif PlayerData.recipe_sugar > ideal_sugar + 1:
			reason = "Too sweet!"
		elif PlayerData.recipe_lemons < ideal_lemons - 1 and PlayerData.recipe_sugar < ideal_sugar - 1:
			reason = "Too weak!"
		else:
			reason = "Not my taste!"
		return false
	return true
