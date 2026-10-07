extends Node

## Autoload `NetSession`: the live multiplayer connection.
##
## Topology: one host (authoritative for the shared world, battle arbitration,
## storage, usernames and guest profiles) and its guests over ENet.
##
## Modes (chosen by the host when opening the game):
## - co-op (default): everyone walks their own rooms of the host's current
##   floor and fights their own battles; the host leads floor changes.
## - follow: guests stand in the host's room and watch every battle.
## - versus: a race. Everyone (host included) runs their own fresh copy of the
##   tower with their own keys, stars and seals; nothing is shared but presence.
## Player caps: duo (2, with optional double battles against trainers) or
## unlimited. Arena challenges and double battles ask the other player first.
##
## Guests play with a profile the host keeps per username (team, gems, money;
## in versus the whole run), created on first join from the guest's own save
## or from fresh starters. The host can forget a saved username.
##
## Traffic classes (one ENet channel each, so a burst on one never delays another):
## - presence: unreliable-ordered 15 Hz position samples, interpolated on arrival
## - world:    reliable, sent only when a fingerprint changes; guests send deltas
## - battle:   reliable lockstep commands; every machine runs the same engine

signal status_changed
signal notice(text: String)
signal join_finished(ok: bool, message: String)
signal disconnected(reason: String)
## Guest: host world applied. Host: a guest edited the world.
signal world_changed(from_remote: bool)
## Everyone except the battler: a battle started that this machine must show.
signal battle_spec_received(spec: Dictionary)
signal battle_command_received(battle_key: String, command: Dictionary)
signal battle_aborted(battle_key: String, reason: String)
signal battle_snapshot_received(battle_key: String, revision: int, snapshot: Dictionary)
## This player is asked something (arena challenge, double battle invite).
## Answer with answer_prompt(prompt_id, accepted).
signal prompt_requested(prompt_id: int, kind: String, from_peer: int, text: String)
## The question expired or was withdrawn before an answer.
signal prompt_closed(prompt_id: int)
## Versus host: the game switched between its campaign and its race state.
signal campaign_replaced

enum Mode { OFFLINE, HOST, GUEST }

const PROTOCOL_VERSION := 4
const MODE_COOP := "coop"
const MODE_FOLLOW := "follow"
const MODE_VERSUS := "versus"
## Duo (2) or unlimited (0, up to ENet's own ceiling).
const DEFAULT_SETTINGS := {"mode": MODE_COOP, "allow_import": true, "max_players": 0, "double_battles": true}
const PLAYER_CAPS: Array[int] = [2, 0]
const ENET_MAX_PEERS := 4095
## How long a challenged/invited player has to answer.
const PROMPT_SECONDS := 15.0
## Guest profile IDs live above the three real save slots.
const GUEST_ID_SLOT_BASE := 100
const PROFILE_SEND_INTERVAL := 1.0
const PROFILE_WRITE_INTERVAL := 2.0
const DEFAULT_PORT := 7777
const MAX_NAME_LENGTH := 16
const PRESENCE_INTERVAL := 1.0 / 15.0
const PRESENCE_KEEPALIVE := 1.0
const INTERPOLATION_DELAY_MSEC := 110
const TELEPORT_DISTANCE := 260.0
const WORLD_POLL_INTERVAL := 0.1
const REQUEST_TIMEOUT := 6.0
const PREFS_PATH := "user://multiplayer.cfg"
const CHANNEL_WORLD := 0
const CHANNEL_PRESENCE := 1
const CHANNEL_BATTLE := 2
const NAME_COLORS: Array[Color] = [
	Color8(255, 236, 140), Color8(140, 220, 255), Color8(255, 160, 200), Color8(160, 255, 170),
	Color8(255, 190, 120), Color8(200, 170, 255), Color8(255, 255, 255), Color8(120, 255, 230),
]
const SNAPSHOT_HISTORY := 12

var mode: Mode = Mode.OFFLINE
## Why the last session ended, for the disconnect screen: "closed" (the host
## closed their game), "lost" (the connection dropped), or "" (we left).
var last_disconnect_kind := ""
## Guest: the host announced it is closing, so the drop that follows is not a loss.
var _host_closing := false
var local_name := ""
## peer_id -> {"name", "gender", "color"}; includes the local player.
var players: Dictionary = {}
## Guest: the room/location the host stands in. The guest follows it.
var host_room_id: StringName = &""
var host_location: Dictionary = {}
## Host-arbitrated battle in progress: {"key","kind","owner","participants","label"}.
var battle_lock: Dictionary = {}
## Host-arbitrated Minion Keeper lock: peer id or 0.
var storage_holder := 0
## Host's choices, sent to every guest: {"mode", "allow_import"}.
var settings: Dictionary = DEFAULT_SETTINGS.duplicate()
## Guest: how the host set up our team on join ("returning", "imported", "fresh", "fresh_blocked").
var join_profile_status := ""

var _peer: ENetMultiplayerPeer
var _runtime: Node
var _pending_join: Dictionary = {}
var _presence: Dictionary = {} # peer_id -> {"room", "samples": [[msec, Vector2]], "pose", "walking", "left"}
var _local_presence: Array = []
var _presence_timer := 0.0
var _presence_keepalive := 0.0
var _world_timer := 0.0
var _last_world_fingerprint := 0
var _guest_world_base: Dictionary = {}
var _guest_world_base_fingerprint := 0
var _profiles := MultiplayerGuestProfiles.new()
var _profile_timer := 0.0
var _last_profile_fingerprint := 0
var _local_status: Dictionary = {}
## Host: questions waiting for an answer: prompt_id -> {"target", "callback"}.
var _prompts: Dictionary = {}
var _prompt_sequence := 0
## Versus host: the real campaign slot to reload when the race is closed.
var _host_real_slot := 0
var _host_profile_timer := 0.0
## Last known own peer id, answered while the connection is opening or closing.
var _local_id := 1
## Peers being closed gracefully: [{"peer", "deadline"}], polled until drained.
var _retiring: Array[Dictionary] = []
const RETIRE_TIMEOUT_MSEC := 1500
var _request_sequence := 0
var _request_replies: Dictionary = {}
var _last_process_usec := 0
var _battle_sequence := 0
var _released_participants: Dictionary = {}
var _pvp_pending: Dictionary = {}
var _snapshot_history: Dictionary = {} # revision -> snapshot, for the active battle
var _snapshot_battle_key := ""
## Every command of the current battle, so a battle scene that subscribes late
## (after its screen fade) still replays the opening turns.
var _command_log: Array[Dictionary] = []
var _color_cursor := 0
var _bound_port := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_runtime = get_node_or_null("/root/CampaignRuntime")
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# --- Public state --------------------------------------------------------------

func is_active() -> bool: return mode != Mode.OFFLINE
func is_host() -> bool: return mode == Mode.HOST
func is_guest() -> bool: return mode == Mode.GUEST
func local_peer_id() -> int:
	var peer := multiplayer.multiplayer_peer
	if not is_active() or peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return _local_id
	_local_id = multiplayer.get_unique_id()
	return _local_id

func player_name(peer_id: int) -> String:
	return String(players.get(peer_id, {}).get("name", "Player %d" % peer_id))

func player_color(peer_id: int) -> Color:
	return NAME_COLORS[int(players.get(peer_id, {}).get("color", 0)) % NAME_COLORS.size()]

func other_player_ids() -> Array[int]:
	var ids: Array[int] = []
	for id in players:
		if int(id) != local_peer_id():
			ids.append(int(id))
	ids.sort()
	return ids

func battle_in_progress() -> bool:
	return not battle_lock.is_empty()

