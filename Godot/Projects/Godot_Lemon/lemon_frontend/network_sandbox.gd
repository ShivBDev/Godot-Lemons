extends Control

const ____TEST_PID : int = 4
var __pid : int = 0
var __uName : String = ""
var __money : int = 0

const BASE_URL: String = "http://127.0.0.1:5212/api"
# Http workers, autosave
@onready var autosave_timer: Timer = $AutoSave
@onready var http_register: HTTPRequest = $HttpWorkers/HttpPlayerRegister
@onready var http_fetch: HTTPRequest = $HttpWorkers/HttpPlayerFetch
@onready var http_sync: HTTPRequest = $HttpWorkers/HttpPlayerSync
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
	stats_label.text = "PID: " + str(__pid) + "\nMoney: " + str(__money)
func _onEarnMoneyPressed() -> void:
	__money += 10
	_updateUI()
func _onSyncUserPressed() -> void:
	if __pid == 0:
		_registerNewPlayer(username_field.text)
	else:
		sync_user_button.text = "Saving..."
		sync_user_button.disabled = true
		_syncUserData()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	http_register.request_completed.connect(_httpRegisterReqComplete)
	http_fetch.request_completed.connect(_httpFetchReqComplete)
	http_sync.request_completed.connect(_httpSyncComplete)

	sync_user_button.pressed.connect(_onSyncUserPressed)
	earn_money_button.pressed.connect(_onEarnMoneyPressed)

	_autoloadSaveData(____TEST_PID)

	autosave_timer.wait_time = 15.0
	autosave_timer.one_shot = false
	autosave_timer.autostart = false
	autosave_timer.timeout.connect(_autoSaveTrigger)

func _autoloadSaveData(pid : int) -> void:
	sync_user_button.disabled = true
	var targetUrl: String = BASE_URL + "/player/profile/" + str(pid)
	var headers: PackedStringArray = ["Content-Type: application/json"]

	var error = http_fetch.request(targetUrl, headers, HTTPClient.METHOD_GET)
	if error != OK:
		print("Error: Failed to initialize network stream.")

func _registerNewPlayer(username: String) -> void:
	sync_user_button.disabled = true
	var targetUrl: String = BASE_URL + "/player/register"
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var payload: Dictionary = { "name": username }
	var jsonPayload = JSON.stringify(payload)
	var error = http_register.request(targetUrl, headers, HTTPClient.METHOD_POST, jsonPayload)
	if error != OK:
		print("Registration request failed to dispatch.")

func _syncUserData() -> void:
	sync_user_button.disabled = true
	__uName = username_field.text #editable, make sure its fresh on save
	# setup payload
	var targetUrl: String = BASE_URL + "/player/sync"
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var payload: Dictionary = {
		"pid": __pid,
		"name": __uName,
		"money": __money,
	}
	var jsonPayload = JSON.stringify(payload)
	var result = http_sync.request(targetUrl, headers, HTTPClient.METHOD_PUT, jsonPayload)
	if result != OK:
		print("Cloud Sync Failed")
		sync_user_button.disabled = false
		sync_user_button.text = "Save"

func _httpRegisterReqComplete(\
_result: int,\
_response_code: int,\
_headers: PackedStringArray,\
_body: PackedByteArray) -> void:
	# REST 201 means success
	if _response_code != 201:
		sync_user_button.disabled = false
		sync_user_button.text = "Try Again"
		print("Registration Failed! Server Status Code: " + str(_response_code))
		return

	var rawJson: String = _body.get_string_from_utf8()
	var jsonParser: JSON = JSON.new()
	var parseResult = jsonParser.parse(rawJson)
	if parseResult != OK:
		sync_user_button.disabled = false
		sync_user_button.text = "Try Again"
		print("Failed to parse the server's registration response.")
		return

	var newPlayerData: Dictionary = jsonParser.get_data()
	__pid = newPlayerData.get("pid", newPlayerData.get("pid", 0))
	__uName = newPlayerData.get("name", newPlayerData.get("name", "Unknown"))
	__money = newPlayerData.get("money", newPlayerData.get("money", 100))
	print("Successfully registered account! Assigned PID: " + str(__pid))
	sync_user_button.disabled = false
	sync_user_button.text = "Save"

	_updateUI()
	autosave_timer.start()

func _httpFetchReqComplete(\
_result: int,\
_response_code: int,\
_headers: PackedStringArray,\
_body: PackedByteArray) -> void:
	if _response_code != 200:
		print("Server Error! Status Code: " + str(_response_code))
		print("Failed to fetch user profile")
		sync_user_button.disabled = false
		sync_user_button.text = "Register"
		return
	var rawJson: String = _body.get_string_from_utf8()
	var jsonParser: JSON = JSON.new()
	var parseResult = jsonParser.parse(rawJson)
	if parseResult == OK:
		var playerData: Dictionary = jsonParser.get_data()
		__pid = playerData.get("pid", 0)
		__uName = playerData.get("name", "")
		__money = playerData.get("money", 0)
		sync_user_button.disabled = false
		sync_user_button.text = "Save"
	else:
		print("Failed to parse user save data!")
		sync_user_button.disabled = false
		sync_user_button.text = "Register"
		return
	_updateUI()
	autosave_timer.start()

func _httpSyncComplete(\
_result: int,\
_response_code: int,\
_headers: PackedStringArray,\
_body: PackedByteArray) -> void:
	sync_user_button.disabled = false
	sync_user_button.text = "Save"
	if _response_code != 200:
		print("Sync Failed! Status: " + str(_response_code))
		return
	print("Game State Saved Successfully!")
