class_name CampaignShinyService
extends RefCounted

const CHANCE_DENOMINATOR := 512

# Only acquisition paths call this. Old saves/imports default to normal; load,
# display and evolution never roll. An optional explicit roll supports fixtures.
static func initialize_new(owned: OwnedMinionState, state, catalog: ContentCatalog, roll: int = -1) -> void:
	if owned.is_shiny:
		if owned.shiny_line_id.is_empty(): owned.shiny_line_id = MinionPaletteService.line_id(owned.definition_id, catalog)
		return
	if CampaignDebugService.enabled(state, "force_shiny"):
		owned.is_shiny = true
		owned.shiny_line_id = MinionPaletteService.line_id(owned.definition_id, catalog)
		return
	if not CampaignModService.enabled(state, "shinies"): return
	var result := randi_range(0, CHANCE_DENOMINATOR - 1) if roll < 0 else roll
	owned.is_shiny = result == 0
	if owned.is_shiny: owned.shiny_line_id = MinionPaletteService.line_id(owned.definition_id, catalog)
