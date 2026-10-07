extends Node3D

# The three people who belong to the stand: the player behind the counter, a
# hired server on the second window, and a hired advertiser pacing the pavement.
#
# The keeper and the server are built from simple capsule pieces. The advertiser
# is a real Customer in puppet mode instead, so he wears the crowd's kind of
# outfit, walks with the crowd's own gait, bob and turn speed, and is only told
# where to go. Only the hired roles appear.

const SHIRT := Color(0.95, 0.86, 0.28)
const APRON := Color(0.96, 0.96, 0.93)
const SKIN := Color(0.93, 0.77, 0.61)
const PANTS := Color(0.22, 0.27, 0.40)
const SIGN := Color(0.97, 0.55, 0.18)
const AD_SHIRT := Color(0.20, 0.45, 0.72)
const AD_PANTS := Color(0.24, 0.26, 0.32)

# Where the advertiser paces, in world space: a stretch of pavement out in front
# of the counter, clear of both queue lanes (which sit at x = 0.31). He walks to
# one end, turns round, and walks back, rather than looping round to the start.
const AD_PATH_A: Vector3 = Vector3(-1.6, 0.0, -0.8)
const AD_PATH_B: Vector3 = Vector3(-1.6, 0.0, -6.8)
const AD_SPEED: float = 1.5
const AD_REACH: float = 0.1
# A short pause at each end, so the turn reads as a person turning round.
const AD_PAUSE: float = 0.5
# Slightly shorter than the crowd, so he reads as staff without being tiny.
const AD_SCALE: float = 0.95

var _keeper: Node3D
var _server: Node3D
var _advertiser: Node3D
var _ad_toward_b: bool = true
var _ad_pause: float = 0.0

func _ready() -> void:
	_keeper = _make_person("Keeper", SHIRT, true)
	_keeper.position = Vector3(-0.55, 0.0, -0.35)
	_server = _make_person("Server", Color(0.86, 0.36, 0.24), true)
	_server.position = Vector3(0.55, 0.0, -0.35)
	_server.visible = false
	_advertiser = _make_advertiser()
	if not PlayerData.profile_updated.is_connected(_refresh):
		PlayerData.profile_updated.connect(_refresh)
	_refresh()

# Walks the advertiser out to one end of the pavement, pauses, and walks him
# back. Every step goes through the Customer's own walk, so the gait, the bob
# and the turn all match the crowd walking past him.
func _process(delta: float) -> void:
	if _advertiser == null or not is_instance_valid(_advertiser) or not _advertiser.visible:
		return
	if _ad_pause > 0.0:
		_ad_pause -= delta
		_advertiser.puppet_walk(delta, Vector3.ZERO)
		return
	var target: Vector3 = AD_PATH_B if _ad_toward_b else AD_PATH_A
	var here: Vector3 = _advertiser.global_position
	var to := Vector3(target.x - here.x, 0.0, target.z - here.z)
	if to.length() <= AD_REACH:
		# Turn round and pause, so the change of direction is a real turn and
		# not a snap from one end of the path to the other.
		_ad_toward_b = not _ad_toward_b
		_ad_pause = AD_PAUSE
		_advertiser.puppet_walk(delta, Vector3.ZERO)
		return
	var step: Vector3 = to.normalized() * (AD_SPEED * delta)
	_advertiser.global_position = Vector3(here.x + step.x, 0.0, here.z + step.z)
	_advertiser.puppet_walk(delta, step)

func _refresh() -> void:
	if _server != null:
		_server.visible = PlayerData.is_hired(StaffMember.STAFF_ID.server)
	if _advertiser != null:
		_advertiser.visible = PlayerData.is_hired(StaffMember.STAFF_ID.advertiser)

# A real customer model in puppet mode: same silhouette and wardrobe as the
# crowd, in the advertiser's colours, carrying a board.
func _make_advertiser() -> Node3D:
	var scene: PackedScene = load("res://scenes/simulation_scenes/Customer.tscn")
	if scene == null:
		return null
	var person = scene.instantiate()
	person.name = "Advertiser"
	# Set before it enters the tree: _ready() reads it to become a puppet and
	# skips the customer-only setup.
	person.puppet = true
	person.scale = Vector3.ONE * AD_SCALE
	person.visible = false
	add_child(person)
	# Only once it is in the tree, because the meshes it tints are resolved by
	# the Customer's own _ready().
	person.set_uniform(AD_SHIRT, AD_PANTS)
	person.global_position = AD_PATH_A
	_add_sign(person)
	return person

func _add_sign(person: Node3D) -> void:
	_mesh(person, "Sign", BoxMesh.new(), SIGN, Vector3(0.34, 1.18, -0.08), Vector3(0.3, 0.38, 0.03))

func _make_person(person_name: String, shirt: Color, apron: bool) -> Node3D:
	var root := Node3D.new()
	root.name = person_name
	add_child(root)
	_mesh(root, "Body", CapsuleMesh.new(), shirt, Vector3(0, 0.95, 0), Vector3(0.28, 0.55, 0.22))
	var head := SphereMesh.new()
	head.radius = 0.16
	head.height = 0.32
	_mesh(root, "Head", head, SKIN, Vector3(0, 1.42, 0), Vector3.ONE)
	_mesh(root, "Pants", CapsuleMesh.new(), PANTS, Vector3(0, 0.48, 0), Vector3(0.26, 0.28, 0.2))
	if apron:
		_mesh(root, "Apron", BoxMesh.new(), APRON, Vector3(0, 0.92, -0.12), Vector3(0.34, 0.42, 0.04))
	return root

func _mesh(parent: Node3D, mesh_name: String, mesh: Mesh, color: Color, pos: Vector3, scale: Vector3) -> void:
	var inst := MeshInstance3D.new()
	inst.name = mesh_name
	inst.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	inst.material_override = mat
	inst.position = pos
	inst.scale = scale
	parent.add_child(inst)
