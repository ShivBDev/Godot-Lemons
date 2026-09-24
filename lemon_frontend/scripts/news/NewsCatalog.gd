extends RefCounted
class_name NewsCatalog

# Tomorrow's headlines. ONE entry per story. DaySimulation rolls one at the
# end of each day, stores it on PlayerData.news, and applies it to the next
# day only. The ticker shows it while shopping and hides once the day starts.
#
# Entry shape:
#   id      : String - stable key
#   text    : String - ticker line, present tense, about tomorrow
#   effect  : String - one of the effect names below
#   value   : float  - magnitude the effect reads
#   area    : String - optional area id; empty means everywhere
#   field   : String - optional shop field the sale applies to
#   recipe  : Dictionary - optional {lemons, sugar, ice} shift, each -3..3
#
# Effects read by the game:
#   traffic       DaySimulation  multiplies arrivals (value is a multiplier)
#   price         Customer       multiplies the price ceiling
#   patience      Customer       multiplies how long they will wait
#   line          Customer       added to how long a line they will join
#   weather_temp  PlayerData     added to tomorrow's forecast temperature
#   weather_rain  PlayerData     forces rain (value >= 0.5) or sun (value < 0.5)
#   recipe        Customer       shifts ideal lemons / sugar / ice
#   sale          ShopMenu       multiplies one field's pack prices (or all)

const EFFECTS_TRAFFIC := "traffic"
const EFFECTS_PRICE := "price"
const EFFECTS_PATIENCE := "patience"
const EFFECTS_LINE := "line"
const EFFECTS_WEATHER_TEMP := "weather_temp"
const EFFECTS_WEATHER_RAIN := "weather_rain"
const EFFECTS_RECIPE := "recipe"
const EFFECTS_SALE := "sale"

