extends HBoxContainer
class_name BottomMenuBar

signal menu_changed(menu: GameControl.MENU)
@onready var recipeMenuButton: Button = $RecipeMenu
@onready var shopMenuButton: Button = $ShopMenu
@onready var settingsMenuButton: Button = $Settings
@onready var upgradesMenuButton: Button = $Upgrades
@onready var areasMenuButton: Button = $Areas
@onready var staffMenuButton: Button = get_node_or_null("Staff")

func _ready() -> void:
	# The tabs are laid out in the scene (TabLayout -> Icon + Word). This only
	# routes each press and asks the audio manager for the softer menu sound.
	recipeMenuButton.pressed.connect(menu_changed.emit.bind(GameControl.MENU.recipe))
	shopMenuButton.pressed.connect(menu_changed.emit.bind(GameControl.MENU.shop))
	settingsMenuButton.pressed.connect(menu_changed.emit.bind(GameControl.MENU.settings))
	upgradesMenuButton.pressed.connect(menu_changed.emit.bind(GameControl.MENU.upgrades))
	areasMenuButton.pressed.connect(menu_changed.emit.bind(GameControl.MENU.areas))
	if staffMenuButton != null:
		staffMenuButton.pressed.connect(menu_changed.emit.bind(GameControl.MENU.staff))
	for button in [recipeMenuButton, shopMenuButton, settingsMenuButton,
			upgradesMenuButton, areasMenuButton, staffMenuButton]:
		if button != null:
			button.set_meta("audio_switch", true)