func is_coop() -> bool: return String(settings.get("mode", MODE_COOP)) == MODE_COOP
func is_follow() -> bool: return is_active() and String(settings.get("mode", MODE_COOP)) == MODE_FOLLOW
func is_versus() -> bool: return is_active() and String(settings.get("mode", MODE_COOP)) == MODE_VERSUS
## Shared host world (co-op and follow); versus players each have their own.
func shares_world() -> bool: return is_active() and not is_versus()
func max_players() -> int: return int(settings.get("max_players", 0))
func double_battles_enabled() -> bool: return max_players() == 2 and bool(settings.get("double_battles", true))

## True while that player is in any battle (trainer, arena, or watching one).
func player_battling(peer_id: int) -> bool:
	return bool(players.get(peer_id, {}).get("battling", false)) or peer_id in battle_lock.get("participants", [])

## Where a player is: {"floor": global floor index, "lobby": bool, "room": id}.
func player_location(peer_id: int) -> Dictionary:
	return (players.get(peer_id, {}).get("where", {}) as Dictionary)

static func mode_label(mode_id: String) -> String:
	match mode_id:
		MODE_FOLLOW: return "Follow the host"
		MODE_VERSUS: return "Versus"
	return "Co-op"

static func cap_label(cap: int) -> String:
	return "Duo" if cap == 2 else ("Unlimited" if cap <= 0 else "%d players" % cap)

func status_text() -> String:
	var mode_name := mode_label(String(settings.get("mode", MODE_COOP)))
	if max_players() == 2:
		mode_name += ", duo"
	match mode:
		Mode.HOST: return "Hosting (%s) · port %d" % [mode_name, _bound_port]
		Mode.GUEST: return "%s's game (%s)" % [player_name(1), mode_name]
	return ""

func load_prefs() -> Dictionary:
	var config := ConfigFile.new()
	config.load(PREFS_PATH)
	return {
		"username": String(config.get_value("multiplayer", "username", "")),
		"host_port": int(config.get_value("multiplayer", "host_port", DEFAULT_PORT)),
		"join_address": String(config.get_value("multiplayer", "join_address", "127.0.0.1")),
		"join_port": int(config.get_value("multiplayer", "join_port", DEFAULT_PORT)),
		"join_slot": int(config.get_value("multiplayer", "join_slot", 1)),
		"join_fresh_gender": String(config.get_value("multiplayer", "join_fresh_gender", "")),
		"host_mode": String(config.get_value("multiplayer", "host_mode", MODE_COOP)),
		"host_allow_import": bool(config.get_value("multiplayer", "host_allow_import", true)),
		"host_max_players": int(config.get_value("multiplayer", "host_max_players", 0)),
		"host_double_battles": bool(config.get_value("multiplayer", "host_double_battles", true)),
	}

func save_prefs(values: Dictionary) -> void:
	var config := ConfigFile.new()
	config.load(PREFS_PATH)
	for key in values:
		config.set_value("multiplayer", String(key), values[key])
	config.save(PREFS_PATH)

static func validate_username(raw: String) -> String:
	var name := raw.strip_edges()
	if name.is_empty():
		return "Choose a username."
	if name.length() > MAX_NAME_LENGTH:
		return "Usernames are at most %d characters." % MAX_NAME_LENGTH
	var allowed := RegEx.create_from_string("^[A-Za-z0-9 _\\-]+$")
	if allowed.search(name) == null:
		return "Use letters, numbers, spaces, - or _."
	return ""

static func local_addresses() -> PackedStringArray:
	var result := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.count(".") == 3 and not address.begins_with("127.") and not address.begins_with("169.254."):
			result.append(address)
	return result

# --- Hosting / joining -----------------------------------------------------------

func host(port: int, username: String, options: Dictionary = {}) -> Dictionary:
	if is_active():
		return {"ok": false, "message": "Already in a multiplayer session."}
	var name_error := validate_username(username)
	if not name_error.is_empty():
		return {"ok": false, "message": name_error}
	if port < 1024 or port > 65535:
		return {"ok": false, "message": "Pick a port between 1024 and 65535."}
	if _session_state() == null:
		return {"ok": false, "message": "Load a campaign before hosting."}
	var chosen := DEFAULT_SETTINGS.duplicate()
	for key in options:
		if chosen.has(key): chosen[key] = options[key]
	if int(chosen.max_players) not in PLAYER_CAPS:
		chosen["max_players"] = 0
	var cap := int(chosen.max_players)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, cap - 1 if cap > 0 else ENET_MAX_PEERS, 3)
	if error != OK:
		return {"ok": false, "message": "Could not open port %d (%s). Is it already in use?" % [port, error_string(error)]}
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	_peer = peer
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	_bound_port = port
	settings = chosen
	var world_id := _ensure_world_id()
	_profiles.open(world_id + ("-versus" if is_versus() else ""))
	local_name = username.strip_edges()
	players.clear()
	_color_cursor = 0
	players[1] = {"name": local_name, "gender": _local_gender(), "color": _next_color(), "battling": false}
	battle_lock.clear()
	storage_holder = 0
	_last_world_fingerprint = 0
	if is_versus():
		var raced := _enter_host_race()
		if not raced.get("ok", false):
			leave()
			return raced
	save_prefs({"username": local_name, "host_port": port, "host_mode": String(settings.mode), "host_allow_import": bool(settings.allow_import), "host_max_players": cap, "host_double_battles": bool(settings.double_battles)})
	status_changed.emit()
	return {"ok": true}

## Versus host: swap the real campaign for the host's own race state (its
## save slot is not written meanwhile); leave() reloads the real campaign.
func _enter_host_race() -> Dictionary:
	var real = _session_state()
	_host_real_slot = int(_runtime.session.save_slot)
	var request := {
		"character": {"name": String(real.character.get("name", local_name)), "gender": String(real.character.get("gender", "male")).to_lower()},
		"import": real.to_dictionary(_content_version()),
		"seen": {},
	}
	for key in real.progression:
		if String(key).ends_with("_seen") and real.progression[key] == true:
			request.seen[String(key)] = true
	var setup := _guest_profile_for(local_name, request)
	var loaded: Dictionary = _runtime.load_detached_campaign(setup.profile.state, GUEST_ID_SLOT_BASE + int(setup.number), _host_race_redirect)
	if not loaded.get("ok", false):
		_runtime.load_campaign(_host_real_slot)
		_host_real_slot = 0
		return {"ok": false, "message": "The race could not start: %s" % loaded.get("message", "unknown error")}
	join_profile_status = String(setup.status)
	campaign_replaced.emit()
	return {"ok": true}

func _host_race_redirect(_payload: Dictionary) -> Dictionary:
	return {"ok": true} # Stored with the other racers in _process.

## Versus host leaving: back to the real campaign.
func _leave_host_race() -> void:
	if _host_real_slot <= 0 or _runtime == null:
		return
	var slot := _host_real_slot
	_host_real_slot = 0
	join_profile_status = ""
	_runtime.load_campaign(slot)
	campaign_replaced.emit()

## True while the versus host plays its race state instead of its campaign.
func host_in_race() -> bool:
	return _host_real_slot > 0

## Host: change the duo double-battle option.
func set_double_battles(enabled: bool) -> void:
	settings["double_battles"] = enabled
	save_prefs({"host_double_battles": enabled})
	if is_host():
		_rpc_settings.rpc(settings)
	status_changed.emit()

## Host: everyone the current world (or race) keeps a profile for.
## [{"key", "name", "number", "has_team", "online"}]
func saved_profiles() -> Array[Dictionary]:
	var online: Dictionary = {}
	for id in players:
		online[MultiplayerGuestProfiles.key_for(player_name(int(id)))] = true
	var result: Array[Dictionary] = []
	for entry in _profiles.listing():
		entry["online"] = online.has(String(entry.key))
		result.append(entry)
	return result

