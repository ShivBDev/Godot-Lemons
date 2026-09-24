extends RefCounted
class_name Popularity

# Per-area reputation. A loved cup is worth 3 points and a neutral cup is
# worth 1. A dislike earns nothing. Points fill the current rank, then roll
# into the next, so a long run of decent cups still climbs. Maxing the
# neighbourhood takes about 1000 points, downtown about 2500, the stadium
# about 5000. Rank 10 is the ceiling: +50 percent foot traffic, line
# patience, and price ceiling.

const MAX_RANK: int = 10
const BONUS_PER_RANK: float = 0.05
const POINTS_LOVE: int = 3
const POINTS_NEUTRAL: int = 1
const POINTS_DISLIKE: int = 0
# Sum of 1..10 is 55. These bases make a full climb land near the targets.
const BASE_POINTS: Dictionary = {
	"neighborhood": 18,
	"city": 45,
	"stadium": 91,
}

static func rank_of(ranks: Variant, area_id: String) -> int:
	if typeof(ranks) != TYPE_DICTIONARY:
		return 0
	var stored: Dictionary = ranks
	if not stored.has(area_id):
		return 0
	return clampi(int(stored[area_id]), 0, MAX_RANK)

static func progress_of(progress: Variant, area_id: String) -> int:
	if typeof(progress) != TYPE_DICTIONARY:
		return 0
	var stored: Dictionary = progress
	if not stored.has(area_id):
		return 0
	return maxi(0, int(stored[area_id]))

# Neighbourhood 18, 36, 54... (990 to max). Downtown 45, 90... (2475).
# Stadium 91, 182... (5005).
static func points_needed(area_id: String, rank: int) -> int:
	var base: int = int(BASE_POINTS.get(AreaCatalog.sanitize(area_id), 18))
	return base * (clampi(rank, 0, MAX_RANK - 1) + 1)

# Verdict strings are compared literally rather than through RecipeOpinion's
# constants: RecipeOpinion already calls into this class, and a two-way
# reference between global classes breaks GDScript's class scope.
static func points_for_verdict(verdict: String) -> int:
	if verdict == "love":
		return POINTS_LOVE
	if verdict == "neutral":
		return POINTS_NEUTRAL
	return POINTS_DISLIKE

static func points_to_max(area_id: String) -> int:
	var total: int = 0
	for rank in MAX_RANK:
		total += points_needed(area_id, rank)
	return total

static func multiplier_for(rank: int) -> float:
	return 1.0 + BONUS_PER_RANK * float(clampi(rank, 0, MAX_RANK))

static func cups_to_next(area_id: String, level: int) -> int:
	return points_needed(area_id, level)

static func traffic_bonus(level: int) -> float:
	return multiplier_for(level)

static func price_bonus(level: int) -> float:
	return multiplier_for(level)

static func patience_bonus(level: int) -> float:
	return multiplier_for(level)

static func line_bonus(level: int) -> int:
	return int(floor(float(clampi(level, 0, MAX_RANK)) * 0.5))

# Adds opinion points and returns how many ranks were gained (usually 0 or 1).
static func apply_points(ranks: Dictionary, progress: Dictionary, area_id: String, earned: int) -> int:
	if earned <= 0:
		return 0
	var rank: int = rank_of(ranks, area_id)
	var points: int = progress_of(progress, area_id) + earned
	var gained: int = 0
	while rank < MAX_RANK and points >= points_needed(area_id, rank):
		points -= points_needed(area_id, rank)
		rank += 1
		gained += 1
	ranks[area_id] = rank
	progress[area_id] = points
	return gained
