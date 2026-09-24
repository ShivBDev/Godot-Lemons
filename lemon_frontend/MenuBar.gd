extends HBoxContainer
class_name BottomMenuBar

signal menu_changed(menu: GameControl.MENU)
@onready var recipeMenuButton: Button = $RecipeMenu
@onready var shopMenuButton: Button = $ShopMenu
@onready var settingsMenuButton: Button = $Settings
@onready var upgradesMenuButton: Button = $Upgrades
@onready var areasMenuButton: Button = $Areas
@onready var staffMenuButton: Button = get_node_or_null("Staff")

# Tab glyphs are square, stacked above the word inside a 72px bar.
const ICON_SIZE: int = 26
const TAB_FONT: int = 14

func _ready() -> void:
	_layout_tabs()
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
	if staffMenuButton != null:
		staffMenuButton.pressed.connect(func():
			menu_changed.emit(GameControl.MENU.staff))

# The scene ships each tab as a Button carrying its own label plus an icon child
# placed at absolute offsets, so the gap between glyph and word was whatever
# those offsets happened to leave and the pair was never centred. Rebuild each
# tab as one centred column instead: the icon and the word then share a single
# even gap, and the pair sits in the middle of the button at any button width.
func _layout_tabs() -> void:
	var tabs: Array = [recipeMenuButton, shopMenuButton, upgradesMenuButton, staffMenuButton, areasMenuButton, settingsMenuButton]
	for button in tabs:
		if button == null or not is_instance_valid(button):
			continue
		_build_tab_column(button)

func _build_tab_column(button: Button) -> void:
	# Idempotent: a reload of this script must not stack a second column.
	if button.has_node("TabLayout"):
		return
	var word: String = button.text
	var icon: Control = button.get_node_or_null("Icon")
	# The column carries the word from here on, so the Button must not draw it
	# as well.
	button.text = ""

	var column := VBoxContainer.new()
	column.name = "TabLayout"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 2)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The tab itself is what gets clicked; nothing inside it may intercept that.
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(column)

	if icon != null and is_instance_valid(icon):
		icon.get_parent().remove_child(icon)
		icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(icon)

	var label := Label.new()
	label.name = "Word"
	label.text = word
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", TAB_FONT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(label)
