extends Node
enum LOGIN_STATUS { logged_out, otp_await, logged_in }
var login_status: LOGIN_STATUS = LOGIN_STATUS.logged_out:
	get:
		return login_status
	set(value):
		login_status = value
		login_status_changed.emit(value)
signal login_status_changed(status: LOGIN_STATUS)
signal sync_completed(is_success: bool, server_message: String)

const BASE_URL: String = "http://127.0.0.1:5212/api"
const SAVE_PATH: String = "user://session_auth.cfg"
var session_token: String = ""
var player_email: String = ""

var http_login: HTTPRequest
var http_verify: HTTPRequest
var http_fetch: HTTPRequest
var http_sync: HTTPRequest

#Utils
func _gameNetPrint(msg : String):
	print("GAME NET ==> %s" % msg)
func _save_local_session() -> void:
	_gameNetPrint("Saving Local Session...")
	var config = ConfigFile.new()
	config.set_value("auth", "session_token", session_token)
	config.set_value("auth", "email", player_email)
	config.save(SAVE_PATH)
func _clear_local_session() -> void:
	_gameNetPrint("Clearing Local Session...")
	session_token = ""
	player_email = ""
	var dir = DirAccess.open("user://")
	if dir and dir.file_exists("session_auth.cfg"):
		dir.remove("session_auth.cfg")
func _parse_server_error(body: PackedByteArray) -> String:
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json and json is Dictionary and json.has("detail"):
		return json["detail"]
	return "Network communication failure."
func _instantiate_network_workers() -> void:
	http_login = HTTPRequest.new()
	http_verify = HTTPRequest.new()
	http_fetch = HTTPRequest.new()
	http_sync = HTTPRequest.new()
	add_child(http_login)
	add_child(http_verify)
	add_child(http_fetch)
	add_child(http_sync)
	http_login.request_completed.connect(_on_otp_request_complete)
	http_verify.request_completed.connect(_on_verify_complete)
	http_fetch.request_completed.connect(_on_fetch_complete)
	http_sync.request_completed.connect(_on_sync_complete)

func _ready() -> void:
	_instantiate_network_workers()

# Local Save Functionality
func try_load_local_session() -> void:
	var config = ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		_gameNetPrint("No Local Save Found...")
		login_status = LOGIN_STATUS.logged_out
		return
	session_token = config.get_value("auth", "session_token", "")
	player_email = config.get_value("auth", "email", "")
	if session_token != "":
		_fetch_save_data()
	else:
		_gameNetPrint("Local Session Invalid...")
		_clear_local_session()
		login_status = LOGIN_STATUS.logged_out
func logout_local_session() -> void:
	_gameNetPrint("Logging out Local Session...")
	var logout_worker = HTTPRequest.new()
	add_child(logout_worker)
	logout_worker.request(BASE_URL + "/player/logout", ["Authorization: " + session_token], HTTPClient.METHOD_POST)
	_clear_local_session()
	login_status = LOGIN_STATUS.logged_out

# Networking Save Fetch
func _fetch_save_data() -> void:
	_gameNetPrint("Fetching Save Data...")
	var target_url = BASE_URL + "/player/profile"
	var headers = ["Authorization: " + session_token]
	http_fetch.request(target_url, headers, HTTPClient.METHOD_GET)
func _on_fetch_complete(_result, _response_code, _headers, _body) -> void:
	if _response_code == 200:
		_gameNetPrint("Login Successful!")
		var json = JSON.parse_string(_body.get_string_from_utf8())
		PlayerData.update_from_server_payload(json["profile"])
		login_status = LOGIN_STATUS.logged_in
	elif _response_code == 401 or _response_code == 404:
		_gameNetPrint("Login Failed: %d" % _response_code)
		_clear_local_session()
		login_status = LOGIN_STATUS.logged_out
# Networking Save Sync
func sync_user_data() -> void:
	_gameNetPrint("Syncing User Data...")
	if session_token == "": return
	var headers = ["Content-Type: application/json", "Authorization: " + session_token]
	var payload = PlayerData.serialize_for_sync()
	http_sync.request(BASE_URL + "/player/sync", headers, HTTPClient.METHOD_PUT, JSON.stringify(payload))
func _on_sync_complete(_result, _response_code, _headers, _body) -> void:
	if _response_code == 200:
		_gameNetPrint("Saved Successfully!")
		sync_completed.emit(true, "SUCCESS")
	elif _response_code == 401 or _response_code == 404:
		_gameNetPrint("Save Failed, Logging Out: %d" % _response_code)
		_clear_local_session()
		login_status = LOGIN_STATUS.logged_out
	else:
		_gameNetPrint("Save Failed, Unknown Error: %d" % _response_code)
		sync_completed.emit(false, _parse_server_error(_body))
# Networking Save Login/Auth
## Login
func request_email_otp(email: String) -> void:
	_gameNetPrint("Submitting OTP Request...")
	player_email = email.strip_edges()
	if player_email == "": return
	var target_url = BASE_URL + "/player/login-or-register"
	var headers = ["Content-Type: application/json"]
	var payload = { "email": player_email }
	http_login.request(target_url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
func _on_otp_request_complete(_result, _response_code, _headers, _body) -> void:
	if _response_code == 200:
		_gameNetPrint("OTP Sent! Awaiting...")
		login_status = LOGIN_STATUS.otp_await
	else:
		_gameNetPrint("Login Not Authorized: %d" % _response_code)
		login_status = LOGIN_STATUS.logged_out
## Auth
func verify_otp_code(code: String) -> void:
	_gameNetPrint("Verifying OTP Code...")
	var payload = { "email": player_email, "code": code.strip_edges() }
	var headers = ["Content-Type: application/json"]
	http_verify.request(BASE_URL + "/player/verify-otp", headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
func _on_verify_complete(_result, _response_code, _headers, _body) -> void:
	if _response_code != 200:
		_gameNetPrint("OTP Verification Failed: %d" % _response_code)
		login_status = LOGIN_STATUS.logged_out
		return
	_gameNetPrint("OTP Verified! Logged In!")
	var json = JSON.parse_string(_body.get_string_from_utf8())
	session_token = json["token"]
	PlayerData.update_from_server_payload(json["profile"])
	_save_local_session()
	login_status = LOGIN_STATUS.logged_in
