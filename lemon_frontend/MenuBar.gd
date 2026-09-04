extends HBoxContainer
class_name BottomMenuBar

signal menu_changed(menu: GameControl.MENU)
@onready var recipeMenuButton: Button = $RecipeMenu
@onready var shopMenuButton: Button = $ShopMenu
@onready var settingsMenuButton: Button = $Settings

func _ready() -> void:
	recipeMenuButton.pressed.connect(func():
		menu_changed.emit(GameControl.MENU.recipe))
	shopMenuButton.pressed.connect(func():
		menu_changed.emit(GameControl.MENU.shop))
	settingsMenuButton.pressed.connect(func():
		menu_changed.emit(GameControl.MENU.settings))
