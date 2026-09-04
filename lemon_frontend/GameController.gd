extends Node

# Game Panels
@onready var loginPanel : Control = $LoginPanel
@onready var otpPanel : Control = $OtpPanel
@onready var gamePanel : Control = $GamePanel
# Fields
@onready var emailField : LineEdit = $LoginPanel/EmailField
@onready var otpField : LineEdit = $OtpPanel/OtpField
@onready var statBox : Label = $GamePanel/PlayerDataLabel
# Buttons
@onready var loginButton : Button = $LoginPanel/LoginButton
@onready var otpSubmitButton : Button = $OtpPanel/OtpSubmitButton
@onready var backToLoginButton : Button = $OtpPanel/BackToLoginButton
@onready var logoutButton : Button = $GamePanel/LogoutButton

# For locking fields and buttons while http pipelines active
func _ui_lockout(locked : bool):
	loginButton.disabled = locked
	otpSubmitButton.disabled = locked
	emailField.editable = !locked
	otpField.editable = !locked

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

func _ready() -> void:
	# Connect to player data / networking signals
	GameNet.login_status_changed.connect(_on_login_status_changed)
	PlayerData.profile_updated.connect(_on_player_profile_updated)
	# Wire up buttons
	loginButton.pressed.connect(_on_login_pressed)
	otpSubmitButton.pressed.connect(_on_otp_submit_pressed)
	backToLoginButton.pressed.connect(_on_return_to_login_pressed)
	logoutButton.pressed.connect(_on_logout_pressed)
	# Try load local save
	loginPanel.visible = false
	otpPanel.visible = false
	gamePanel.visible = false
	_ui_lockout(true)
	GameNet.try_load_local_session()

# Active UI Control
func _on_login_status_changed(status : GameNet.LOGIN_STATUS):
	_ui_lockout(false)
	loginPanel.visible = false
	otpPanel.visible = false
	gamePanel.visible = false
	match status:
		GameNet.LOGIN_STATUS.logged_out:
			loginPanel.visible = true
			emailField.text = ""
			otpField.text = ""
		GameNet.LOGIN_STATUS.otp_await:
			otpPanel.visible = true
			otpField.text = ""
			otpField.grab_focus()
		GameNet.LOGIN_STATUS.logged_in:
			gamePanel.visible = true
			_on_player_profile_updated()

# Button control functions
func _on_login_pressed():
	var emailVal : String = emailField.text.strip_edges()
	if emailVal == "" : return
	_ui_lockout(true)
	GameNet.request_email_otp(emailVal)

func _on_otp_submit_pressed():
	var otpVal : String = otpField.text.strip_edges()
	# if otp invalid length, not numeric, or less than 0, don't submit
	if otpVal.length() != 6 or \
		not otpVal.is_valid_int() or \
		otpVal.to_int() < 0:
			return
	_ui_lockout(true)
	GameNet.verify_otp_code(otpVal)

func _on_return_to_login_pressed():
	GameNet.login_status = GameNet.LOGIN_STATUS.logged_out

func _on_logout_pressed():
	GameNet.logout_local_session()