## Host: drop a username's kept team. Its next join is a first visit again.
func forget_profile(username: String) -> Dictionary:
	if not is_host():
		return {"ok": false, "message": "Only the host keeps teams."}
	for id in players:
		if MultiplayerGuestProfiles.key_for(player_name(int(id))) == MultiplayerGuestProfiles.key_for(username):
			return {"ok": false, "message": "%s is playing right now." % player_name(int(id))}
	_profiles.forget(username)
	_profiles.save()
	status_changed.emit()
	return {"ok": true}

## Host: change who may bring a team from their own save (newcomers only).
func set_allow_import(allowed: bool) -> void:
	settings["allow_import"] = allowed
	save_prefs({"host_allow_import": allowed})
	if is_host():
		_rpc_settings.rpc(settings)
	status_changed.emit()

@rpc("authority", "call_remote", "reliable", CHANNEL_WORLD)
func _rpc_settings(values: Dictionary) -> void:
	settings = values.duplicate()
	status_changed.emit()

## The host world's ID names its guest-profile file. Created once, saved with
## the host campaign, and never shared (it is a personal progression key).
func _ensure_world_id() -> String:
	var state = _session_state()
	var id := String(state.progression.get("multiplayer_world_id", ""))
	if id.is_empty():
		id = Crypto.new().generate_random_bytes(8).hex_encode()
		state.progression["multiplayer_world_id"] = id
		if _runtime != null:
			_runtime.save_campaign()
	return id

## Connects and handshakes; join_finished reports the outcome. `team` says
## what to play with on a first visit: {"slot": n} brings the party, gems and
## money of that save (if the host allows it), {"fresh": true, "gender": g}
## starts with the new-campaign starters. A returning username always gets
## the team the host kept for it. The guest's own saves are never written.
func join(address: String, port: int, username: String, team: Dictionary) -> Dictionary:
	if is_active():
		return {"ok": false, "message": "Already in a multiplayer session."}
	var name_error := validate_username(username)
	if not name_error.is_empty():
		return {"ok": false, "message": name_error}
	address = address.strip_edges()
	if address.is_empty():
		return {"ok": false, "message": "Enter the host's IP address."}
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port, 3)
	if error != OK:
		return {"ok": false, "message": "Could not reach %s:%d (%s)." % [address, port, error_string(error)]}
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	_peer = peer
	multiplayer.multiplayer_peer = peer
	mode = Mode.GUEST
	local_name = username.strip_edges()
	_pending_join = {"request": _join_request(team)}
	var prefs := {"username": local_name, "join_address": address, "join_port": port}
	if team.has("slot"): prefs["join_slot"] = int(team.slot)
	prefs["join_fresh_gender"] = String(team.get("gender", "")) if bool(team.get("fresh", false)) else ""
	save_prefs(prefs)
	get_tree().create_timer(8.0).timeout.connect(func() -> void:
		if not _pending_join.is_empty() and mode == Mode.GUEST:
			_fail_join("The host did not answer. Check the IP, the port, and that the host opened their game.")
	)
	status_changed.emit()
	return {"ok": true}

## What the host needs to set up our team if it has none for this username.
## Tutorials already seen in any of our saves stay seen in the new profile.
func _join_request(team: Dictionary) -> Dictionary:
	var seen: Dictionary = {}
	var chosen: Dictionary = {}
	if _runtime != null and _runtime.session != null:
		for slot in range(1, SaveRepository.SLOT_COUNT + 1):
			var loaded: Dictionary = _runtime.session.save_repository.load_slot(slot)
			if not loaded.get("ok", false):
				continue
			for key in loaded.state.get("progression", {}):
				if String(key).ends_with("_seen") and loaded.state.progression[key] == true:
					seen[String(key)] = true
			if team.has("slot") and int(team.slot) == slot:
				chosen = loaded.state
	if not chosen.is_empty():
		var character: Dictionary = chosen.get("character", {})
		return {
			"character": {"name": String(character.get("name", local_name)), "gender": String(character.get("gender", "male")).to_lower()},
			"import": {"character": character, "party": chosen.get("party", []), "owned_gems": chosen.get("owned_gems", []), "progression": chosen.get("progression", {})},
			"seen": seen,
		}
	var gender := String(team.get("gender", "male")).to_lower()
	return {"character": {"name": local_name, "gender": "female" if gender == "female" else "male"}, "import": {}, "seen": seen}

func leave(reason: String = "") -> void:
	if not is_active():
		return
	var was_guest := is_guest()
	if was_guest:
		_flush_guest_world()
		_send_profile(true)
	elif is_host():
		_store_host_race()
		_profiles.save_if_dirty()
		# Sent before the reliable queue drains, so guests know it was on purpose.
		_rpc_host_closing.rpc()
	if _peer != null:
		_retire_peer(_peer)
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_reset()
	if was_guest:
		_end_guest_session()
	else:
		_leave_host_race()
	status_changed.emit()
	if not reason.is_empty():
		disconnected.emit(reason)

## Close a connection without losing what is still queued on it (the last
## battle command, world delta or profile): ENet's disconnect_later waits for
## the outgoing reliable queue to drain, so the old peer is polled until every
## connection has closed, then released.
func _retire_peer(peer: ENetMultiplayerPeer) -> void:
	if peer.host == null:
		peer.close()
		return
	for connection in peer.host.get_peers():
		connection.peer_disconnect_later()
	_retiring.append({"peer": peer, "deadline": Time.get_ticks_msec() + RETIRE_TIMEOUT_MSEC})

func _poll_retiring() -> void:
	for index in range(_retiring.size() - 1, -1, -1):
		var entry: Dictionary = _retiring[index]
		var peer: ENetMultiplayerPeer = entry.peer
		var open := false
		if peer.host != null:
			peer.poll()
			for connection in peer.host.get_peers():
				open = open or connection.get_state() != ENetPacketPeer.STATE_DISCONNECTED
		if not open or Time.get_ticks_msec() > int(entry.deadline):
			peer.close()
			_retiring.remove_at(index)

func _reset() -> void:
	mode = Mode.OFFLINE
	_host_closing = false
	_peer = null
	players.clear()
	_presence.clear()
	battle_lock.clear()
	storage_holder = 0
	host_room_id = &""
	host_location.clear()
	settings = DEFAULT_SETTINGS.duplicate()
	_local_status.clear()
	_local_id = 1
	for prompt_id in _prompts.keys():
		prompt_closed.emit(prompt_id)
	_prompts.clear()
	_pending_join.clear()
	_pvp_pending.clear()
	_released_participants.clear()
	_snapshot_history.clear()
	_guest_world_base.clear()
	for request_id in _request_replies.keys():
		_request_replies[request_id] = {"ok": false, "message": "Disconnected."}

func _on_connected_to_server() -> void:
	_rpc_hello.rpc_id(1, PROTOCOL_VERSION, _content_version(), local_name, _pending_join.get("request", {}))

func _on_connection_failed() -> void:
	_fail_join("Could not connect. Check the IP and port, and that the host's firewall allows it.")

func _fail_join(message: String) -> void:
	if mode != Mode.GUEST:
		return
	_pending_join.clear()
	if _peer != null:
		_retire_peer(_peer)
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_reset()
	status_changed.emit()
	join_finished.emit(false, message)

func _on_server_disconnected() -> void:
	var host := player_name(1)
	if _host_closing:
		last_disconnect_kind = "closed"
		leave("%s closed their game." % host)
	else:
		last_disconnect_kind = "lost"
		leave("The connection to %s's game was lost." % host)

