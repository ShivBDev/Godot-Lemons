extends Control

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

func _startLoginOrRegistration(email: String, username: String) -> void:
	sync_user_button.disabled = true
	var targetUrl: String = BASE_URL + "/player/login-or-register"
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var payload: Dictionary = { "email": email, "name": username }
	var jsonPayload = JSON.stringify(payload)
	http_login_register.request(targetUrl, headers, HTTPClient.METHOD_POST, jsonPayload)
func _submitOtpVerification(email: String, code: String) -> void:
	var targetUrl: String = BASE_URL + "/player/verify-otp"
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var payload: Dictionary = { "email": email, "code": code }
	var jsonPayload = JSON.stringify(payload)
	http_verify.request(targetUrl, headers, HTTPClient.METHOD_POST, jsonPayload)

func _syncUserData() -> void:
	sync_user_button.disabled = true
	__uName = username_field.text
	var targetUrl: String = BASE_URL + "/player/sync"
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var payload: Dictionary = {
		"email": __email,
		"name": __uName,
		"money": __money
	}
	var jsonPayload = JSON.stringify(payload)
	var error = http_sync.request(targetUrl, headers, HTTPClient.METHOD_PUT, jsonPayload)
	if error != OK:
		print("Sync update failed to dispatch.")
		sync_user_button.disabled = false

func _httpLoginRegisterComplete(\
_result: int,\
_response_code: int,\
_headers: PackedStringArray,\
_body: PackedByteArray) -> void:
	if _response_code == 200:
		print("OTP Sent! Awaiting submission.")
		# For prototyping, auto-submit code 123456
		_submitOtpVerification("player@test.com", "123456")

func _httpVerifyComplete(\
_result: int,\
_response_code: int,\
_headers: PackedStringArray,\
_body: PackedByteArray) -> void:
	if _response_code == 200:
		var json = JSON.parse_string(_body.get_string_from_utf8())
		__email = json["email"]
		__uName = json["name"]
		__money = json["money"]
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
