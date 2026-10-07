extends Sprite3D
class_name ReactionIcon

# A small badge that pops above a customer's head and floats up as they walk
# away from the stand. It is parented to the sim, not to the customer, and it
# runs on REAL time, so it stays on screen for its full life even at fast
# forward or after the customer has walked off and been freed.
#
# While the customer is alive the badge tracks their position every frame, so it
# drifts along above them instead of being left behind where they were standing.
# The sim hands the person over with follow() once the badge is in the tree.
#
# One art set is shared with the end-of-day results panel, so a green face in
# the world means exactly what a green face on the summary means.

const LIFETIME: float = 3.2
const RISE: float = 0.75
const POP_TIME: float = 0.18
const FADE_START: float = 0.6   # fraction of LIFETIME before fading begins
# How high above the customer's feet the badge sits: clear of a hat, so the
# face is never hidden behind one.
const HEAD_OFFSET: float = 1.95
# 256 px source art; 0.0019 m per px gives a badge about 0.49 m across, a little
# wider than a head: easy to read from the fixed camera without hiding the
# neighbours in a line.
const PIXEL_SIZE: float = 0.0019

const PATHS: Dictionary = {
	"love": "res://assets/ui/icons/face_loved.svg",
	"neutral": "res://assets/ui/icons/face_neutral.svg",
	"dislike": "res://assets/ui/icons/face_disliked.svg",
	"wait": "res://assets/ui/icons/react_clock.svg",
	"queue": "res://assets/ui/icons/react_crowd.svg",
	"price": "res://assets/ui/icons/react_price.svg",
	"stock": "res://assets/ui/icons/react_soldout.svg",
}

static var _cache: Dictionary = {}

var _age: float = 0.0
# The person this badge belongs to while they are alive, plus the last spot
# they were seen at, so the badge keeps rising from there once they are gone.
var _target: Node3D = null
var _anchor: Vector3 = Vector3.ZERO
var _has_anchor: bool = false

static func texture_for(kind: String) -> Texture2D:
	if _cache.has(kind):
		return _cache[kind]
	var path: String = str(PATHS.get(kind, ""))
	var tex: Texture2D = null
	if not path.is_empty() and ResourceLoader.exists(path):
		tex = load(path)
	_cache[kind] = tex
	return tex

# Icon key for a rejection reason, via the same bucketing the day tally uses,
# so the badge and the results count can never disagree. "" means no icon.
static func kind_for_reason(reason: String) -> String:
	var key: String = RecipeOpinion.skip_key_for(reason)
	if PATHS.has(key):
		return key
	return ""

static func make(kind: String) -> ReactionIcon:
	var tex: Texture2D = texture_for(kind)
	if tex == null:
		return null
	var icon := ReactionIcon.new()
	icon.texture = tex
	return icon

func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pixel_size = PIXEL_SIZE
	no_depth_test = true
	shaded = false
	render_priority = 10
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	scale = Vector3.ONE * 0.4

# Points the badge at the person it belongs to. Called AFTER add_child(), so the
# very first frame already sits above a real head instead of at the world origin,
# and the badge then rides along with them as they walk off.
func follow(person: Node3D) -> void:
	_target = person
	if person != null and is_instance_valid(person):
		_anchor = Vector3(person.position.x, 0.0, person.position.z)
		_has_anchor = true
		position = Vector3(_anchor.x, HEAD_OFFSET, _anchor.z)

# Puts the badge at a fixed spot, for a caller that has no live person to track.
func place(world_pos: Vector3) -> void:
	_anchor = Vector3(world_pos.x, 0.0, world_pos.z)
	_has_anchor = true
	position = Vector3(_anchor.x, HEAD_OFFSET, _anchor.z)

func _process(delta: float) -> void:
	_age += delta
	# Ride above the customer while they are still walking, and hold the last
	# spot we saw them at once they are freed, so the badge finishes its float
	# instead of snapping somewhere else.
	if _target != null and is_instance_valid(_target):
		_anchor = Vector3(_target.position.x, 0.0, _target.position.z)
		_has_anchor = true
	var t: float = clampf(_age / LIFETIME, 0.0, 1.0)
	# Quick pop in, then an easing drift upward.
	var pop: float = clampf(_age / POP_TIME, 0.0, 1.0)
	var s: float = lerpf(0.4, 1.0, ease(pop, 0.4))
	if pop < 1.0:
		s *= 1.0 + 0.12 * sin(pop * PI)
	scale = Vector3.ONE * s
	if _has_anchor:
		position.x = _anchor.x
		position.z = _anchor.z
		position.y = HEAD_OFFSET + RISE * ease(t, 0.6)
	var alpha: float = 1.0
	if t > FADE_START:
		alpha = 1.0 - (t - FADE_START) / (1.0 - FADE_START)
	modulate = Color(1, 1, 1, alpha)
	if _age >= LIFETIME:
		queue_free()