@rpc("authority", "call_remote", "reliable", CHANNEL_WORLD)
func _rpc_host_closing() -> void:
	_host_closing = true

func _on_peer_connected(_peer_id: int) -> void:
	pass # Guests are only registered once their hello is accepted.

func _on_peer_disconnected(peer_id: int) -> void:
	if not is_host() or not players.has(peer_id):
		return
	var name := player_name(peer_id)
	players.erase(peer_id)
	_presence.erase(peer_id)
	_profiles.save_if_dirty()
	if storage_holder == peer_id:
		storage_holder = 0
	for prompt_id in _prompts.keys():
		if int(_prompts[prompt_id].target) == peer_id:
			_finish_prompt(prompt_id, false, {}, "left")
	if not battle_lock.is_empty() and peer_id in battle_lock.get("participants", []):
		_abort_battle("%s disconnected." % name)
	_broadcast_players()
	notice.emit("%s left the game." % name)
	_rpc_notice.rpc("%s left the game." % name)

@rpc("any_peer", "call_remote", "reliable", CHANNEL_WORLD)
func _rpc_hello(protocol: int, content_version: String, username: String, request: Dictionary) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	var rejection := ""
	if protocol != PROTOCOL_VERSION or content_version != _content_version():
		rejection = "Version mismatch: the host runs a different build of the game."
	elif not validate_username(username).is_empty():
		rejection = validate_username(username)
	elif max_players() > 0 and players.size() >= max_players():
		rejection = "The game is full (%s)." % cap_label(max_players())
	else:
		for existing in players.values():
			if String(existing.name).to_lower() == username.strip_edges().to_lower():
				rejection = "The username \"%s\" is already taken in this game." % username.strip_edges()
	if not rejection.is_empty():
		_rpc_rejected.rpc_id(sender, rejection)
		# Give the reliable rejection time to arrive before dropping the peer.
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if _peer != null and is_host() and sender in multiplayer.get_peers(): _peer.disconnect_peer(sender)
		)
		return
	var setup := _guest_profile_for(username.strip_edges(), request)
	var profile: Dictionary = setup.profile
	var guest_state: Dictionary
	var world: Dictionary = {}
	var state = _session_state()
	if is_versus():
		guest_state = profile.state
	else:
		guest_state = MultiplayerWorldSync.guest_state_payload(state.to_dictionary(_content_version()), profile)
		world = MultiplayerWorldSync.extract_world(state)
	var gender := String(guest_state.get("character", {}).get("gender", "male")).to_lower()
	players[sender] = {"name": username.strip_edges(), "gender": gender, "color": _next_color(), "battling": false}
	_rpc_welcome.rpc_id(sender, players, guest_state, world, _host_location_payload(), battle_lock, settings, {"status": setup.status, "number": setup.number})
	_broadcast_players()
	var message := "%s joined the game." % player_name(sender)
	notice.emit(message)
	_rpc_notice.rpc(message)

## Host: the team a guest plays with. A known username gets its kept profile;
## a newcomer brings their save's team (if allowed) or starts fresh.
func _guest_profile_for(username: String, request: Dictionary) -> Dictionary:
	var number := _profiles.number_for(username)
	if _profiles.has_profile(username):
		var kept := _profiles.profile(username)
		var kept_party: Array = kept.get("state", {}).get("party", []) if is_versus() else kept.get("party", [])
		if not kept_party.is_empty():
			return {"profile": kept, "status": "returning", "number": number}
	var character: Dictionary = request.get("character", {"name": username, "gender": "male"})
	var imported: Dictionary = request.get("import", {})
	var status := "fresh"
	var profile: Dictionary = {}
	if not imported.is_empty():
		if bool(settings.get("allow_import", true)):
			profile = MultiplayerWorldSync.profile_from_save(imported, "mp%d-" % number)
			var party_size := (profile.party as Array).size()
			if party_size >= 1 and party_size <= 5:
				status = "imported"
				if (profile.character as Dictionary).is_empty():
					profile["character"] = character
			else:
				profile = {}
		else:
			status = "fresh_blocked"
	if profile.is_empty():
		profile = MultiplayerWorldSync.fresh_profile(_runtime.catalog, character, "slot-%d-" % (GUEST_ID_SLOT_BASE + number))
	for key in request.get("seen", {}):
		if String(key).ends_with("_seen"):
			profile.progression[String(key)] = true
	if is_versus():
		# A racer's profile is the whole run, started fresh at the tower's door.
		profile = {"state": MultiplayerWorldSync.race_state_payload(_runtime.catalog, _session_state().campaign_id, profile, _race_seed(), _content_version())}
	_profiles.store(username, profile)
	_profiles.save()
	return {"profile": profile, "status": status, "number": number}

@rpc("authority", "call_remote", "reliable", CHANNEL_WORLD)
func _rpc_rejected(reason: String) -> void:
	_fail_join(reason)

@rpc("authority", "call_remote", "reliable", CHANNEL_WORLD)
func _rpc_welcome(roster: Dictionary, guest_state: Dictionary, world: Dictionary, location: Dictionary, lock: Dictionary, host_settings: Dictionary, info: Dictionary) -> void:
	if _pending_join.is_empty():
		return
	_pending_join.clear()
	_local_status.clear()
	players = roster
	battle_lock = lock
	settings = host_settings.duplicate()
	join_profile_status = String(info.get("status", ""))
	var loaded: Dictionary = _runtime.load_detached_campaign(guest_state, GUEST_ID_SLOT_BASE + int(info.get("number", 0)), _guest_save_redirect) if _runtime != null else {"ok": false, "message": "runtime unavailable"}
	if not loaded.get("ok", false):
		leave()
		join_finished.emit(false, "The host's world could not be loaded: %s" % loaded.get("message", "unknown error"))
		return
	if shares_world():
		_apply_host_world(world, location, true)
	_last_profile_fingerprint = MultiplayerWorldSync.fingerprint(_local_profile())
	status_changed.emit()
	join_finished.emit(true, "")

@rpc("authority", "call_remote", "reliable", CHANNEL_WORLD)
func _rpc_players(roster: Dictionary) -> void:
	players = roster
	for id in _presence.keys():
		if not players.has(id):
			_presence.erase(id)
	status_changed.emit()

@rpc("authority", "call_remote", "reliable", CHANNEL_WORLD)
func _rpc_notice(text: String) -> void:
	notice.emit(text)

func _broadcast_players() -> void:
	_rpc_players.rpc(players)
	status_changed.emit()

func _next_color() -> int:
	_color_cursor += 1
	return _color_cursor - 1

# --- Presence -------------------------------------------------------------------------

## Called every frame by the shell while the local player explores a room.
func update_local_presence(room_id: StringName, position: Vector2, presence: Dictionary) -> void:
	_local_presence = [String(room_id), position.x, position.y, String(presence.get("pose", "front")), bool(presence.get("walking", false)), bool(presence.get("left", false))]

func clear_local_presence() -> void:
	if not _local_presence.is_empty():
		_local_presence = []
		if is_active():
			_rpc_presence.rpc([])

@rpc("any_peer", "call_remote", "unreliable_ordered", CHANNEL_PRESENCE)
func _rpc_presence(sample: Array) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender):
		return
	if sample.size() < 6:
		_presence.erase(sender)
		return
	var entry: Dictionary = _presence.get(sender, {"samples": []})
	var position := Vector2(float(sample[1]), float(sample[2]))
	var samples: Array = entry.samples
	if String(entry.get("room", "")) != String(sample[0]):
		samples.clear() # A new room never interpolates from the old one.
	samples.append([Time.get_ticks_msec(), position])
	while samples.size() > 8:
		samples.pop_front()
	entry["room"] = String(sample[0])
	entry["pose"] = String(sample[3])
	entry["walking"] = bool(sample[4])
	entry["left"] = bool(sample[5])
	entry["samples"] = samples
	_presence[sender] = entry

