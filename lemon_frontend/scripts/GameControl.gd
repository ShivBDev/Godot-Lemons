extends Control
class_name GameControl

enum MENU { recipe, shop, settings, upgrades, areas, staff }
@onready var menuBar: BottomMenuBar = $MenuBar
@onready var recipeMenu: Control = $Menus/RecipeMenu
@onready var shopMenu: Control = $Menus/ShopMenu
@onready var settingsMenu: Control = $Menus/SettingsMenu
@onready var upgradesMenu: Control = $Menus/UpgradesMenu
@onready var areasMenu: Control = $Menus/AreasMenu
@onready var staffMenu: Control = $Menus/StaffMenu
@onready var autosaveTimer: Timer = $AutoSave
@onready var daySimulator: SubViewportContainer = $DaySimulator
@onready var startDayButton: Button = $StartDayButton
# Optional: a scene without the cost line still runs, it just stays quiet.
@onready var startDayCost: Label = get_node_or_null("StartDayCost")
@onready var menus: Control = $Menus
@onready var daySim: DaySimulation = $DaySimulator/SubViewport/DaySimulation

# Set to "cost" or "stock" when a click is turned down, so the label can say
# the same thing again instead of just sitting on text the player may be
# reading. Cleared on the very next refresh.
var _start_block_notice: String = ""

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
	# The day's up-front cost moves with the area and the staff roster, so the
	# button re-reads it whenever the profile changes underneath it.
	if not PlayerData.profile_updated.is_connected(_refresh_start_button):
		PlayerData.profile_updated.connect(_refresh_start_button)
	if not PlayerData.area_changed.is_connected(_on_area_changed):
		PlayerData.area_changed.connect(_on_area_changed)
	call_deferred("_connect_day_sim")
	_refresh_start_button()

func _on_game_panel_visibility_changed():
	if visible == true:
		autosaveTimer.start()
		_refresh_start_button()
	else:
		autosaveTimer.stop()

func _on_menu_changed(menu: MENU):
	recipeMenu.visible = false
	shopMenu.visible = false
	settingsMenu.visible = false
	upgradesMenu.visible = false
	areasMenu.visible = false
	if staffMenu != null:
		staffMenu.visible = false
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
		MENU.staff:
			if staffMenu != null:
				staffMenu.visible = true

func _on_area_changed(_area_id: MapArea.AreaID) -> void:
	_refresh_start_button()

func _connect_day_sim() -> void:
	if daySim == null or not is_instance_valid(daySim):
		return
	if not daySim.day_finished.is_connected(_on_day_finished):
		daySim.day_finished.connect(_on_day_finished)
	_refresh_start_button()

# Shows what the coming day costs up front and locks the button out when the
# till cannot cover it. Both numbers come from PlayerData, so this can never
# disagree with the charge start_day() actually makes.
func _refresh_start_button() -> void:
	if startDayButton == null or not is_instance_valid(startDayButton):
		return
	var running: bool = daySim != null and is_instance_valid(daySim) and daySim.is_running()
	var cost: float = PlayerData.day_start_cost()
	var afford: bool = PlayerData.can_afford_day_start()
	var stocked: bool = PlayerData.can_brew_pitcher()
	# Locked either because the day cannot be paid for or because there is
	# nothing to brew. The line below says which.
	startDayButton.disabled = running or not afford or not stocked
	if _start_block_notice != "":
		_warn_start_block()
		_start_block_notice = ""
		return
	if startDayCost == null or not is_instance_valid(startDayCost):
		return
	if running:
		startDayCost.text = ""
	elif not afford:
		startDayCost.text = "Locked: today costs $%.2f, you have $%.2f" % [cost, PlayerData.money]
	elif not stocked:
		startDayCost.text = _stock_shortfall_text()
	else:
		startDayCost.text = "No up-front cost today" if cost <= 0.0 else "Today costs $%.2f up front" % cost

# What one pitcher is missing, in the player's words. Comes straight from
# PlayerData, so the lock line and the Shop's rescue packs can never disagree
# about which ingredients are short.
func _stock_shortfall_text() -> String:
	return "Locked: Need at least %s to start day." % PlayerData.pitcher_shortfall_text()

# Says the shortfall again when a click is turned down. Money is reported first
# when both are short, because a free pack cannot fix an unpaid pitch fee.
func _warn_start_block() -> void:
	if startDayCost == null or not is_instance_valid(startDayCost):
		return
	if not PlayerData.can_afford_day_start():
		startDayCost.text = "Locked: today costs $%.2f, you have $%.2f" % [PlayerData.day_start_cost(), PlayerData.money]
	elif _start_block_notice == "stock":
		startDayCost.text = _stock_shortfall_text()

func _on_start_day_pressed() -> void:
	if daySim == null or not is_instance_valid(daySim):
		return
	if daySim.is_running():
		return
	# Belt and braces over the disabled state: never open a day that cannot be
	# paid for or brewed. The notice says which of the two is short.
	if not PlayerData.can_start_day():
		_start_block_notice = "stock" if PlayerData.can_afford_day_start() else "cost"
		_refresh_start_button()
		return
	startDayButton.disabled = true
	startDayButton.visible = false
	if startDayCost != null and is_instance_valid(startDayCost):
		startDayCost.visible = false
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
	if startDayCost != null and is_instance_valid(startDayCost):
		startDayCost.visible = true
	_refresh_start_button()
