class_name RoomArtCatalog
extends RefCounted

## Which tower-room payload objects are drawn art and which are invisible
## markers, plus a cached texture lookup. Shared by the Workshop's room
## editor and the mod builder's room-object validation, and kept in step with
## CampaignRoomView._is_semantic_marker / _art_texture_name.

const ART_DIRECTORY := "res://content/base/art/rooms/"
## Art themes offered in the Workshop's object palette, in this order.
const PALETTE_PREFIXES := ["generalRoom_", "plantRoom_", "eggery_", "room_"]
const ICE_ART := ["iDoor_top", "iDoor_down", "iDoor_side", "iFloor1", "iFloor2", "iFloor3", "iFloor4", "iFloor5", "iFloor6", "iFloor7", "iFloor8",
	"iUp", "iDown", "iSide", "iGrass", "iPath1", "iPath2", "iPuddle", "iPuddle2", "iPuddle3",
	"iRock2", "iRock3", "iRock_big", "iRock_small", "iSnowman1", "iSnowman2", "iSage", "iNPC_snowy", "iNPC_bluey", "iNPC_baldy",
	"iTree1_full", "iTree2", "iTree3", "iTree4", "iWater", "iThaw", "iWater2", "iThaw2"]
static var _cache: Dictionary = {}
static var _library: Array[String] = []
static var _mod_art: Dictionary = {}

static func is_marker(sprite_name: String) -> bool:
	return sprite_name == "collRect" or sprite_name == "regularDoor" or sprite_name == "regularDoor_eggery" \
		or sprite_name.begins_with("menus_speechBubble") or sprite_name.begins_with("roomTransitionObject") \
		or sprite_name.begins_with("teleport_roomTransitionObject") or sprite_name.begins_with("telport_roomTransitionObject") \
		or sprite_name == "roomTransition_startingRoomToLobby" or sprite_name.begins_with("entryObject") \
		or sprite_name.begins_with("expert_entryObject") or sprite_name.begins_with("expert_roomTransitionObject") \
		or sprite_name.begins_with("buttonZoneObject") or sprite_name.begins_with("sound") \
		or sprite_name.to_lower().contains("music") or sprite_name.begins_with("wallRect_")

static func texture_name(sprite_name: String) -> String:
	if sprite_name.begins_with("eggery_egg") and sprite_name.trim_prefix("eggery_egg").is_valid_int(): return "eggery_egg"
	if sprite_name == "regularDoor_eggery": return "regularDoor"
	return sprite_name

static func texture(sprite_name: String) -> Texture2D:
	var tile := RoomPuzzleTile.kind(sprite_name)
	if not tile.is_empty(): return RoomPuzzleTile.TEXTURES[tile]
	if sprite_name.begins_with("mod_art:"):
		var mod_id := sprite_name.trim_prefix("mod_art:").get_slice("/", 0)
		var path := "sprites/" + sprite_name.get_file()
		if not path.begins_with("sprites/room_"): return null
		if not _mod_art.has(sprite_name):
			var bytes := UserModRepository.read_file(mod_id, path)
			var image := Image.new()
			if bytes.is_empty() or image.load_png_from_buffer(bytes) != OK: return null
			_mod_art[sprite_name] = ImageTexture.create_from_image(image)
		return _mod_art[sprite_name]
	var art_name := texture_name(sprite_name)
	if art_name.is_empty(): return null
	if _cache.has(art_name): return _cache[art_name]
	var path := ART_DIRECTORY + art_name + ".png"
	var result := load(path) as Texture2D if ResourceLoader.exists(path) else SourceMenuArt.texture(art_name)
	_cache[art_name] = result
	return result

## Every placeable piece of room art in the project, for the object palette.
## Animation frames (names ending in a digit) and player sprites are left out.
static func library() -> Array[String]:
	if not _library.is_empty(): return _library
	var found: Array[String] = []
	for file in ResourceLoader.list_directory(ART_DIRECTORY):
		if not file.ends_with(".png"): continue
		var sprite_name := file.get_basename()
		if not PALETTE_PREFIXES.any(func(prefix: String) -> bool: return sprite_name.begins_with(prefix)): continue
		if sprite_name.right(1).is_valid_int() or is_marker(sprite_name): continue
		if not UserModBuilder.object_addable(sprite_name): continue
		found.append(sprite_name)
	found.sort_custom(func(a: String, b: String) -> bool:
		var left := PALETTE_PREFIXES.find(PALETTE_PREFIXES.filter(func(prefix: String) -> bool: return a.begins_with(prefix))[0])
		var right := PALETTE_PREFIXES.find(PALETTE_PREFIXES.filter(func(prefix: String) -> bool: return b.begins_with(prefix))[0])
		return left < right if left != right else a.naturalnocasecmp_to(b) < 0)
	for tile in RoomPuzzleTile.LABELS:
		found.append(RoomPuzzleTile.PREFIX + String(tile))
	found.append_array(ICE_ART)
	_library = found
	return _library

## A readable name for a sprite, e.g. "plantRoom_oakTree" -> "Oak tree".
static func caption(sprite_name: String) -> String:
	var tile := RoomPuzzleTile.kind(sprite_name)
	if not tile.is_empty(): return RoomPuzzleTile.LABELS[tile]
	if sprite_name.begins_with("mod_art:"): return sprite_name.get_file().get_basename().trim_prefix("room_").capitalize()
	if sprite_name in ICE_ART: return "Ice · " + sprite_name.substr(1).capitalize()
	if sprite_name == "collRect": return "Wall"
	if sprite_name.begins_with("buttonZoneObject"): return "Interaction zone %s" % sprite_name.trim_prefix("buttonZoneObject")
	var bare := sprite_name
	for prefix in PALETTE_PREFIXES: bare = bare.trim_prefix(prefix)
	return bare.capitalize()

static func clear_mod_art() -> void:
	_mod_art.clear()