## Interpolated view of a remote player, rendered INTERPOLATION_DELAY_MSEC in
## the past so 15 Hz samples always have a pair to blend between.
func presence_of(peer_id: int) -> Dictionary:
	var entry: Dictionary = _presence.get(peer_id, {})
	var samples: Array = entry.get("samples", [])
	if samples.is_empty():
		return {}
	var render_time := Time.get_ticks_msec() - INTERPOLATION_DELAY_MSEC
	var position: Vector2 = samples[-1][1]
	for index in range(samples.size() - 1, 0, -1):
		var older: Array = samples[index - 1]
		var newer: Array = samples[index]
		if int(older[0]) <= render_time:
			var span := maxf(1.0, float(newer[0] - older[0]))
			var weight := clampf(float(render_time - int(older[0])) / span, 0.0, 1.0)
			var from: Vector2 = older[1]
			var to: Vector2 = newer[1]
			position = to if from.distance_to(to) > TELEPORT_DISTANCE else from.lerp(to, weight)
			break
		position = older[1]
	return {"room": StringName(entry.room), "position": position, "pose": StringName(entry.pose), "walking": bool(entry.walking), "left": bool(entry.left)}

# --- Per-frame work ---------------------------------------------------------------

func _process(scaled_delta: float) -> void:
	# A paused or slowed battle replay (Engine.time_scale below 1) must never
	# slow presence, world sync or saving: never count less than real time.
	var now := Time.get_ticks_usec()
	var real_delta := 0.0 if _last_process_usec == 0 else float(now - _last_process_usec) / 1000000.0
	_last_process_usec = now
	var delta := maxf(scaled_delta, real_delta)
	if not _retiring.is_empty():
		_poll_retiring()
	if not is_active() or not _pending_join.is_empty():
		return
	_presence_timer += delta
	_presence_keepalive += delta
	if _presence_timer >= PRESENCE_INTERVAL and not _local_presence.is_empty():
		_presence_timer = 0.0
		var signature := hash(_local_presence)
		if signature != int(get_meta("last_presence", 0)) or _presence_keepalive >= PRESENCE_KEEPALIVE:
			set_meta("last_presence", signature)
			_presence_keepalive = 0.0
			_rpc_presence.rpc(_local_presence)
	_world_timer += delta
	if _world_timer >= WORLD_POLL_INTERVAL and shares_world():
		_world_timer = 0.0
		if is_host():
			_broadcast_world_if_changed()
		elif is_guest():
			_flush_guest_world()
	_profile_timer += delta
	if is_guest() and _profile_timer >= PROFILE_SEND_INTERVAL:
		_profile_timer = 0.0
		_send_profile()
	elif is_host() and _profile_timer >= PROFILE_WRITE_INTERVAL:
		_profile_timer = 0.0
		_store_host_race()
		_profiles.save_if_dirty()

# --- Shared world ----------------------------------------------------------------------

func _broadcast_world_if_changed(force: bool = false) -> void:
	var state = _session_state()
	if state == null:
		return
	var world := MultiplayerWorldSync.extract_world(state)
	var location := _host_location_payload()
	var fingerprint := MultiplayerWorldSync.fingerprint([world, String(location.get("room_id", "")), String(location.get("spawn_id", ""))])
	if not force and fingerprint == _last_world_fingerprint:
		return
	_last_world_fingerprint = fingerprint
	_rpc_world.rpc(world, location)

@rpc("authority", "call_remote", "reliable", CHANNEL_WORLD)
func _rpc_world(world: Dictionary, location: Dictionary) -> void:
	if not is_guest() or not shares_world() or _session_state() == null:
		return
	# Send our unsent edits first so they are merged instead of overwritten.
	_flush_guest_world()
	_apply_host_world(world, location)

func _apply_host_world(world: Dictionary, location: Dictionary, joining: bool = false) -> void:
	var state = _session_state()
	# Co-op guests keep their own room; joining always starts beside the host.
	MultiplayerWorldSync.apply_world(state, world, storage_holder != local_peer_id(), joining or is_follow())
	host_room_id = StringName(world.get("current_room_id", ""))
	host_location = location.duplicate(true)
	_guest_world_base = MultiplayerWorldSync.editable_world(MultiplayerWorldSync.extract_world(state))
	_guest_world_base_fingerprint = MultiplayerWorldSync.fingerprint(_guest_world_base)
	world_changed.emit(true)

## Guest: send any world edit made locally (chest, door, battle reward…) as a
## delta. The host merges it, then re-broadcasts the authoritative world.
func _flush_guest_world() -> void:
	var state = _session_state()
	if state == null or _guest_world_base.is_empty():
		return
	var current := MultiplayerWorldSync.editable_world(MultiplayerWorldSync.extract_world(state))
	var fingerprint := MultiplayerWorldSync.fingerprint(current)
	if fingerprint == _guest_world_base_fingerprint:
		return
	var delta: Variant = MultiplayerWorldSync.diff(_guest_world_base, current)
	_guest_world_base = current
	_guest_world_base_fingerprint = fingerprint
	if delta != null:
		_rpc_world_delta.rpc_id(1, delta)

@rpc("any_peer", "call_remote", "reliable", CHANNEL_WORLD)
func _rpc_world_delta(delta: Dictionary) -> void:
	if not is_host() or not shares_world() or not players.has(multiplayer.get_remote_sender_id()):
		return
	var state = _session_state()
	if state == null:
		return
	var world := MultiplayerWorldSync.extract_world(state)
	var edited: Dictionary = MultiplayerWorldSync.merge(MultiplayerWorldSync.editable_world(world), delta)
	world["progression"] = edited.get("progression", world.progression)
	world["room_state"] = edited.get("room_state", world.room_state)
	MultiplayerWorldSync.apply_world(state, world, false)
	world_changed.emit(true)
	_broadcast_world_if_changed()

func _host_location_payload() -> Dictionary:
	var state = _session_state()
	if state == null:
		return {}
	var location: Dictionary = (state.room_state.get("current_location", {}) as Dictionary).duplicate(true)
	location["room_id"] = String(state.current_room_id)
	# Co-op guests adopt the host's checkpoint when the host changes floor.
	location["safe"] = state.safe_location.duplicate(true)
	return location

# --- Guest profile (kept by the host) ----------------------------------------------------

## Every guest save lands here instead of a save slot; the profile itself is
## sent to the host at most once per PROFILE_SEND_INTERVAL (and on leaving).
func _guest_save_redirect(_payload: Dictionary) -> Dictionary:
	return {"ok": true}

## What the host keeps for this player: the personal part of the state, or
## in versus the whole run.
func _local_profile() -> Dictionary:
	var state = _session_state()
	if state == null:
		return {}
	if is_versus():
		return {"state": state.to_dictionary(_content_version())}
	return MultiplayerWorldSync.extract_profile(state)

func _send_profile(force: bool = false) -> void:
	var state = _session_state()
	if not is_guest() or state == null or not _pending_join.is_empty():
		return
	var profile := _local_profile()
	var fingerprint := MultiplayerWorldSync.fingerprint(profile)
	if fingerprint == _last_profile_fingerprint and not force:
		return
	_last_profile_fingerprint = fingerprint
	_rpc_profile.rpc_id(1, profile)