const ITEMS: Array = [
	{
		"id": "heat_wave",
		"text": "A heat wave is rolling in. Tomorrow will run well past the usual high.",
		"effect": EFFECTS_WEATHER_TEMP,
		"value": 18.0,
	},
	{
		"id": "cold_snap",
		"text": "A cold snap is due overnight. Tomorrow drops well below the usual range.",
		"effect": EFFECTS_WEATHER_TEMP,
		"value": -18.0,
	},
	{
		"id": "surprise_storm",
		"text": "A surprise storm is on the radar. Rain tomorrow, no matter the season.",
		"effect": EFFECTS_WEATHER_RAIN,
		"value": 1.0,
	},
	{
		"id": "clear_skies",
		"text": "Clear skies are locked in. Tomorrow stays dry even if the odds said otherwise.",
		"effect": EFFECTS_WEATHER_RAIN,
		"value": 0.0,
	},
	{
		"id": "scorcher",
		"text": "Forecasters are calling tomorrow a scorcher. People will want ice.",
		"effect": EFFECTS_RECIPE,
		"value": 1.0,
		"recipe": {"ice": 3},
	},
	{
		"id": "chilly_morning",
		"text": "A chilly morning is forecast. The crowd will want less ice in the cup.",
		"effect": EFFECTS_RECIPE,
		"value": 1.0,
		"recipe": {"ice": -3},
	},
	{
		"id": "sweet_tooth",
		"text": "A candy fair is in town. Everyone walking past wants a sweeter cup.",
		"effect": EFFECTS_RECIPE,
		"value": 1.0,
		"recipe": {"sugar": 2},
	},
	{
		"id": "tart_trend",
		"text": "A food column is pushing tart lemonade. Customers want more lemon.",
		"effect": EFFECTS_RECIPE,
		"value": 1.0,
		"recipe": {"lemons": 2, "sugar": -1},
	},
	{
		"id": "mild_palate",
		"text": "A wellness blog is telling people to ease off. Milder cups will sell.",
		"effect": EFFECTS_RECIPE,
		"value": 1.0,
		"recipe": {"lemons": -2, "sugar": -1},
	},
	{
		"id": "neighborhood_block_party",
		"text": "A block party is posted for the neighborhood. Foot traffic there jumps.",
		"effect": EFFECTS_TRAFFIC,
		"value": 1.45,
		"area": "neighborhood",
	},
	{
		"id": "downtown_parade",
		"text": "A parade is routing through downtown. The avenue will be packed.",
		"effect": EFFECTS_TRAFFIC,
		"value": 1.4,
		"area": "city",
	},
	{
		"id": "stadium_doubleheader",
		"text": "The stadium has a doubleheader. The concourse will be shoulder to shoulder.",
		"effect": EFFECTS_TRAFFIC,
		"value": 1.5,
		"area": "stadium",
	},
	{
		"id": "road_closure",
		"text": "A road closure is diverting cars past the neighborhood stand.",
		"effect": EFFECTS_TRAFFIC,
		"value": 1.25,
		"area": "neighborhood",
	},
	{
		"id": "office_holiday",
		"text": "Downtown offices are closed tomorrow. The avenue will be quiet.",
		"effect": EFFECTS_TRAFFIC,
		"value": 0.7,
		"area": "city",
	},
	{
		"id": "rained_out_game",
		"text": "The stadium game may be rained out. Expect a thinner concourse.",
		"effect": EFFECTS_TRAFFIC,
		"value": 0.65,
		"area": "stadium",
	},
	{
		"id": "tourist_weekend",
		"text": "A tourist weekend is starting. More people everywhere, and they linger.",
		"effect": EFFECTS_TRAFFIC,
		"value": 1.2,
	},
	{
		"id": "payday",
		"text": "Payday just landed. Customers will pay a little more without blinking.",
		"effect": EFFECTS_PRICE,
		"value": 1.2,
	},
	{
		"id": "tight_wallets",
		"text": "A local paper says wallets are tight. Price ceilings drop a notch.",
		"effect": EFFECTS_PRICE,
		"value": 0.85,
	},
	{
		"id": "stadium_splurge",
		"text": "Match-day spending is up. Stadium customers will pay more for a cold cup.",
		"effect": EFFECTS_PRICE,
		"value": 1.25,
		"area": "stadium",
	},
	{
		"id": "downtown_expense_accounts",
		"text": "Expense accounts are open downtown. Office crowds will pay up.",
		"effect": EFFECTS_PRICE,
		"value": 1.2,
		"area": "city",
	},
	{
		"id": "patient_crowd",
		"text": "Nothing else is open nearby. People will wait longer in line.",
		"effect": EFFECTS_PATIENCE,
		"value": 1.4,
	},
	{
		"id": "rushed_morning",
		"text": "Everyone is running late. Lines that look long will be walked past.",
		"effect": EFFECTS_PATIENCE,
		"value": 0.7,
	},
	{
		"id": "festival_queues",
		"text": "A street festival trained people to queue. Longer lines are fine today.",
		"effect": EFFECTS_LINE,
		"value": 2.0,
	},
	{
		"id": "no_patience",
		"text": "A transit delay has everyone irritable. Short lines only.",
		"effect": EFFECTS_LINE,
		"value": -1.0,
	},
	{
		"id": "lemon_sale",
		"text": "The market has lemons on sale. Pack prices drop for one day.",
		"effect": EFFECTS_SALE,
		"value": 0.7,
		"field": "lemon_stock",
	},
	{
		"id": "sugar_sale",
		"text": "A wholesaler is dumping sugar. Sugar packs are cheaper tomorrow.",
		"effect": EFFECTS_SALE,
		"value": 0.75,
		"field": "sugar_stock",
	},
	{
		"id": "ice_sale",
		"text": "The ice plant is overstocked. Ice packs are on sale.",
		"effect": EFFECTS_SALE,
		"value": 0.6,
		"field": "ice_stock",
	},
	{
		"id": "cup_sale",
		"text": "A cup supplier is clearing inventory. Cup packs are discounted.",
		"effect": EFFECTS_SALE,
		"value": 0.7,
		"field": "cup_stock",
	},
	{
		"id": "storewide_sale",
		"text": "The supply shop is running a storewide sale. Every pack is cheaper.",
		"effect": EFFECTS_SALE,
		"value": 0.8,
		"field": "",
	},
	{
		"id": "price_hike",
		"text": "Supply costs jumped overnight. Shop prices are up across the board.",
		"effect": EFFECTS_SALE,
		"value": 1.25,
		"field": "",
	},
	{
		"id": "citrus_shortage",
		"text": "A citrus shortage is hitting the market. Lemons cost more tomorrow.",
		"effect": EFFECTS_SALE,
		"value": 1.4,
		"field": "lemon_stock",
	},
	{
		"id": "perfect_picnic",
		"text": "Picnic weather is forecast, and the crowd wants a balanced cup.",
		"effect": EFFECTS_RECIPE,
		"value": 1.0,
		"recipe": {"lemons": 0, "sugar": 1, "ice": 1},
	},
]

static func all() -> Array:
	return ITEMS

static func count() -> int:
	return ITEMS.size()

static func get_item(id: String) -> Dictionary:
	for item in ITEMS:
		if str(item.get("id", "")) == id:
			return item
	return {}

static func roll() -> Dictionary:
	if ITEMS.is_empty():
		return {}
	return ITEMS[randi() % ITEMS.size()].duplicate(true)

static func sanitize(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var stored: Dictionary = raw
	var item: Dictionary = get_item(str(stored.get("id", "")))
	if item.is_empty():
		return {}
	return item.duplicate(true)

static func headline(item: Dictionary) -> String:
	return str(item.get("text", ""))

static func applies_to_area(item: Dictionary, area_id: String) -> bool:
	var locked: String = str(item.get("area", ""))
	if locked.is_empty():
		return true
	return locked == area_id

static func effect_of(item: Dictionary) -> String:
	return str(item.get("effect", ""))

static func value_of(item: Dictionary) -> float:
	return float(item.get("value", 1.0))

static func sale_multiplier(item: Dictionary, field: String) -> float:
	if effect_of(item) != EFFECTS_SALE:
		return 1.0
	var locked: String = str(item.get("field", ""))
	if not locked.is_empty() and locked != field:
		return 1.0
	return maxf(0.1, value_of(item))

static func recipe_shift(item: Dictionary) -> Dictionary:
	if effect_of(item) != EFFECTS_RECIPE:
		return {}
	var recipe: Variant = item.get("recipe", {})
	if typeof(recipe) != TYPE_DICTIONARY:
		return {}
	return recipe
