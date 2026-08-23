extends Control

const __save_path: String = "user://session_auth.cfg"
var __session_token: String = ""
var __email : String = ""
var __uName : String = ""
var __money : int = 0

const BASE_URL: String = "http://127.0.0.1:5212/api"
# Http workers, autosave
@onready var autosave_timer: Timer = $AutoSave
@onready var http_login_register: HTTPRequest = $HttpWorkers/HttpLoginReg
@onready var http_verify: HTTPRequest = $HttpWorkers/HttpVerify
@onready var http_sync: HTTPRequest = $HttpWorkers/HttpSync
# UI Objects
@onready var sync_user_button: Button = $VBoxContainer/SyncUser
@onready var earn_money_button: Button = $VBoxContainer/EarnGold
@onready var username_field: LineEdit = $VBoxContainer/Username
@onready var stats_label: Label = $VBoxContainer/Stats

func _autoSaveTrigger():
	print("auto saving...")
	_syncUserData()
func _updateUI() -> void:
	username_field.text = __uName
	stats_label.text = "Email: " + __email + "\nMoney: " + str(__money)
func _onEarnMoneyPressed() -> void:
	__money += 10
	_updateUI()
func _onSyncUserPressed() -> void:
	if __email == "":
		_startLoginOrRegistration("player@test.com", username_field.text)
	else:
		sync_user_button.text = "Saving..."
		sync_user_button.disabled = true
		_syncUserData()
func _save_session_locally(token: String, email: String) -> void:
	var config = ConfigFile.new()
	config.set_value("auth", "session_token", token)
	config.set_value("auth", "email", email)
	var error = config.save(__save_path)
	if error != OK:
		print("Failed to cache session data locally.")

func _tryLoadSaveData() -> void:
	var config = ConfigFile.new()
	var error = config.load(__save_path)
	if error != OK:
		print("No local session token found. User must log in.")
		return

	var saved_token = config.get_value("auth", "session_token", "")
	var saved_email = config.get_value("auth", "email", "")

	if saved_token != "" and saved_email != "":
		print("Found saved session token. Verifying with server...")
		__session_token = saved_token
		__email = saved_email
		_syncUserData()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	http_login_register.request_completed.connect(_httpLoginRegisterComplete)
	http_verify.request_completed.connect(_httpVerifyComplete)
	http_sync.request_completed.connect(_httpSyncComplete)

	sync_user_button.pressed.connect(_onSyncUserPressed)
	earn_money_button.pressed.connect(_onEarnMoneyPressed)

	autosave_timer.wait_time = 15.0
	autosave_timer.one_shot = false
	autosave_timer.autostart = false
	autosave_timer.timeout.connect(_autoSaveTrigger)
	_tryLoadSaveData()

func _startLoginOrRegistration(email: String, username: String) -> void:
	sync_user_button.disabled = true
	var targetUrl: String = BASE_URL + "/player/login-or-register"
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var payload: Dictionary = { "email": email, "name": username }
	var jsonPayload = JSON.stringify(payload)
	print("Sending Login Request...")
	http_login_register.request(targetUrl, headers, HTTPClient.METHOD_POST, jsonPayload)
func _submitOtpVerification(email: String, code: String) -> void:
	var targetUrl: String = BASE_URL + "/player/verify-otp"
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var payload: Dictionary = { "email": email, "code": code }
	var jsonPayload = JSON.stringify(payload)
	print("Sending OTP...")
	http_verify.request(targetUrl, headers, HTTPClient.METHOD_POST, jsonPayload)

func _syncUserData() -> void:
	sync_user_button.disabled = true
	__uName = username_field.text
	var targetUrl: String = BASE_URL + "/player/sync"
	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"Authorization: " + __session_token
	]
	var payload: Dictionary = { "name": username_field.text, "money": __money }
	http_sync.request(targetUrl, headers, HTTPClient.METHOD_PUT, JSON.stringify(payload))

func _onLogoutPressed() -> void:
	var targetUrl: String = BASE_URL + "/player/logout"
	var headers: PackedStringArray = ["Authorization: " + __session_token]
	# Reset states locally immediately
	__session_token = ""
	__email = ""
	_updateUI()
	var dir = DirAccess.open("user://")
	if dir.file_exists("session_auth.cfg"):
		dir.remove("session_auth.cfg")
	# Tell server to delete context row tracking
	var http_logout = HTTPRequest.new()
	add_child(http_logout)
	http_logout.request(targetUrl, headers, HTTPClient.METHOD_POST)

func _httpLoginRegisterComplete(\
_result: int,\
_response_code: int,\
_headers: PackedStringArray,\
_body: PackedByteArray) -> void:
	if _response_code == 200:
		# For prototyping, auto-submit code 123456
		_submitOtpVerification("player@test.com", "123456")

func _httpVerifyComplete(\
_result: int,\
_response_code: int,\
_headers: PackedStringArray,\
_body: PackedByteArray) -> void:
	if _response_code == 200:
		var json = JSON.parse_string(_body.get_string_from_utf8())
		print("Grabbing Session Token")
		__session_token = json["token"]
		__email = json["profile"]["email"]
		__uName = json["profile"]["name"]
		__money = json["profile"]["money"]
		_updateUI()
		sync_user_button.disabled = false
		autosave_timer.start()

func _httpSyncComplete(\
_result: int,\
_response_code: int,\
_headers: PackedStringArray,\
_body: PackedByteArray) -> void:
	sync_user_button.disabled = false
	sync_user_button.text = "Sync Progress"
	if _response_code == 200:
		print("Save data synchronized successfully.")
	elif _response_code == 401:
		print("Your session has expired. Wiping local data.")
		autosave_timer.stop()
		__session_token = ""
		__email = ""
		_updateUI()
		var dir = DirAccess.open("user://")
		if dir.file_exists("session_auth.cfg"):
			dir.remove("session_auth.cfg")
		# TODO:open the registration panel here
