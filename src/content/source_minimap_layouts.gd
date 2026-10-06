class_name SourceMinimapLayouts
extends Resource

## Inspector-editable transcription of StaticData.SetupLevels minimap data.
## Entries preserve source room-array order and MiniMapDataObject defaults.
@export var provenance: String = "StaticData.as :: SetupLevels; MiniMapDataObject constructor defaults"
@export var layouts: Array = []

func layout_for_floor(source_floor: int) -> Dictionary:
	for layout in layouts:
		if int(layout.get("floor_index", -1)) == source_floor:
			return (layout as Dictionary).duplicate(true)
	return {}
