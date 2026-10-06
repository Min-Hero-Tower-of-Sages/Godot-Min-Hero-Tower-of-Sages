extends RefCounted

## Apply BaseTopDownLevel.AddObject's music assignments in authored order.
## A hallway inherits the previous regional track, not the battle/title track.
static func profile(room: RoomDefinition, previous_region: String, opening_room: bool = false) -> Dictionary:
	var payload := room.ensure_payload()
	var track := "forestTrack" # AS3's unassigned int defaults to MUSIC_GRASS_LEVEL (0).
	var lowered := false
	if payload != null:
		for object in payload.objects:
			match String(object.get("spriteName", "")):
				"plantRoom_groundTile":
					track = "forestTrack"
					lowered = false
				"fireRoom_groundTile":
					track = "fireTrack"
					lowered = false
				"electricRoom_floorTile":
					track = "electricTrack"
					lowered = false
				"undeadRoom_groundTile":
					track = "undeadTrack"
					lowered = false
				"generalRoom_floorTile":
					track = "hallway"
					lowered = true
				"grass_music_override": track = "forestTrack"
				"fire_music_override": track = "fireTrack"
				"electric_music_override": track = "electricTrack"
				"undead_music_override": track = "undeadTrack"
				"introMusic_music_override", "riverMusic_music_override": track = "riverTrack"
				"mainMenu_music_override": track = "titleTrack"
				"halfVolume_music_override": lowered = true
				"fullVolume_music_override": lowered = false
	var hallway := track == "hallway"
	if hallway:
		track = previous_region
	return {
		"track": track,
		"region": previous_region if hallway or track.is_empty() else track,
		"inherits_region": hallway,
		"volume": 0.1 if opening_room else 0.4 if lowered else 1.0,
		"fade_seconds": 3.0 if opening_room or lowered else 2.0,
	}

static func regional_for_floor(catalog: ContentCatalog, campaign: CampaignDefinition, floor_index: int) -> String:
	# Older port saves have no previous-region field. Recover it from the
	# actual floor payload, not from the title or battle track currently playing.
	var source_floor := CampaignTowerModeService.source_floor_index(floor_index)
	# An all-hallway floor (the Grand Sage) retains the preceding region.
	for offset in source_floor + 1:
		for floor_data in campaign.floors:
			if int(floor_data.get("floor_index", -1)) != source_floor - offset:
				continue
			for room_id in floor_data.get("room_ids", []):
				var room := catalog.get_definition(StringName(room_id)) as RoomDefinition
				if room == null:
					continue
				var candidate := profile(room, "")
				if not candidate.inherits_region and String(candidate.track) in ["forestTrack", "fireTrack", "electricTrack", "undeadTrack"]:
					return String(candidate.track)
	return ""
