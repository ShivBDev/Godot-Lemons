extends Control
@onready var logoutButton: Button = $LogoutButton
@onready var logoutModal: ConfirmationDialog = $LogoutConfirmation
@onready var changeUsernameButton: Button = $ChangeNameButton
@onready var changeUsernameModal: ConfirmationDialog = $ChangeUsernameModal
@onready var newUsernameField: LineEdit = $ChangeUsernameModal/Layout/UsernameField

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	logoutButton.pressed.connect(_on_logout_pressed)
	logoutModal.confirmed.connect(_on_logout_pressed)
	changeUsernameButton.pressed.connect(_on_change_username_pressed)
	changeUsernameModal.confirmed.connect(_on_new_username_submitted)

func _on_logout_pressed():
	logoutModal.popup_centered()
func _on_logout_confirmed():
	GameNet.logout_local_session()

func _on_change_username_pressed():
	newUsernameField.text = PlayerData.username
	changeUsernameModal.popup_centered()
	newUsernameField.grab_focus()
func _on_new_username_submitted():
	var requestedUsername : String = newUsernameField.text.strip_edges()
	if requestedUsername == "" or \
		requestedUsername == PlayerData.username or \
		requestedUsername.length() > 20:
			return
	PlayerData.username = requestedUsername
	GameNet.sync_user_data()
	PlayerData.profile_updated.emit()