@rpc("any_peer", "call_remote", "reliable", CHANNEL_WORLD)
func _rpc_profile(profile: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not is_host() or not players.has(sender):
		return
	var party: Array = profile.get("state", {}).get("party", []) if is_versus() else profile.get("party", [])
	if party.is_empty():
		return # Never replace a team with nothing.
	_profiles.store(player_name(sender), profile)

## Versus host: keep its own run with the other racers.
func _store_host_race() -> void:
	if not is_host() or not host_in_race() or _session_state() == null:
		return
	var profile := _local_profile()
	var fingerprint := MultiplayerWorldSync.fingerprint(profile)
	if fingerprint != _last_profile_fingerprint:
		_last_profile_fingerprint = fingerprint
		_profiles.store(local_name, profile)

## Every racer's run hands out the same chests.
func _race_seed() -> int:
	if not _profiles.meta.has("race_seed"):
		_profiles.set_meta_value("race_seed", randi())
	return int(_profiles.meta.race_seed)

## Guest left: drop the borrowed world. The next screen is the title screen.
func _end_guest_session() -> void:
	join_profile_status = ""
	if _runtime == null or _runtime.session == null:
		return
	_runtime.session.state = null
	_runtime.session.save_redirect = Callable()

# --- Requests (guest -> host, awaitable) ----------------------------------------------------

func _await_reply(request_id: int, timeout: float = REQUEST_TIMEOUT) -> Dictionary:
	var started := Time.get_ticks_msec()
	while not _request_replies.has(request_id) or _request_replies[request_id] == null:
		if Time.get_ticks_msec() - started > int(timeout * 1000.0) or not is_active():
			_request_replies.erase(request_id)
			return {"ok": false, "message": "The host did not answer in time."}
		await get_tree().process_frame
	var reply: Dictionary = _request_replies[request_id]
	_request_replies.erase(request_id)
	return reply

func _new_request() -> int:
	_request_sequence += 1
	_request_replies[_request_sequence] = null
	return _request_sequence

@rpc("authority", "call_remote", "reliable", CHANNEL_WORLD)
func _rpc_reply(request_id: int, reply: Dictionary) -> void:
	if _request_replies.has(request_id):
		_request_replies[request_id] = reply

func _reply(peer_id: int, request_id: int, reply: Dictionary) -> void:
	if peer_id == 1:
		if _request_replies.has(request_id): _request_replies[request_id] = reply
	else:
		_rpc_reply.rpc_id(peer_id, request_id, reply)

# --- Battles: arbitration ----------------------------------------------------------------

## Ask the host for the single battle slot. Everyone else will watch it.
func request_battle(kind: String, label: String) -> Dictionary:
	if not is_active() or (is_coop() and kind == "trainer"):
		return {"ok": true, "key": ""} # Co-op trainer fights stay on this machine.
	var request_id := _new_request()
	if is_host():
		_handle_battle_request(1, request_id, kind, label)
	else:
		_rpc_request_battle.rpc_id(1, request_id, kind, label)
	return await _await_reply(request_id)

@rpc("any_peer", "call_remote", "reliable", CHANNEL_BATTLE)
func _rpc_request_battle(request_id: int, kind: String, label: String) -> void:
	if is_host():
		_handle_battle_request(multiplayer.get_remote_sender_id(), request_id, kind, label)

func _handle_battle_request(peer_id: int, request_id: int, kind: String, label: String) -> void:
	if not battle_lock.is_empty():
		_reply(peer_id, request_id, {"ok": false, "message": "A battle is already in progress."})
		return
	_battle_sequence += 1
	battle_lock = {"key": "battle-%d" % _battle_sequence, "kind": kind, "owner": peer_id, "participants": [peer_id], "label": label}
	_released_participants.clear()
	_broadcast_lock()
	_reply(peer_id, request_id, {"ok": true, "key": battle_lock.key})

## The battler finished (returned to the room). Frees the slot for everyone.
func release_battle(battle_key: String) -> void:
	if not is_active() or battle_key.is_empty():
		return
	if is_host():
		_handle_release(1, battle_key)
	else:
		_rpc_release_battle.rpc_id(1, battle_key)

@rpc("any_peer", "call_remote", "reliable", CHANNEL_BATTLE)
func _rpc_release_battle(battle_key: String) -> void:
	if is_host():
		_handle_release(multiplayer.get_remote_sender_id(), battle_key)

func _handle_release(peer_id: int, battle_key: String) -> void:
	if String(battle_lock.get("key", "")) != battle_key:
		return
	_released_participants[peer_id] = true
	for participant in battle_lock.get("participants", []):
		if not _released_participants.has(int(participant)) and players.has(int(participant)):
			return
	battle_lock.clear()
	_broadcast_lock()

func _abort_battle(reason: String) -> void:
	var key := String(battle_lock.get("key", ""))
	battle_lock.clear()
	_pvp_pending.clear()
	_broadcast_lock()
	if not key.is_empty():
		battle_aborted.emit(key, reason)
		_rpc_battle_aborted.rpc(key, reason)

@rpc("authority", "call_remote", "reliable", CHANNEL_BATTLE)
func _rpc_battle_aborted(battle_key: String, reason: String) -> void:
	battle_aborted.emit(battle_key, reason)

func _broadcast_lock() -> void:
	_rpc_battle_lock.rpc(battle_lock)
	status_changed.emit()

@rpc("authority", "call_remote", "reliable", CHANNEL_BATTLE)
func _rpc_battle_lock(lock: Dictionary) -> void:
	battle_lock = lock
	status_changed.emit()

# --- Battles: lockstep stream ----------------------------------------------------------

## Battler: publish a battle so every other player starts spectating it.
func publish_battle_spec(spec: Dictionary) -> void:
	if is_active():
		_begin_snapshot_history(String(spec.get("key", "")))
		_rpc_battle_spec.rpc(spec)

@rpc("any_peer", "call_remote", "reliable", CHANNEL_BATTLE)
func _rpc_battle_spec(spec: Dictionary) -> void:
	_begin_snapshot_history(String(spec.get("key", "")))
	battle_spec_received.emit(spec)

## Participant: broadcast an accepted command. `pre_snapshot` is the engine
## snapshot before submitting; receivers compare fingerprints to detect drift.
func send_battle_command(battle_key: String, command: Dictionary, pre_snapshot: Dictionary) -> void:
	if not is_active():
		return
	remember_snapshot(battle_key, int(command.get("revision", 0)), pre_snapshot)
	var payload := command.duplicate(true)
	payload["check"] = MultiplayerWorldSync.fingerprint(pre_snapshot)
	_rpc_battle_command.rpc(battle_key, payload)

@rpc("any_peer", "call_remote", "reliable", CHANNEL_BATTLE)
func _rpc_battle_command(battle_key: String, command: Dictionary) -> void:
	var tagged := command.duplicate(true)
	tagged["sender"] = multiplayer.get_remote_sender_id()
	if battle_key == _snapshot_battle_key:
		_command_log.append(tagged)
	battle_command_received.emit(battle_key, tagged)

func remember_snapshot(battle_key: String, revision: int, snapshot: Dictionary) -> void:
	if battle_key != _snapshot_battle_key:
		_begin_snapshot_history(battle_key)
	_snapshot_history[revision] = snapshot.duplicate(true)
	while _snapshot_history.size() > SNAPSHOT_HISTORY:
		_snapshot_history.erase(_snapshot_history.keys().min())

func _begin_snapshot_history(battle_key: String) -> void:
	if battle_key != _snapshot_battle_key:
		_command_log.clear()
	_snapshot_battle_key = battle_key
	_snapshot_history.clear()

func buffered_battle_commands(battle_key: String) -> Array[Dictionary]:
	return _command_log.duplicate(true) if battle_key == _snapshot_battle_key else [] as Array[Dictionary]

## Receiver detected drift: ask the command's sender for its state at `revision`.
func request_battle_snapshot(battle_key: String, revision: int, from_peer: int) -> void:
	if is_active() and players.has(from_peer):
		_rpc_snapshot_request.rpc_id(from_peer, battle_key, revision)

@rpc("any_peer", "call_remote", "reliable", CHANNEL_BATTLE)
func _rpc_snapshot_request(battle_key: String, revision: int) -> void:
	if battle_key == _snapshot_battle_key and _snapshot_history.has(revision):
		_rpc_snapshot_reply.rpc_id(multiplayer.get_remote_sender_id(), battle_key, revision, _snapshot_history[revision])

@rpc("any_peer", "call_remote", "reliable", CHANNEL_BATTLE)
func _rpc_snapshot_reply(battle_key: String, revision: int, snapshot: Dictionary) -> void:
	battle_snapshot_received.emit(battle_key, revision, snapshot)

# --- PvP arena -------------------------------------------------------------------------

## Challenge another player. Both parties fight with fully restored minions;
## nothing from the battle is written back to either campaign.
func request_pvp(target_peer: int, local_team: Array) -> Dictionary:
	if not is_active():
		return {"ok": false, "message": "Not in a multiplayer game."}
	var request_id := _new_request()
	if is_host():
		_handle_pvp_request(1, request_id, target_peer, local_team)
	else:
		_rpc_request_pvp.rpc_id(1, request_id, target_peer, local_team)
	return await _await_reply(request_id, PROMPT_SECONDS + REQUEST_TIMEOUT)

@rpc("any_peer", "call_remote", "reliable", CHANNEL_BATTLE)
func _rpc_request_pvp(request_id: int, target_peer: int, team: Array) -> void:
	if is_host():
		_handle_pvp_request(multiplayer.get_remote_sender_id(), request_id, target_peer, team)

func _handle_pvp_request(challenger: int, request_id: int, target_peer: int, team: Array) -> void:
	if not battle_lock.is_empty():
		_reply(challenger, request_id, {"ok": false, "message": "A battle is already in progress."})
		return
	if not players.has(target_peer) or target_peer == challenger:
		_reply(challenger, request_id, {"ok": false, "message": "That player is no longer here."})
		return
	if player_battling(target_peer):
		_reply(challenger, request_id, {"ok": false, "message": "%s is in a battle right now." % player_name(target_peer)})
		return
	_battle_sequence += 1
	var key := "battle-%d" % _battle_sequence
	battle_lock = {"key": key, "kind": "pvp", "owner": challenger, "participants": [challenger, target_peer], "label": "%s vs %s" % [player_name(challenger), player_name(target_peer)]}
	_released_participants.clear()
	_pvp_pending = {"key": key, "challenger": challenger, "target": target_peer, "challenger_team": team, "request_id": request_id}
	_broadcast_lock()
	_ask(target_peer, "pvp", challenger, "%s challenges you to an arena battle!" % player_name(challenger), func(accepted: bool, payload: Dictionary, reason: String) -> void:
		if String(_pvp_pending.get("key", "")) != key:
			return
		if not accepted:
			_pvp_pending.clear()
			_reply(challenger, request_id, {"ok": false, "message": _refusal_text(target_peer, reason)})
			battle_lock.clear()
			_broadcast_lock()
			return
		_handle_pvp_team(target_peer, key, payload.get("team", []))
	)

func _refusal_text(peer_id: int, reason: String) -> String:
	match reason:
		"timeout": return "%s did not answer." % player_name(peer_id)
		"left": return "%s left the game." % player_name(peer_id)
	return "%s declined." % player_name(peer_id)

func _handle_pvp_team(peer_id: int, battle_key: String, team: Array) -> void:
	if String(_pvp_pending.get("key", "")) != battle_key or int(_pvp_pending.target) != peer_id:
		return
	var pending := _pvp_pending.duplicate(true)
	_pvp_pending.clear()
	if team.is_empty():
		_reply(int(pending.challenger), int(pending.request_id), {"ok": false, "message": "%s has no minions able to battle." % player_name(peer_id)})
		_abort_battle("The challenge could not start.")
		return
	var spec := build_pvp_spec(battle_key, int(pending.challenger), pending.challenger_team, peer_id, team, randi())
	_reply(int(pending.challenger), int(pending.request_id), {"ok": true, "key": battle_key})
	_rpc_battle_spec.rpc(spec)
	_begin_snapshot_history(battle_key)
	# Start from the same wire form the guests decode, so all engines match.
	battle_spec_received.emit(bytes_to_var(var_to_bytes(spec)))

## Pure spec builder (also used by tests): team 0 = challenger, team 1 = rival.
func build_pvp_spec(battle_key: String, challenger: int, challenger_team: Array, rival: int, rival_team: Array, seed: int) -> Dictionary:
	var combatants: Array = []
	for entry in challenger_team:
		var copy: Dictionary = (entry as Dictionary).duplicate(true)
		copy["team"] = 0
		copy["instance_id"] = "p0:%s" % String(copy.get("instance_id", ""))
		combatants.append(copy)
	for entry in rival_team:
		var copy: Dictionary = (entry as Dictionary).duplicate(true)
		copy["team"] = 1
		copy["instance_id"] = "p1:%s" % String(copy.get("instance_id", ""))
		combatants.append(copy)
	return {
		"key": battle_key,
		"kind": "pvp",
		"seed": seed,
		"setup": {"battle_id": battle_key, "tie_first_team": seed & 1, "combatants": combatants},
		"rules": {"id": "base:rules/multiplayer_pvp", "display_name": "Arena battle", "party_size": 5, "configuration": {"ai_teams": [], "refill_on_activation": true}},
		"controllers": {0: challenger, 1: rival},
		"names": {0: player_name(challenger), 1: player_name(rival)},
	}

## This player's party as fully healed combatants for an arena battle.
func provide_pvp_team() -> Array:
	var state = _session_state()
	if state == null:
		return []
	var built: Dictionary = CampaignProgressionService.party_setup_combatants(state, _runtime.catalog)
	if not built.get("ok", false):
		return []
	var team: Array = []
	for entry in built.combatants:
		var healed: Dictionary = (entry as Dictionary).duplicate(true)
		healed["health"] = int(healed.get("max_health", healed.get("health", 1)))
		healed["energy"] = int(healed.get("max_energy", healed.get("energy", 0)))
		team.append(healed)
	return team

# --- Shared Minion Keeper ----------------------------------------------------------------

func acquire_storage() -> Dictionary:
	if not shares_world():
		return {"ok": true} # Solo or versus: the storage is this player's own.
	var request_id := _new_request()
	if is_host():
		_handle_storage_request(1, request_id)
	else:
		_rpc_request_storage.rpc_id(1, request_id)
	return await _await_reply(request_id)

@rpc("any_peer", "call_remote", "reliable", CHANNEL_WORLD)
func _rpc_request_storage(request_id: int) -> void:
	if is_host():
		_handle_storage_request(multiplayer.get_remote_sender_id(), request_id)

func _handle_storage_request(peer_id: int, request_id: int) -> void:
	if storage_holder != 0 and storage_holder != peer_id and players.has(storage_holder):
		_reply(peer_id, request_id, {"ok": false, "message": "%s is using the Minion Keeper right now." % player_name(storage_holder)})
		return
	storage_holder = peer_id
	_rpc_storage_holder.rpc(storage_holder)
	_reply(peer_id, request_id, {"ok": true})

## Close the Minion Keeper and publish the (possibly reorganised) storage.
func release_storage() -> void:
	if not shares_world():
		return
	var state = _session_state()
	var storage: Array = []
	if state != null:
		for owned in state.storage:
			storage.append(owned.to_dictionary())
	if is_host():
		_commit_storage(1, storage)
	else:
		_rpc_commit_storage.rpc_id(1, storage)

@rpc("any_peer", "call_remote", "reliable", CHANNEL_WORLD)
func _rpc_commit_storage(storage: Array) -> void:
	if is_host():
		_commit_storage(multiplayer.get_remote_sender_id(), storage)

func _commit_storage(peer_id: int, storage: Array) -> void:
	if storage_holder != peer_id:
		return
	var state = _session_state()
	if state != null and peer_id != 1:
		var world := MultiplayerWorldSync.extract_world(state)
		world["storage"] = storage
		MultiplayerWorldSync.apply_world(state, world, true)
		world_changed.emit(true)
	storage_holder = 0
	_rpc_storage_holder.rpc(0)
	_broadcast_world_if_changed(true)
	# Storage now lives only in the host save; persist it so nobody's minion is
	# lost or duplicated if the host quits without saving.
	if _runtime != null:
		_runtime.save_campaign()

@rpc("authority", "call_remote", "reliable", CHANNEL_WORLD)
func _rpc_storage_holder(peer_id: int) -> void:
	storage_holder = peer_id

# --- Status --------------------------------------------------------------------------------

## Shown in everyone's roster, minimap and floor selector, and keeps arena
## challenges away from players who are already fighting. `status`:
## {"battling": bool, "where": {"floor", "lobby", "room"}, "stars": int}.
## Sent to the host only when it changes.
func set_local_status(status: Dictionary) -> void:
	if not is_active() or not _pending_join.is_empty() or status == _local_status:
		return
	_local_status = status.duplicate(true)
	if is_host():
		_set_status(1, _local_status)
	else:
		_rpc_status.rpc_id(1, _local_status)

@rpc("any_peer", "call_remote", "reliable", CHANNEL_WORLD)
func _rpc_status(status: Dictionary) -> void:
	if is_host():
		_set_status(multiplayer.get_remote_sender_id(), status)

func _set_status(peer_id: int, status: Dictionary) -> void:
	if not players.has(peer_id):
		return
	for key in ["battling", "where", "stars"]:
		if status.has(key):
			players[peer_id][key] = status[key]
	_broadcast_players()

# --- Questions (consent) -------------------------------------------------------------------

## Host: ask `target` something; `callback(accepted, payload, reason)` runs
## once, with reason "timeout" or "left" when no answer came.
func _ask(target: int, kind: String, from_peer: int, text: String, callback: Callable) -> void:
	_prompt_sequence += 1
	var prompt_id := _prompt_sequence
	_prompts[prompt_id] = {"target": target, "callback": callback}
	if target == 1:
		prompt_requested.emit(prompt_id, kind, from_peer, text)
	else:
		_rpc_prompt.rpc_id(target, prompt_id, kind, from_peer, text)
	get_tree().create_timer(PROMPT_SECONDS).timeout.connect(func() -> void:
		if _prompts.has(prompt_id):
			_finish_prompt(prompt_id, false, {}, "timeout")
	)

@rpc("authority", "call_remote", "reliable", CHANNEL_WORLD)
func _rpc_prompt(prompt_id: int, kind: String, from_peer: int, text: String) -> void:
	prompt_requested.emit(prompt_id, kind, from_peer, text)

@rpc("authority", "call_remote", "reliable", CHANNEL_WORLD)
func _rpc_prompt_closed(prompt_id: int) -> void:
	prompt_closed.emit(prompt_id)

## The asked player's answer. Accepting sends this player's battle team.
func answer_prompt(prompt_id: int, accepted: bool) -> void:
	if not is_active():
		return
	var payload := {"team": provide_pvp_team()} if accepted else {}
	if is_host():
		_on_prompt_answer(1, prompt_id, accepted, payload)
	else:
		_rpc_prompt_answer.rpc_id(1, prompt_id, accepted, payload)

@rpc("any_peer", "call_remote", "reliable", CHANNEL_WORLD)
func _rpc_prompt_answer(prompt_id: int, accepted: bool, payload: Dictionary) -> void:
	if is_host():
		_on_prompt_answer(multiplayer.get_remote_sender_id(), prompt_id, accepted, payload)

func _on_prompt_answer(peer_id: int, prompt_id: int, accepted: bool, payload: Dictionary) -> void:
	if _prompts.has(prompt_id) and int(_prompts[prompt_id].target) == peer_id:
		_finish_prompt(prompt_id, accepted, payload, "")

func _finish_prompt(prompt_id: int, accepted: bool, payload: Dictionary, reason: String) -> void:
	var entry: Dictionary = _prompts[prompt_id]
	_prompts.erase(prompt_id)
	if not reason.is_empty():
		# Unanswered: take the question off the asked player's screen.
		if int(entry.target) == 1:
			prompt_closed.emit(prompt_id)
		elif players.has(int(entry.target)):
			_rpc_prompt_closed.rpc_id(int(entry.target), prompt_id)
	(entry.callback as Callable).call(accepted, payload, reason)

# --- Duo double battle ----------------------------------------------------------------------

## Before a trainer fight in a duo game: invite the partner. The reply is
## {"ok": true, "partner": 0} for a solo fight, or {"ok": true, "partner": id,
## "team": [...], "key": battle key} when the partner joins.
func request_double(trainer_name: String) -> Dictionary:
	if not is_active() or not double_battles_enabled():
		return {"ok": true, "partner": 0}
	var request_id := _new_request()
	if is_host():
		_handle_double_request(1, request_id, trainer_name)
	else:
		_rpc_request_double.rpc_id(1, request_id, trainer_name)
	return await _await_reply(request_id, PROMPT_SECONDS + REQUEST_TIMEOUT)

@rpc("any_peer", "call_remote", "reliable", CHANNEL_BATTLE)
func _rpc_request_double(request_id: int, trainer_name: String) -> void:
	if is_host():
		_handle_double_request(multiplayer.get_remote_sender_id(), request_id, trainer_name)

func _handle_double_request(peer_id: int, request_id: int, trainer_name: String) -> void:
	var partner := 0
	for id in players:
		if int(id) != peer_id:
			partner = int(id)
	if not double_battles_enabled() or partner == 0 or player_battling(partner) or not battle_lock.is_empty():
		_reply(peer_id, request_id, {"ok": true, "partner": 0})
		return
	_battle_sequence += 1
	var key := "battle-%d" % _battle_sequence
	battle_lock = {"key": key, "kind": "double", "owner": peer_id, "participants": [peer_id, partner], "label": trainer_name}
	_released_participants.clear()
	_broadcast_lock()
	_ask(partner, "double", peer_id, "%s is battling %s. Fight together?" % [player_name(peer_id), trainer_name], func(accepted: bool, payload: Dictionary, reason: String) -> void:
		var team: Array = payload.get("team", [])
		if not accepted or team.is_empty():
			if String(battle_lock.get("key", "")) == key:
				battle_lock.clear()
				_broadcast_lock()
			_reply(peer_id, request_id, {"ok": true, "partner": 0, "message": _refusal_text(partner, reason) if not accepted else ""})
			return
		_reply(peer_id, request_id, {"ok": true, "partner": partner, "team": team, "key": key})
	)

# --- Helpers ---------------------------------------------------------------------------

func _session_state():
	return _runtime.session.state if _runtime != null and _runtime.session != null else null

func _content_version() -> String:
	return String(_runtime.catalog.content_version) if _runtime != null and _runtime.catalog != null else ""

func _local_gender() -> String:
	var state = _session_state()
	return String(state.character.get("gender", "male")).to_lower() if state != null else "male"
