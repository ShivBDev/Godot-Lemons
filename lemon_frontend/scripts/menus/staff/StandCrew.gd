extends Node3D

# The three people who belong to the stand: the player behind the counter,
# a hired server on the second window, and a hired advertiser pacing the
# pavement. Built from the same capsule pieces as a customer so no extra
# model import is required. Only the hired roles appear.

const SHIRT := Color(0.95, 0.86, 0.28)
const APRON := Color(0.96, 0.96, 0.93)
const SKIN := Color(0.93, 0.77, 0.61)
const PANTS := Color(0.22, 0.27, 0.40)
const SIGN := Color(0.97, 0.55, 0.18)
const AD_SHIRT := Color(0.20, 0.45, 0.72)

var _keeper: Node3D
var _server: Node3D
var _advertiser: Node3D
var _ad_phase: float = 0.0

func _ready() -> void:
	_keeper = _make_person("Keeper", SHIRT, true)
	_keeper.position = Vector3(-0.55, 0.0, -0.35)
	_server = _make_person("Server", Color(0.86, 0.36, 0.24), true)
	_server.position = Vector3(0.55, 0.0, -0.35)
	_server.visible = false
	_advertiser = _make_person("Advertiser", AD_SHIRT, false)
	_advertiser.position = Vector3(1.8, 0.0, -3.2)
	_advertiser.visible = false
	_add_sign(_advertiser)
	if not PlayerData.profile_updated.is_connected(_refresh):
		PlayerData.profile_updated.connect(_refresh)
	_refresh()

func _process(delta: float) -> void:
	if _advertiser == null or not _advertiser.visible:
		return
	_ad_phase += delta * 0.7
	var loop: float = fposmod(_ad_phase, 1.0)
	_advertiser.position.x = lerpf(-2.2, 2.2, loop)
	_advertiser.position.z = -3.4
	_advertiser.rotation.y = 0.0 if loop < 0.5 else PI

func _refresh() -> void:
	if _server != null:
		_server.visible = PlayerData.is_hired(StaffMember.STAFF_ID.server)
	if _advertiser != null:
		_advertiser.visible = PlayerData.is_hired(StaffMember.STAFF_ID.advertiser)

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

func _add_sign(person: Node3D) -> void:
	_mesh(person, "Sign", BoxMesh.new(), SIGN, Vector3(0.35, 1.15, -0.05), Vector3(0.28, 0.36, 0.03))

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
