extends Control
class_name GameControl

enum MENU { recipe, shop, settings, upgrades, areas }
@onready var menuBar: BottomMenuBar = $MenuBar
@onready var recipeMenu: Control = $Menus/RecipeMenu
@onready var shopMenu: Control = $Menus/ShopMenu
@onready var settingsMenu: Control = $Menus/SettingsMenu
@onready var upgradesMenu: Control = $Menus/UpgradesMenu
@onready var areasMenu: Control = $Menus/AreasMenu
@onready var autosaveTimer: Timer = $AutoSave
@onready var daySimulator: SubViewportContainer = $DaySimulator
@onready var startDayButton: Button = $StartDayButton
@onready var menus: Control = $Menus
@onready var daySim: DaySimulation = $DaySimulator/SubViewport/DaySimulation

func _ready() -> void:
	visibility_changed.connect(_on_game_panel_visibility_changed)
	menuBar.menu_changed.connect(_on_menu_changed)
	_on_menu_changed(MENU.recipe) # Default View
	#Autosave
	autosaveTimer.autostart = false
	autosaveTimer.one_shot = false
	autosaveTimer.wait_time = 5.0
	autosaveTimer.timeout.connect(func(): GameNet.sync_user_data())
	if visible: autosaveTimer.start()
	startDayButton.pressed.connect(_on_start_day_pressed)
	call_deferred("_connect_day_sim")

func _on_game_panel_visibility_changed():
	if visible == true:
		autosaveTimer.start()
	else:
		autosaveTimer.stop()

func _on_menu_changed(menu: MENU):
	recipeMenu.visible = false
	shopMenu.visible = false
	settingsMenu.visible = false
	upgradesMenu.visible = false
	areasMenu.visible = false
	match menu:
		MENU.recipe:
			recipeMenu.visible = true
		MENU.shop:
			shopMenu.visible = true
		MENU.settings:
			settingsMenu.visible = true
		MENU.upgrades:
			upgradesMenu.visible = true
		MENU.areas:
			areasMenu.visible = true

func _connect_day_sim() -> void:
	if daySim == null or not is_instance_valid(daySim):
		return
	if not daySim.day_finished.is_connected(_on_day_finished):
		daySim.day_finished.connect(_on_day_finished)

func _on_start_day_pressed() -> void:
	if daySim == null or not is_instance_valid(daySim):
		return
	if daySim.is_running():
		return
	startDayButton.disabled = true
	startDayButton.visible = false
	menus.visible = false
	menuBar.visible = false
	daySimulator.visible = true
	daySim.start_day()

func _on_day_finished() -> void:
	daySimulator.visible = true
	menus.visible = true
	menuBar.visible = true
	startDayButton.visible = true
	startDayButton.disabled = false
