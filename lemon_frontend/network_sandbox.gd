extends Control
# Consts and Locals
const BASE_URL: String = "http://127.0.0.1:5212/api"
const SAVE_PATH: String = "user://session_auth.cfg"
var __session_token: String = ""
var __email : String = ""
var __uName : String = ""
var __money : int = 0
# Panel Refs
@onready var login_panel: VBoxContainer = $Panels/LoginPanel
@onready var otp_panel: VBoxContainer = $Panels/OtpPanel
@onready var game_panel: VBoxContainer = $Panels/GamePanel
## Login/Register
@onready var login_email: LineEdit = $Panels/LoginPanel/EmailField
@onready var login_button: Button = $Panels/LoginPanel/LoginBtn
## Otp
@onready var otp_code: LineEdit = $Panels/OtpPanel/OtpField
@onready var otp_submit_button: Button = $Panels/OtpPanel/OtpSubmitBtn
## Game Panel
@onready var username_field: LineEdit = $Panels/GamePanel/Username/UsernameField
@onready var stats_label: Label = $Panels/GamePanel/Stats
@onready var earn_money_button: Button = $Panels/GamePanel/EarnMoney
@onready var logout_button: Button = $Panels/GamePanel/Logout
# Http Workers
@onready var network_status: Label = $NetworkStatus
const ERR_CLR: Color = Color.RED
const WRN_CLR: Color = Color.ORANGE
const MSG_CLR: Color = Color.GREEN
@onready var http_fetch: HTTPRequest = $HttpWorkers/HttpFetch
@onready var http_login_register: HTTPRequest = $HttpWorkers/HttpLoginReg
@onready var http_verify: HTTPRequest = $HttpWorkers/HttpVerify
@onready var http_sync: HTTPRequest = $HttpWorkers/HttpSync
@onready var autosave_timer: Timer = $AutoSave

func _ready() -> void:
	# Connect Signals
	http_fetch.request_completed.connect(_onFetchComplete)
	http_login_register.request_completed.connect(_onLoginRegisterComplete)
	http_verify.request_completed.connect(_onOtpVerifyComplete)
	http_sync.request_completed.connect(_onSyncComplete)

	login_button.pressed.connect(_onLoginPressed)
	otp_submit_button.pressed.connect(_onOtpSubmitPressed)
	earn_money_button.pressed.connect(_onEarnMoneyPressed)
	logout_button.pressed.connect(_onLogoutPressed)
	username_field.text_changed.connect(func(newTxt:String): __uName = newTxt)

	autosave_timer.wait_time = 15.0
	autosave_timer.one_shot = false
	autosave_timer.autostart = false
	autosave_timer.timeout.connect(_autoSaveTrigger)
	_switchToPanel(null)
	_tryLoadSaveData()

func _switchToPanel(active_panel: VBoxContainer) -> void:
	login_panel.visible = (active_panel == login_panel)
	otp_panel.visible = (active_panel == otp_panel)
	game_panel.visible = (active_panel == game_panel)
func _updateUI() -> void:
	username_field.text = __uName
	stats_label.text = "Email: " + __email + "\nGold: " + str(__money)
func _onEarnMoneyPressed() -> void:
	__money += 10
	_updateUI()
func _setNetworkStatus(msg:String, color:Color = Color.WHITE):
	network_status.text = msg
	network_status.add_theme_color_override("font_color", color)

# Save Data Functions
## Local Save functionality
func _saveSessionLocally(token: String, email: String) -> void:
	var config = ConfigFile.new()
	config.set_value("auth", "session_token", token)
	config.set_value("auth", "email", email)
	config.save(SAVE_PATH)
func _clearLocalSession() -> void:
	var dir = DirAccess.open("user://")
	if dir and dir.file_exists("session_auth.cfg"):
		dir.remove("session_auth.cfg")
func _tryLoadSaveData() -> void:
	var config = ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		_switchToPanel(login_panel)
		return
	__session_token = config.get_value("auth", "session_token", "")
	__email = config.get_value("auth", "email", "")
	if __session_token != "" and __email != "":
		_setNetworkStatus("Local session found! Fetching user profile...", MSG_CLR)
		_fetchSaveData()
	else:
		_setNetworkStatus("Local session not found! Log in Required.", WRN_CLR)
		_switchToPanel(login_panel)
