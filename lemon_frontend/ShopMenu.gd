extends Control

@onready var buyLemonsSmall: Button = $Lemons/BuyS
@onready var buyLemonsMed: Button = $Lemons/BuyM
@onready var buyLemonsLg: Button = $Lemons/BuyL
@onready var currLemonCt: Label = $Lemons/Stock
@onready var buySugarSmall: Button = $Sugar/BuyS
@onready var buySugarMed: Button = $Sugar/BuyM
@onready var buySugarLg: Button = $Sugar/BuyL
@onready var currSugarCt: Label = $Sugar/Stock
@onready var buyIceSmall: Button = $Ice/BuyS
@onready var buyIceMed: Button = $Ice/BuyM
@onready var buyIceLg: Button = $Ice/BuyL
@onready var currIceCt: Label = $Ice/Stock
@onready var buyCupsSmall: Button = $Cups/BuyS
@onready var buyCupsMed: Button = $Cups/BuyM
@onready var buyCupsLg: Button = $Cups/BuyL
@onready var currCupsCt: Label = $Cups/Stock

func _ready() -> void:
	buyLemonsSmall.pressed.connect(_buy_item.bind("lemon_stock", 12, 4.50))
	buyLemonsMed.pressed.connect(_buy_item.bind("lemon_stock", 24, 7.50))
	buyLemonsLg.pressed.connect(_buy_item.bind("lemon_stock", 48, 12.50))
	PlayerData.profile_updated.connect(func(): currLemonCt.text = str(PlayerData.lemon_stock))
	buySugarSmall.pressed.connect(_buy_item.bind("sugar_stock", 12, 4.80))
	buySugarMed.pressed.connect(_buy_item.bind("sugar_stock", 20, 7.00))
	buySugarLg.pressed.connect(_buy_item.bind("sugar_stock", 50, 15.00))
	PlayerData.profile_updated.connect(func(): currSugarCt.text = str(PlayerData.sugar_stock))
	buyIceSmall.pressed.connect(_buy_item.bind("ice_stock", 50, 1.00))
	buyIceMed.pressed.connect(_buy_item.bind("ice_stock", 200, 3.00))
	buyIceLg.pressed.connect(_buy_item.bind("ice_stock", 500, 5.50))
	PlayerData.profile_updated.connect(func(): currIceCt.text = str(PlayerData.ice_stock))
	buyCupsSmall.pressed.connect(_buy_item.bind("cup_stock", 75, 1.00))
	buyCupsMed.pressed.connect(_buy_item.bind("cup_stock", 250, 2.50))
	buyCupsLg.pressed.connect(_buy_item.bind("cup_stock", 500, 4.50))
	PlayerData.profile_updated.connect(func(): currCupsCt.text = str(PlayerData.cup_stock))

func _buy_item(item: String, quantity: int, price: float):
	if price > PlayerData.money: return
	PlayerData[item] += quantity
	PlayerData.money -= price
	PlayerData.profile_updated.emit()
