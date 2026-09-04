extends Control
class_name GameControl

enum MENU { recipe, shop, settings }
@onready var statBox : Label = $PlayerDataLabel
@onready var menuBar: BottomMenuBar = $MenuBar
@onready var recipeMenu: Control = $Menus/RecipeMenu
@onready var shopMenu: Control = $Menus/ShopMenu
@onready var settingsMenu: Control = $Menus/SettingsMenu

func _ready() -> void:
	PlayerData.profile_updated.connect(_on_player_profile_updated)
	visibility_changed.connect(func(): if visible == true: _on_player_profile_updated())
	menuBar.menu_changed.connect(_on_menu_changed)
	_on_menu_changed(MENU.recipe)

func _on_menu_changed(menu: MENU):
	recipeMenu.visible = false
	shopMenu.visible = false
	settingsMenu.visible = false
	match menu:
		MENU.recipe: recipeMenu.visible = true
		MENU.shop: shopMenu.visible = true
		MENU.settings: settingsMenu.visible = true

func _on_player_profile_updated():
	statBox.text = "Name: %s\n" % PlayerData.username + \
		"Money: %.2f\n" % PlayerData.money + \
		"Day: %d\n" % PlayerData.day_count + \
		"====Inventory:\n" + \
		"Lemons: %d\n" %PlayerData.lemon_stock + \
		"Sugar: %d\n" %PlayerData.sugar_stock + \
		"Ice: %d\n" %PlayerData.ice_stock + \
		"====Recipe\n" + \
		"Lemons: %d\n" %PlayerData.recipe_lemons + \
		"Sugar: %d\n" %PlayerData.recipe_sugar + \
		"Ice: %d\n" %PlayerData.recipe_ice + \
		"Sale Price: %.2f\n" % PlayerData.sale_price
