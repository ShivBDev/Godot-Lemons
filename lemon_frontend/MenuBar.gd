extends HBoxContainer
class_name BottomMenuBar

signal menu_changed(menu: GameControl.MENU)
@onready var recipeMenuButton: Button = $RecipeMenu
@onready var shopMenuButton: Button = $ShopMenu
@onready var settingsMenuButton: Button = $Settings
@onready var upgradesMenuButton: Button = $Upgrades
@onready var areasMenuButton: Button = $Areas

func _ready() -> void:
	# TEMP DIAGNOSTIC - remove once the recipe tab issue is settled.
	recipeMenuButton.pressed.connect(func():
		print("[menu] tab pressed: recipe")
		menu_changed.emit(GameControl.MENU.recipe))
	shopMenuButton.pressed.connect(func():
		print("[menu] tab pressed: shop")
		menu_changed.emit(GameControl.MENU.shop))
	settingsMenuButton.pressed.connect(func():
		print("[menu] tab pressed: settings")
		menu_changed.emit(GameControl.MENU.settings))
	upgradesMenuButton.pressed.connect(func():
		print("[menu] tab pressed: upgrades")
		menu_changed.emit(GameControl.MENU.upgrades))
	areasMenuButton.pressed.connect(func():
		print("[menu] tab pressed: areas")
		menu_changed.emit(GameControl.MENU.areas))
