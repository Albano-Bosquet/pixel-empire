class_name UpdateChecker
extends Node
## Looks up the latest GitHub release of the game and, on request, downloads
## its installer and launches it (the installer updates the game in place;
## the game quits so its files can be replaced). Data: update_settings.json.
##
## States: IDLE -> CHECKING -> (UP_TO_DATE | AVAILABLE | FAILED)
##         AVAILABLE -> DOWNLOADING -> (LAUNCHED | FAILED)

signal state_changed(state: State)

enum State { IDLE, CHECKING, UP_TO_DATE, AVAILABLE, DOWNLOADING, LAUNCHED, FAILED }

const SETTINGS := "res://assets/data/update_settings.json"

var state: State = State.IDLE
## Version of the newest release (without the leading "v"), once known.
var latest_version := ""
## Installer download URL and file name of the newest release.
var installer_url := ""
var installer_name := ""
var _cfg: Dictionary = {}
var _http: HTTPRequest


func _ready() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
	_cfg = raw if raw is Dictionary else {}


## The running game's version (project setting application/config/version).
static func current_version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## Compares dotted versions ("1.2.0" vs "v1.10"): -1, 0 or 1. Missing parts are 0.
static func compare_versions(a: String, b: String) -> int:
	var pa := a.trim_prefix("v").split(".")
	var pb := b.trim_prefix("v").split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return 1 if x > y else -1
	return 0


## Picks the installer asset from a GitHub release JSON: {"version", "url", "name"},
## or an empty dictionary when the release has no installer.
static func parse_release(release: Dictionary, prefix: String, suffix: String) -> Dictionary:
	var tag := String(release.get("tag_name", ""))
	if tag == "":
		return {}
	for a in release.get("assets", []):
		var n := String(a.get("name", ""))
		if n.begins_with(prefix) and n.ends_with(suffix):
			return {"version": tag.trim_prefix("v"), "url": String(a.get("browser_download_url", "")), "name": n}
	return {}


## Asks GitHub for the latest release (asynchronous; watch `state_changed`).
func check() -> void:
	if state == State.CHECKING or state == State.DOWNLOADING:
		return
	_set_state(State.CHECKING)
	_http = _new_request()
	_http.timeout = float(_cfg.get("check_timeout", 10.0))
	_http.request_completed.connect(_on_checked)
	var err := _http.request(String(_cfg.get("latest_release_api", "")), _headers(["Accept: application/vnd.github+json"]))
	if err != OK:
		_set_state(State.FAILED)


## Downloads the installer of the newest release, runs it and quits the game.
func download_and_install() -> void:
	if state != State.AVAILABLE:
		return
	_set_state(State.DOWNLOADING)
	var dir := String(_cfg.get("download_dir", "user://updates"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := dir.path_join(installer_name)
	_http = _new_request()
	_http.download_file = path
	_http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		_http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			_set_state(State.FAILED)
			return
		var pid := OS.create_process(ProjectSettings.globalize_path(path), [])
		if pid <= 0:
			_set_state(State.FAILED)
			return
		_set_state(State.LAUNCHED)
		get_tree().quit())
	if _http.request(installer_url, _headers([])) != OK:
		_set_state(State.FAILED)


## Download progress 0..1 (0 when the size is not known yet).
func progress() -> float:
	if state != State.DOWNLOADING or _http == null or not is_instance_valid(_http) or _http.get_body_size() <= 0:
		return 0.0
	return float(_http.get_downloaded_bytes()) / float(_http.get_body_size())


func _on_checked(result: int, code: int, _headers_in: PackedStringArray, body: PackedByteArray) -> void:
	_http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_set_state(State.FAILED)
		return
	var raw: Variant = JSON.parse_string(body.get_string_from_utf8())
	var info := parse_release(raw if raw is Dictionary else {}, String(_cfg.get("installer_prefix", "")), String(_cfg.get("installer_suffix", ".exe")))
	if info.is_empty():
		_set_state(State.FAILED)
		return
	latest_version = info["version"]
	installer_url = info["url"]
	installer_name = info["name"]
	_set_state(State.AVAILABLE if compare_versions(latest_version, current_version()) > 0 else State.UP_TO_DATE)


func _new_request() -> HTTPRequest:
	var r := HTTPRequest.new()
	add_child(r)
	return r


func _headers(extra: Array) -> PackedStringArray:
	var h := PackedStringArray(["User-Agent: " + String(_cfg.get("user_agent", "PixelEmpire"))])
	for e in extra:
		h.append(e)
	return h


func _set_state(s: State) -> void:
	state = s
	state_changed.emit(s)
