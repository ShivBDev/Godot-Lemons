extends RefCounted
class_name RecipeOpinion

# Scores one cup against one customer's three ideals.
# A perfect match (every ingredient within 1 of the ideal) is loved.
# A close miss is neutral. A wide miss is disliked, and names the ingredient
# that was furthest off so the end-of-day screen can tally too much / too little.

const INGREDIENTS: Array = ["lemons", "sugar", "ice"]
const PERFECT_DELTA: int = 1
const NEUTRAL_DELTA: int = 3

const LOVE := "love"
const NEUTRAL := "neutral"
const DISLIKE := "dislike"

const TOO_MUCH := "too_much"
const TOO_LITTLE := "too_little"
const JUST_RIGHT := "just_right"

static func score(recipe_lemons: int, recipe_sugar: int, recipe_ice: int, ideal_lemons: int, ideal_sugar: int, ideal_ice: int) -> Dictionary:
	var deltas: Dictionary = {
		"lemons": recipe_lemons - ideal_lemons,
		"sugar": recipe_sugar - ideal_sugar,
		"ice": recipe_ice - ideal_ice,
	}
	var worst_abs: int = 0
	var worst_id: String = "lemons"
	var worst_delta: int = 0
	var parts: Dictionary = {}
	for id in INGREDIENTS:
		var delta: int = int(deltas[id])
		var magnitude: int = absi(delta)
		var band: String = JUST_RIGHT
		if delta > PERFECT_DELTA:
			band = TOO_MUCH
		elif delta < -PERFECT_DELTA:
			band = TOO_LITTLE
		parts[id] = {"delta": delta, "band": band}
		if magnitude > worst_abs:
			worst_abs = magnitude
			worst_id = id
			worst_delta = delta
	var verdict: String = LOVE
	if worst_abs > NEUTRAL_DELTA:
		verdict = DISLIKE
	elif worst_abs > PERFECT_DELTA:
		verdict = NEUTRAL
	return {
		"verdict": verdict,
		"perfect": verdict == LOVE,
		"worst": worst_id,
		"worst_delta": worst_delta,
		"parts": parts,
	}

static func empty_totals() -> Dictionary:
	return empty_tally()

static func add_totals(tally: Dictionary, opinion: Dictionary) -> void:
	record(tally, opinion)

static func summary_line(opinion: Dictionary) -> String:
	var verdict: String = str(opinion.get("verdict", opinion.get("band", NEUTRAL)))
	if verdict == LOVE:
		return "Loved it"
	var worst: String = str(opinion.get("worst", ""))
	var delta: int = int(opinion.get("worst_delta", 0))
	if worst.is_empty() or delta == 0:
		return ""
	var word: String = "too much" if delta > 0 else "too little"
	return "%s %s" % [worst.capitalize(), word]

const SKIP_PRICE := "price"
const SKIP_QUEUE := "queue"
const SKIP_WAIT := "wait"
const SKIP_TASTE := "taste"
const SKIP_STOCK := "stock"
const SKIP_OTHER := "other"
const SKIP_KEYS: Array = [SKIP_PRICE, SKIP_QUEUE, SKIP_WAIT, SKIP_TASTE, SKIP_STOCK, SKIP_OTHER]

# Sorts a rejection's bubble text into the bucket it is counted under, so a
# walk-away always lands somewhere specific instead of piling into "other".
# Order matters: price is tested before taste, because a customer who never
# tried the cup must not be filed as disliking the recipe.
static func skip_key_for(reason: String) -> String:
	var text: String = reason.to_lower().strip_edges()
	if text.contains("expensive") or text.contains("price"):
		return SKIP_PRICE
	if text.contains("line") or text.contains("queue"):
		return SKIP_QUEUE
	if text.contains("gotta go") or text.contains("wait") or text.contains("patience"):
		return SKIP_WAIT
	if text.contains("stock"):
		return SKIP_STOCK
	# Taste: they got a cup and the mix missed their ideal. These are the
	# strings Customer._dislike_reason() produces ("Too sour!", "Not cold
	# enough!", "Not my taste!" and the rest).
	if text.contains("sour") or text.contains("sweet") or text.contains("cold") \
			or text.contains("weak") or text.contains("strong") \
			or text.contains("bitter") or text.contains("taste"):
		return SKIP_TASTE
	return SKIP_OTHER

