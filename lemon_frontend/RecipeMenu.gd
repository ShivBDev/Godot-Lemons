extends Control

@onready var lemonCount: Label = $Lemons/Count
@onready var lemonInc: Button = $Lemons/Increase
@onready var lemonDec: Button = $Lemons/Decrease
@onready var sugarCount: Label = $Sugar/Count
@onready var sugarInc: Button = $Sugar/Increase
@onready var sugarDec: Button = $Sugar/Decrease
@onready var iceCount: Label = $Ice/Count
@onready var iceInc: Button = $Ice/Increase
@onready var iceDec: Button = $Ice/Decrease
@onready var priceValue: Label = $Price/Value
@onready var priceInc: Button = $Price/Increase
@onready var priceDec: Button = $Price/Decrease

func _ready() -> void:
	lemonInc.pressed.connect(_adjust_recipe.bind("recipe_lemons", 1, 1, 20))
	lemonDec.pressed.connect(_adjust_recipe.bind("recipe_lemons", -1, 1, 20))
	PlayerData.profile_updated.connect(func(): lemonCount.text = str(PlayerData.recipe_lemons))
	sugarInc.pressed.connect(_adjust_recipe.bind("recipe_sugar", 1, 1, 20))
	sugarDec.pressed.connect(_adjust_recipe.bind("recipe_sugar", -1, 1, 20))
	PlayerData.profile_updated.connect(func(): sugarCount.text = str(PlayerData.recipe_sugar))
	iceInc.pressed.connect(_adjust_recipe.bind("recipe_ice", 1, 0, 20))
	iceDec.pressed.connect(_adjust_recipe.bind("recipe_ice", -1, 0, 20))
	PlayerData.profile_updated.connect(func(): iceCount.text = str(PlayerData.recipe_ice))
	priceInc.pressed.connect(_adjust_price.bind(0.10, 0.10, 5.00))
	priceDec.pressed.connect(_adjust_price.bind(-0.10, 0.10, 5.00))
	PlayerData.profile_updated.connect(func(): priceValue.text = "%.2f" % PlayerData.sale_price)

func _adjust_recipe(ingredient: String, offset: int, minVal: int, maxVal: int) -> void:
	var currVal = PlayerData[ingredient]
	var newVal = clamp(currVal + offset, minVal, maxVal)
	if currVal == newVal: return
	PlayerData[ingredient] = newVal
	PlayerData.profile_updated.emit()

func _adjust_price(offset: float, minVal: float, maxVal: float):
	var currVal = PlayerData.sale_price
	var newVal = clamp(currVal + offset, minVal, maxVal)
	if currVal == newVal: return
	PlayerData.sale_price = newVal
	PlayerData.profile_updated.emit()