## Network Save Sync
func _fetchSaveData() -> void:
	var target_url = BASE_URL + "/player/profile"
	var headers = ["Authorization: " + __session_token]
	http_fetch.request(target_url, headers, HTTPClient.METHOD_GET)
func _onFetchComplete(_result, _response_code, _headers, _body) -> void:
	if _response_code == 200 and game_panel.visible == false:
		_setNetworkStatus("User Profile Fetched!", MSG_CLR)
		var json = JSON.parse_string(_body.get_string_from_utf8())
		__email = json["email"]
		__uName = json["name"]
		__money = json["money"]
		_updateUI()
		_switchToPanel(game_panel)
		autosave_timer.start() # Safe to start autosaving now
	elif _response_code == 401:
		_setNetworkStatus("Saved session was invalid or expired! Log in Again.", ERR_CLR)
		_clearLocalSession()
		__session_token = ""
		__email = ""
		_switchToPanel(login_panel)
func _autoSaveTrigger() -> void:
	_setNetworkStatus("Autosaving...", MSG_CLR)
	_syncUserData()
func _syncUserData() -> void:
	if __session_token == "": return
	var target_url = BASE_URL + "/player/sync"
	var headers = [
		"Content-Type: application/json",
		"Authorization: " + __session_token
	]
	var finalName = __uName.strip_edges()
	if finalName == "": finalName = "New Player"
	var payload = { "name": finalName, "money": __money }
	http_sync.request(target_url, headers, HTTPClient.METHOD_PUT, JSON.stringify(payload))
func _onSyncComplete(_result, _response_code, _headers, _body) -> void:
	if _response_code == 200:
		_setNetworkStatus("Save verified by server.", MSG_CLR)
	elif _response_code == 401:
		_setNetworkStatus("Session invalidated. Returning to Login screen.", ERR_CLR)
		_clearLocalSession()
		__session_token = ""
		_switchToPanel(login_panel)
## Logout
func _onLogoutPressed() -> void:
	_setNetworkStatus("Logging Out...", WRN_CLR)
	autosave_timer.stop()
	var target_url = BASE_URL + "/player/logout"
	var headers = ["Authorization: " + __session_token]
	var logout_worker = HTTPRequest.new()
	add_child(logout_worker)
	logout_worker.request(target_url, headers, HTTPClient.METHOD_POST)
	_clearLocalSession()
	__session_token = ""
	__email = ""
	login_email.text = ""
	otp_code.text = ""
	_switchToPanel(login_panel)

#Auth
## Login
func _onLoginPressed() -> void:
	_setNetworkStatus("Logging in with email...", MSG_CLR)
	if login_email.text.strip_edges() == "": return
	login_button.disabled = true
	var target_url = BASE_URL + "/player/login-or-register"
	var headers = ["Content-Type: application/json"]
	var payload = { "email": login_email.text.strip_edges() }
	http_login_register.request(target_url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
func _onLoginRegisterComplete(_result, _response_code, _headers, _body) -> void:
	if _response_code == 200:
		_setNetworkStatus("Auth Request Accepted, Enter Code...", MSG_CLR)
		var json = JSON.parse_string(_body.get_string_from_utf8())
		__email = json["email"]
		_switchToPanel(otp_panel)
	else:
		_setNetworkStatus("Authentication request rejected by server.", WRN_CLR)
	login_button.disabled = false
## Otp
func _onOtpSubmitPressed() -> void:
	_setNetworkStatus("Submitting OTP...", MSG_CLR)
	if otp_code.text.strip_edges() == "": return
	otp_submit_button.disabled = true
	var target_url = BASE_URL + "/player/verify-otp"
	var headers = ["Content-Type: application/json"]
	var payload = { "email": __email, "code": otp_code.text.strip_edges() }
	http_verify.request(target_url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
func _onOtpVerifyComplete(_result, _response_code, _headers, _body) -> void:
	if _response_code != 200:
		_setNetworkStatus("Invalid OTP sequence.", ERR_CLR)
		otp_submit_button.disabled = false
		return
	_setNetworkStatus("OTP Response Verified!", MSG_CLR)
	var json = JSON.parse_string(_body.get_string_from_utf8())
	__session_token = json["token"]
	__email = json["profile"]["email"]
	__uName = json["profile"]["name"]
	__money = json["profile"]["money"]
	_saveSessionLocally(__session_token, __email)
	_updateUI()
	_switchToPanel(game_panel)
	autosave_timer.start()
	otp_submit_button.disabled = false
