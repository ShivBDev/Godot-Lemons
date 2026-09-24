extends Control

# Settings tab.
#
# The career-stats block is built here because it is data-driven: one label
# filled from PlayerData.stats_lines(), so every number lives in the profile
# and this file only prints it. The change-username and log-out buttons stay in
# the scene because they own their confirmation dialogs.
#
# Both buttons carry a transparent icon drawn from res://assets/ui/icons. The glyph and
# the word are lifted into a centred row for the same reason the bottom tab bar
# does it, so the pair sits together instead of wherever an offset left them.

const PANEL_STYLE := preload("res://assets/ui/style_inset.tres")
# Paths rather than preloads: a preload on a glyph the editor has not imported
# yet would fail this whole script at parse time. These load at runtime behind a
# guard instead, so a missing icon costs the icon and nothing else.
const LOGOUT_ICON_PATH := "res://assets/ui/icons/logout.svg"
const RENAME_ICON_PATH := "res://assets/ui/icons/rename.svg"

const ICON_SIDE: int = 28
const PANEL_LEFT: float = 24.0
const PANEL_WIDTH: float = 652.0
const PANEL_TOP: float = 84.0
const PANEL_HEIGHT: float = 176.0
const HEADING_FONT: int = 20
const STATS_FONT: int = 17

var _statsLabel: Label

@onready var logoutButton: Button = $LogoutButton
@onready var logoutModal: ConfirmationDialog = $LogoutConfirmation
@onready var changeUsernameButton: Button = $ChangeNameButton
@onready var changeUsernameModal: ConfirmationDialog = $ChangeUsernameModal
@onready var newUsernameField: LineEdit = $ChangeUsernameModal/Layout/UsernameField

func _ready() -> void:
	logoutButton.pressed.connect(_on_logout_pressed)
	logoutModal.confirmed.connect(_on_logout_confirmed)
	changeUsernameButton.pressed.connect(_on_change_username_pressed)
	changeUsernameModal.confirmed.connect(_on_new_username_submitted)
	_build_stats_panel()
	_add_button_icon(logoutButton, _load_texture(LOGOUT_ICON_PATH))
	_add_button_icon(changeUsernameButton, _load_texture(RENAME_ICON_PATH))
	if not PlayerData.profile_updated.is_connected(_refresh_stats):
		PlayerData.profile_updated.connect(_refresh_stats)
	# The profile can change while the tab is closed, so re-read on every open.
	visibility_changed.connect(_on_visibility_changed)
	_refresh_stats()

func _on_visibility_changed() -> void:
	if visible:
		_refresh_stats()

# --- Career stats --------------------------------------------------------

func _build_stats_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "StatsPanel"
	panel.add_theme_stylebox_override("panel", PANEL_STYLE)
	panel.offset_left = PANEL_LEFT
	panel.offset_top = PANEL_TOP
	panel.offset_right = PANEL_LEFT + PANEL_WIDTH
	panel.offset_bottom = PANEL_TOP + PANEL_HEIGHT
	# Decoration only: the buttons below it stay the only things that click.
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)

	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "Career"
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_theme_font_size_override("font_size", HEADING_FONT)
	heading.add_theme_color_override("font_color", Color(0.45, 0.33, 0.19))
	column.add_child(heading)

	_statsLabel = Label.new()
	_statsLabel.name = "Stats"
	_statsLabel.text = ""
	_statsLabel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_statsLabel.add_theme_font_size_override("font_size", STATS_FONT)
	_statsLabel.add_theme_color_override("font_color", Color(0.15, 0.25, 0.15))
	column.add_child(_statsLabel)

func _refresh_stats() -> void:
	if _statsLabel == null:
		return
	_statsLabel.text = "\n".join(PlayerData.stats_lines())

# --- Buttons -------------------------------------------------------------

# Null instead of a crash when the glyph is not imported yet.
func _load_texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

# Rebuilds the button's contents as a centred icon + word row. Idempotent, so a
# script reload cannot stack a second row inside the same button.
func _add_button_icon(button: Button, texture: Texture2D) -> void:
	if button == null or not is_instance_valid(button) or texture == null:
		return
	if button.has_node("ButtonLayout"):
		return
	var word: String = button.text
	# The row carries the word from here on, so the Button must not draw it too.
	button.text = ""

	var row := HBoxContainer.new()
	row.name = "ButtonLayout"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The button itself is what gets clicked; nothing inside it may intercept.
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = texture
	icon.custom_minimum_size = Vector2(ICON_SIDE, ICON_SIDE)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var label := Label.new()
	label.name = "Word"
	label.text = word
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)

# --- Buttons: actions ----------------------------------------------------

func _on_logout_pressed() -> void:
	logoutModal.popup_centered()

func _on_logout_confirmed() -> void:
	GameNet.logout_local_session()

func _on_change_username_pressed() -> void:
	newUsernameField.text = PlayerData.username
	changeUsernameModal.popup_centered()
	newUsernameField.grab_focus()

func _on_new_username_submitted() -> void:
	var requestedUsername : String = newUsernameField.text.strip_edges()
	if requestedUsername == "" or \
		requestedUsername == PlayerData.username or \
		requestedUsername.length() > 20:
			return
	PlayerData.username = requestedUsername
	GameNet.sync_user_data(true)
	PlayerData.profile_updated.emit()
