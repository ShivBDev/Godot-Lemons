extends Control

# Settings tab.
#
# The layout lives in the scene (MainPage -> AudioPage / AccountPage); this
# script only swaps pages and fills the career stats label from PlayerData.
# Audio values are owned by the AudioManager autoload, kept in its own local
# config, so nothing here touches the player save.

@onready var _title: Label = $Title
@onready var mainPage: Control = $MainPage
@onready var audioPage: Control = $AudioPage
@onready var accountPage: Control = $AccountPage
@onready var statsLabel: Label = $MainPage/StatsPanel/Margin/Column/Stats

@onready var audioButton: Button = $MainPage/AudioButton
@onready var accountButton: Button = $MainPage/AccountButton
@onready var muteCheck: CheckButton = $AudioPage/MuteCheck
@onready var musicSlider: HSlider = $AudioPage/MusicSlider
@onready var musicValue: Label = $AudioPage/MusicValue
@onready var sfxSlider: HSlider = $AudioPage/SfxSlider
@onready var sfxValue: Label = $AudioPage/SfxValue
@onready var audioBack: Button = $AudioPage/BackButton

@onready var logoutButton: Button = $AccountPage/LogoutButton
@onready var logoutModal: ConfirmationDialog = $LogoutConfirmation
@onready var changeUsernameButton: Button = $AccountPage/ChangeNameButton
@onready var changeUsernameModal: ConfirmationDialog = $ChangeUsernameModal
@onready var newUsernameField: LineEdit = $ChangeUsernameModal/Layout/UsernameField
@onready var deleteAccountButton: Button = $AccountPage/DeleteAccountButton
@onready var deleteAccountModal: ConfirmationDialog = $DeleteAccountModal
@onready var deleteAccountConfirmationField: LineEdit = $DeleteAccountModal/Layout/ConfirmationField
@onready var accountBack: Button = $AccountPage/BackButton

func _ready() -> void:
	audioButton.pressed.connect(_show_page.bind(audioPage))
	accountButton.pressed.connect(_show_page.bind(accountPage))
	audioBack.pressed.connect(_show_page.bind(mainPage))
	accountBack.pressed.connect(_show_page.bind(mainPage))

	muteCheck.toggled.connect(AudioManager.set_muted)
	musicSlider.value_changed.connect(_on_music_changed)
	sfxSlider.value_changed.connect(_on_sfx_changed)
	AudioManager.settings_changed.connect(_sync_audio_controls)
	_sync_audio_controls()

	logoutButton.pressed.connect(_on_logout_pressed)
	logoutModal.confirmed.connect(_on_logout_confirmed)
	changeUsernameButton.pressed.connect(_on_change_username_pressed)
	changeUsernameModal.confirmed.connect(_on_new_username_submitted)
	deleteAccountButton.pressed.connect(_on_delete_account_pressed)
	deleteAccountModal.confirmed.connect(_on_delete_account_confirmed)

	if not PlayerData.profile_updated.is_connected(_refresh_stats):
		PlayerData.profile_updated.connect(_refresh_stats)
	# The profile can change while the tab is closed, so re-read on every open.
	visibility_changed.connect(_on_visibility_changed)
	_show_page(mainPage)
	_refresh_stats()

func _show_page(page: Control) -> void:
	# Each subpage carries its own heading, so the tab's title steps aside.
	_title.visible = page == mainPage
	for p in [mainPage, audioPage, accountPage]:
		p.visible = p == page

func _on_visibility_changed() -> void:
	if visible:
		_show_page(mainPage)
		_refresh_stats()
		_sync_audio_controls()

# --- Career stats --------------------------------------------------------

func _refresh_stats() -> void:
	statsLabel.text = "\n".join(PlayerData.stats_lines())

# --- Audio ---------------------------------------------------------------

# The sliders are 0-100; AudioManager speaks 0.0-1.0.
func _on_music_changed(value: float) -> void:
	AudioManager.set_music_volume(value / 100.0)
	_sync_audio_controls()

func _on_sfx_changed(value: float) -> void:
	AudioManager.set_sfx_volume(value / 100.0)
	_sync_audio_controls()

# Pulls the live values out of AudioManager without re-triggering the setters.
func _sync_audio_controls() -> void:
	muteCheck.set_pressed_no_signal(AudioManager.muted)
	musicSlider.set_value_no_signal(roundi(AudioManager.music_volume * 100.0))
	sfxSlider.set_value_no_signal(roundi(AudioManager.sfx_volume * 100.0))
	musicValue.text = "%d%%" % roundi(musicSlider.value)
	sfxValue.text = "%d%%" % roundi(sfxSlider.value)

# --- Account -------------------------------------------------------------

func _on_logout_pressed() -> void:
	logoutModal.popup_centered()

func _on_logout_confirmed() -> void:
	# Save before logging out
	GameNet.sync_user_data()
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

func _on_delete_account_pressed() -> void:
	deleteAccountModal.popup_centered()

func _on_delete_account_confirmed() -> void:
	var confirmationText : String = deleteAccountConfirmationField.text.strip_edges()
	if confirmationText != "DeleteMe":
		return
	GameNet.delete_player_account()
