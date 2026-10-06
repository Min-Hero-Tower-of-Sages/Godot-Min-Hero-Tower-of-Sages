# Save schema and migration convention

Three files live under `user://`: `save_slot_1.json` through
`save_slot_3.json`. Each successful write is first serialized to `.tmp`, parsed
and validated, then the previous live file is renamed to `.bak` before replacement.
Load attempts the backup after a live-file error and reports recovery explicitly.

Schema 1 required `schema_version`, `content_version`, `character`, `party`,
`storage`, `progression`, `room_state`, `safe_location`, `active_mods`, and
`pending_mods`. Definitions and instances use stable IDs. Scene trees, Resources,
resource paths as identity, callables, and derived stat caches are forbidden.

Schema 2 adds `campaign_id`, `current_room_id`, `battle_sequence`,
`pending_battle`, `applied_battle_ids`, and `last_battle_result`. Party/storage
entries are serialized owned-minion records with stable instance/definition IDs,
level/experience, learned move IDs, and persistent HP/energy. It rejects duplicate
owned instance IDs and malformed nested records. Schema-1 files migrate in
memory when loaded; the next successful save writes schema 2 while the prior live
file is kept as `.bak` by the atomic replacement path.

Future migrations must remain pure transformations from schema N to N+1, validate
every referenced content ID against the active catalog, and never overwrite a
save whose schema is newer than the running build. Flash import is out of scope.