static func empty_tally() -> Dictionary:
	var bands: Dictionary = {}
	for id in INGREDIENTS:
		bands[id] = {TOO_MUCH: 0, TOO_LITTLE: 0, JUST_RIGHT: 0}
	var skips: Dictionary = {}
	for key in SKIP_KEYS:
		skips[key] = 0
	return {
		"served": 0,
		"loved": 0,
		"neutral": 0,
		"disliked": 0,
		"points": 0,
		"walked_up": 0,
		"skipped": 0,
		"skips": skips,
		"bands": bands,
	}

static func record(tally: Dictionary, opinion: Dictionary) -> void:
	tally["served"] = int(tally.get("served", 0)) + 1
	var verdict: String = str(opinion.get("verdict", NEUTRAL))
	if verdict == LOVE:
		tally["loved"] = int(tally.get("loved", 0)) + 1
	elif verdict == DISLIKE:
		tally["disliked"] = int(tally.get("disliked", 0)) + 1
	else:
		tally["neutral"] = int(tally.get("neutral", 0)) + 1
	tally["points"] = int(tally.get("points", 0)) + Popularity.points_for_verdict(verdict)
	var parts: Dictionary = opinion.get("parts", {})
	var bands: Dictionary = tally.get("bands", {})
	for id in INGREDIENTS:
		if not bands.has(id):
			bands[id] = {TOO_MUCH: 0, TOO_LITTLE: 0, JUST_RIGHT: 0}
		var part: Dictionary = parts.get(id, {})
		var band: String = str(part.get("band", JUST_RIGHT))
		if not bands[id].has(band):
			band = JUST_RIGHT
		bands[id][band] = int(bands[id][band]) + 1
	tally["bands"] = bands

static func note_arrival(tally: Dictionary) -> void:
	tally["walked_up"] = int(tally.get("walked_up", 0)) + 1

static func note_skip(tally: Dictionary, reason: String) -> void:
	var key: String = skip_key_for(reason)
	var skips: Dictionary = tally.get("skips", {})
	skips[key] = int(skips.get(key, 0)) + 1
	tally["skips"] = skips
	tally["skipped"] = int(tally.get("skipped", 0)) + 1

static func summary_lines(tally: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var served: int = int(tally.get("served", 0))
	var arrivals: int = int(tally.get("walked_up", 0))
	var skipped: int = int(tally.get("skipped", 0))
	var skips: Dictionary = tally.get("skips", {})
	lines.append("Served %d of %d customers, %d walked away" % [served, arrivals, skipped])
	lines.append("Loved %d  |  Neutral %d  |  Disliked %d" % [
		int(tally.get("loved", 0)),
		int(tally.get("neutral", 0)),
		int(tally.get("disliked", 0)),
	])
	# Every reason a customer left, named outright, so nothing hides in a
	# vague "other" bin.
	lines.append("Too expensive: %d" % int(skips.get(SKIP_PRICE, 0)))
	lines.append("Line too long: %d" % int(skips.get(SKIP_QUEUE, 0)))
	lines.append("Waited too long: %d" % int(skips.get(SKIP_WAIT, 0)))
	# A taste is never a walk-away any more: a customer only leaves without a
	# cup over the price, so unlike the other lines this one only shows up when
	# it actually happened.
	var taste: int = int(skips.get(SKIP_TASTE, 0))
	if taste > 0:
		lines.append("Didn't like the mix: %d" % taste)
	lines.append("Stand was out: %d" % int(skips.get(SKIP_STOCK, 0)))
	var other: int = int(skips.get(SKIP_OTHER, 0))
	if other > 0:
		lines.append("Other: %d" % other)
	var bands: Dictionary = tally.get("bands", {})
	var labels: Dictionary = {"lemons": "Lemons", "sugar": "Sugar", "ice": "Ice"}
	for id in INGREDIENTS:
		var row: Dictionary = bands.get(id, {})
		lines.append("%s: %d too much, %d too little, %d just right" % [
			str(labels[id]),
			int(row.get(TOO_MUCH, 0)),
			int(row.get(TOO_LITTLE, 0)),
			int(row.get(JUST_RIGHT, 0)),
		])
	return lines
