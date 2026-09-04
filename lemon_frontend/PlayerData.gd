extends Node

signal profile_updated

# Core State Model
var username: String = "New Player"
var money: float = 100.00
var day_count: int = 1

# Active Day Inventory
var lemon_stock: int = 0
var sugar_stock: int = 0
var ice_stock: int = 0

# Recipe
var recipe_lemons: int = 4
var recipe_sugar: int = 4
var recipe_ice: int = 4
var sale_price: float = 1.00

func update_from_server_payload(profile_dict: Dictionary) -> void:
	if profile_dict.has("name"): username = profile_dict["name"]
	if profile_dict.has("money"): money = float(profile_dict["money"])
	if profile_dict.has("dayCount"): day_count = profile_dict["dayCount"]
	if profile_dict.has("lemonStock"): lemon_stock = profile_dict["lemonStock"]
	if profile_dict.has("sugarStock"): sugar_stock = profile_dict["sugarStock"]
	if profile_dict.has("iceStock"): ice_stock = profile_dict["iceStock"]
	if profile_dict.has("recipeLemons"): recipe_lemons = profile_dict["recipeLemons"]
	if profile_dict.has("recipeSugar"): recipe_sugar = profile_dict["recipeSugar"]
	if profile_dict.has("recipeIce"): recipe_ice = profile_dict["recipeIce"]
	if profile_dict.has("salePrice"): sale_price = profile_dict["salePrice"]
	profile_updated.emit()

func serialize_for_sync() -> Dictionary:
	return {
		"name": username,
		"state": {
			"money": money,
			"dayCount": day_count,
			"lemonStock": lemon_stock,
			"sugarStock": sugar_stock,
			"iceStock": ice_stock,
			"recipeLemons": recipe_lemons,
			"recipeSugar": recipe_sugar,
			"recipeIce": recipe_ice,
			"salePrice": sale_price
		}
	}
