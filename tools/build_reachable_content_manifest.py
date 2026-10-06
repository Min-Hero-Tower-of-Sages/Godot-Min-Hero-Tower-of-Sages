"""Build a combined, per-entry reference/content coverage manifest.

This is an inventory tool, not a converter. It joins the source-class index,
strictly staged definition data, maintained Godot Resources, normalized room
records, and the isolated SWF export. Gaps that still need a reachability or
behavior audit are emitted as explicit rows rather than inferred as complete.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
FIELDS = ("kind", "id_or_name", "source", "recovery", "conversion", "validation", "notes")
STAGED_CONTENT = ROOT / "development/staged_import/content-20260911-j"
STAGED_MOVES = ROOT / "development/staged_import/moves-20260911-g"
CATALOG_DIR = ROOT / "content/imported/recovered-20260911"
SOURCE_CLASS_CSV = ROOT / "development/inventory/coverage_manifest.csv"
ROOM_MANIFEST = ROOT / "development/normalized/rooms-20260908/room_manifest.json"
ROOM_DIR = ROOM_MANIFEST.parent
EXPORT_DIR = ROOT / "development/extracted/full-20260908"
SOURCE_INVENTORY = ROOT / "development/inventory/reference_inventory.json"
RECONCILIATION = ROOT / "development/inventory/reconciliation.json"
DEFAULT_OUTPUT = ROOT / "development/inventory/reachable_content_manifest.csv"


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as file:
        return json.load(file)


def csv_quote(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return str(value).replace("\r", " ").replace("\n", " ")


def source_location(path: str, line: Any = None) -> str:
    normalized = str(path).replace("\\", "/")
    return f"{normalized}:{line}" if line not in (None, "") else normalized


def resource_file(subdirectory: str, content_id: str) -> Path:
    filename = content_id.replace(":", "__").replace("/", "_") + ".tres"
    return CATALOG_DIR / subdirectory / filename


def resource_status(subdirectory: str, content_id: str) -> tuple[str, str]:
    path = resource_file(subdirectory, content_id)
    if path.is_file():
        return "typed_resource", "catalog_validated_2026-09-23"
    return "missing_resource", "not_validated"


def add_row(rows: list[dict[str, str]], **values: Any) -> None:
    row = {field: csv_quote(values.get(field, "")) for field in FIELDS}
    rows.append(row)


def add_source_classes(rows: list[dict[str, str]]) -> None:
    with SOURCE_CLASS_CSV.open("r", encoding="utf-8-sig", newline="") as file:
        source_rows = list(csv.DictReader(file))
    for record in source_rows:
        old_kind = record.get("kind", "unknown")
        notes = record.get("notes", "")
        prefix = "Class-level source inventory; per-entry data coverage is tracked separately."
        add_row(
            rows,
            kind=f"source_class/{old_kind}",
            id_or_name=record.get("id_or_name", ""),
            source=record.get("source", ""),
            recovery=record.get("recovery", ""),
            conversion=record.get("conversion", ""),
            validation=record.get("validation", ""),
            notes=f"{prefix} {notes}".strip(),
        )


def add_staged_definitions(rows: list[dict[str, str]]) -> Counter[str]:
    counts: Counter[str] = Counter()
    types = read_json(STAGED_CONTENT / "types.json")
    minions = read_json(STAGED_CONTENT / "minions.json")
    trees = read_json(STAGED_CONTENT / "talent_trees.json")
    move_index = read_json(STAGED_CONTENT / "move_index.json")
    constructed_moves = read_json(STAGED_MOVES / "moves.json")
    type_chart = read_json(STAGED_CONTENT / "type_chart.json")

    for entry in types:
        conversion, validation = resource_status("types", entry["id"])
        add_row(
            rows,
            kind="type",
            id_or_name=entry["id"],
            source=entry["source"],
            recovery="recovered_edited_or_mod_source",
            conversion=conversion,
            validation=validation,
            notes=f"legacy_constant={entry.get('legacy_constant', '')}; display_name={entry.get('display_name', '')}",
        )
        counts["type"] += 1

    conversion, validation = resource_status("type_charts", type_chart["id"])
    add_row(
        rows,
        kind="type_chart",
        id_or_name=type_chart["id"],
        source=type_chart.get("source", "development/staged_import/content-20260911-j/type_chart.json"),
        recovery="recovered_edited_source",
        conversion=conversion,
        validation=validation,
        notes=f"raw_assignments={type_chart.get('raw_assignment_count', '')}; unique_pairs={len(type_chart.get('multipliers', {}))}",
    )
    counts["type_chart"] += 1

    for entry in minions:
        migration = entry.get("migration", {})
        conversion, validation = resource_status("minions", entry["id"])
        notes = {
            "display_name": entry.get("display_name", ""),
            "source_mod": migration.get("source_mod", ""),
            "legacy_identity": migration.get("legacy_identity", ""),
            "legacy_function": migration.get("legacy_function", ""),
            "presentation_id": entry.get("presentation_id", ""),
            "evolution_id": entry.get("evolution_id", ""),
        }
        add_row(
            rows,
            kind="minion",
            id_or_name=entry["id"],
            source=source_location(migration.get("source", ""), migration.get("line")),
            recovery="recovered_edited_or_mod_source",
            conversion=conversion,
            validation=validation,
            notes=notes,
        )
        counts["minion"] += 1

    for entry in trees:
        conversion, validation = resource_status("talent_trees", entry["id"])
        nodes = entry.get("nodes", [])
        move_refs = sum(len(node.get("move_ids", [])) for node in nodes)
        add_row(
            rows,
            kind="talent_tree",
            id_or_name=entry["id"],
            source=source_location(entry.get("source", ""), entry.get("line")),
            recovery="recovered_edited_or_mod_source",
            conversion=conversion,
            validation=validation,
            notes=f"display_name={entry.get('display_name', '')}; nodes={len(nodes)}; ordered_move_references={move_refs}",
        )
        counts["talent_tree"] += 1

    constructed_by_id = {entry["id"]: entry for entry in constructed_moves}
    for entry in move_index:
        content_id = entry["id"]
        constructed = constructed_by_id.get(content_id)
        conversion, validation = resource_status("moves", content_id)
        if constructed is None:
            recovery = "source_id_declared_but_not_constructed"
            conversion = "unavailable_tombstone" if conversion == "typed_resource" else conversion
            validation = "catalog_validated_unavailable_2026-09-23" if conversion == "unavailable_tombstone" else validation
            source = entry.get("source", "")
            note = f"legacy_constant={entry.get('legacy_constant', '')}; source value absent; not executable by design"
            counts["unavailable_move"] += 1
        else:
            recovery = "recovered_constructed_move_values"
            source = source_location(constructed.get("source", entry.get("source", "")), constructed.get("line"))
            note = f"legacy_constant={entry.get('legacy_constant', '')}; effects={len(constructed.get('effects', []))}; available=true"
            counts["constructed_move"] += 1
        add_row(
            rows,
            kind="move",
            id_or_name=content_id,
            source=source,
            recovery=recovery,
            conversion=conversion,
            validation=validation,
            notes=note,
        )

    presentation_by_id: dict[str, dict[str, Any]] = {}
    for entry in minions:
        presentation_by_id.setdefault(entry["presentation_id"], entry)
    for presentation_id, entry in presentation_by_id.items():
        migration = entry.get("migration", {})
        conversion, validation = resource_status("presentations", presentation_id)
        add_row(
            rows,
            kind="minion_presentation",
            id_or_name=presentation_id,
            source=source_location(migration.get("source", ""), migration.get("line")),
            recovery="recovered_sprite_identity_and_offsets",
            conversion=conversion,
            validation=validation,
            notes=f"legacy_sprite={migration.get('legacy_sprite', '')}; source_mod={migration.get('source_mod', '')}; full bitmap/origin/animation binding pending",
        )
        counts["minion_presentation"] += 1

    return counts


def add_rooms(rows: list[dict[str, str]]) -> Counter[str]:
    manifest = read_json(ROOM_MANIFEST)
    counts: Counter[str] = Counter()
    families: dict[str, dict[str, Any]] = {}

    def walk(node: Any):
        if isinstance(node, dict):
            yield node
            children = node.get("children", [])
            if isinstance(children, list):
                for child in children:
                    yield from walk(child)

    for room in manifest.get("rooms", []):
        identity = room.get("asset_identity", {})
        container = identity.get("container", manifest.get("container", "unknown"))
        character_id = identity.get("character_id", room.get("character_id", ""))
        class_name = identity.get("class_name", room.get("class_name", ""))
        room_id = room.get("id", "")
        normalized = ROOM_DIR / room.get("file", "")
        source_binary = room.get("source_binary", f"{character_id}_{class_name}.bin")
        add_row(
            rows,
            kind="room_payload",
            id_or_name=room_id or f"{container}|{character_id}|{class_name}",
            source=f"{container}|{character_id}|{class_name}",
            recovery="recovered_original_swf_binary",
            conversion="normalized_compressed_xml" if normalized.is_file() else "missing_normalized_xml",
            validation="xml_mapping_passed" if manifest.get("error_count") == 0 and normalized.is_file() else "requires_review",
            notes=f"normalized={normalized.relative_to(ROOT).as_posix()}; source_binary={source_binary}; Godot room scene and object behavior not yet ported",
        )
        counts["room_payload"] += 1
        if not normalized.is_file():
            continue
        payload = read_json(normalized)
        xml_root = payload.get("xml", {})
        object_index = 0
        for node in walk(xml_root):
            if node.get("tag") != "levelObject":
                continue
            object_index += 1
            attributes = node.get("attributes", {})
            if not isinstance(attributes, dict):
                attributes = {"raw": attributes}
            sprite_name = str(attributes.get("spriteName", "<missing-sprite-name>"))
            family = families.setdefault(sprite_name, {"instances": 0, "rooms": set(), "samples": []})
            family["instances"] += 1
            family["rooms"].add(room_id)
            if len(family["samples"]) < 3:
                family["samples"].append(f"{room_id}#{object_index}")
            add_row(
                rows,
                kind="room_object_instance",
                id_or_name=f"{room_id}/object/{object_index:04d}",
                source=f"{container}|{character_id}|{class_name}#{object_index}",
                recovery="recovered_original_swf_room_xml",
                conversion="normalized_room_object_record",
                validation="source_node_parsed_behavior_not_validated",
                notes={"sprite_name": sprite_name, "attributes": attributes, "scene_behavior_ported": False},
            )
            counts["room_object_instance"] += 1

    for sprite_name, family in families.items():
        add_row(
            rows,
            kind="room_object_family",
            id_or_name=sprite_name,
            source="development/normalized/rooms-20260908/room_manifest.json",
            recovery="recovered_original_swf_room_xml",
            conversion="sprite_family_inventory_only",
            validation="room_object_behavior_mapping_pending",
            notes={
                "instance_count": family["instances"],
                "room_count": len(family["rooms"]),
                "sample_instances": family["samples"],
            },
        )
        counts["room_object_family"] += 1
    counts["room_manifest_errors"] = int(manifest.get("error_count", 0))
    return counts


def add_room_dispatch_map(rows: list[dict[str, str]]) -> Counter[str]:
    inventory = read_json(SOURCE_INVENTORY)
    source_root = edited_source_root(inventory)
    source_file = source_root / "scripts/TopDown/Levels/BaseTopDownLevel.as"
    source_text = source_file.read_text(encoding="utf-8-sig")
    code_text = strip_comments(source_text)
    method_pattern = re.compile(
        r"^\s*(?:(?:override|static|final)\s+)*(?:private|protected|public)\s+(?:override\s+)?function\s+(?P<name>[A-Za-z_$][A-Za-z0-9_$]*)\s*\(",
        re.MULTILINE,
    )
    method_data: dict[str, dict[str, Any]] = {}
    for method_match in method_pattern.finditer(code_text):
        opening_brace = code_text.find("{", method_match.end())
        if opening_brace < 0:
            continue
        body = braced_body(code_text, opening_brace)
        method_name = method_match.group("name")
        method_data.setdefault(method_name, {
            "body": body,
            "created_classes": list(dict.fromkeys(re.findall(r"\bnew\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*\(", body))),
            "source_line": source_text.count("\n", 0, method_match.start()) + 1,
        })

    try:
        static_file, _standard_floor_count, static_rooms_by_floor = static_room_slot_map(source_root)
    except (OSError, ValueError):
        static_file = None
        static_rooms_by_floor = {}
    source_room_slots: dict[str, list[dict[str, Any]]] = {}
    for floor_index, room_definitions in static_rooms_by_floor.items():
        for room_index, room_definition in enumerate(room_definitions):
            source_class = room_definition.get("source_class")
            if source_class:
                source_room_slots.setdefault(str(source_class), []).append({
                    "floor_index": floor_index if floor_index >= 0 else None,
                    "room_index": room_index,
                    "special_room_index": -floor_index - 1 if floor_index < 0 else None,
                    "room_definition": room_definition,
                })

    source_level_dir = source_root / "scripts/TopDown/Levels"
    source_calls_by_sprite: dict[str, list[dict[str, Any]]] = {}
    dynamic_call_count = 0
    if source_level_dir.is_dir():
        for room_script in sorted(source_level_dir.rglob("*.as")):
            if room_script.stem == "BaseTopDownLevel":
                # Its generic XML loop is already expanded into normalized room instances.
                continue
            room_source = room_script.read_text(encoding="utf-8-sig")
            room_code = strip_comments(room_source)
            functions = list(method_pattern.finditer(room_code))
            function_index = 0
            call_index_by_line: Counter[int] = Counter()
            add_call_pattern = re.compile(r"\bAddObject\s*\(")
            for call_match in add_call_pattern.finditer(room_code):
                opening_paren = room_code.find("(", call_match.start())
                closing_paren = matching_delimiter(room_code, opening_paren, "(", ")")
                raw_arguments = room_code[opening_paren + 1:closing_paren].strip()
                sprite_match = re.match(r"\s*(['\"])(.*?)\1", raw_arguments, re.DOTALL)
                line = room_source.count("\n", 0, call_match.start()) + 1
                call_index_by_line[line] += 1
                call_index = call_index_by_line[line]
                while function_index + 1 < len(functions) and functions[function_index + 1].start() < call_match.start():
                    function_index += 1
                method_name = functions[function_index].group("name") if functions and functions[function_index].start() < call_match.start() else "<outside-method>"
                if not sprite_match:
                    dynamic_call_count += 1
                    add_row(
                        rows,
                        kind="source_room_object_unresolved",
                        id_or_name=f"base:source_room_object/{trainer_slug(room_script.stem)}/line/{line}/call/{call_index}",
                        source=source_location(str(room_script), line),
                        recovery="current_edited_source_AddObject_callsite",
                        conversion="dynamic_sprite_name_not_resolved",
                        validation="explicit_source_callsite_review_required",
                        notes={"source_class": room_script.stem, "source_method": method_name, "arguments": raw_arguments},
                    )
                    continue

                sprite_name = sprite_match.group(2)
                source_callsite = {
                    "source": source_location(str(room_script), line),
                    "source_class": room_script.stem,
                    "source_method": method_name,
                    "source_line": line,
                    "callsite_index_on_line": call_index,
                    "arguments": raw_arguments,
                }
                source_calls_by_sprite.setdefault(sprite_name, []).append(source_callsite)
                slots = source_room_slots.get(room_script.stem, [])
                resolved_slots = slots or [None]
                for slot in resolved_slots:
                    room_definition = slot.get("room_definition", {}) if slot else {}
                    if room_definition.get("room_slug"):
                        room_key = str(room_definition["room_slug"])
                    else:
                        scope = f"special-{slot['special_room_index']}" if slot and slot["special_room_index"] is not None else "source"
                        room_key = f"{scope}-{trainer_slug(room_script.stem)}"
                    if slot and slot["special_room_index"] is not None:
                        slot_segment = f"special/{slot['special_room_index']}/slot/{slot['room_index']}"
                    elif slot:
                        slot_segment = f"floor/{slot['floor_index']}/slot/{slot['room_index']}"
                    else:
                        slot_segment = "unbound"
                    add_row(
                        rows,
                        kind="source_room_object_instance",
                        id_or_name=(
                            f"base:room/{room_key}/{slot_segment}/source_object/"
                            f"{line:04d}/{call_index:02d}"
                        ),
                        source=source_location(str(room_script), line),
                        recovery="current_edited_source_room_placement_callsite",
                        conversion="source_script_placement_not_Godot_scene_converted",
                        validation="static_source_callsite_recovered" if slot else "room_registry_binding_unresolved",
                        notes={
                            "sprite_name": sprite_name,
                            "source_class": room_script.stem,
                            "source_method": method_name,
                            "callsite_index_on_line": call_index,
                            "arguments": raw_arguments,
                            "static_room_slot": slot,
                            "scene_behavior_ported": False,
                        },
                    )

    existing_family_names = {
        row["id_or_name"] for row in rows if row["kind"] == "room_object_family"
    }
    for sprite_name, callsites in source_calls_by_sprite.items():
        source_classes = sorted({callsite["source_class"] for callsite in callsites})
        reachable_slots = [slot for class_name in source_classes for slot in source_room_slots.get(class_name, [])]
        if sprite_name not in existing_family_names:
            add_row(
                rows,
                kind="room_object_family",
                id_or_name=sprite_name,
                source="current edited room CreateObjects() AddObject callsites",
                recovery="current_edited_source_script_room_placement",
                conversion="source_dispatch_pending",
                validation="source_authored_family_not_in_normalized_xml",
                notes={
                    "instance_count": 0,
                    "room_count": len(reachable_slots),
                    "sample_instances": [],
                    "source_script_instance_count": len(callsites),
                    "source_script_room_count": len(reachable_slots),
                    "source_script_classes": source_classes,
                },
            )
        else:
            family_row = next(
                row for row in rows
                if row["kind"] == "room_object_family" and row["id_or_name"] == sprite_name
            )
            family_notes = json.loads(family_row["notes"])
            family_notes["source_script_instance_count"] = len(callsites)
            family_notes["source_script_room_count"] = len(reachable_slots)
            family_notes["source_script_classes"] = source_classes
            family_row["notes"] = csv_quote(family_notes)

    if dynamic_call_count:
        add_row(
            rows,
            kind="open_reachability_audit",
            id_or_name="dynamic_source_room_object_names",
            source=source_location(str(source_level_dir)),
            recovery="current_edited_source_callsite_scan",
            conversion="dynamic_sprite_name_not_resolved",
            validation="source_room_placement_gap",
            notes=f"{dynamic_call_count} AddObject callsites do not have a literal sprite name; see source_room_object_unresolved rows.",
        )
    unregistered_classes = sorted({
        callsite["source_class"]
        for callsites in source_calls_by_sprite.values()
        for callsite in callsites
        if not source_room_slots.get(callsite["source_class"])
    })
    if unregistered_classes:
        add_row(
            rows,
            kind="open_reachability_audit",
            id_or_name="source_room_class_registry_binding",
            source=source_location(str(static_file or source_root / "scripts/PresistentData/StaticData.as")),
            recovery="current_source_room_class_callsites_recovered",
            conversion="source_room_classes_not_found_in_static_room_registry",
            validation="source_room_class_reachability_requires_review",
            notes={"source_classes": unregistered_classes},
        )

    add_object = method_data.get("AddObject")
    if not source_file.is_file() or add_object is None:
        raise FileNotFoundError(f"BaseTopDownLevel.AddObject dispatch not found: {source_file}")
    add_object_match = next(match for match in method_pattern.finditer(code_text) if match.group("name") == "AddObject")
    add_object_open = code_text.find("{", add_object_match.end())
    add_object_offset = add_object_open + 1
    branches = top_level_if_branches(add_object["body"])
    dispatch_rules: list[dict[str, Any]] = []
    exact_rules: dict[str, list[dict[str, Any]]] = {}
    prefix_rules: list[dict[str, Any]] = []
    for branch in branches:
        condition = branch["condition"]
        branch_body = branch["body"]
        handler_methods = list(dict.fromkeys(re.findall(r"\bthis\.(?P<name>Add[A-Za-z0-9_$]+)\s*\(", branch_body)))
        handler_classes = {
            method: method_data.get(method, {}).get("created_classes", [])
            for method in handler_methods
        }
        condition_exact = list(dict.fromkeys(re.findall(r"param1\s*==\s*(['\"])(.*?)\1", condition)))
        exact_names = list(dict.fromkeys(value for _quote, value in condition_exact))
        prefix_matches = list(dict.fromkeys(re.findall(
            r"param1\.slice\(\s*0\s*,\s*(\d+)\s*\)\s*==\s*(['\"])(.*?)\2",
            condition,
        )))
        branch_offset = add_object_offset + int(branch["start"])
        guard_text = condition + " " + branch_body
        guards = []
        for flag, pattern in (
            ("randomized_or_seeded_choice", r"Math\.random|nextNumber\s*\("),
            ("campaign_or_room_state_gate", r"Singleton\.dynamicData|Singleton\.staticData"),
            ("ambient_audio_or_music", r"BackgroundMusicTracks|m_backgroundMusic|soundController"),
            ("floor_or_mode_gate", r"m_currFloor|HardMode|IceFloor|Nuzlocke|InfiniteTower"),
        ):
            if re.search(pattern, guard_text, re.IGNORECASE):
                guards.append(flag)
        categories: list[str] = []
        class_names = {class_name for values in handler_classes.values() for class_name in values}
        method_names_lower = " ".join(handler_methods).casefold()
        for class_name, category in (
            ("ButtonZone", "trainer_or_dialogue_interaction_zone"),
            ("RoomTransitionObject", "room_transition"),
            ("ExpertRoomTransitionObject", "expert_room_transition"),
            ("RegularKeyDoor", "locked_door"),
            ("BossToEggeryDoorWall", "eggery_gate"),
            ("GoldChest", "gold_chest"),
            ("GemChest", "gem_chest"),
            ("ElevatorObject", "elevator_transition"),
            ("HealStone", "healing_station"),
            ("EggeryExitBlockade", "eggery_collision_gate"),
            ("CourtyardExitBlockade", "courtyard_collision_gate"),
            ("WallCollObject", "collision_geometry"),
        ):
            if class_name in class_names:
                categories.append(category)
        if any(token in method_names_lower for token in ("visual", "splash", "torch", "fire")):
            categories.append("visual_or_environmental_effect")
        if "backgroundsound" in method_names_lower or "music" in guard_text.casefold():
            categories.append("ambient_audio_or_music_control")
        if not categories:
            categories.append("source_dispatch_handler_present")
        record = {
            "branch_order": branch["order"],
            "condition": condition,
            "source": source_location(str(source_file), source_text.count("\n", 0, branch_offset) + 1),
            "handler_methods": handler_methods,
            "handler_classes": handler_classes,
            "behavior_categories": list(dict.fromkeys(categories)),
            "source_guards": guards,
        }
        dispatch_rules.append(record)
        for sprite_name in exact_names:
            exact_rules.setdefault(sprite_name, []).append(record)
        for length, _quote, prefix in prefix_matches:
            prefix_rules.append({**record, "prefix": prefix, "declared_prefix_length": int(length)})

    fallback_match = list(re.finditer(
        r"\belse\s*\{\s*this\.AddJustVisualObject\(param1\s*,",
        add_object["body"],
    ))
    fallback_line = None
    if fallback_match:
        fallback_offset = add_object_offset + fallback_match[-1].start()
        fallback_line = source_text.count("\n", 0, fallback_offset) + 1
    fallback_record = {
        "branch_order": None,
        "condition": "final else fallback (no explicit sprite condition matched)",
        "source": source_location(str(source_file), fallback_line),
        "handler_methods": ["AddJustVisualObject"],
        "handler_classes": {"AddJustVisualObject": method_data.get("AddJustVisualObject", {}).get("created_classes", [])},
        "behavior_categories": ["visual_only_default_fallback"],
        "source_guards": [],
    }

    def select_rule(sprite_name: str) -> tuple[str, dict[str, Any]]:
        candidates = list(exact_rules.get(sprite_name, []))
        candidates.extend(rule for rule in prefix_rules if sprite_name.startswith(rule["prefix"]))
        if candidates:
            selected = min(candidates, key=lambda rule: int(rule["branch_order"]))
            match_type = "exact_source_condition" if selected in exact_rules.get(sprite_name, []) else "source_prefix_condition"
            return match_type, selected
        return "source_default_visual_fallback", fallback_record

    family_rows = [row for row in rows if row["kind"] == "room_object_family"]
    rules_by_name: dict[str, dict[str, Any]] = {}
    counts: Counter[str] = Counter()
    for family_row in family_rows:
        sprite_name = family_row["id_or_name"]
        match_type, rule = select_rule(sprite_name)
        dispatch_id = f"base:room_behavior/{sprite_name}"
        dispatch_note = {
            "sprite_name": sprite_name,
            "match_type": match_type,
            "source_condition": rule["condition"],
            "source_branch_order": rule["branch_order"],
            "source_handler_methods": rule["handler_methods"],
            "source_handler_classes": rule["handler_classes"],
            "behavior_categories": rule["behavior_categories"],
            "source_guards": rule["source_guards"],
            "dispatch_id": dispatch_id,
        }
        rules_by_name[sprite_name] = dispatch_note
        family_notes = json.loads(family_row["notes"])
        family_notes["dispatch_id"] = dispatch_id
        family_notes["source_handler_methods"] = rule["handler_methods"]
        family_notes["behavior_categories"] = rule["behavior_categories"]
        family_row["notes"] = csv_quote(family_notes)
        family_row["conversion"] = "source_dispatch_mapped_not_Godot_converted"
        family_row["validation"] = match_type
        add_row(
            rows,
            kind="room_behavior_dispatch",
            id_or_name=dispatch_id,
            source=rule["source"],
            recovery="current_edited_source_AddObject_branch",
            conversion="source_handler_indexed_Godot_behavior_not_converted",
            validation=match_type,
            notes=dispatch_note,
        )
        counts[f"room_behavior_{match_type}"] += 1
        if rule["source_guards"]:
            counts["room_behavior_families_with_dynamic_guards"] += 1

    for row in rows:
        if row["kind"] not in {"room_object_instance", "source_room_object_instance"}:
            continue
        try:
            instance_notes = json.loads(row["notes"])
        except (json.JSONDecodeError, TypeError):
            instance_notes = {}
        sprite_name = str(instance_notes.get("sprite_name", "<missing-sprite-name>"))
        family_dispatch = rules_by_name.get(sprite_name)
        if family_dispatch is None:
            continue
        instance_notes["dispatch_id"] = family_dispatch["dispatch_id"]
        instance_notes["behavior_categories"] = family_dispatch["behavior_categories"]
        instance_notes["scene_behavior_ported"] = False
        row["notes"] = csv_quote(instance_notes)
        row["conversion"] = "source_dispatch_linked_not_Godot_converted"
        row["validation"] = family_dispatch["match_type"]
        counts["room_object_instances_linked_to_dispatch"] += 1

    counts.update(add_room_behavior_source_inventory(
        rows,
        inventory=inventory,
        source_root=source_root,
        source_file=source_file,
        source_text=source_text,
        dispatch_rules=dispatch_rules,
        fallback_record=fallback_record,
    ))

    if len(rules_by_name) != len(family_rows) or fallback_line is None:
        add_row(
            rows,
            kind="open_reachability_audit",
            id_or_name="room_object_dispatch_completeness",
            source=source_location(str(source_file)),
            recovery="BaseTopDownLevel.AddObject_partially_parsed",
            conversion="some_room_families_not_linked",
            validation="dispatch_audit_incomplete",
            notes={"family_count": len(family_rows), "dispatch_count": len(rules_by_name), "fallback_line": fallback_line},
        )
        counts["room_behavior_dispatch_audit_row"] = 1
    return counts


def mask_actionscript_strings(text: str) -> str:
    """Blank quoted strings without changing offsets, for syntax-only scans."""
    output = list(text)
    quote: str | None = None
    escaped = False
    for index, char in enumerate(text):
        if quote is not None:
            if char != "\n":
                output[index] = " "
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
        elif char in {"\"", "'"}:
            quote = char
            output[index] = " "
    return "".join(output)


def room_method_effects(code: str, method: tuple[str, int, int, int]) -> dict[str, Any]:
    """Summarize constructions, calls, and mutable writes inside one AS method."""
    method_name, declaration, body_start, body_end = method
    # Mask per method rather than per class: one malformed/odd quoted string in
    # an unrelated method must not hide every effect after it in the file.
    method_code = code[body_start:body_end]
    syntax = mask_actionscript_strings(method_code)
    source_line_offset = code.count("\n", 0, body_start)
    call_pattern = re.compile(
        r"(?P<callee>[A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)*)\s*\("
    )
    constructor_pattern = re.compile(
        r"\bnew\s+(?P<type>[A-Za-z_$][A-Za-z0-9_$.]*)\s*\("
    )
    ignored_calls = {"if", "for", "while", "switch", "catch", "function", "with"}
    constructors: list[dict[str, Any]] = []
    for match in constructor_pattern.finditer(syntax):
        global_match_start = body_start + match.start()
        opening = syntax.find("(", match.start("type") + len(match.group("type")))
        try:
            closing = matching_delimiter(code, body_start + opening, "(", ")")
        except ValueError:
            continue
        constructors.append({
            "type": match.group("type"),
            "arguments": split_actionscript_arguments(code[body_start + opening + 1:closing]),
            "source_line": source_line_offset + method_code.count("\n", 0, match.start()) + 1,
            "guards": enclosing_actionscript_guards(code, global_match_start, body_start),
        })

    calls: list[dict[str, Any]] = []
    for match in call_pattern.finditer(syntax):
        global_match_start = body_start + match.start()
        callee = match.group("callee")
        leaf = callee.rsplit(".", 1)[-1]
        if leaf in ignored_calls:
            continue
        prefix = syntax[max(0, match.start() - 8):match.start()].rstrip()
        if prefix.endswith("new"):
            continue
        opening = syntax.find("(", match.start("callee") + len(callee))
        try:
            closing = matching_delimiter(code, body_start + opening, "(", ")")
        except ValueError:
            continue
        calls.append({
            "callee": callee,
            "arguments": split_actionscript_arguments(code[body_start + opening + 1:closing]),
            "source_line": source_line_offset + method_code.count("\n", 0, match.start()) + 1,
            "guards": enclosing_actionscript_guards(code, global_match_start, body_start),
        })

    write_pattern = re.compile(
        r"(?P<target>(?:this\.)?[A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)*)"
        r"\s*(?P<operator>\+\+|--|\+=|-=|(?<![=!<>])=(?!=))"
    )
    visual_fields = {"visible", "alpha", "x", "y", "rotation", "scaleX", "scaleY", "width", "height"}
    writes: list[dict[str, Any]] = []
    for match in write_pattern.finditer(syntax):
        target = match.group("target")
        leaf = target.rsplit(".", 1)[-1]
        if "." not in target and not leaf.startswith("m_") and leaf not in visual_fields:
            continue
        value_end = syntax.find(";", match.end())
        if value_end < 0:
            value_end = len(method_code)
        global_match_start = body_start + match.start()
        value = code[body_start + match.end():body_start + value_end].strip()
        writes.append({
            "target": target,
            "operator": match.group("operator"),
            "value_expression": value[:240],
            "source_line": source_line_offset + method_code.count("\n", 0, match.start()) + 1,
            "guards": enclosing_actionscript_guards(code, global_match_start, body_start),
        })
    return {
        "method": method_name,
        "source_line": code.count("\n", 0, declaration) + 1,
        "constructors": constructors,
        "calls": calls,
        "writes": writes,
    }


def room_effect_categories(method_name: str, effects: dict[str, Any]) -> list[str]:
    text = " ".join(
        [method_name]
        + [call["callee"] for call in effects["calls"]]
        + [write["target"] for write in effects["writes"]]
        + [constructor["type"] for constructor in effects["constructors"]]
    ).casefold()
    categories: list[str] = []
    for pattern, category in (
        (r"dynamicdata|staticdata|m_currfloor|m_currkeys|m_has|healall|checkpoint|reward|chest", "campaign_or_persistent_world_state"),
        (r"transition|setscene|roomindex|roomtransition|teleport|elevator", "room_or_screen_transition"),
        (r"oncoll|collision|m_issolid|wallcoll|buttonzone", "collision_or_interaction_dispatch"),
        (r"interation|interaction|button|chat|dialog|text", "player_interaction_or_dialogue"),
        (r"sound|music|ambience|playsound", "audio_trigger_or_policy"),
        (r"animation|playhealed|playanim", "character_or_object_animation"),
        (r"sprite|tween|timeline|alpha|visible|addchild|removechild", "visual_or_timeline_presentation"),
    ):
        if re.search(pattern, text):
            categories.append(category)
    if not categories:
        categories.append("object_lifecycle_or_helper_behavior")
    return categories


def add_room_behavior_source_inventory(
    rows: list[dict[str, str]],
    *,
    inventory: dict[str, Any],
    source_root: Path,
    source_file: Path,
    source_text: str,
    dispatch_rules: list[dict[str, Any]],
    fallback_record: dict[str, Any],
) -> Counter[str]:
    """Index factory methods and the reachable room-object class effect surface."""
    counts: Counter[str] = Counter()
    repository_root = Path(str(inventory.get("reference_root", "")))
    original_script_root = EXPORT_DIR / "script/scripts"
    script_sources: dict[str, Path] = {
        path.relative_to(source_root).as_posix(): path
        for path in sorted((source_root / "scripts").rglob("*.as"))
    }
    edited_paths = set(script_sources)
    if original_script_root.is_dir():
        for path in sorted(original_script_root.rglob("*.as")):
            relative = f"scripts/{path.relative_to(original_script_root).as_posix()}"
            script_sources.setdefault(relative, path)

    def path_label(path: Path) -> str:
        try:
            return path.relative_to(repository_root).as_posix()
        except ValueError:
            return path.as_posix()

    script_files_by_stem: dict[str, list[tuple[str, Path]]] = defaultdict(list)
    for relative, path in script_sources.items():
        script_files_by_stem[path.stem].append((relative, path))
    class_index: dict[str, list[dict[str, Any]]] = {}

    def load_class_candidates(short_name: str) -> list[dict[str, Any]]:
        if short_name in class_index:
            return class_index[short_name]
        candidates: list[dict[str, Any]] = []
        for relative, path in script_files_by_stem.get(short_name, []):
            try:
                raw = path.read_text(encoding="utf-8-sig")
            except (OSError, UnicodeError):
                continue
            code = strip_comments(raw)
            declaration = re.search(
                r"\b(?:class|interface)\s+(?P<name>[A-Za-z_$][\w$]*)"
                r"(?:\s+extends\s+(?P<parent>[A-Za-z_$][\w$.]*))?",
                code,
            )
            if not declaration:
                continue
            package_match = re.search(r"\bpackage(?:\s+([A-Za-z0-9_.]+))?\s*\{", code)
            package = package_match.group(1) if package_match and package_match.group(1) else ""
            imports = re.findall(r"\bimport\s+([A-Za-z0-9_.*]+)\s*;", code)
            candidates.append({
                "class_name": declaration.group("name"),
                "qualified_name": f"{package}.{declaration.group('name')}" if package else declaration.group("name"),
                "package": package,
                "parent": declaration.group("parent"),
                "imports": imports,
                "source_path": relative,
                "file": path,
                "code": code,
                "methods": action_script_functions(code),
                "is_edited_source": relative in edited_paths,
            })
        class_index[short_name] = candidates
        return candidates

    def resolve_type(type_name: str, package: str) -> list[dict[str, Any]]:
        short_name = type_name.rsplit(".", 1)[-1]
        candidates = load_class_candidates(short_name)
        if "." in type_name:
            qualified = [item for item in candidates if item["qualified_name"] == type_name]
            if qualified:
                return qualified
        same_package = [item for item in candidates if item["package"] == package]
        if same_package:
            return same_package
        if len(candidates) <= 1:
            return candidates
        return candidates

    base_code = strip_comments(source_text)
    base_methods = {
        method[0]: method for method in action_script_functions(base_code)
    }
    invoked_methods = {
        name
        for rule in [*dispatch_rules, fallback_record]
        for name in rule.get("handler_methods", [])
    }
    invoked_methods.update({name for name in base_methods if name.startswith("Add") and name != "AddObject"})
    pending_types: list[tuple[str, str, str]] = []
    for method_name in sorted(invoked_methods):
        method = base_methods.get(method_name)
        if method is None:
            add_row(
                rows,
                kind="room_behavior_handler",
                id_or_name=f"base:room_handler/{method_name}",
                source=source_location(path_label(source_file)),
                recovery="current_edited_source_AddObject_handler_index",
                conversion="factory_handler_source_missing",
                validation="dispatch_reference_without_method_body",
                notes={"method": method_name},
            )
            counts["room_behavior_handler_missing_body"] += 1
            continue
        effects = room_method_effects(base_code, method)
        for constructor in effects["constructors"]:
            pending_types.append((constructor["type"], f"BaseTopDownLevel.{method_name}", "factory_constructor"))
        add_row(
            rows,
            kind="room_behavior_handler",
            id_or_name=f"base:room_handler/{method_name}",
            source=source_location(path_label(source_file), effects["source_line"]),
            recovery="edited_source_factory_method_with_overlay_precedence",
            conversion="source_factory_inventory_only_not_Godot_converted",
            validation="constructor_calls_state_writes_and_guarded_calls_indexed",
            notes={
                "method": method_name,
                "constructors": effects["constructors"],
                "calls": effects["calls"],
                "mutable_writes": effects["writes"],
                "effect_categories": room_effect_categories(method_name, effects),
            },
        )
        counts["room_behavior_handler"] += 1
        counts["room_behavior_factory_constructor_calls"] += len(effects["constructors"])
        counts["room_behavior_factory_state_writes"] += len(effects["writes"])

    reachable: dict[str, dict[str, Any]] = {}
    unresolved_types: dict[str, set[str]] = defaultdict(set)
    while pending_types:
        type_name, reached_via, relationship = pending_types.pop(0)
        candidates = resolve_type(type_name, "TopDown.LevelObjects")
        if not candidates:
            unresolved_types[type_name].add(reached_via)
            continue
        for candidate in candidates:
            source_path = candidate["source_path"]
            newly_reachable = source_path not in reachable
            if newly_reachable:
                reachable[source_path] = {**candidate, "reached_via": set()}
            reachable[source_path]["reached_via"].add(f"{relationship}:{reached_via}")
            if not newly_reachable:
                continue
            current = reachable[source_path]
            parent = current.get("parent")
            if parent:
                pending_types.append((parent, current["qualified_name"], "extends"))
            # Follow constructed helper classes only within the room-object package;
            # framework/UI dependencies remain explicit call/type references, not a
            # recursive crawl into the whole game.
            if current["package"].startswith("TopDown.LevelObjects"):
                for method in current["methods"]:
                    method_effects = room_method_effects(current["code"], method)
                    for constructor in method_effects["constructors"]:
                        pending_types.append((
                            constructor["type"],
                            f"{current['qualified_name']}.{method[0]}",
                            "nested_constructor",
                        ))

    for class_info in sorted(reachable.values(), key=lambda item: item["qualified_name"]):
        class_name = class_info["class_name"]
        qualified_name = class_info["qualified_name"]
        class_id = f"base:room_type/{qualified_name}"
        source = source_location(class_info["source_path"])
        effect_ids: list[str] = []
        parent_candidates = resolve_type(class_info["parent"], class_info["package"]) if class_info["parent"] else []
        parent_names = [candidate["qualified_name"] for candidate in parent_candidates]
        add_row(
            rows,
            kind="room_interaction_class",
            id_or_name=class_id,
            source=source,
            recovery="edited_source_overlay_with_original_swf_only_classes",
            conversion="interaction_class_inventory_only_not_Godot_converted",
            validation="class_and_inheritance_links_indexed",
            notes={
                "class_name": class_name,
                "qualified_class_name": qualified_name,
                "base_class": class_info["parent"],
                "resolved_base_classes": parent_names,
                "method_count": len(class_info["methods"]),
                "reached_via": sorted(class_info["reached_via"]),
                "source_overlay": "edited_source_wins_path_overlap" if class_info["is_edited_source"] else "original_swf_only_class",
            },
        )
        counts["room_interaction_class"] += 1
        for method in class_info["methods"]:
            effects = room_method_effects(class_info["code"], method)
            method_name = effects["method"]
            line = effects["source_line"]
            effect_id = f"base:room_effect/{qualified_name}/{method_name}/line/{line}"
            effect_ids.append(effect_id)
            categories = room_effect_categories(method_name, effects)
            role = (
                "player_interaction_callback" if method_name in {"OnInteration", "OnPotentialInteration"}
                else "collision_callback" if method_name in {"OnColl", "OnCollision"}
                else "object_visual_setup" if method_name in {"AddSprite", "AddVisuals"}
                else "object_cleanup" if method_name == "Cleanup"
                else "constructor" if method_name == class_name
                else "transition_or_state_callback" if re.search(r"Transition|Teleport|Unlock|Heal|Reward", method_name, re.IGNORECASE)
                else "other_source_method"
            )
            for constructor in effects["constructors"]:
                nested_type = constructor["type"]
                if resolve_type(nested_type, class_info["package"]):
                    counts["room_interaction_nested_source_constructions"] += 1
            add_row(
                rows,
                kind="room_interaction_effect",
                id_or_name=effect_id,
                source=source_location(class_info["source_path"], line),
                recovery="edited_source_overlay_with_original_swf_only_classes",
                conversion="source_effect_map_only_not_Godot_converted",
                validation="direct_calls_mutations_constructors_and_guards_indexed",
                notes={
                    "class_name": class_name,
                    "qualified_class_name": qualified_name,
                    "method": method_name,
                    "method_role": role,
                    "effect_categories": categories,
                    "constructors": effects["constructors"],
                    "calls": effects["calls"],
                    "mutable_writes": effects["writes"],
                },
            )
            counts["room_interaction_effect"] += 1
            counts["room_interaction_method_calls"] += len(effects["calls"])
            counts["room_interaction_state_writes"] += len(effects["writes"])
        # Backpatch the declared class-to-effect edge list after its methods have been emitted.
        class_row = next(row for row in rows if row["kind"] == "room_interaction_class" and row["id_or_name"] == class_id)
        class_notes = json.loads(class_row["notes"])
        class_notes["effect_ids"] = effect_ids
        class_row["notes"] = csv_quote(class_notes)

    for unresolved, reasons in sorted(unresolved_types.items()):
        add_row(
            rows,
            kind="room_behavior_external_type",
            id_or_name=f"base:room_external_type/{unresolved}",
            source=";".join(sorted(reasons)),
            recovery="source_type_reference_not_defined_in_recovered_script_overlay",
            conversion="external_or_library_type_reference",
            validation="implementation_outside_recovered_room_script_classes",
            notes={"type_name": unresolved, "reached_via": sorted(reasons)},
        )
        counts["room_behavior_external_type"] += 1

    room_family_count = sum(row["kind"] == "room_object_family" for row in rows)
    room_dispatch_count = sum(row["kind"] == "room_behavior_dispatch" for row in rows)
    room_instance_count = sum(
        row["kind"] in {"room_object_instance", "source_room_object_instance"}
        for row in rows
    )
    room_instance_dispatch_count = sum(
        row["kind"] in {"room_object_instance", "source_room_object_instance"}
        and row["conversion"] == "source_dispatch_linked_not_Godot_converted"
        for row in rows
    )
    add_row(
        rows,
        kind="completed_reachability_audit",
        id_or_name="room_interaction_source_effects",
        source="BaseTopDownLevel.AddObject families, factory handlers, reachable room-object classes, and recovered source overlay",
        recovery="room_dispatch_factory_class_hierarchy_and_method_effects_reconciled",
        conversion="Godot_room_components_and_campaign_services_deferred_to_complete_migration",
        validation="all_room_families_have_dispatch_and_reachable_source_effect_inventory",
        notes={
            "room_object_families": room_family_count,
            "dispatch_families": room_dispatch_count,
            "room_instances_linked_to_dispatch": room_instance_dispatch_count,
            "normalized_and_source_room_instances": room_instance_count,
            "factory_handlers": counts["room_behavior_handler"],
            "reachable_source_classes_and_ancestors": counts["room_interaction_class"],
            "method_effect_records": counts["room_interaction_effect"],
            "guarded_call_sites": counts["room_interaction_method_calls"],
            "mutable_state_writes": counts["room_interaction_state_writes"],
            "external_or_library_types": counts["room_behavior_external_type"],
            "source_overlay_policy": "edited source wins path overlap; original SWF scripts fill absent edited paths",
        },
    )
    add_row(
        rows,
        kind="deferred_migration_audit",
        id_or_name="room_interaction_conversion",
        source="room objects, collision/interact callbacks, room transitions, chests, healing/checkpoints, and campaign state effects",
        recovery="source_behavior_inventory_complete",
        conversion="Godot_interactable_components_and_campaign_services_not_converted",
        validation="complete_migration_backlog_not_reference_recovery_gap",
        notes="Preserve these recovered effects while implementing scene integration, collision flow, checkpoint/save semantics, rewards, and room transition presentation.",
    )

    counts["room_interaction_overlay_script_count"] = len(script_sources)
    counts["room_interaction_edited_script_count"] = len(edited_paths)
    counts["room_interaction_classes_with_methods"] = len(reachable)
    return counts


def add_progression_flow_inventory(rows: list[dict[str, str]]) -> Counter[str]:
    """Join campaign event flows to exact guarded state/effect sites and save keys."""
    inventory = read_json(SOURCE_INVENTORY)
    repository_root = Path(str(inventory.get("reference_root", "")))
    source_root = edited_source_root(inventory)
    original_script_root = EXPORT_DIR / "script/scripts"
    script_sources: dict[str, Path] = {
        path.relative_to(source_root).as_posix(): path
        for path in sorted((source_root / "scripts").rglob("*.as"))
    }
    edited_paths = set(script_sources)
    if original_script_root.is_dir():
        for path in sorted(original_script_root.rglob("*.as")):
            script_sources.setdefault(
                f"scripts/{path.relative_to(original_script_root).as_posix()}", path
            )

    def path_label(path: Path) -> str:
        try:
            return path.relative_to(repository_root).as_posix()
        except ValueError:
            return path.as_posix()

    # These are the source entry points that join battle outcomes, campaign
    # progression, floor selection, checkpoints, evolution, and persistence.
    flows = [
        ("scripts/BattleSystems/BattleScreen.as", "OpenVictoryMenus", "victory_outcome_and_rewards"),
        ("scripts/BattleSystems/Other/BaseBattleFinishScreen.as", "BringInScreen", "xp_level_talent_evolution_and_nuzlocke"),
        ("scripts/BattleSystems/Other/BaseBattleFinishScreen.as", "BringInEvolutionScreen", "evolution_popup_entry"),
        ("scripts/BattleSystems/Other/BaseBattleFinishScreen.as", "ExitEvolutionScreen", "evolution_popup_return"),
        ("scripts/BattleSystems/WinScreen/EvolvingPopup.as", "BringInForMinion", "evolution_candidate_selection"),
        ("scripts/BattleSystems/WinScreen/EvolvingPopup.as", "FinishEvolution", "evolution_commit_and_dex_update"),
        ("scripts/Utilities/Utility.as", "UnlockNextFloor", "milestone_floor_unlock_rules"),
        ("scripts/LevelSelect/LevelSelectScreen.as", "StartActivate", "level_select_unlock_and_mode_visibility"),
        ("scripts/LevelSelect/LevelSelectScreen.as", "GetTotalNumberOfUnlockedFloors", "level_select_unlocked_floor_count"),
        ("scripts/LevelSelect/FloorInformationObject.as", "GoButtonPressed", "floor_entry_and_party_reset"),
        ("scripts/BattleSystems/LoseScreen/LoseScreen.as", "GotoTopDownScreen_part2", "loss_checkpoint_or_infinite_run_end"),
        ("scripts/PresistentData/DynamicData.as", "SetNewReturnToOnDeathPoint", "checkpoint_capture"),
        ("scripts/PresistentData/DynamicData.as", "SetToReturnToOnDeathPoint", "checkpoint_restore"),
        ("scripts/PresistentData/DynamicData.as", "SaveAllData", "three_slot_save_write"),
        ("scripts/PresistentData/DynamicData.as", "LoadData", "three_slot_load_and_mod_rebuild_order"),
        ("scripts/PresistentData/DynamicData.as", "UpdateTrainersStarsForCurrentTrainer", "trainer_star_and_first_win_progress"),
        ("scripts/PresistentData/DynamicData.as", "AddAllStarsAndSetThatWeHaveBeatenAllTheTrainers", "synthetic_all_trainers_completion"),
        ("scripts/PresistentData/DynamicData.as", "SetupDataForBringingInANewFloor", "new_floor_progression_reset"),
        ("scripts/PresistentData/StaticData.as", "GetMoneyRewardForCurrentFloor", "floor_money_reward_formula"),
        ("scripts/PresistentData/StaticData.as", "GetGemTierRewardForCurrentFloor", "floor_gem_reward_tier"),
        ("scripts/PresistentData/StaticData.as", "GetCurrentLevelFromFloorAndRoom", "floor_room_to_level_dispatch"),
        ("scripts/PresistentData/StaticData.as", "PreBuildRoomsForFloor", "floor_room_reachability_build"),
    ]
    counts: Counter[str] = Counter()
    source_cache: dict[str, tuple[str, list[tuple[str, int, int, int]]]] = {}
    missing_flows: list[str] = []
    for source_path, method_name, flow_kind in flows:
        path = script_sources.get(source_path)
        if path is None or not path.is_file():
            missing_flows.append(f"{source_path}::{method_name}")
            continue
        if source_path not in source_cache:
            code = strip_comments(path.read_text(encoding="utf-8-sig"))
            source_cache[source_path] = (code, declared_actionscript_methods(code))
        code, methods = source_cache[source_path]
        matches = [method for method in methods if method[0] == method_name]
        if not matches:
            missing_flows.append(f"{source_path}::{method_name}")
            continue
        # Source flow entry points are unique; if the compiler export ever adds an
        # overload, record each body separately instead of silently dropping one.
        for overload_index, method in enumerate(matches, 1):
            effects = room_method_effects(code, method)
            line = effects["source_line"]
            overload_suffix = f"/overload/{overload_index}" if len(matches) > 1 else ""
            flow_id = f"base:progression_flow/{method_name}{overload_suffix}"
            call_sites = effects["calls"]
            writes = effects["writes"]
            effect_count = len(call_sites) + len(writes)
            add_row(
                rows,
                kind="progression_flow",
                id_or_name=flow_id,
                source=source_location(path_label(path), line),
                recovery="edited_source_overlay_with_original_swf_only_fallback",
                conversion="campaign_state_service_not_Godot_converted",
                validation="method_calls_state_writes_and_enclosing_guards_indexed",
                notes={
                    "flow": flow_kind,
                    "source_class": path.stem,
                    "method": method_name,
                    "call_sites_with_arguments_and_guards": call_sites,
                    "state_writes_with_values_and_guards": writes,
                    "effect_site_count": effect_count,
                    "source_overlay": "edited source" if source_path in edited_paths else "original SWF-only class",
                },
            )
            counts["progression_flow"] += 1
            counts["progression_flow_call_sites"] += len(call_sites)
            counts["progression_flow_state_writes"] += len(writes)

            if method_name == "SaveAllData":
                for call_index, call in enumerate(call_sites, 1):
                    if call["callee"].rsplit(".", 1)[-1] != "SaveValue" or not call["arguments"]:
                        continue
                    field_match = re.match(r"\s*(['\"])(.*?)\1\s*$", call["arguments"][0], re.DOTALL)
                    if not field_match:
                        continue
                    field = field_match.group(2)
                    add_row(
                        rows,
                        kind="progression_save_field",
                        id_or_name=f"base:save_field/{field}/line/{call['source_line']}/write/{call_index}",
                        source=source_location(path_label(path), call["source_line"]),
                        recovery="literal_SaveValue_call_in_source_SaveAllData",
                        conversion="Godot_save_schema_key_not_migrated",
                        validation="source_key_payload_indices_and_guards_recovered",
                        notes={
                            "serialized_key": field,
                            "SaveValue_arguments": call["arguments"],
                            "enclosing_guards": call["guards"],
                            "save_slot_method_argument": "SaveAllData(param1)",
                        },
                    )
                    counts["progression_save_field"] += 1

    dynamic_path = "scripts/PresistentData/DynamicData.as"
    if dynamic_path in script_sources:
        path = script_sources[dynamic_path]
        raw = path.read_text(encoding="utf-8-sig")
        code = strip_comments(raw)
        field_pattern = re.compile(
            r"\b(?P<visibility>public|protected|private)?\s*(?:static\s+)?var\s+"
            r"(?P<field>m_[A-Za-z0-9_$]+)\s*:\s*(?P<type>[A-Za-z_$][A-Za-z0-9_.$<>]*)"
        )
        save_keys = {
            json.loads(row["notes"]).get("serialized_key")
            for row in rows if row["kind"] == "progression_save_field"
        }
        for match in field_pattern.finditer(code):
            field = match.group("field")
            normalized = field.casefold()
            if re.search(r"floor|room|position|direction|transition|death|return", normalized):
                category = "floor_room_and_checkpoint_state"
            elif re.search(r"money|key|gem|star|seal|currency|reward", normalized):
                category = "currency_reward_and_collectibles"
            elif re.search(r"minion|party|owned|seen|evol", normalized):
                category = "party_roster_and_dex"
            elif re.search(r"unlock|beaten|trainer|map|tutorial|infinite|hard|mod|nuzlocke", normalized):
                category = "campaign_gates_and_modes"
            else:
                category = "save_configuration_or_metadata"
            line = code.count("\n", 0, match.start()) + 1
            add_row(
                rows,
                kind="progression_state_field",
                id_or_name=f"base:progression_state/{field}",
                source=source_location(path_label(path), line),
                recovery="edited_DynamicData_declaration_with_overlay_precedence",
                conversion="campaign_state_resource_not_migrated",
                validation="typed_state_field_linked_to_source_save_key_when_present",
                notes={
                    "field": field,
                    "source_type": match.group("type"),
                    "visibility": match.group("visibility") or "package_default",
                    "semantic_group": category,
                    "serialized_by_SaveAllData": field in save_keys,
                },
            )
            counts["progression_state_field"] += 1

    for missing in missing_flows:
        add_row(
            rows,
            kind="progression_flow_missing_source",
            id_or_name=f"base:progression_flow_missing/{trainer_slug(missing)}",
            source=missing,
            recovery="requested_source_method_not_found_in_overlay",
            conversion="not_inventoried",
            validation="progression_source_gap",
            notes="The flow audit could not find this expected method at the selected source path.",
        )
        counts["progression_flow_missing_source"] += 1

    expected_save_field_count = 47
    progression_complete = not missing_flows and counts["progression_save_field"] == expected_save_field_count
    audit_kind = "completed_reachability_audit" if progression_complete else "open_reachability_audit"
    add_row(
        rows,
        kind=audit_kind,
        id_or_name="progression_reward_source_flows",
        source="battle outcomes, floor rewards/unlocks, evolution, level select, death return, DynamicData save/load, and StaticData room/floor dispatch",
        recovery="source_entry_points_and_persisted_state_reconciled",
        conversion="Godot_campaign_progression_and_save_schema_not_connected",
        validation="source_progression_flows_complete" if progression_complete else "source_progression_audit_incomplete",
        notes={
            "flow_methods": counts["progression_flow"],
            "call_sites": counts["progression_flow_call_sites"],
            "state_writes": counts["progression_flow_state_writes"],
            "dynamic_data_state_fields": counts["progression_state_field"],
            "literal_save_field_calls": counts["progression_save_field"],
            "expected_literal_save_field_calls": expected_save_field_count,
            "missing_flows": missing_flows,
            "scope_note": "Source behavior inventory only; reward, save, and campaign services remain runtime migration work.",
        },
    )
    counts["completed_source_audit_progression"] = int(progression_complete)
    counts["open_reachability_audit"] += int(not progression_complete)
    if progression_complete:
        add_row(
            rows,
            kind="deferred_migration_audit",
            id_or_name="progression_system_conversion",
            source="battle result rewards, level unlocks, XP/evolution, checkpoint travel, and three-slot save/load",
            recovery="source_progression_inventory_complete",
            conversion="Godot_campaign_state_service_and_source_save_compatibility_not_converted",
            validation="complete_migration_backlog_not_reference_recovery_gap",
            notes="Implement only after linking the exact source guards, save keys, reward tables, room effects, and level-selection rules in the migrated campaign service.",
        )
        counts["deferred_progression_migration"] = 1
    return counts


def add_menu_route_and_availability_rows(
    rows: list[dict[str, str]],
    *,
    menu_file: Path,
    source_path: str,
    menu_raw: str,
    menu_code: str,
    class_name: str,
    parent_class: str | None,
    field_types: dict[str, set[str]],
    bound_handlers: set[str],
) -> Counter[str]:
    """Inventory direct menu/modal calls and control availability assignments."""
    counts: Counter[str] = Counter()
    methods = action_script_functions(menu_code)
    method_ranges = [(name, body_start, body_end) for name, _start, body_start, body_end in methods]

    def method_at(offset: int) -> tuple[str, int, int]:
        for method_name, body_start, body_end in reversed(method_ranges):
            if body_start <= offset <= body_end:
                return method_name, body_start, body_end
        return "<outside-method>", 0, len(menu_code)

    route_pattern = re.compile(
        r"(?P<receiver>(?:(?:this|super)\.)?[A-Za-z_$][A-Za-z0-9_$]*(?:\[[^\]\r\n]+\])?(?:\.[A-Za-z_$][A-Za-z0-9_$]*(?:\[[^\]\r\n]+\])?)*)"
        r"\.(?P<operation>BringIn|BringOut|Open|Close|Toggle|SetSceneTo)\s*\("
    )
    route_index_by_line: Counter[int] = Counter()
    for route in route_pattern.finditer(menu_code):
        opening = menu_code.find("(", route.start("operation"))
        try:
            closing = matching_delimiter(menu_code, opening, "(", ")")
        except ValueError:
            continue
        arguments = menu_code[opening + 1:closing].strip()
        receiver = route.group("receiver")
        operation = route.group("operation")
        route_method, body_start, _body_end = method_at(route.start())
        line = menu_raw.count("\n", 0, route.start()) + 1
        route_index_by_line[line] += 1

        target_state_match = re.match(r"\s*GameState\.([A-Za-z0-9_]+)", arguments) if operation == "SetSceneTo" else None
        leaf = receiver.rsplit(".", 1)[-1]
        leaf_field = re.match(r"(m_[A-Za-z0-9_$]+)", leaf)
        if operation == "SetSceneTo":
            target_kind = "root_screen_state" if target_state_match else "dynamic_screen_state"
            resolved_targets: list[str] = []
        elif receiver == "this":
            target_kind = "current_menu_class"
            resolved_targets = [class_name]
        elif receiver == "super":
            resolved_targets = [parent_class] if parent_class else []
            target_kind = "typed_superclass" if parent_class else "unresolved_superclass"
        elif leaf_field:
            resolved_targets = sorted(field_types.get(leaf_field.group(1), set()))
            target_kind = "typed_menu_field" if len(resolved_targets) == 1 else (
                "ambiguous_menu_field" if resolved_targets else "untyped_menu_field"
            )
        else:
            resolved_targets = []
            target_kind = "receiver_not_resolved_to_menu_field"

        callback_names = list(dict.fromkeys(re.findall(r"\bthis\.([A-Za-z_$][A-Za-z0-9_$]*)\b", arguments)))
        add_row(
            rows,
            kind="menu_route_edge",
            id_or_name=f"base:menu_route/{source_path}/line/{line}/call/{route_index_by_line[line]}",
            source=source_location(str(menu_file), line),
            recovery="current_edited_menu_route_callsite",
            conversion="Godot_menu_route_not_connected",
            validation=target_kind,
            notes={
                "menu_class": class_name,
                "source_method": route_method,
                "source_method_is_bound_callback": route_method in bound_handlers,
                "operation": operation,
                "receiver": receiver,
                "resolved_target_classes": resolved_targets,
                "target_game_state": f"GameState.{target_state_match.group(1)}" if target_state_match else None,
                "arguments": arguments,
                "callback_methods_in_arguments": callback_names,
                "enclosing_if_and_loop_guards": enclosing_actionscript_guards(menu_code, route.start(), body_start),
            },
        )
        counts["menu_route_edges"] += 1
        counts[f"menu_route_target_{target_kind}"] += 1

    availability_pattern = re.compile(
        r"(?P<target>(?:(?:this|super)\.)?[A-Za-z_$][A-Za-z0-9_$]*(?:\[[^\]\r\n]+\])?(?:\.[A-Za-z_$][A-Za-z0-9_$]*(?:\[[^\]\r\n]+\])?)*)"
        r"\.(?P<property>visible|enabled|mouseEnabled|mouseChildren)\s*=\s*(?P<value>[^;\r\n]+)"
    )
    state_index_by_line: Counter[int] = Counter()
    for assignment in availability_pattern.finditer(menu_code):
        method_name, body_start, _body_end = method_at(assignment.start())
        line = menu_raw.count("\n", 0, assignment.start()) + 1
        state_index_by_line[line] += 1
        add_row(
            rows,
            kind="menu_control_availability",
            id_or_name=f"base:menu_availability/{source_path}/line/{line}/assignment/{state_index_by_line[line]}",
            source=source_location(str(menu_file), line),
            recovery="current_edited_menu_control_state_assignment",
            conversion="Godot_control_availability_not_connected",
            validation="assignment_and_enclosing_guards_indexed",
            notes={
                "menu_class": class_name,
                "source_method": method_name,
                "target": assignment.group("target"),
                "property": assignment.group("property"),
                "value_expression": assignment.group("value").strip(),
                "enclosing_if_and_loop_guards": enclosing_actionscript_guards(menu_code, assignment.start(), body_start),
            },
        )
        counts["menu_control_availability_rules"] += 1
    return counts


def add_menu_navigation_inventory(rows: list[dict[str, str]]) -> Counter[str]:
    inventory = read_json(SOURCE_INVENTORY)
    source_root = edited_source_root(inventory)
    script_root = source_root / "scripts"
    original_script_root = EXPORT_DIR / "script/scripts"
    script_sources: dict[str, Path] = {
        path.relative_to(source_root).as_posix(): path
        for path in sorted(script_root.rglob("*.as"))
    }
    edited_script_paths = set(script_sources)
    if original_script_root.is_dir():
        for original_path in sorted(original_script_root.rglob("*.as")):
            relative_path = f"scripts/{original_path.relative_to(original_script_root).as_posix()}"
            script_sources.setdefault(relative_path, original_path)
    method_pattern = re.compile(
        r"^\s*(?:(?:override|static|final)\s+)*(?:private|protected|public)\s+(?:override\s+)?function\s+(?P<name>[A-Za-z_$][A-Za-z0-9_$]*)\s*\(",
        re.MULTILINE,
    )
    menu_source_by_path = {
        str(row["source"]).split("::", 1)[-1]: row
        for row in rows if row["kind"] == "source_class/menu"
    }
    for source_path in script_sources:
        if source_path.startswith(("scripts/MainMenu/", "scripts/TopDown/Menus/")):
            menu_source_by_path.setdefault(source_path, {
                "kind": "source_class/menu",
                "id_or_name": f"source_class/menu/{source_path}",
                "source": source_path,
                "recovery": "recovered_original_swf_only_class" if source_path not in edited_script_paths else "recovered_edited_source",
                "conversion": "not_converted",
                "validation": "folder_scoped_menu_source",
                "notes": "Menu-tree class included by source path despite class-index category.",
            })
    menu_sources = [menu_source_by_path[path] for path in sorted(menu_source_by_path)]
    counts: Counter[str] = Counter()
    menu_field_types: dict[str, set[str]] = defaultdict(set)
    for field_file in script_sources.values():
        field_code = strip_comments(field_file.read_text(encoding="utf-8-sig"))
        for match in re.finditer(
            r"\bvar\s+(?P<field>m_[A-Za-z0-9_$]*)\s*:\s*(?P<class>[A-Za-z_$][A-Za-z0-9_$]*)",
            field_code,
        ):
            menu_field_types[match.group("field")].add(match.group("class"))
        for match in re.finditer(
            r"\b(?P<field>m_[A-Za-z0-9_$]*)\s*=\s*new\s+(?P<class>[A-Za-z_$][A-Za-z0-9_$]*)\s*\(",
            field_code,
        ):
            menu_field_types[match.group("field")].add(match.group("class"))

    for menu_source in menu_sources:
        source_reference = str(menu_source["source"])
        source_path = source_reference.split("::", 1)[-1]
        menu_file = script_sources.get(source_path, source_root / source_path)
        class_name = menu_file.stem
        package_name = ""
        method_count = 0
        action_binding_count = 0
        route_counts: Counter[str] = Counter()
        if menu_file.is_file():
            menu_raw = menu_file.read_text(encoding="utf-8-sig")
            menu_code = strip_comments(menu_raw)
            package_match = re.search(r"\bpackage\s+([A-Za-z0-9_.]+)", menu_code)
            package_name = package_match.group(1) if package_match else ""
            parent_match = re.search(
                r"\bclass\s+[A-Za-z_$][A-Za-z0-9_$]*\s+extends\s+([A-Za-z_$][A-Za-z0-9_$.]*)",
                menu_code,
            )
            parent_class = parent_match.group(1) if parent_match else None
            method_count = len(list(method_pattern.finditer(menu_code)))
            function_ranges = action_script_functions(menu_code)
            function_by_name = {name: (body_start, body_end) for name, _start, body_start, body_end in function_ranges}
            action_handlers: dict[str, dict[str, Any]] = {}
            action_index_by_line: Counter[int] = Counter()

            def add_menu_action_binding(
                kind: str,
                control: str,
                handler: str,
                event: str,
                start_offset: int,
                details: str,
            ) -> None:
                nonlocal action_binding_count
                line = menu_raw.count("\n", 0, start_offset) + 1
                action_index_by_line[line] += 1
                action_id = f"base:menu_action/{source_path}/line/{line}/binding/{action_index_by_line[line]}"
                add_row(
                    rows,
                    kind="menu_action_binding",
                    id_or_name=action_id,
                    source=source_location(str(menu_file), line),
                    recovery="current_edited_menu_source",
                    conversion="Godot_menu_action_not_connected",
                    validation="callback_handler_found" if handler in function_by_name else "callback_handler_not_found",
                    notes={
                        "menu_class": class_name,
                        "binding_kind": kind,
                        "control_or_receiver": control,
                        "event": event,
                        "callback": handler,
                        "details": details,
                    },
                )
                action_binding_count += 1
                counts["menu_action_bindings"] += 1
                if handler not in action_handlers:
                    action_handlers[handler] = {"source_line": line, "binding_ids": [action_id]}
                else:
                    action_handlers[handler]["binding_ids"].append(action_id)

            constructor_pattern = re.compile(r"\bnew\s+(?P<control>[A-Za-z_$][\w$]*Button)\s*\(")
            for constructor in constructor_pattern.finditer(menu_code):
                opening = menu_code.find("(", constructor.start())
                closing = matching_delimiter(menu_code, opening, "(", ")")
                arguments = menu_code[opening + 1:closing]
                first_argument = arguments.split(",", 1)[0].strip()
                callback = re.match(r"(?:this\.)?(?P<name>[A-Za-z_$][\w$]*)\s*$", first_argument)
                if callback is None:
                    continue
                before = menu_code[max(0, constructor.start() - 180):constructor.start()]
                assignments = list(re.finditer(r"this\.(?P<field>m_[A-Za-z0-9_$]+)\s*=\s*$", before))
                control_name = assignments[-1].group("field") if assignments else constructor.group("control")
                add_menu_action_binding(
                    "button_constructor_callback",
                    control_name,
                    callback.group("name"),
                    "activate",
                    constructor.start(),
                    arguments.strip(),
                )

            listener_pattern = re.compile(
                r"\.addEventListener\s*\(\s*(?P<event>[A-Za-z0-9_.]+)\s*,\s*(?:this\.)?(?P<callback>[A-Za-z_$][\w$]*)"
            )
            for listener in listener_pattern.finditer(menu_code):
                receiver_prefix = menu_code[max(0, listener.start() - 100):listener.start()]
                receiver_match = re.search(r"(?P<receiver>(?:this\.)?m_[A-Za-z0-9_$]+)\s*$", receiver_prefix)
                add_menu_action_binding(
                    "event_listener_callback",
                    receiver_match.group("receiver") if receiver_match else "<receiver-unresolved>",
                    listener.group("callback"),
                    listener.group("event"),
                    listener.start(),
                    menu_code[listener.start():menu_code.find(";", listener.start()) if ";" in menu_code[listener.start():] else listener.end()].strip(),
                )

            route_counts = add_menu_route_and_availability_rows(
                rows,
                menu_file=menu_file,
                source_path=source_path,
                menu_raw=menu_raw,
                menu_code=menu_code,
                class_name=class_name,
                parent_class=parent_class,
                field_types=menu_field_types,
                bound_handlers=set(action_handlers),
            )
            counts.update(route_counts)

            for handler, details in sorted(action_handlers.items()):
                body_range = function_by_name.get(handler)
                body = menu_code[body_range[0]:body_range[1]] if body_range else ""
                local_calls = list(dict.fromkeys(
                    f"{match.group(1) or ''}{match.group(2)}.{match.group(3)}"
                    for match in re.finditer(r"\b(this\.)?(m_[A-Za-z0-9_$]+)\.(BringIn|BringOut|Open|Close|Toggle|Update)\s*\(", body)
                ))
                visibility_changes = [
                    {"target": match.group(1), "visible": match.group(2).lower() == "true"}
                    for match in re.finditer(r"\bthis\.(m_[A-Za-z0-9_$]+)\.visible\s*=\s*(true|false)", body, re.IGNORECASE)
                ]
                target_states = re.findall(r"\bSetSceneTo\s*\(\s*GameState\.([A-Za-z0-9_]+)", body)
                add_row(
                    rows,
                    kind="menu_action_handler",
                    id_or_name=f"base:menu_handler/{source_path}/{handler}",
                    source=source_location(str(menu_file), details["source_line"]),
                    recovery="current_edited_menu_source",
                    conversion="Godot_menu_action_not_connected",
                    validation="handler_body_summarized" if body_range else "callback_method_body_unresolved",
                    notes={
                        "menu_class": class_name,
                        "handler": handler,
                        "binding_ids": details["binding_ids"],
                        "local_menu_calls": local_calls,
                        "visibility_changes": visibility_changes,
                        "target_game_states": target_states,
                    },
                )
                counts["menu_action_handlers"] += 1
        menu_id = f"base:menu/{source_path.removesuffix('.as')}"
        add_row(
            rows,
            kind="menu_entry",
            id_or_name=menu_id,
            source=source_location(str(menu_file)) if menu_file.is_file() else menu_source["source"],
            recovery=menu_source["recovery"],
            conversion="source_menu_not_Godot_converted",
            validation="menu_routes_and_control_availability_indexed",
            notes={
                "class_name": class_name,
                "package": package_name,
                "source_class_inventory_id": menu_source["id_or_name"],
                "source_method_count": method_count,
                "action_binding_count": action_binding_count,
                "route_edge_count": route_counts["menu_route_edges"],
                "control_availability_rule_count": route_counts["menu_control_availability_rules"],
                "reachable_route_audit_pending": False,
            },
        )
        counts["menu_entries"] += 1
        if action_binding_count:
            counts["menu_classes_with_action_bindings"] += 1
        else:
            counts["menu_classes_without_action_bindings"] += 1

    controller_file = script_root / "Utilities/ScreenController.as"
    main_file = script_root / "Main.as"
    controller_text = controller_file.read_text(encoding="utf-8-sig") if controller_file.is_file() else ""
    main_text = main_file.read_text(encoding="utf-8-sig") if main_file.is_file() else ""
    controller_code = strip_comments(controller_text)
    main_code = strip_comments(main_text)
    screen_classes = {
        field: class_name
        for field, class_name in re.findall(
            r"(?:public|private|protected)\s+var\s+(m_[A-Za-z0-9_]*Screen)\s*:\s*([A-Za-z0-9_]+)",
            controller_code,
        )
    }
    screen_states: dict[str, dict[str, Any]] = {}
    state_case_pattern = re.compile(
        r"case\s+GameState\.(?P<state>[A-Za-z0-9_]+)\s*:(?P<body>.*?)(?=case\s+GameState\.|default\s*:|$)",
        re.DOTALL,
    )
    for state_match in state_case_pattern.finditer(main_code):
        state_name = state_match.group("state")
        field_match = re.search(r"\b(m_[A-Za-z0-9_]*Screen)\b", state_match.group("body"))
        if not field_match:
            continue
        field_name = field_match.group(1)
        screen_states.setdefault(state_name, {
            "state": f"GameState.{state_name}",
            "screen_field": field_name,
            "screen_class": screen_classes.get(field_name),
            "source_line": main_text.count("\n", 0, state_match.start()) + 1,
        })
    for state_name, state_data in sorted(screen_states.items()):
        add_row(
            rows,
            kind="screen_state_entry",
            id_or_name=f"base:screen_state/GameState.{state_name}",
            source=source_location(str(main_file), state_data["source_line"]),
            recovery="current_Main_and_ScreenController_state_dispatch",
            conversion="root_screen_state_not_Godot_routed",
            validation="screen_state_to_controller_class_mapped" if state_data["screen_class"] else "screen_controller_class_unresolved",
            notes=state_data,
        )
        counts["root_screen_states"] += 1

    transition_calls = 0
    for relative_path, source_file in sorted(script_sources.items()):
        source_text = source_file.read_text(encoding="utf-8-sig")
        code_text = strip_comments(source_text)
        functions = list(method_pattern.finditer(code_text))
        call_index_by_line: Counter[int] = Counter()
        for call_match in re.finditer(r"\bSetSceneTo\s*\(", code_text):
            declaration_prefix = code_text[max(0, call_match.start() - 32):call_match.start()]
            if re.search(r"\bfunction\s*$", declaration_prefix):
                continue
            opening_paren = code_text.find("(", call_match.start())
            try:
                closing_paren = matching_delimiter(code_text, opening_paren, "(", ")")
            except ValueError:
                continue
            arguments = code_text[opening_paren + 1:closing_paren].strip()
            target_match = re.match(r"\s*GameState\.([A-Za-z0-9_]+)", arguments)
            target_state = target_match.group(1) if target_match else None
            line = source_text.count("\n", 0, call_match.start()) + 1
            call_index_by_line[line] += 1
            caller_method = "<outside-method>"
            for function_match in reversed(functions):
                if function_match.start() < call_match.start():
                    caller_method = function_match.group("name")
                    break
            package_match = re.search(r"\bpackage\s+([A-Za-z0-9_.]+)", code_text)
            package_name = package_match.group(1) if package_match else ""
            class_match = re.search(r"\bclass\s+([A-Za-z0-9_]+)", code_text)
            class_name = class_match.group(1) if class_match else source_file.stem
            add_row(
                rows,
                kind="menu_navigation_edge",
                id_or_name=f"base:menu_edge/{relative_path}/line/{line}/call/{call_index_by_line[line]}",
                source=source_location(str(source_file), line),
                recovery="current_edited_SetSceneTo_callsite" if relative_path in edited_script_paths else "original_swf_only_SetSceneTo_callsite",
                conversion="root_screen_transition_not_Godot_routed",
                validation="literal_GameState_transition_indexed" if target_state else "dynamic_screen_target_expression_indexed",
                notes={
                    "source_class": f"{package_name}.{class_name}" if package_name else class_name,
                    "source_method": caller_method,
                    "target_game_state": f"GameState.{target_state}" if target_state else None,
                    "target_state_expression": arguments,
                    "target_screen_class": screen_states.get(target_state, {}).get("screen_class") if target_state else None,
                    "call_arguments": arguments,
                },
            )
            if target_state:
                transition_calls += 1
            else:
                counts["dynamic_screen_transition_callsites"] += 1
    counts["direct_screen_transitions"] = transition_calls

    unresolved_route_kinds = {
        "dynamic_screen_state",
        "untyped_menu_field",
        "ambiguous_menu_field",
        "receiver_not_resolved_to_menu_field",
        "unresolved_superclass",
    }
    unresolved_route_targets = sum(counts.get(f"menu_route_target_{name}", 0) for name in unresolved_route_kinds)
    dynamic_screen_targets = counts["dynamic_screen_transition_callsites"]
    unresolved_root_screens = sum(
        row["kind"] == "screen_state_entry" and row["validation"] == "screen_controller_class_unresolved"
        for row in rows
    )
    route_target_summary = {
        key.removeprefix("menu_route_target_"): value
        for key, value in sorted(counts.items()) if key.startswith("menu_route_target_")
    }
    menu_audit_complete = unresolved_route_targets == 0 and dynamic_screen_targets == 0 and unresolved_root_screens == 0
    menu_audit_kind = "completed_reachability_audit" if menu_audit_complete else "open_reachability_audit"
    add_row(
        rows,
        kind=menu_audit_kind,
        id_or_name="menu_routes_and_control_availability",
        source="edited MainMenu/TopDown/Menus sources overlaid on original SWF-only menu scripts; all source-script SetSceneTo callsites",
        recovery="all_menu_tree_sources_joined_with_current_overlay_precedence",
        conversion="Godot_menu_runtime_routing_deferred_to_complete_migration",
        validation="all_static_routes_and_control_state_rules_indexed" if menu_audit_complete else "menu_route_targets_or_screen_states_explicitly_unresolved",
        notes={
            "menu_tree_classes": counts["menu_entries"],
            "edited_menu_tree_classes": sum(
                path.startswith(("scripts/MainMenu/", "scripts/TopDown/Menus/"))
                for path in menu_source_by_path if path in edited_script_paths
            ),
            "original_swf_only_menu_tree_classes": sum(
                path.startswith(("scripts/MainMenu/", "scripts/TopDown/Menus/"))
                for path in menu_source_by_path if path not in edited_script_paths
            ),
            "button_and_listener_bindings": counts["menu_action_bindings"],
            "callback_handler_summaries": counts["menu_action_handlers"],
            "modal_and_root_route_calls": counts["menu_route_edges"],
            "route_target_resolution_counts": route_target_summary,
            "control_visibility_and_input_rules": counts["menu_control_availability_rules"],
            "root_screen_states": counts["root_screen_states"],
            "literal_screen_transitions": counts["direct_screen_transitions"],
            "dynamic_screen_target_calls": dynamic_screen_targets,
            "unresolved_menu_route_targets": unresolved_route_targets,
            "unresolved_root_screens": unresolved_root_screens,
            "source_overlay_policy": "edited class wins on path overlap; original SWF scripts included where edited path is absent",
        },
    )
    if menu_audit_complete:
        counts["completed_source_audit_menu"] = 1
    else:
        counts["open_reachability_audit"] += 1

    if not controller_file.is_file() or not main_file.is_file():
        add_row(
            rows,
            kind="open_reachability_audit",
            id_or_name="menu_root_screen_registry",
            source=source_location(str(script_root)),
            recovery="required_menu_root_sources_missing",
            conversion="screen_registry_unresolved",
            validation="menu_root_mapping_incomplete",
            notes={"ScreenController.as": controller_file.is_file(), "Main.as": main_file.is_file()},
        )
        counts["menu_root_mapping_errors"] += 1
    return counts


def asset_identity(container: str, filename: str) -> str:
    stem = Path(filename).stem
    extension = Path(filename).suffix.lower()
    match = re.match(r"^(\d+)_(.+)$", stem)
    if match:
        return f"{container}|{match.group(1)}|{match.group(2)}|{extension}"
    return f"{container}|{stem}|{extension}"


def add_original_assets(rows: list[dict[str, str]]) -> Counter[str]:
    counts: Counter[str] = Counter()
    folder_kinds = {
        "image": ("asset_image", {".png", ".jpg", ".jpeg"}),
        "sound": ("asset_sound", {".mp3", ".wav", ".ogg"}),
        "font": ("asset_font", {".ttf", ".otf"}),
        "binaryData": ("asset_binary", {".bin"}),
    }
    for folder, (kind, extensions) in folder_kinds.items():
        asset_dir = EXPORT_DIR / folder
        if not asset_dir.is_dir():
            counts[f"missing_export_dir_{folder}"] += 1
            continue
        for asset in sorted(asset_dir.rglob("*")):
            if not asset.is_file() or asset.suffix.lower() not in extensions:
                continue
            original_asset_path = ROOT / "content/base/art/battle" / asset.name
            sidecar = original_asset_path.with_suffix(original_asset_path.suffix + ".import")
            if kind == "asset_image" and original_asset_path.is_file():
                conversion = "reused_in_playable_battle"
                validation = "godot_import_metadata_present" if sidecar.is_file() else "import_not_confirmed"
            else:
                conversion = "raw_export_only"
                validation = "not_mapped_to_maintained_content"
            identity = asset_identity("original.swf", asset.name)
            add_row(
                rows,
                kind=kind,
                id_or_name=identity,
                source=f"original.swf/{asset.relative_to(EXPORT_DIR).as_posix()}",
                recovery="exported_original_swf_asset",
                conversion=conversion,
                validation=validation,
                notes=f"export_filename={asset.name}; preserve container, character ID, and qualified class identity; original animation/timeline linkage audit pending",
            )
            counts[kind] += 1
    return counts


def add_edited_source_assets(rows: list[dict[str, str]]) -> Counter[str]:
    inventory = read_json(SOURCE_INVENTORY)
    counts: Counter[str] = Counter()
    reference_root = str(inventory.get("reference_root", "edited_source")).replace("\\", "/")
    asset_exts = {".png", ".jpg", ".jpeg", ".swf"}
    for entry in inventory.get("files", []):
        path = str(entry.get("path", ""))
        if Path(path).suffix.lower() not in asset_exts:
            continue
        kind = "edited_source_swf" if Path(path).suffix.lower() == ".swf" else "edited_source_image"
        add_row(
            rows,
            kind=kind,
            id_or_name=f"edited_source|{path.replace(chr(92), '/')}",
            source=f"{reference_root}/{path.replace(chr(92), '/')}",
            recovery="current_edited_source_hashed",
            conversion="overlay_reconciled_by_qualified_identity" if kind == "edited_source_image" else "source_build_input",
            validation="sha256_recorded",
            notes=f"size_bytes={entry.get('size', '')}; sha256={entry.get('sha256', '')}",
        )
        counts[kind] += 1
    return counts


def add_mod_groups(rows: list[dict[str, str]]) -> Counter[str]:
    inventory = read_json(SOURCE_INVENTORY)
    groups = inventory.get("known_mod_groups", [])
    counts: Counter[str] = Counter()
    for group in groups:
        add_row(
            rows,
            kind="mod_group",
            id_or_name=group,
            source="development/inventory/reference_inventory.json::known_mod_groups",
            recovery="reconciled_source_group_name",
            conversion="content_partial_rule_and_dependency_audit_open",
            validation="source_inventory_present",
            notes="Group name recovered; enumerate members, dependency restrictions, availability rules, and reload semantics before M1 closure.",
        )
        counts["mod_group"] += 1
    return counts


def string_literals(text: str) -> list[str]:
    return [match.group(2) for match in re.finditer(r"(['\"])(.*?)\1", text, re.DOTALL)]


def array_literal_after(text: str, pattern: str) -> tuple[str, int] | None:
    match = re.search(pattern, text, re.DOTALL)
    if not match:
        return None
    opening = text.find("[", match.start(), match.end())
    if opening < 0:
        return None
    closing = matching_delimiter(text, opening, "[", "]")
    return text[opening + 1:closing], opening


def action_script_functions(text: str) -> list[tuple[str, int, int, int]]:
    """Return named ActionScript method ranges as (name, declaration, body start, body end)."""
    masked = list(text)
    quote: str | None = None
    escaped = False
    for index, char in enumerate(text):
        if quote is not None:
            masked[index] = "\n" if char == "\n" else " "
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
        elif char in {"\"", "'"}:
            quote = char
            masked[index] = " "
    syntax = "".join(masked)
    functions: list[tuple[str, int, int, int]] = []
    for match in re.finditer(r"\bfunction\s+([A-Za-z_$][\w$]*)\s*\(", syntax):
        opening = syntax.find("(", match.start())
        closing = matching_delimiter(syntax, opening, "(", ")")
        body_open = syntax.find("{", closing + 1)
        semicolon = syntax.find(";", closing + 1)
        if body_open < 0 or (semicolon >= 0 and semicolon < body_open):
            continue
        try:
            body_close = matching_delimiter(syntax, body_open, "{", "}")
        except ValueError:
            # Some source exports contain syntactically incomplete/odd method
            # declarations. The keyed-access inventory remains useful; skip only
            # function attribution for that declaration instead of aborting M1.
            continue
        functions.append((match.group(1), match.start(), body_open + 1, body_close))
    return functions


def declared_actionscript_methods(text: str) -> list[tuple[str, int, int, int]]:
    """Return modifier-qualified source method ranges without anonymous functions."""
    pattern = re.compile(
        r"^\s*(?:(?:override|static|final)\s+)*(?:private|protected|public)\s+"
        r"(?:override\s+)?function\s+(?P<name>[A-Za-z_$][A-Za-z0-9_$]*)\s*\(",
        re.MULTILINE,
    )
    methods: list[tuple[str, int, int, int]] = []
    for match in pattern.finditer(text):
        closing_parenthesis = matching_delimiter(text, text.find("(", match.end("name")), "(", ")")
        opening_brace = text.find("{", closing_parenthesis + 1)
        semicolon = text.find(";", closing_parenthesis + 1)
        if opening_brace < 0 or (semicolon >= 0 and semicolon < opening_brace):
            continue
        try:
            closing_brace = matching_delimiter(text, opening_brace, "{", "}")
        except ValueError:
            continue
        methods.append((match.group("name"), match.start(), opening_brace + 1, closing_brace))
    return methods


def add_rule_toggle_inventory(rows: list[dict[str, str]]) -> Counter[str]:
    """Inventory mod groups, flag registration/use sites, guards, policies, and special modes."""
    inventory = read_json(SOURCE_INVENTORY)
    repository_root = Path(str(inventory.get("reference_root", "")))
    source_root = edited_source_root(inventory)
    scripts_root = source_root / "scripts"
    mod_menu_path = scripts_root / "MainMenu/ModMenu.as"
    settings_path = scripts_root / "TopDown/Menus/SettingsMenu.as"
    static_data_path = scripts_root / "PresistentData/StaticData.as"
    dynamic_data_path = scripts_root / "PresistentData/DynamicData.as"
    port_catalog_path = ROOT / "src/content/content_catalog.gd"
    port_pack_catalog_path = ROOT / "content/imported/recovered-20260911/catalog.tres"
    counts: Counter[str] = Counter()

    required = [mod_menu_path, settings_path, static_data_path, dynamic_data_path]
    missing = [path for path in required if not path.is_file()]
    if missing:
        add_row(
            rows,
            kind="open_reachability_audit",
            id_or_name="rule_toggle_source_parser_inputs",
            source=";".join(str(path) for path in missing),
            recovery="edited_source_unavailable",
            conversion="not_inventoried",
            validation="source_parser_input_missing",
            notes="Cannot enumerate the mod toggle registry, UI groups, persistence, or application boundary without all source files.",
        )
        return Counter({"rule_toggle_parser_missing_inputs": len(missing)})

    def relative_source(path: Path, source_text: str, offset: int) -> str:
        try:
            path_label = path.relative_to(repository_root).as_posix()
        except ValueError:
            path_label = path.as_posix()
        return source_location(path_label, source_text.count("\n", 0, offset) + 1)

    mod_menu_raw = mod_menu_path.read_text(encoding="utf-8")
    settings_raw = settings_path.read_text(encoding="utf-8")
    static_raw = static_data_path.read_text(encoding="utf-8")
    dynamic_raw = dynamic_data_path.read_text(encoding="utf-8")
    port_catalog_raw = port_catalog_path.read_text(encoding="utf-8") if port_catalog_path.is_file() else ""
    port_pack_catalog_raw = port_pack_catalog_path.read_text(encoding="utf-8") if port_pack_catalog_path.is_file() else ""
    mod_menu = strip_comments(mod_menu_raw)
    settings = strip_comments(settings_raw)
    static = strip_comments(static_raw)

    order_match = re.search(r"this\.m_toggleTexts\.push\s*\(", mod_menu)
    title_groups: list[str] = []
    if order_match:
        open_paren = mod_menu.find("(", order_match.start())
        close_paren = matching_delimiter(mod_menu, open_paren, "(", ")")
        title_groups = string_literals(mod_menu[open_paren + 1:close_paren])

    title_defs: dict[str, dict[str, Any]] = {}
    for match in re.finditer(r"this\.m_toggleDict\s*\[\s*(['\"])(.*?)\1\s*\]\s*=\s*\[", mod_menu, re.DOTALL):
        opening = match.end() - 1
        closing = matching_delimiter(mod_menu, opening, "[", "]")
        values = string_literals(mod_menu[opening + 1:closing])
        if values:
            title_defs[match.group(2)] = {"description": values[0], "flags": values[1:], "offset": match.start()}

    settings_names_array = array_literal_after(settings, r"this\.m_modGroupNames\s*=\s*\[")
    settings_members_array = array_literal_after(settings, r"this\.m_modGroupMods\s*=\s*\[")
    settings_groups = string_literals(settings_names_array[0]) if settings_names_array else []
    settings_members: list[list[str]] = []
    if settings_members_array:
        for member_match in re.finditer(r"\[([^\[\]]*)\]", settings_members_array[0], re.DOTALL):
            settings_members.append(string_literals(member_match.group(1)))

    registry_minion: list[str] = []
    registry_other: list[str] = []
    for field, target in (("m_all_minion_mods", registry_minion), ("m_all_other_mods", registry_other)):
        for match in re.finditer(rf"this\.{field}\.push\s*\(", static):
            opening = static.find("(", match.start())
            closing = matching_delimiter(static, opening, "(", ")")
            target.extend(string_literals(static[opening + 1:closing]))
    registered_flags = list(dict.fromkeys(registry_minion + registry_other))
    group_members = {group: title_defs.get(group, {}).get("flags", []) for group in title_groups}
    settings_member_map = {
        group: settings_members[index]
        for index, group in enumerate(settings_groups)
        if index < len(settings_members)
    }

    integrity_issues: list[str] = []
    if not order_match:
        integrity_issues.append("title-screen group order not parsed")
    if len(settings_groups) != len(settings_members):
        integrity_issues.append(f"settings group/member counts differ ({len(settings_groups)} vs {len(settings_members)})")
    if title_groups != settings_groups:
        integrity_issues.append("title-screen and in-save group order differ")
    for group in title_groups:
        if group not in title_defs:
            integrity_issues.append(f"missing title-screen definition for {group}")
        if group_members.get(group, []) != settings_member_map.get(group, []):
            integrity_issues.append(f"title-screen and in-save members differ for {group}")
    ui_flags = {flag for members in group_members.values() for flag in members}
    unknown_ui_flags = sorted(ui_flags - set(registered_flags))
    ungrouped_registered = sorted(set(registered_flags) - ui_flags)
    if unknown_ui_flags:
        integrity_issues.append(f"UI flags not in StaticData registry: {unknown_ui_flags}")

    title_line = relative_source(mod_menu_path, mod_menu_raw, order_match.start()) if order_match else str(mod_menu_path)
    settings_line = relative_source(settings_path, settings_raw, settings_names_array[1] if settings_names_array else 0)
    group_for_flag = {flag: group for group, flags in group_members.items() for flag in flags}
    for group in title_groups:
        definition = title_defs.get(group, {})
        flags = group_members.get(group, [])
        add_row(
            rows,
            kind="rule_toggle_group",
            id_or_name=group,
            source=f"{title_line}; {settings_line}",
            recovery="current_edited_source",
            conversion="source_rule_group_inventoried",
            validation="title_and_save_settings_members_compared",
            notes=f"description={definition.get('description', '')}; members={flags}; state_probe=first_member; both_surfaces_toggle_all_members",
        )
        counts["rule_toggle_group"] += 1

    static_registry_pattern = r"this\.m_all_(?:minion|other)_mods\.push\s*\("
    registry_sources: dict[str, str] = {}
    for match in re.finditer(static_registry_pattern, static):
        opening = static.find("(", match.start())
        closing = matching_delimiter(static, opening, "(", ")")
        for flag in string_literals(static[opening + 1:closing]):
            registry_sources.setdefault(flag, relative_source(static_data_path, static_raw, match.start()))

    for flag in registered_flags:
        forced = flag in {"BMod 1", "BMod 2", "BMod 3"}
        group = group_for_flag.get(flag, "")
        if forced:
            category = "always_on_internal_minion"
        elif flag in registry_minion:
            category = "optional_minion_content"
        else:
            category = "optional_rule_or_mode"
        add_row(
            rows,
            kind="rule_toggle_flag",
            id_or_name=flag,
            source=registry_sources.get(flag, ""),
            recovery="current_edited_source",
            conversion="registered_flag_inventoried",
            validation="grouped_or_internal_classification_recorded",
            notes=f"category={category}; display_group={group or 'none'}; constructor_default=false; save_load_override={'forced_true' if forced else 'persisted_value_or_existing_default'}; ungrouped_registry_flags={ungrouped_registered}",
        )
        counts["rule_toggle_flag"] += 1

    # All explicit mod-dictionary/config-map accesses, with exact case and source function.
    key_access = re.compile(r"(?:m_isMod|param1)\s*\[\s*(['\"])(.*?)\1\s*\]")
    known_casefold = {flag.casefold(): flag for flag in registered_flags}
    aliases_block = re.search(r"const\s+LEGACY_MOD_FLAG_ALIASES\s*:=\s*\{([^}]*)\}", port_catalog_raw, re.DOTALL)
    port_aliases = {
        match.group(1): match.group(2)
        for match in re.finditer(r"&\"([^\"]+)\"\s*:\s*&\"([^\"]+)\"", aliases_block.group(1) if aliases_block else "")
    }
    canonical_port_flags = {
        flag_match.group(1)
        for array_match in re.finditer(r"(?m)^mod_flag_ids\s*=\s*Array\[StringName\]\(\[(.*?)\]\)", port_pack_catalog_raw, re.DOTALL)
        for flag_match in re.finditer(r"&\"([^\"]+)\"", array_match.group(1))
    }
    canonical_port_groups: dict[str, str] = {}
    for source_flag, canonical in port_aliases.items():
        if canonical in canonical_port_flags and source_flag in group_for_flag:
            canonical_port_groups[canonical] = group_for_flag[source_flag]
    alias_source = relative_source(port_catalog_path, port_catalog_raw, aliases_block.start()) if aliases_block else ""
    reported_port_corrections: set[str] = set()
    for path in sorted(scripts_root.rglob("*.as")):
        raw = path.read_text(encoding="utf-8", errors="replace")
        code = strip_comments(raw)
        function_ranges = action_script_functions(code)
        for occurrence, match in enumerate(key_access.finditer(code), 1):
            is_config_parameter = match.group(0).lstrip().startswith("param1")
            if is_config_parameter and (path.name != "StaticData.as" or not any(
                name in {"CreateFinalInitialThings", "SetupTypeEffectivenessArray"}
                and start <= match.start() <= end
                for name, start, _body_start, end in function_ranges
            )):
                continue
            flag = match.group(2)
            containing = next((fn for fn in reversed(function_ranges) if fn[1] <= match.start() <= fn[3]), None)
            function_name = containing[0] if containing else "<class-scope>"
            suffix = code[match.end():match.end() + 12]
            operation = "write" if re.match(r"\s*=(?!=|>)", suffix) else "read"
            source_ref = relative_source(path, raw, match.start())
            line = raw.count("\n", 0, match.start()) + 1
            column = match.start() - raw.rfind("\n", 0, match.start())
            id_value = f"{flag}|{path.relative_to(repository_root).as_posix()}:{line}:{column}"
            matched_flag = known_casefold.get(flag.casefold(), "")
            extra = f"registered_case_match={matched_flag}; " if matched_flag and matched_flag != flag else ""
            exact_port_alias = port_aliases.get(flag, "")
            alias_is_valid = bool(exact_port_alias and exact_port_alias in canonical_port_flags)
            add_row(
                rows,
                kind="rule_flag_access",
                id_or_name=id_value,
                source=source_ref,
                recovery="current_edited_source",
                conversion="exact_flag_access_inventoried",
                validation="registered_flag" if flag in registered_flags else "unregistered_exact_key_review",
                notes=f"flag={flag}; access={operation}; map={'config_parameter' if is_config_parameter else 'm_isMod'}; function={function_name}; {extra}source_line={raw.splitlines()[line - 1].strip()}",
            )
            counts["rule_flag_access"] += 1
            if flag not in registered_flags:
                add_row(
                    rows,
                    kind="rule_flag_reference_anomaly",
                    id_or_name=f"{flag}|{path.relative_to(repository_root).as_posix()}:{line}",
                    source=source_ref,
                    recovery="current_edited_source",
                    conversion="explicit_port_alias_applied" if alias_is_valid else "not_silently_corrected",
                    validation="exact_legacy_alias_resolves_to_canonical_port_flag" if alias_is_valid else "flag_missing_from_exact_registry",
                    notes=f"exact_reference={flag}; case_insensitive_registered_match={matched_flag or 'none'}; port_alias={exact_port_alias or 'none'}; preserve original source bytes; no general case-insensitive lookup",
                )
                counts["rule_flag_reference_anomaly"] += 1
            if alias_is_valid and flag not in reported_port_corrections:
                add_row(
                    rows,
                    kind="rule_flag_port_correction",
                    id_or_name=f"{flag}->{exact_port_alias}",
                    source=f"{source_ref}; {alias_source}; src/content/content_pack_definition.gd",
                    recovery="source_anomaly_and_maintained_port_metadata",
                    conversion="exact_legacy_flag_alias_resolves_to_canonical_pack_membership",
                    validation="canonical_pack_flag_and_lookup_tested",
                    notes=f"source_key={flag}; canonical_key={exact_port_alias}; content_group={canonical_port_groups.get(exact_port_alias, 'unresolved')}; alias_is_exact_only=true",
                )
                reported_port_corrections.add(flag)
                counts["rule_flag_port_correction"] += 1

    # Preserve compound source guards as rules, without claiming every guard is a hard dependency.
    for path in sorted(scripts_root.rglob("*.as")):
        raw = path.read_text(encoding="utf-8", errors="replace")
        code = strip_comments(raw)
        syntax = list(code)
        quote: str | None = None
        escaped = False
        for index, char in enumerate(code):
            if quote is not None:
                syntax[index] = "\n" if char == "\n" else " "
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == quote:
                    quote = None
            elif char in {"\"", "'"}:
                quote = char
                syntax[index] = " "
        syntax_text = "".join(syntax)
        for match in re.finditer(r"\bif\s*\(", syntax_text):
            opening = syntax_text.find("(", match.start())
            closing = matching_delimiter(syntax_text, opening, "(", ")")
            condition = code[opening + 1:closing].strip()
            refs = list(dict.fromkeys(key_access.findall(condition)))
            flags = [ref[1] for ref in refs]
            if not flags:
                continue
            line = raw.count("\n", 0, match.start()) + 1
            location = relative_source(path, raw, match.start())
            kind = "rule_flag_dependency_guard" if len(flags) > 1 else "rule_flag_guard"
            add_row(
                rows,
                kind=kind,
                id_or_name=f"{path.relative_to(repository_root).as_posix()}:{line}",
                source=location,
                recovery="current_edited_source",
                conversion="source_guard_inventoried",
                validation="compound_guard_recorded_not_promoted_to_ui_dependency" if len(flags) > 1 else "single_flag_guard_recorded",
                notes=f"flags={flags}; condition={condition}; review_function_scope_required_for_semantics",
            )
            counts[kind] += 1

    # The legacy has two configuration surfaces, and applies persisted flags on save-load rebuild.
    policy_rows = [
        ("title_mod_menu", relative_source(mod_menu_path, mod_menu_raw, mod_menu_raw.find("public function ToggleCarousel")), "Flips every member in the selected group; reads the first member for display; does not call SaveAllData or check owned minions / current floor in this handler."),
        ("in_save_settings", relative_source(settings_path, settings_raw, settings_raw.find("private function ToggleModGroup")), "Sets every member to the selected state and saves immediately; disabling content groups Zanyu through Ice Floor checks owned modded minions; Ice Floor also cannot be disabled while m_FloorType is icefloor; rule-only groups have no such guard."),
        ("persistence", relative_source(dynamic_data_path, dynamic_raw, dynamic_raw.find("public function SaveAllData")), "SaveAllData persists every m_all_mods flag separately as m_isMod_<key>; group coherence is supplied by the UI, not normalized by persistence."),
        ("apply_boundary", relative_source(dynamic_data_path, dynamic_raw, dynamic_raw.find("Singleton.staticData.CreateFinalInitialThings(this.m_isMod)")), "LoadData(slot,true) reads the saved flags, rebuilds trainer progress arrays, then calls CreateFinalInitialThings(m_isMod); that reconstructs mod-dependent IDs, moves/types, minions, trainers, eggery inventory and top-down sprites. Settings text says restart SWF; title-menu edits are only in memory until a save flow persists them."),
    ]
    for surface, source_ref, detail in policy_rows:
        add_row(
            rows,
            kind="rule_toggle_policy",
            id_or_name=surface,
            source=source_ref,
            recovery="current_edited_source",
            conversion="source_configuration_policy_inventoried",
            validation="menu_persistence_and_rebuild_callsites_traced",
            notes=detail,
        )
        counts["rule_toggle_policy"] += 1

    lobby_path = scripts_root / "TopDown/Levels/MainTower/Lobby.as"
    lobby_raw = lobby_path.read_text(encoding="utf-8", errors="replace") if lobby_path.is_file() else ""
    lobby_code = strip_comments(lobby_raw)
    mode_match = re.search(r"private\s+function\s+GetInfiniteTowerModeName\s*\(", lobby_code)
    mode_source = relative_source(lobby_path, lobby_raw, mode_match.start()) if mode_match else str(lobby_path)
    infinite_modes = [
        ("infinite_tower:0", "Normal", "mode_id=0; trainer_pool=151 normal trainers; health carries, defeated minions remain down, energy is refilled between battles"),
        ("infinite_tower:1", "Hard", "mode_id=1; trainer_pool=151 hard trainers; health carries, defeated minions remain down, energy is refilled between battles"),
        ("infinite_tower:2", "All Trainers", "mode_id=2; trainer_pool=302 normal plus hard trainers; health carries, defeated minions remain down, energy is refilled between battles"),
    ]
    for mode_id, name, detail in infinite_modes:
        add_row(
            rows,
            kind="rule_game_mode",
            id_or_name=mode_id,
            source=mode_source,
            recovery="current_edited_source",
            conversion="mode_value_and_run_rules_inventoried",
            validation="lobby_labels_and_trainer_pool_counts_source_checked",
            notes=f"display_name={name}; {detail}; run start/end healing and resume state are implemented in DynamicData infinite-tower services",
        )
        counts["rule_game_mode"] += 1
    for group in title_groups:
        for flag in group_members.get(group, []):
            if flag not in registered_flags:
                continue
            counts[f"rule_grouped_flag/{group}"] += 1

    if integrity_issues:
        add_row(
            rows,
            kind="rule_inventory_integrity_issue",
            id_or_name="mod_group_registry_crosscheck",
            source=f"{title_line}; {settings_line}",
            recovery="current_edited_source",
            conversion="partial_rule_inventory",
            validation="crosscheck_mismatch",
            notes="; ".join(integrity_issues),
        )
        counts["rule_inventory_integrity_issue"] = len(integrity_issues)
    else:
        counts["rule_inventory_integrity_issue"] = 0
    counts["rule_registered_flags"] = len(registered_flags)
    counts["rule_ungrouped_registered_flags"] = len(ungrouped_registered)
    counts["rule_dependency_flags"] = sum(row["kind"] == "rule_flag_dependency_guard" for row in rows)
    return counts


def edited_source_root(inventory: dict[str, Any]) -> Path:
    repository_root = Path(str(inventory.get("reference_root", "")))
    source_root = repository_root / "source"
    return source_root if source_root.is_dir() else repository_root


def braced_body(text: str, opening_brace: int) -> str:
    """Return one ActionScript method body, ignoring braces in strings/comments."""
    depth = 0
    quote: str | None = None
    escaped = False
    line_comment = False
    block_comment = False
    index = opening_brace
    while index < len(text):
        char = text[index]
        following = text[index + 1] if index + 1 < len(text) else ""
        if line_comment:
            if char == "\n":
                line_comment = False
        elif block_comment:
            if char == "*" and following == "/":
                block_comment = False
                index += 1
        elif quote is not None:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
        elif char == "/" and following == "/":
            line_comment = True
            index += 1
        elif char == "/" and following == "*":
            block_comment = True
            index += 1
        elif char in {"\"", "'"}:
            quote = char
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[opening_brace + 1:index]
        index += 1
    raise ValueError("unterminated ActionScript method body")


def strip_comments(text: str) -> str:
    """Blank ActionScript comments while preserving quoted strings and offsets."""
    output = list(text)
    quote: str | None = None
    escaped = False
    line_comment = False
    block_comment = False
    index = 0
    while index < len(text):
        char = text[index]
        following = text[index + 1] if index + 1 < len(text) else ""
        if line_comment:
            if char == "\n":
                line_comment = False
            else:
                output[index] = " "
        elif block_comment:
            if char == "*" and following == "/":
                output[index] = output[index + 1] = " "
                block_comment = False
                index += 1
            elif char != "\n":
                output[index] = " "
        elif quote is not None:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
        elif char in {"\"", "'"}:
            quote = char
        elif char == "/" and following == "/":
            output[index] = output[index + 1] = " "
            line_comment = True
            index += 1
        elif char == "/" and following == "*":
            output[index] = output[index + 1] = " "
            block_comment = True
            index += 1
        index += 1
    return "".join(output)


def matching_delimiter(text: str, opening_index: int, opening: str, closing: str) -> int:
    """Find a matching delimiter while ignoring delimiters inside strings."""
    depth = 0
    quote: str | None = None
    escaped = False
    for index in range(opening_index, len(text)):
        char = text[index]
        if quote is not None:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            continue
        if char in {"\"", "'"}:
            quote = char
        elif char == opening:
            depth += 1
        elif char == closing:
            depth -= 1
            if depth == 0:
                return index
    raise ValueError(f"unmatched delimiter {opening!r} in ActionScript source")


def split_actionscript_arguments(text: str) -> list[str]:
    """Split a delimiter body on top-level commas, preserving nested expressions."""
    parts: list[str] = []
    start = 0
    depth = 0
    quote: str | None = None
    escaped = False
    for index, char in enumerate(text):
        if quote is not None:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            continue
        if char in {"\"", "'"}:
            quote = char
        elif char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        elif char == "," and depth == 0:
            parts.append(text[start:index].strip())
            start = index + 1
    tail = text[start:].strip()
    if tail or parts:
        parts.append(tail)
    return parts


def enclosing_actionscript_guards(text: str, offset: int, lower_bound: int = 0) -> list[dict[str, str]]:
    """Record enclosing if/else and loop guards, including single-statement branches."""
    guards: list[dict[str, str]] = []

    def skip_space(index: int) -> int:
        while index < len(text) and text[index].isspace():
            index += 1
        return index

    def statement_end(start: int) -> int:
        start = skip_space(start)
        if start >= len(text):
            return start
        if text[start] == "{":
            try:
                return matching_delimiter(text, start, "{", "}")
            except ValueError:
                return len(text)
        nested_if = re.match(r"if\s*\(", text[start:])
        if nested_if:
            opening = start + nested_if.end() - 1
            try:
                condition_end = matching_delimiter(text, opening, "(", ")")
            except ValueError:
                return start
            then_end = statement_end(condition_end + 1)
            else_start = skip_space(then_end + 1)
            if re.match(r"else\b", text[else_start:]):
                return statement_end(else_start + len("else"))
            return then_end
        semicolon = text.find(";", start)
        brace_end = text.find("}", start)
        if semicolon < 0:
            return brace_end if brace_end >= 0 else len(text)
        if brace_end >= 0 and brace_end < semicolon:
            return brace_end
        return semicolon

    region = text[lower_bound:offset]
    for match in re.finditer(r"\b(if|while|for)\s*\(", region):
        opening = lower_bound + match.end() - 1
        try:
            condition_end = matching_delimiter(text, opening, "(", ")")
        except ValueError:
            continue
        if condition_end >= offset:
            continue
        body_start = skip_space(condition_end + 1)
        body_end = statement_end(body_start)
        condition = text[opening + 1:condition_end].strip()
        if body_start <= offset <= body_end:
            guards.append({"kind": match.group(1), "condition": condition})
            continue
        if match.group(1) != "if":
            continue
        else_start = skip_space(body_end + 1)
        if not re.match(r"else\b", text[else_start:]):
            continue
        else_body_start = skip_space(else_start + len("else"))
        else_body_end = statement_end(else_body_start)
        if else_body_start <= offset <= else_body_end:
            guards.append({"kind": "if_else", "condition": f"!({condition})"})

    for match in re.finditer(r"\bswitch\s*\(", region):
        opening = lower_bound + match.end() - 1
        try:
            condition_end = matching_delimiter(text, opening, "(", ")")
        except ValueError:
            continue
        body_start = skip_space(condition_end + 1)
        if body_start >= len(text) or text[body_start] != "{":
            continue
        try:
            body_end = matching_delimiter(text, body_start, "{", "}")
        except ValueError:
            continue
        if not body_start < offset <= body_end:
            continue
        switch_expression = text[opening + 1:condition_end].strip()
        switch_body = text[body_start + 1:body_end]
        labels: list[tuple[int, str | None]] = []
        label_pattern = re.compile(r"\bcase\s+(?P<value>[^:]+?)\s*:|\bdefault\s*:")
        for label in label_pattern.finditer(switch_body):
            nested_depth = 0
            label_quote: str | None = None
            label_escaped = False
            for character in switch_body[:label.start()]:
                if label_quote is not None:
                    if label_escaped:
                        label_escaped = False
                    elif character == "\\":
                        label_escaped = True
                    elif character == label_quote:
                        label_quote = None
                elif character in {"\"", "'"}:
                    label_quote = character
                elif character == "{":
                    nested_depth += 1
                elif character == "}":
                    nested_depth -= 1
            if nested_depth == 0:
                labels.append((body_start + 1 + label.start(), label.group("value").strip() if label.group("value") else None))
        prior_labels = [label for label in labels if label[0] <= offset]
        if prior_labels:
            label_offset, case_value = prior_labels[-1]
            next_label_offset = next((entry[0] for entry in labels if entry[0] > label_offset), body_end)
            if offset < next_label_offset:
                condition = "default" if case_value is None else f"{switch_expression} == {case_value}"
                guards.append({"kind": "switch_case", "condition": condition})
    return guards


def top_level_if_branches(body: str) -> list[dict[str, Any]]:
    """Extract the outer if/else-if chain without mistaking nested guards for dispatch rules."""
    branch_starts: list[int] = []
    depth = 0
    quote: str | None = None
    escaped = False
    index = 0
    while index < len(body):
        char = body[index]
        if quote is not None:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            index += 1
            continue
        if char in {"\"", "'"}:
            quote = char
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        elif depth == 0 and body.startswith("if", index):
            before = body[index - 1] if index else " "
            after_index = index + 2
            after = body[after_index] if after_index < len(body) else " "
            if not (before.isalnum() or before in "_$") and not (after.isalnum() or after in "_$"):
                branch_starts.append(index)
                index += 1
        index += 1

    branches: list[dict[str, Any]] = []
    for branch_index, branch_start in enumerate(branch_starts):
        condition_open = body.find("(", branch_start + 2)
        if condition_open < 0:
            continue
        condition_close = matching_delimiter(body, condition_open, "(", ")")
        opening_brace = body.find("{", condition_close + 1)
        if opening_brace < 0:
            continue
        closing_brace = matching_delimiter(body, opening_brace, "{", "}")
        branches.append({
            "condition": body[condition_open + 1:condition_close].strip(),
            "body": body[opening_brace + 1:closing_brace],
            "start": branch_start,
            "end": closing_brace + 1,
            "order": branch_index + 1,
        })
    return branches


def normalized_legacy_name(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", value.casefold())


def trainer_slug(value: str) -> str:
    value = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", value)
    return re.sub(r"[^a-zA-Z0-9]+", "_", value).strip("_").casefold()


def static_room_slot_map(source_root: Path) -> tuple[Path, int, dict[int, list[dict[str, Any]]]]:
    static_file = source_root / "scripts/PresistentData/StaticData.as"
    source_text = static_file.read_text(encoding="utf-8-sig")
    code_text = strip_comments(source_text)
    floor_count_match = re.search(
        r"NUM_OF_FLOORS_IN_THE_STANDARD_TOWER\s*:\s*int\s*=\s*(\d+)", code_text
    )
    setup_match = re.search(
        r"\bfunction\s+SetupLevels\s*\([^)]*\)\s*:\s*void\s*\{", code_text
    )
    push_match = re.search(
        r"this\.m_normalRooms\[\s*(?P<index_variable>_loc\d+_)\s*\]\.push\(",
        code_text[setup_match.start():] if setup_match else "",
    )
    if not floor_count_match or not setup_match or not push_match:
        raise ValueError(f"could not identify StaticData.SetupLevels room registry in {static_file}")

    standard_floor_count = int(floor_count_match.group(1))
    index_variable = push_match.group("index_variable")
    opening_brace = code_text.find("{", setup_match.start(), setup_match.end())
    body = braced_body(code_text, opening_brace)
    event_pattern = re.compile(
        rf"\b(?:var\s+)?{re.escape(index_variable)}\s*(?::\s*[A-Za-z0-9_\.]+)?\s*=\s*(?P<floor>-?\d+)\s*;"
        rf"|this\.m_normalRooms\[\s*{re.escape(index_variable)}\s*\]\.push\((?P<room>.*?)\);",
        re.DOTALL,
    )
    rooms_by_floor: dict[int, list[dict[str, Any]]] = {}
    current_floor: int | None = None
    method_offset = opening_brace + 1
    for event in event_pattern.finditer(body):
        if event.group("floor") is not None:
            current_floor = int(event.group("floor"))
            rooms_by_floor.setdefault(current_floor, [])
            continue
        if current_floor is None:
            continue
        expression = event.group("room")
        container_match = re.search(r"LevelContainer\.([A-Za-z0-9_]+)", expression)
        class_match = re.search(r"new\s+([A-Za-z0-9_]+)\s*\(", expression)
        if container_match:
            definition = {
                "kind": "swf_room_payload",
                "level_container": container_match.group(1),
                "room_slug": trainer_slug(container_match.group(1)),
                "source_class": class_match.group(1) if class_match else None,
            }
        elif class_match:
            definition = {"kind": "source_room_class", "source_class": class_match.group(1)}
        else:
            definition = {"kind": "unresolved_room_definition", "expression": expression.strip()}
        absolute_offset = method_offset + event.start()
        definition["source_line"] = source_text.count("\n", 0, absolute_offset) + 1
        rooms_by_floor[current_floor].append(definition)
    special_room_pushes = list(re.finditer(
        r"this\.m_specialRooms\.push\((?P<room>.*?)\);",
        body,
        re.DOTALL,
    ))
    for special_index, special_match in enumerate(special_room_pushes):
        class_match = re.search(r"new\s+([A-Za-z0-9_]+)\s*\(", special_match.group("room"))
        if not class_match:
            continue
        synthetic_floor_key = -(special_index + 1)
        rooms_by_floor[synthetic_floor_key] = [{
            "kind": "source_room_class",
            "source_class": class_match.group(1),
            "special_room_index": special_index,
            "source_line": source_text.count("\n", 0, method_offset + special_match.start()) + 1,
        }]
    return static_file, standard_floor_count, rooms_by_floor


def add_trainer_room_bindings(rows: list[dict[str, str]]) -> Counter[str]:
    inventory = read_json(SOURCE_INVENTORY)
    source_root = edited_source_root(inventory)
    try:
        static_file, standard_floor_count, rooms_by_floor = static_room_slot_map(source_root)
    except (OSError, ValueError) as error:
        add_row(
            rows,
            kind="open_reachability_audit",
            id_or_name="trainer_room_binding_source_mapping",
            source=str(source_root / "scripts/PresistentData/StaticData.as"),
            recovery="current_edited_source_available",
            conversion="room_slot_registry_not_parsed",
            validation="trainer_room_binding_open",
            notes=str(error),
        )
        return Counter({"trainer_room_binding_parse_errors": 1})

    payload_rows = {
        row["id_or_name"]: row
        for row in rows
        if row["kind"] == "room_payload"
    }
    payload_by_slug = {
        room_id.rsplit("/", 1)[-1]: room_id
        for room_id in payload_rows
        if room_id.startswith("base:room/")
    }
    objects_by_room: dict[str, list[tuple[str, dict[str, Any]]]] = {}
    for row in rows:
        if row["kind"] != "room_object_instance" or "/object/" not in row["id_or_name"]:
            continue
        room_id = row["id_or_name"].rsplit("/object/", 1)[0]
        try:
            notes = json.loads(row["notes"])
        except (json.JSONDecodeError, TypeError):
            notes = {}
        objects_by_room.setdefault(room_id, []).append((row["id_or_name"], notes))

    source_scripts = list((source_root / "scripts").rglob("*.as"))
    scripts_by_stem: dict[str, list[Path]] = {}
    for path in source_scripts:
        scripts_by_stem.setdefault(path.stem, []).append(path)
    source_room_cache: dict[str, tuple[Path | None, list[dict[str, Any]], list[dict[str, Any]]]] = {}

    def is_trainer_actor(sprite_name: str) -> bool:
        lowered = sprite_name.casefold()
        return (
            any(token in lowered for token in ("enemy", "trainer", "npc", "wizard"))
            and "statue" not in lowered
        )

    def source_room_targets(class_name: str) -> tuple[Path | None, list[dict[str, Any]], list[dict[str, Any]]]:
        if class_name in source_room_cache:
            return source_room_cache[class_name]
        candidates = scripts_by_stem.get(class_name, [])
        room_file = candidates[0] if len(candidates) == 1 else None
        actors: list[dict[str, Any]] = []
        buttons: list[dict[str, Any]] = []
        if room_file is not None:
            room_text = room_file.read_text(encoding="utf-8-sig")
            room_code = strip_comments(room_text)
            add_object_pattern = re.compile(r"\bAddObject\(\s*['\"](?P<sprite>[^'\"]+)['\"]")
            for match in add_object_pattern.finditer(room_code):
                sprite_name = match.group("sprite")
                line = room_text.count("\n", 0, match.start()) + 1
                callsite = {"source": source_location(str(room_file), line), "sprite_name": sprite_name}
                if is_trainer_actor(sprite_name):
                    actors.append(callsite)
                if sprite_name.casefold().startswith("buttonzoneobject"):
                    buttons.append(callsite)
        result = (room_file, actors, buttons)
        source_room_cache[class_name] = result
        return result

    counts: Counter[str] = Counter()
    for trainer_row in [row for row in rows if row["kind"] == "trainer_entry"]:
        try:
            trainer = json.loads(trainer_row["notes"])
        except (json.JSONDecodeError, TypeError):
            trainer = {}
        floor_index = trainer.get("resolved_floor_index")
        room_index = trainer.get("resolved_trainer_room_id")
        room_definition: dict[str, Any] | None = None
        if floor_index is not None and room_index is not None:
            base_floor = int(floor_index) % standard_floor_count
            room_list = rooms_by_floor.get(base_floor, [])
            if 0 <= int(room_index) < len(room_list):
                room_definition = room_list[int(room_index)]

        room_id = ""
        source_room_file: Path | None = None
        actor_targets: list[dict[str, Any]] = []
        button_targets: list[dict[str, Any]] = []
        resolution = "room_slot_not_resolved"
        if room_definition:
            if room_definition["kind"] == "swf_room_payload":
                room_id = payload_by_slug.get(str(room_definition["room_slug"]), "")
                if room_id:
                    for object_id, object_notes in objects_by_room.get(room_id, []):
                        sprite_name = str(object_notes.get("sprite_name", ""))
                        target = {"object_id": object_id, "sprite_name": sprite_name}
                        if is_trainer_actor(sprite_name):
                            actor_targets.append(target)
                        if sprite_name.casefold().startswith("buttonzoneobject"):
                            button_targets.append(target)
                    resolution = "room_payload_and_actor_bound" if actor_targets else "room_payload_bound_actor_missing"
                else:
                    resolution = "room_payload_missing"
            elif room_definition["kind"] == "source_room_class":
                source_room_file, actor_targets, button_targets = source_room_targets(
                    str(room_definition["source_class"])
                )
                if source_room_file:
                    resolution = "source_room_class_and_actor_bound" if actor_targets else "source_room_class_bound_actor_missing"
                else:
                    resolution = "source_room_class_file_missing"
            else:
                resolution = "room_definition_unresolved"

        if not room_definition:
            counts["trainer_room_binding_missing_slots"] += 1
        elif resolution in {"room_payload_missing", "source_room_class_file_missing", "room_definition_unresolved"}:
            counts["trainer_room_binding_missing_definitions"] += 1
        elif not actor_targets:
            counts["trainer_room_binding_missing_actors"] += 1
        if not button_targets:
            counts["trainer_room_binding_missing_button_zones"] += 1

        binding_id = f"{trainer_row['id_or_name']}/room_binding"
        add_row(
            rows,
            kind="trainer_room_binding",
            id_or_name=binding_id,
            source="|".join(filter(None, [
                trainer_row["source"],
                source_location(str(static_file), room_definition.get("source_line") if room_definition else None),
                payload_rows.get(room_id, {}).get("source", ""),
                str(source_room_file) if source_room_file else "",
            ])),
            recovery="trainer_room_index_joined_to_static_room_registry",
            conversion="trainer_to_room_and_actor_reference_record",
            validation=resolution,
            notes={
                "trainer_id": trainer_row["id_or_name"],
                "floor_index": floor_index,
                "standard_tower_floor_index": int(floor_index) % standard_floor_count if floor_index is not None else None,
                "trainer_room_id_and_room_list_index": room_index,
                "room_definition": room_definition,
                "room_payload_id": room_id or None,
                "source_room_class_file": str(source_room_file) if source_room_file else None,
                "trainer_actor_targets": actor_targets,
                "button_zone_targets": button_targets,
                "lookup_basis": "StaticData.GetRoomForTransitionID returns the m_normalRooms list index; TrainerSystem.LoadTrianer selects m_trainerRoomID using that same current-room index.",
            },
        )
        counts["trainer_room_bindings"] += 1

    unresolved = sum(counts[key] for key in (
        "trainer_room_binding_missing_slots",
        "trainer_room_binding_missing_definitions",
        "trainer_room_binding_missing_actors",
        "trainer_room_binding_missing_button_zones",
    ))
    if unresolved:
        add_row(
            rows,
            kind="open_reachability_audit",
            id_or_name="trainer_room_binding_completeness",
            source=source_location(str(static_file)),
            recovery="trainer_and_static_room_sources_joined",
            conversion="partial_room_and_actor_binding",
            validation="some_trainer_room_targets_require_review",
            notes={key: value for key, value in counts.items() if key.startswith("trainer_room_binding_missing_")},
        )
        counts["trainer_room_binding_audit_row"] = 1
    return counts


def add_trainers(rows: list[dict[str, str]]) -> Counter[str]:
    inventory = read_json(SOURCE_INVENTORY)
    source_root = edited_source_root(inventory)
    trainer_file = source_root / "scripts/TopDown/Trainers/TrainerSystem.as"
    minion_dex_file = source_root / "scripts/States/MinionDexID.as"
    if not trainer_file.is_file() or not minion_dex_file.is_file():
        add_row(
            rows,
            kind="open_reachability_audit",
            id_or_name="trainer_source_registry",
            source=str(trainer_file),
            recovery="current_edited_source_not_available_to_manifest_tool",
            conversion="not_converted",
            validation="trainer_instances_not_enumerated",
            notes="The current TrainerSystem.as and MinionDexID.as are required to enumerate trainer entries and cross-reference roster identities.",
        )
        return Counter({"trainer_source_unavailable": 1})

    trainer_text = trainer_file.read_text(encoding="utf-8-sig")
    minion_dex_text = minion_dex_file.read_text(encoding="utf-8-sig")
    static_data_file = source_root / "scripts/PresistentData/StaticData.as"
    static_data_text = static_data_file.read_text(encoding="utf-8-sig")
    floor_count_match = re.search(
        r"NUM_OF_FLOORS_IN_THE_STANDARD_TOWER\s*:\s*int\s*=\s*(\d+)",
        strip_comments(static_data_text),
    )
    standard_floor_count = int(floor_count_match.group(1)) if floor_count_match else 0
    minions = read_json(STAGED_CONTENT / "minions.json")
    move_index = read_json(STAGED_CONTENT / "move_index.json")

    dex_constants = {
        match.group(1): int(match.group(2))
        for match in re.finditer(
            r"public\s+static\s+const\s+(DEX_ID_[A-Za-z0-9_]+)\s*:\s*(?:int|uint)\s*=\s*(-?\d+)\s*;",
            minion_dex_text,
        )
    }
    minions_by_numeric: dict[int, list[str]] = {}
    minions_by_name: dict[str, list[str]] = {}
    for entry in minions:
        migration = entry.get("migration", {})
        numeric_id = migration.get("legacy_numeric_id")
        if numeric_id is not None:
            minions_by_numeric.setdefault(int(numeric_id), []).append(entry["id"])
        for key in ("legacy_identity", "legacy_function"):
            legacy_name = migration.get(key)
            if legacy_name:
                minions_by_name.setdefault(normalized_legacy_name(str(legacy_name)), []).append(entry["id"])

    moves_by_numeric: dict[int, list[str]] = {}
    for entry in move_index:
        moves_by_numeric.setdefault(int(entry["legacy_numeric_id"]), []).append(entry["id"])

    method_pattern = re.compile(
        r"^\s*(?:private|public|protected)\s+function\s+(?P<name>CreateFloor[A-Za-z0-9_]*)\s*\(\s*\)\s*:\s*void\s*\{",
        re.MULTILINE,
    )
    trainer_call_pattern = re.compile(
        r"(?P<variable>[A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*(?:this\.)?AddTrainerToFloor\((?P<args>[^;]*?)\)\s*;"
    )
    minion_call_pattern = re.compile(
        r"\b[A-Za-z_$][A-Za-z0-9_$]*\.AddMinion\(\s*MinionDexID\.(?P<constant>[A-Za-z0-9_]+)\s*,\s*\[(?P<moves>[^\]]*)\]\s*\)"
    )
    code_text = strip_comments(trainer_text)
    method_records: list[dict[str, Any]] = []
    for method_match in method_pattern.finditer(code_text):
        method_name = method_match.group("name")
        if method_name == "CreateFloors":
            continue
        opening_brace = code_text.find("{", method_match.start(), method_match.end())
        body = braced_body(code_text, opening_brace)
        method_records.append({
            "name": method_name,
            "body": body,
            "body_start": opening_brace + 1,
            "source_line": trainer_text.count("\n", 0, method_match.start()) + 1,
        })

    total_calls = 0
    roster_count = 0
    unresolved_minion_refs = 0
    ambiguous_minion_refs = 0
    unresolved_move_refs = 0
    for method in method_records:
        name = method["name"]
        body = method["body"]
        calls = list(trainer_call_pattern.finditer(body))
        assignments = list(re.finditer(r"\b(_loc\d+_)\s*(?::\s*(?:int|Number))?\s*=\s*([^;]+);", body))
        for call_index, call in enumerate(calls):
            total_calls += 1
            end = calls[call_index + 1].start() if call_index + 1 < len(calls) else len(body)
            trainer_block = body[call.end():end]
            raw_args = [value.strip() for value in call.group("args").split(",")]
            trainer_type = raw_args[0] if raw_args else "<missing>"
            floor_expression = raw_args[1] if len(raw_args) > 1 else "<missing>"
            room_expression = raw_args[2] if len(raw_args) > 2 else "<missing>"

            def parse_integer_expression(expression: str) -> int | None:
                expression = re.sub(r"\s+", "", expression)
                if re.fullmatch(r"-?\d+", expression):
                    return int(expression)
                hard_mode_offset = re.fullmatch(r"(-?\d+)\+this\.m_extraHardModeModifier", expression)
                if hard_mode_offset and standard_floor_count:
                    return standard_floor_count + int(hard_mode_offset.group(1))
                hard_mode_offset = re.fullmatch(r"this\.m_extraHardModeModifier\+(-?\d+)", expression)
                if hard_mode_offset and standard_floor_count:
                    return standard_floor_count + int(hard_mode_offset.group(1))
                if expression == "this.m_extraHardModeModifier" and standard_floor_count:
                    return standard_floor_count
                matches = [item for item in assignments if item.start() < call.start() and item.group(1) == expression]
                return parse_integer_expression(matches[-1].group(2)) if matches else None

            def resolve_integer(expression: str) -> int | None:
                return parse_integer_expression(expression)

            resolved_floor = resolve_integer(floor_expression)
            resolved_room = resolve_integer(room_expression)
            is_hard = name.endswith("_hardMode")
            floor_label = name.removeprefix("CreateFloor").removesuffix("_hardMode")
            mode = "hard" if is_hard else "standard"
            floor_component = trainer_slug(floor_label) or "unknown"
            room_component = str(resolved_room) if resolved_room is not None else trainer_slug(room_expression)
            trainer_id = f"base:trainer/{mode}/{floor_component}/room/{room_component}"
            source_offset = method["body_start"] + call.start()
            source_line = trainer_text.count("\n", 0, source_offset) + 1

            trainer_assignments = {
                match.group(1): match.group(2).strip()
                for match in re.finditer(
                    rf"\b{re.escape(call.group('variable'))}\.(m_[A-Za-z0-9_]+)\s*=\s*(.*?);",
                    trainer_block,
                    re.DOTALL,
                )
            }
            modifiers = [
                {"method": match.group(1), "arguments": match.group(2).strip()}
                for match in re.finditer(
                    rf"\b{re.escape(call.group('variable'))}\.(AddMod_[A-Za-z0-9_]+)\((.*?)\)\s*;",
                    trainer_block,
                    re.DOTALL,
                )
            ]
            roster_matches = list(minion_call_pattern.finditer(trainer_block))
            roster_records: list[dict[str, Any]] = []
            trainer_has_unresolved = False
            trainer_has_ambiguous = False
            trainer_has_unresolved_moves = False
            for roster_index, roster_match in enumerate(roster_matches, start=1):
                dex_constant = roster_match.group("constant")
                dex_numeric = dex_constants.get(dex_constant)
                stem = dex_constant.removeprefix("DEX_ID_")
                candidates = set(minions_by_name.get(normalized_legacy_name(stem), []))
                if dex_numeric is not None:
                    candidates.update(minions_by_numeric.get(dex_numeric, []))
                minion_definition = sorted(candidates)[0] if len(candidates) == 1 else ""
                if not candidates:
                    unresolved_minion_refs += 1
                    trainer_has_unresolved = True
                elif len(candidates) > 1:
                    ambiguous_minion_refs += 1
                    trainer_has_ambiguous = True
                try:
                    legacy_move_ids = [int(value.strip()) for value in roster_match.group("moves").split(",") if value.strip()]
                except ValueError:
                    legacy_move_ids = []
                    trainer_has_unresolved_moves = True
                move_candidates = {str(legacy_id): sorted(moves_by_numeric.get(legacy_id, [])) for legacy_id in legacy_move_ids}
                if any(not candidates for candidates in move_candidates.values()):
                    unresolved_move_refs += sum(not candidates for candidates in move_candidates.values())
                    trainer_has_unresolved_moves = True
                elif any(len(candidates) > 1 for candidates in move_candidates.values()):
                    trainer_has_unresolved_moves = True
                roster_record = {
                    "slot": roster_index,
                    "minion_constant": dex_constant,
                    "legacy_minion_id": dex_numeric,
                    "minion_definition_id": minion_definition or None,
                    "minion_resolution_candidates": sorted(candidates),
                    "legacy_move_ids": legacy_move_ids,
                    "move_definition_candidates": move_candidates,
                }
                roster_records.append(roster_record)
                roster_source_line = trainer_text.count("\n", 0, method["body_start"] + call.end() + roster_match.start()) + 1
                roster_validation = "references_resolved" if minion_definition and not trainer_has_unresolved_moves else "references_require_review"
                add_row(
                    rows,
                    kind="trainer_roster_entry",
                    id_or_name=f"{trainer_id}/minion/{roster_index:02d}",
                    source=source_location(str(trainer_file), roster_source_line),
                    recovery="recovered_current_edited_source",
                    conversion="typed_trainer_roster_not_yet_imported",
                    validation=roster_validation,
                    notes=roster_record,
                )
                roster_count += 1

            trainer_validation = "trainer_and_roster_source_parsed"
            if trainer_has_unresolved or trainer_has_ambiguous or trainer_has_unresolved_moves:
                trainer_validation = "roster_references_require_review"
            row_notes = {
                "builder_method": name,
                "trainer_type": trainer_type,
                "floor_index_expression": floor_expression,
                "resolved_floor_index": resolved_floor,
                "trainer_room_id_expression": room_expression,
                "resolved_trainer_room_id": resolved_room,
                "roster_count": len(roster_records),
                "trainer_fields": trainer_assignments,
                "battle_modifiers": modifiers,
                "roster_reference_issues": {
                    "unresolved_minion": trainer_has_unresolved,
                    "ambiguous_minion": trainer_has_ambiguous,
                    "unresolved_or_ambiguous_move": trainer_has_unresolved_moves,
                },
            }
            add_row(
                rows,
                kind="trainer_entry",
                id_or_name=trainer_id,
                source=source_location(str(trainer_file), source_line),
                recovery="recovered_current_edited_source",
                conversion="trainer_record_in_manifest_not_godot_resource",
                validation=trainer_validation,
                notes=row_notes,
            )

    expected_calls = len(re.findall(r"\b(?:this\.)?AddTrainerToFloor\(", code_text)) - 1
    # One declaration contributes a textual match but is not a trainer entry.
    counts: Counter[str] = Counter({
        "trainer_builder_methods": len(method_records),
        "trainer_source_calls": total_calls,
        "trainer_roster_entries": roster_count,
        "trainer_unresolved_minion_references": unresolved_minion_refs,
        "trainer_ambiguous_minion_references": ambiguous_minion_refs,
        "trainer_unresolved_move_references": unresolved_move_refs,
        "trainer_dex_constants": len(dex_constants),
    })
    if total_calls != expected_calls:
        add_row(
            rows,
            kind="open_reachability_audit",
            id_or_name="trainer_source_parse_completeness",
            source=source_location(str(trainer_file)),
            recovery="current_edited_source_available",
            conversion="partial_trainer_method_parse",
            validation="source_calls_do_not_match_emitted_entries",
            notes=f"source_call_count={expected_calls}; parsed_create_floor_calls={total_calls}; investigate calls outside CreateFloor methods",
        )
        counts["trainer_source_parse_mismatch"] = abs(expected_calls - total_calls)
    return counts


def add_audio_inventory(rows: list[dict[str, str]]) -> Counter[str]:
    """Join edited-source sound/music callsites to recovered SWF sound identities."""
    inventory = read_json(SOURCE_INVENTORY)
    repository_root = Path(str(inventory.get("reference_root", "")))
    source_root = edited_source_root(inventory)
    scripts_root = source_root / "scripts"
    music_enum_path = scripts_root / "States/BackgroundMusicTracks.as"
    distance_object_path = scripts_root / "TopDown/LevelObjects/SoundDistanceObject.as"
    controller_path = EXPORT_DIR / "script/scripts/Utilities/SoundController.as"
    original_scripts_root = EXPORT_DIR / "script/scripts"
    current_script_files = sorted(scripts_root.rglob("*.as"))
    current_script_relatives = {path.relative_to(scripts_root).as_posix().casefold() for path in current_script_files}
    script_inputs: list[tuple[Path, str, str]] = [
        (path, path.relative_to(repository_root).as_posix(), "current_edited_source")
        for path in current_script_files
    ]
    for original_path in sorted(original_scripts_root.rglob("*.as")):
        relative = original_path.relative_to(original_scripts_root).as_posix()
        if relative.casefold() not in current_script_relatives:
            script_inputs.append((original_path, f"original.swf/script/scripts/{relative}", "original_swf_only_class"))
    counts: Counter[str] = Counter()
    asset_rows = [row for row in rows if row["kind"] == "asset_sound"]
    asset_ids_by_name: dict[str, list[str]] = {}
    asset_row_by_id = {row["id_or_name"]: row for row in asset_rows}
    asset_name_pattern = re.compile(r"Utilities\.SoundController_(.+?)_Utilities\.SoundController_")
    for asset in asset_rows:
        match = asset_name_pattern.search(asset["id_or_name"])
        if match:
            asset_ids_by_name.setdefault(match.group(1), []).append(asset["id_or_name"])

    resolved_call_counts: Counter[str] = Counter()
    source_api_counts: Counter[str] = Counter()
    callback_count = 0
    call_index_by_source: Counter[str] = Counter()
    callback_index_by_source: Counter[str] = Counter()
    dynamic_audio_call_rows: list[tuple[dict[str, str], str]] = []
    api_pattern = re.compile(
        r"m_soundController\.(PlaySound|ChangeMusicTrack|FadeCurrentMusic|"
        r"PlayExtraBackgroundTrack|TurnOffExtraBackgroundTrack|"
        r"SetCurrBackgroundMusicVolume|SetBackgroundMusicVolume)\b"
    )
    sound_field_assignment = re.compile(r"(?:this\.)?(m_[A-Za-z0-9_$]+)\s*=\s*(['\"])(.*?)\2", re.DOTALL)
    for path, source_path, source_recovery in script_inputs:
        raw = path.read_text(encoding="utf-8", errors="replace")
        code = strip_comments(raw)
        function_ranges = action_script_functions(code)
        field_sound_assignments: dict[str, list[tuple[int, str]]] = {}
        for assignment in sound_field_assignment.finditer(code):
            field_sound_assignments.setdefault(assignment.group(1), []).append((assignment.start(), assignment.group(3)))
        for match in api_pattern.finditer(code):
            api = match.group(1)
            containing_function = next((fn for fn in reversed(function_ranges) if fn[1] <= match.start() <= fn[3]), None)
            function = containing_function[0] if containing_function else "<class-scope>"
            function_body_start = containing_function[2] if containing_function else 0
            line = raw.count("\n", 0, match.start()) + 1
            column = match.start() - raw.rfind("\n", 0, match.start())
            source_ref = source_location(source_path, line)
            suffix_start = match.end()
            while suffix_start < len(code) and code[suffix_start].isspace():
                suffix_start += 1
            if suffix_start < len(code) and code[suffix_start] == "(":
                try:
                    close = matching_delimiter(code, suffix_start, "(", ")")
                except ValueError:
                    close = suffix_start
                    arguments: list[str] = []
                else:
                    arguments = split_actionscript_arguments(code[suffix_start + 1:close])
                first_argument = arguments[0] if arguments else ""
                string_match = re.fullmatch(r"(['\"])(.*?)\1", first_argument, re.DOTALL)
                sound_name = string_match.group(2) if api == "PlaySound" and string_match else ""
                sound_name_origin = "literal_argument" if sound_name else ""
                if api == "PlaySound" and not sound_name:
                    field_match = re.search(r"\b(m_[A-Za-z0-9_$]+)\b", first_argument)
                    if field_match:
                        assignments = field_sound_assignments.get(field_match.group(1), [])
                        prior_literals = [value for offset, value in assignments if offset < match.start() and value]
                        if prior_literals:
                            sound_name = prior_literals[-1]
                            sound_name_origin = "same_class_literal_field_assignment"
                matching_assets = asset_ids_by_name.get(sound_name, [])
                asset_id = matching_assets[0] if len(matching_assets) == 1 else ""
                call_key = f"{source_path}:{line}:{column}"
                call_index_by_source[call_key] += 1
                kind = "audio_callsite" if api == "PlaySound" else "music_control_callsite"
                conversion = ("literal_sound_asset_resolved" if sound_name_origin == "literal_argument" else "class_field_sound_asset_resolved") if asset_id else (
                    "dynamic_sound_reference_requires_source_context" if api == "PlaySound"
                    else "music_control_call_inventoried"
                )
                validation = ("exact_swf_sound_asset_match" if sound_name_origin == "literal_argument" else "field_assignment_sound_asset_match") if asset_id else (
                    "dynamic_sound_identity_unresolved" if api == "PlaySound"
                    else "call_signature_inventoried"
                )
                add_row(
                    rows,
                    kind=kind,
                    id_or_name=f"{source_path}:{line}:{column}:{call_index_by_source[call_key]}",
                    source=source_ref,
                    recovery=source_recovery,
                    conversion=conversion,
                    validation=validation,
                    notes={
                        "api": api,
                        "function": function,
                        "argument_expressions": arguments,
                        "sound_name": sound_name or None,
                        "sound_name_origin": sound_name_origin or None,
                        "sound_asset_id": asset_id or None,
                        "sound_asset_candidates": matching_assets,
                        "volume_expression": arguments[1] if api == "PlaySound" and len(arguments) > 1 else ("1 (source default)" if api == "PlaySound" else None),
                        "enclosing_if_and_loop_guards": enclosing_actionscript_guards(code, match.start(), function_body_start),
                        "source_line": raw.splitlines()[line - 1].strip(),
                        "trigger_and_tween_timing": "callsite identified; enclosing behavior review remains required",
                    },
                )
                dynamic_field_match = re.search(r"\b(m_[A-Za-z0-9_$]+)\b", first_argument) if api == "PlaySound" and not asset_id else None
                if dynamic_field_match:
                    dynamic_audio_call_rows.append((rows[-1], dynamic_field_match.group(1)))
                source_api_counts[api] += 1
                if asset_id:
                    resolved_call_counts[sound_name] += 1
                continue

            if api == "PlaySound":
                call_key = f"{source_path}:{line}:{column}"
                callback_index_by_source[call_key] += 1
                before = code[max(0, match.start() - 220):match.start()]
                after = code[match.end():min(len(code), match.end() + 300)]
                function_body_start = containing_function[2] if containing_function else 0
                properties = re.findall(r"['\"]([A-Za-z][A-Za-z0-9_]*)['\"]\s*:", before)
                params_match = re.search(r"['\"]onCompleteParams['\"]\s*:\s*(\[[^\]]*\])", after, re.DOTALL)
                callback_params = string_literals(params_match.group(1)) if params_match else []
                callback_sound = callback_params[0] if callback_params else ""
                matching_assets = asset_ids_by_name.get(callback_sound, [])
                callback_asset_id = matching_assets[0] if len(matching_assets) == 1 else ""
                add_row(
                    rows,
                    kind="audio_callback_binding",
                    id_or_name=f"{source_path}:{line}:{column}:{callback_index_by_source[call_key]}",
                    source=source_ref,
                    recovery=source_recovery,
                    conversion="scheduled_play_sound_callback_inventoried",
                    validation="callback_sound_asset_resolved" if callback_asset_id else "callback_parameters_need_context_review",
                    notes={
                        "api": api,
                        "function": function,
                        "enclosing_if_and_loop_guards": enclosing_actionscript_guards(code, match.start(), function_body_start),
                        "callback_property_candidates": properties[-3:],
                        "callback_parameter_literals": callback_params,
                        "sound_name": callback_sound or None,
                        "sound_asset_id": callback_asset_id or None,
                        "source_context": f"{before[-120:]}{match.group(0)}{after[:180]}",
                    },
                )
                callback_count += 1
                if callback_asset_id:
                    resolved_call_counts[callback_sound] += 1

    visual_sound_bindings_by_field: dict[str, list[str]] = {
        "m_impactSound": [],
        "m_mainSound": [],
        "m_mainSound2": [],
    }
    visual_sound_call_pattern = re.compile(r"\b(?:[A-Za-z_$][\w$]*\s*\.\s*)?SetSounds\s*\(")
    for path, source_path, source_recovery in script_inputs:
        raw = path.read_text(encoding="utf-8", errors="replace")
        code = strip_comments(raw)
        function_ranges = action_script_functions(code)
        for match in visual_sound_call_pattern.finditer(code):
            if re.search(r"\bfunction\s*$", code[max(0, match.start() - 24):match.start()]):
                continue
            opening = code.find("(", match.start())
            try:
                closing = matching_delimiter(code, opening, "(", ")")
            except ValueError:
                continue
            arguments = split_actionscript_arguments(code[opening + 1:closing])
            if len(arguments) < 4:
                continue
            containing = next((fn for fn in reversed(function_ranges) if fn[1] <= match.start() <= fn[3]), None)
            function_name = containing[0] if containing else "<class-scope>"
            function_start = containing[2] if containing else 0
            case_matches = list(re.finditer(r"(?m)^\s*case\s+([^:\n]+)\s*:", code[function_start:match.start()]))
            dispatch_case = case_matches[-1].group(1).strip() if case_matches else "<dispatch-case-unresolved>"
            literal_sounds: list[str] = []
            sound_asset_ids: list[str | None] = []
            for sound_argument in (arguments[0], arguments[2]):
                literal_match = re.fullmatch(r"(['\"])(.*?)\1", sound_argument, re.DOTALL)
                sound_name = literal_match.group(2) if literal_match else ""
                candidates = asset_ids_by_name.get(sound_name, [])
                asset_id = candidates[0] if len(candidates) == 1 else ""
                literal_sounds.append(sound_name)
                sound_asset_ids.append(asset_id or None)
                if asset_id:
                    resolved_call_counts[sound_name] += 1
            line = raw.count("\n", 0, match.start()) + 1
            column = match.start() - raw.rfind("\n", 0, match.start())
            add_row(
                rows,
                kind="visual_sound_binding",
                id_or_name=f"{source_path}:{line}:{column}",
                source=source_location(source_path, line),
                recovery=f"{source_recovery}_visual_dispatch",
                conversion="visual_move_sound_names_and_volumes_inventoried",
                validation="literal_sound_assets_resolved" if all(sound_asset_ids[index] or not literal_sounds[index] for index in range(2)) else "one_or_more_visual_sound_ids_unresolved",
                notes={
                    "function": function_name,
                    "visual_move_dispatch_case": dispatch_case,
                    "impact_sound": literal_sounds[0] or None,
                    "impact_volume": arguments[1],
                    "impact_asset_id": sound_asset_ids[0],
                    "main_sound": literal_sounds[1] or None,
                    "main_volume": arguments[3],
                    "main_asset_id": sound_asset_ids[1],
                },
            )
            binding_id = f"{source_path}:{line}:{column}"
            visual_sound_bindings_by_field["m_impactSound"].append(binding_id)
            visual_sound_bindings_by_field["m_mainSound"].append(binding_id)
            counts["visual_sound_bindings"] += 1

    visual_sound_field_assignment = re.compile(
        r"(?:[A-Za-z_$][\w$]*\s*\.\s*)?(m_impactSound|m_mainSound2|m_mainSound)\s*=\s*(['\"])(.*?)\2",
        re.DOTALL,
    )
    for path, source_path, source_recovery in script_inputs:
        raw = path.read_text(encoding="utf-8", errors="replace")
        code = strip_comments(raw)
        function_ranges = action_script_functions(code)
        for match in visual_sound_field_assignment.finditer(code):
            field_name, sound_name = match.group(1), match.group(3)
            if not sound_name:
                continue
            containing = next((fn for fn in reversed(function_ranges) if fn[1] <= match.start() <= fn[3]), None)
            function_name = containing[0] if containing else "<class-scope>"
            function_start = containing[2] if containing else 0
            case_matches = list(re.finditer(r"(?m)^\s*case\s+([^:\n]+)\s*:", code[function_start:match.start()]))
            dispatch_case = case_matches[-1].group(1).strip() if case_matches else "<dispatch-case-unresolved>"
            candidates = asset_ids_by_name.get(sound_name, [])
            asset_id = candidates[0] if len(candidates) == 1 else ""
            line = raw.count("\n", 0, match.start()) + 1
            column = match.start() - raw.rfind("\n", 0, match.start())
            binding_id = f"{source_path}:{line}:{column}"
            volume_field = {
                "m_impactSound": "m_impactSoundVolume",
                "m_mainSound": "m_mainSoundVolume",
                "m_mainSound2": "m_mainSoundVolume2",
            }[field_name]
            add_row(
                rows,
                kind="visual_sound_binding",
                id_or_name=binding_id,
                source=source_location(source_path, line),
                recovery=f"{source_recovery}_visual_dispatch",
                conversion="visual_move_sound_field_and_asset_inventoried",
                validation="exact_swf_sound_asset_match" if asset_id else "visual_sound_asset_unresolved",
                notes={
                    "function": function_name,
                    "visual_move_dispatch_case": dispatch_case,
                    "sound_field": field_name,
                    "sound_name": sound_name,
                    "sound_asset_id": asset_id or None,
                    "volume_field": volume_field,
                    "volume_expression": "default or branch-assigned value; see adjacent source assignments",
                },
            )
            visual_sound_bindings_by_field[field_name].append(binding_id)
            if asset_id:
                resolved_call_counts[sound_name] += 1
            counts["visual_sound_field_bindings"] += 1

    for audio_row, field_name in dynamic_audio_call_rows:
        notes = json.loads(audio_row["notes"])
        bindings = visual_sound_bindings_by_field.get(field_name, [])
        notes["sound_parameter_channel"] = field_name
        notes["visual_sound_configuration_ids"] = bindings
        notes["visual_sound_configuration_count"] = len(bindings)
        if bindings:
            audio_row["conversion"] = "dynamic_sound_channel_joined_to_visual_move_configurations"
            audio_row["validation"] = "dynamic_channel_bound_to_exact_visual_sound_definitions"
        audio_row["notes"] = csv_quote(notes)

    sound_trigger_pattern = re.compile(r"\b(PlayHitSound|PlayMainSound2?)\b")
    for path, source_path, source_recovery in script_inputs:
        raw = path.read_text(encoding="utf-8", errors="replace")
        code = strip_comments(raw)
        function_ranges = action_script_functions(code)
        for match in sound_trigger_pattern.finditer(code):
            prefix = code[max(0, match.start() - 24):match.start()]
            if re.search(r"\bfunction\s*$", prefix):
                continue
            containing_function = next((fn for fn in reversed(function_ranges) if fn[1] <= match.start() <= fn[3]), None)
            function = containing_function[0] if containing_function else "<class-scope>"
            function_body_start = containing_function[2] if containing_function else 0
            suffix = code[match.end():match.end() + 16]
            direct_call = bool(re.match(r"\s*\(", suffix))
            channel = {"PlayHitSound": "m_impactSound", "PlayMainSound": "m_mainSound", "PlayMainSound2": "m_mainSound2"}[match.group(1)]
            line = raw.count("\n", 0, match.start()) + 1
            column = match.start() - raw.rfind("\n", 0, match.start())
            binding_ids = visual_sound_bindings_by_field.get(channel, [])
            add_row(
                rows,
                kind="visual_sound_trigger",
                id_or_name=f"{source_path}:{line}:{column}",
                source=source_location(source_path, line),
                recovery=f"{source_recovery}_visual_timing",
                conversion="visual_sound_channel_trigger_inventoried",
                validation="configuration_channel_joined" if binding_ids else "sound_channel_has_no_static_binding",
                notes={
                    "trigger_method": match.group(1),
                    "trigger_kind": "direct_call" if direct_call else "callback_reference",
                    "sound_field_channel": channel,
                    "function": function,
                    "enclosing_if_and_loop_guards": enclosing_actionscript_guards(code, match.start(), function_body_start),
                    "source_context": code[max(0, match.start() - 100):min(len(code), match.end() + 150)],
                    "visual_sound_configuration_count": len(binding_ids),
                },
            )
            counts["visual_sound_triggers"] += 1

    if music_enum_path.is_file() and controller_path.is_file():
        enum_raw = music_enum_path.read_text(encoding="utf-8", errors="replace")
        controller_raw = controller_path.read_text(encoding="utf-8", errors="replace")
        enum_values = {
            name: int(value)
            for name, value in re.findall(r"const\s+(MUSIC_[A-Za-z0-9_]+)\s*:\s*int\s*=\s*(-?\d+)", enum_raw)
        }
        constructor = re.search(r"public\s+function\s+SoundController\s*\(", controller_raw)
        array_match = re.search(r"new\s+Array\s*\(", controller_raw[constructor.start():]) if constructor else None
        if constructor and array_match:
            opening = constructor.start() + array_match.end() - 1
            closing = matching_delimiter(controller_raw, opening, "(", ")")
            track_arguments = split_actionscript_arguments(controller_raw[opening + 1:closing])
            enum_by_index = {value: name for name, value in enum_values.items()}
            for index, track_argument in enumerate(track_arguments):
                enum_name = enum_by_index.get(index)
                if not enum_name:
                    continue
                sound_name = track_argument.strip().removeprefix("this.")
                candidates = asset_ids_by_name.get(sound_name, [])
                asset_id = candidates[0] if len(candidates) == 1 else ""
                if asset_id:
                    resolved_call_counts[sound_name] += 1
                line = controller_raw.count("\n", 0, opening + 1 + len(controller_raw[opening + 1:closing].split(",", index)[0])) + 1
                enum_match = re.search(rf"\bconst\s+{re.escape(enum_name)}\b", enum_raw)
                enum_line = enum_raw.count("\n", 0, enum_match.start()) + 1 if enum_match else 1
                add_row(
                    rows,
                    kind="music_track_binding",
                    id_or_name=f"BackgroundMusicTracks.{enum_name}",
                    source=f"{source_location(str(controller_path.relative_to(ROOT)), line)}; {source_location(str(music_enum_path), enum_line)}",
                    recovery="original_swf_controller_joined_to_current_source_enum",
                    conversion="loopable_track_mapped_to_embedded_sound",
                    validation="exact_swf_sound_asset_match" if asset_id else "track_asset_unresolved",
                    notes={"track_index": index, "controller_array_expression": track_argument, "sound_name": sound_name, "sound_asset_id": asset_id or None},
                )
                counts["music_track_bindings"] += 1

        for enum_name, behavior in (("MUSIC_NONE", "silence_no_loopable_track"), ("MUSIC_HALLWAY", "restore_saved_previous_music_track")):
            if enum_name not in enum_values:
                continue
            line_match = re.search(rf"const\s+{enum_name}\s*:", enum_raw)
            line = enum_raw.count("\n", 0, line_match.start()) + 1 if line_match else 1
            add_row(
                rows,
                kind="music_track_policy",
                id_or_name=f"BackgroundMusicTracks.{enum_name}",
                source=f"{source_location(str(music_enum_path), line)}; {source_location(str(controller_path.relative_to(ROOT)))}",
                recovery="current_source_enum_and_original_swf_controller",
                conversion="non_asset_track_mode_inventoried",
                validation="source_special_case_recorded",
                notes={"track_index": enum_values[enum_name], "behavior": behavior},
            )
            counts["music_track_policies"] += 1

    if distance_object_path.is_file():
        distance_raw = distance_object_path.read_text(encoding="utf-8", errors="replace")
        movement_match = re.search(r"function\s+OnCharMovement\s*\(", distance_raw)
        line = distance_raw.count("\n", 0, movement_match.start()) + 1 if movement_match else 1
        add_row(
            rows,
            kind="sound_distance_policy",
            id_or_name="SoundDistanceObject.attenuation",
            source=source_location(distance_object_path.relative_to(repository_root).as_posix(), line),
            recovery="current_edited_source",
            conversion="distance_scaled_ambience_policy_inventoried",
            validation="start_cleanup_volume_curve_linked",
            notes={
                "volume_curve": "minVolume + maxVolume * max(0, 1 - distance / roomMaxDistance)",
                "start_stop": "AddSprite starts the optional extra track; Cleanup pauses it",
                "track_volume": "writes either current-track or explicit-track volume",
            },
        )
        counts["sound_distance_policies"] += 1

    for asset in asset_rows:
        match = asset_name_pattern.search(asset["id_or_name"])
        sound_name = match.group(1) if match else asset["id_or_name"]
        add_row(
            rows,
            kind="audio_asset_binding",
            id_or_name=sound_name,
            source=asset["source"],
            recovery="recovered_original_swf_sound_symbol",
            conversion="sound_symbol_joined_to_edited_callsite_inventory",
            validation="one_or_more_static_source_or_visual_bindings" if resolved_call_counts[sound_name] else "asset_recovered_without_static_source_binding_found",
            notes={
                "swf_asset_id": asset["id_or_name"],
                "source_filename": asset_row_by_id[asset["id_or_name"]]["notes"],
                "exact_source_reference_count": resolved_call_counts[sound_name],
                "source_scan_scope": "edited scripts plus original-SWF-only classes; edited class wins on path overlap",
                "unreferenced_is_not_assumed_unused": True,
                "manual_review_note": "A recovered asset with no source binding remains listed rather than being discarded.",
            },
        )
        counts["audio_assets_joined"] += 1

    controller_raw = controller_path.read_text(encoding="utf-8", errors="replace") if controller_path.is_file() else ""
    controller_code = strip_comments(controller_raw)
    play_sound_method = next((fn for fn in action_script_functions(controller_code) if fn[0] == "PlaySound"), None)
    play_sound_line = controller_raw.count("\n", 0, play_sound_method[1]) + 1 if play_sound_method else 1
    add_row(
        rows,
        kind="sound_controller_policy",
        id_or_name="SoundController.PlaySound",
        source=source_location(str(controller_path.relative_to(ROOT)), play_sound_line),
        recovery="original_swf_sound_controller_method",
        conversion="mute_lookup_volume_and_play_contract_inventoried",
        validation="source_method_body_reviewed",
        notes={
            "mute_guard": "m_isSoundOn=false returns null without playback",
            "sound_lookup": "SoundController[param1] as Class, then instantiate as Sound",
            "default_volume": 1.0,
            "volume_behavior": "volume 1 calls play(); other volumes call play(0, 0, SoundTransform(volume))",
            "repeat_count": 0,
            "return": "played Sound instance, or null when muted",
        },
    )
    counts["sound_controller_policies"] += 1

    unbound_audio_assets = sorted(
        match.group(1) if (match := asset_name_pattern.search(asset["id_or_name"])) else asset["id_or_name"]
        for asset in asset_rows
        if not resolved_call_counts[match.group(1) if (match := asset_name_pattern.search(asset["id_or_name"])) else asset["id_or_name"]]
    )
    add_row(
        rows,
        kind="completed_reachability_audit",
        id_or_name="audio_event_bindings",
        source="78 recovered sound assets; edited and original-only ActionScript audio events; recovered SoundController and music track table",
        recovery="source_assets_and_event_bindings_reconciled",
        conversion="Godot playback resources deferred to complete-migration milestone",
        validation="all_source_audio_references_resolved_or_explicitly_unreferenced",
        notes={
            "audio_assets": len(asset_rows),
            "controller_api_calls": sum(source_api_counts.values()),
            "direct_play_sound_calls": source_api_counts["PlaySound"],
            "scheduled_play_sound_callbacks": callback_count,
            "visual_set_sounds_bindings": counts["visual_sound_bindings"],
            "visual_field_assignments": counts["visual_sound_field_bindings"],
            "visual_trigger_methods": counts["visual_sound_triggers"],
            "music_track_bindings": counts["music_track_bindings"],
            "unreferenced_recovered_assets": unbound_audio_assets,
        },
    )
    counts["completed_source_audit_audio"] = 1

    counts["audio_direct_callsites"] = sum(source_api_counts.values())
    counts["audio_play_sound_callsites"] = source_api_counts["PlaySound"]
    counts["audio_music_control_callsites"] = sum(count for api, count in source_api_counts.items() if api != "PlaySound")
    counts["audio_callback_bindings"] = callback_count
    counts["audio_literal_asset_resolutions"] = sum(resolved_call_counts.values())
    return counts


def add_animation_inventory(rows: list[dict[str, str]]) -> Counter[str]:
    """Join source move IDs to visual dispatches, symbols, and exported images."""
    inventory = read_json(SOURCE_INVENTORY)
    repository_root = Path(str(inventory.get("reference_root", "")))
    source_root = edited_source_root(inventory)
    original_scripts_root = EXPORT_DIR / "script/scripts"

    def source_file(relative: str) -> tuple[Path, str, str] | None:
        edited = source_root / relative
        if edited.is_file():
            return edited, edited.relative_to(repository_root).as_posix(), "current_edited_source"
        original = original_scripts_root / relative.removeprefix("scripts/")
        if original.is_file():
            return original, f"original.swf/script/scripts/{relative.removeprefix('scripts/')}", "original_swf_only_class"
        return None

    required_paths = {
        "visual_ids": "scripts/States/MinionVisualMoveID.as",
        "static_data": "scripts/PresistentData/StaticData.as",
        "base_moves": "scripts/Minions/MinionMove/AllBaseMovesContainer.as",
        "sprite_handler": "scripts/Utilities/SpriteHandler.as",
    }
    resolved_paths = {name: source_file(relative) for name, relative in required_paths.items()}
    missing_inputs = [name for name, source in resolved_paths.items() if source is None]
    counts: Counter[str] = Counter()
    if missing_inputs:
        add_row(
            rows,
            kind="open_reachability_audit",
            id_or_name="animation_source_binding_inputs",
            source=";".join(required_paths[name] for name in missing_inputs),
            recovery="required_visual_binding_sources_missing",
            conversion="animation_dispatch_or_sprite_identity_unresolved",
            validation="animation_inventory_incomplete",
            notes={"missing_inputs": missing_inputs},
        )
        counts["animation_inventory_missing_inputs"] = len(missing_inputs)
        counts["open_reachability_audit"] += 1
        return counts

    visual_path, visual_label, visual_recovery = resolved_paths["visual_ids"]
    static_path, static_label, static_recovery = resolved_paths["static_data"]
    base_moves_path, base_moves_label, base_moves_recovery = resolved_paths["base_moves"]
    sprite_path, sprite_label, sprite_recovery = resolved_paths["sprite_handler"]
    visual_raw = visual_path.read_text(encoding="utf-8-sig")
    visual_code = strip_comments(visual_raw)
    visual_constant_pattern = re.compile(
        r"\b(?:public|protected|private)?\s*static\s+const\s+"
        r"(?P<name>[A-Za-z_$][A-Za-z0-9_$]*)\s*:\s*int\s*=\s*(?P<value>-?\d+)\s*;"
    )
    visual_constants: dict[str, dict[str, Any]] = {}
    visual_names_by_value: dict[int, str] = {}
    for match in visual_constant_pattern.finditer(visual_code):
        name = match.group("name")
        value = int(match.group("value"))
        visual_constants[name] = {
            "value": value,
            "line": visual_raw.count("\n", 0, match.start()) + 1,
        }
        visual_names_by_value.setdefault(value, name)

    static_raw = static_path.read_text(encoding="utf-8-sig")
    static_code = strip_comments(static_raw)
    visual_method = next(
        (method for method in declared_actionscript_methods(static_code) if method[0] == "GetVisualMinionMove"),
        None,
    )
    dispatch_cases: dict[str, dict[str, Any]] = {}
    dispatch_line = 1
    if visual_method is not None:
        dispatch_line = static_raw.count("\n", 0, visual_method[1]) + 1
        method_code = static_code[visual_method[2]:visual_method[3]]
        case_pattern = re.compile(r"(?m)^\s*case\s+MinionVisualMoveID\.(?P<name>[A-Za-z_$][A-Za-z0-9_$]*)\s*:")
        case_matches = list(case_pattern.finditer(method_code))
        constructor_pattern = re.compile(
            r"\bnew\s+(?P<class>[A-Za-z_$][A-Za-z0-9_$.]*)\s*\("
        )
        for index, case_match in enumerate(case_matches):
            case_end = case_matches[index + 1].start() if index + 1 < len(case_matches) else len(method_code)
            case_start = case_match.end()
            trailing_switch_branch = re.search(
                r"(?m)^\s*(?:default\s*:|case\s+this\.MoveClass\b)",
                method_code[case_start:case_end],
            )
            if trailing_switch_branch:
                case_end = case_start + trailing_switch_branch.start()
            case_text = method_code[case_start:case_end]
            syntax = mask_actionscript_strings(case_text)
            constructors: list[dict[str, Any]] = []
            for constructor_match in constructor_pattern.finditer(syntax):
                opening = syntax.find("(", constructor_match.start("class") + len(constructor_match.group("class")))
                try:
                    closing = matching_delimiter(case_text, opening, "(", ")")
                except ValueError:
                    continue
                arguments = split_actionscript_arguments(case_text[opening + 1:closing])
                constructors.append({
                    "class": constructor_match.group("class"),
                    "arguments": arguments,
                    "source_line": static_raw.count(
                        "\n", 0, visual_method[2] + case_start + constructor_match.start()
                    ) + 1,
                })
            absolute_case = visual_method[2] + case_match.start()
            dispatch_cases[case_match.group("name")] = {
                "source_line": static_raw.count("\n", 0, absolute_case) + 1,
                "constructors": constructors,
            }

    # Flash symbols are identified by both the qualified class and character ID.
    # Never join on the numeric prefix alone.
    symbol_class_ids: dict[str, list[int]] = defaultdict(list)
    symbol_csv = EXPORT_DIR / "symbolClass/symbols.csv"
    if symbol_csv.is_file():
        with symbol_csv.open("r", encoding="utf-8-sig", newline="") as file:
            for symbol_row in csv.reader(file, delimiter=";"):
                if len(symbol_row) < 2 or not symbol_row[0].strip().isdigit():
                    continue
                symbol_class_ids[symbol_row[1].strip()].append(int(symbol_row[0].strip()))

    sprite_raw = sprite_path.read_text(encoding="utf-8-sig")
    sprite_code = strip_comments(sprite_raw)
    sprite_symbol_by_field: dict[str, str] = {}
    sprite_field_pattern = re.compile(
        r"\b(?:public|protected|private)?\s*(?:static\s+)?(?:var|const)\s+"
        r"(?P<field>[A-Za-z_$][A-Za-z0-9_$]*)\s*:\s*Class\s*=\s*"
        r"(?P<symbol>[A-Za-z_$][A-Za-z0-9_$]*)\s*;"
    )
    for match in sprite_field_pattern.finditer(sprite_code):
        symbol = match.group("symbol")
        prefix = "SpriteHandler_"
        if symbol.startswith(prefix):
            sprite_symbol_by_field[match.group("field")] = f"Utilities.{symbol}"

    image_rows_by_class: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        if row["kind"] != "asset_image":
            continue
        parts = row["id_or_name"].split("|")
        if len(parts) == 4 and parts[0] == "original.swf":
            image_rows_by_class[parts[2]].append(row)

    visual_sound_by_case: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        if row["kind"] != "visual_sound_binding":
            continue
        notes = json.loads(row["notes"])
        if notes.get("function") != "GetVisualMinionMove":
            continue
        case_match = re.search(r"MinionVisualMoveID\.([A-Za-z_$][A-Za-z0-9_$]*)", notes.get("visual_move_dispatch_case", ""))
        if case_match:
            visual_sound_by_case[case_match.group(1)].append({
                "source": row["source"],
                "sound_configuration": notes,
            })

    # Build a compact symbol-resolution detail used by both family and content rows.
    family_asset_details: dict[str, list[dict[str, Any]]] = defaultdict(list)
    family_constructor_details: dict[str, list[dict[str, Any]]] = {}
    unresolved_visual_asset_keys: list[str] = []
    for name, constant in sorted(visual_constants.items(), key=lambda item: (item[1]["value"], item[0])):
        dispatch = dispatch_cases.get(name)
        constructors = dispatch["constructors"] if dispatch else []
        family_constructor_details[name] = constructors
        asset_keys: list[str] = []
        for constructor in constructors:
            for argument in constructor["arguments"]:
                literal = re.fullmatch(r"\s*(['\"])(.*?)\1\s*", argument, re.DOTALL)
                if literal:
                    key = literal.group(2)
                    if key.startswith("mv_") or key in sprite_symbol_by_field:
                        if key not in asset_keys:
                            asset_keys.append(key)
        for asset_key in asset_keys:
            sprite_symbol = sprite_symbol_by_field.get(asset_key, f"Utilities.SpriteHandler_{asset_key}")
            character_ids = sorted(set(symbol_class_ids.get(sprite_symbol, [])))
            matching_images = image_rows_by_class.get(sprite_symbol, [])
            for character_id in character_ids:
                matching_images = [
                    image_row for image_row in image_rows_by_class.get(sprite_symbol, [])
                    if image_row["id_or_name"].startswith(f"original.swf|{character_id}|")
                    and image_row["id_or_name"].endswith("|.png")
                ]
                family_asset_details[name].append({
                    "asset_key": asset_key,
                    "sprite_handler_field": asset_key if asset_key in sprite_symbol_by_field else None,
                    "symbol_class": sprite_symbol,
                    "symbol_character_id": character_id,
                    "exported_image_id": matching_images[0]["id_or_name"] if matching_images else None,
                    "exported_image_source": matching_images[0]["source"] if matching_images else None,
                })
            if not character_ids or not matching_images:
                unresolved_visual_asset_keys.append(f"{name}:{asset_key}")
                if not character_ids:
                    family_asset_details[name].append({
                        "asset_key": asset_key,
                        "sprite_handler_field": asset_key if asset_key in sprite_symbol_by_field else None,
                        "symbol_class": sprite_symbol,
                        "symbol_character_id": None,
                        "exported_image_id": None,
                        "exported_image_source": None,
                    })

    for name, constant in sorted(visual_constants.items(), key=lambda item: (item[1]["value"], item[0])):
        dispatch = dispatch_cases.get(name)
        if dispatch:
            dispatch_status = "explicit_static_dispatch_case"
            source_line = dispatch["source_line"]
        elif name == "VISUALS_SameAsClass":
            dispatch_status = "dynamic_minion_move_class_alias"
            source_line = constant["line"]
        else:
            dispatch_status = "method_fallthrough_to_TestVisualMove"
            source_line = constant["line"]
        constructors = family_constructor_details.get(name, [])
        family_id = f"base:animation_family/{name}"
        family_assets = family_asset_details.get(name, [])
        family_sounds = visual_sound_by_case.get(name, [])
        add_row(
            rows,
            kind="animation_family",
            id_or_name=family_id,
            source=source_location(static_label if dispatch else visual_label, source_line),
            recovery=f"{static_recovery if dispatch else visual_recovery}_visual_id_join",
            conversion="Godot_animation_timeline_and_audio_player_not_connected",
            validation=dispatch_status,
            notes={
                "visual_id_name": name,
                "numeric_visual_id": constant["value"],
                "static_dispatch_status": dispatch_status,
                "implementation_classes": sorted({item["class"] for item in constructors}),
                "implementation_constructors": constructors,
                "asset_keys": sorted({asset["asset_key"] for asset in family_assets}),
                "asset_symbol_bindings": family_assets,
                "visual_sound_bindings": family_sounds,
                "swf_symbol_identity_policy": "qualified_class_and_character_id; never numeric prefix alone",
                "timeline_frames_reconstructed": False,
            },
        )
        counts["animation_family"] += 1
        counts[f"animation_dispatch_status_{dispatch_status}"] += 1
        for asset_index, asset in enumerate(family_assets, 1):
            add_row(
                rows,
                kind="animation_asset_binding",
                id_or_name=f"{family_id}/asset/{asset_index}",
                source=source_location(static_label if dispatch else visual_label, source_line),
                recovery="visual_constructor_to_SpriteHandler_symbolClass_and_exported_PNG",
                conversion="source_asset_identity_recovered_not_Godot_animation",
                validation="qualified_symbol_and_character_id_resolved" if asset["exported_image_id"] else "visual_asset_symbol_or_image_unresolved",
                notes=asset,
            )
            counts["animation_asset_binding"] += 1

    move_rows = [row for row in rows if row["kind"] == "move"]
    moves_by_constant: dict[str, list[dict[str, Any]]] = defaultdict(list)
    available_move_ids: set[str] = set()
    move_notes_by_id: dict[str, dict[str, Any]] = {}
    for row in move_rows:
        try:
            notes = json.loads(row["notes"])
        except json.JSONDecodeError:
            # The staged importer intentionally keeps this older move-row field
            # as compact semicolon-delimited text rather than a JSON object.
            notes = {}
            constant_match = re.search(r"(?:^|;\s*)legacy_constant=([^;]+)", row["notes"])
            available_match = re.search(r"(?:^|;\s*)available=(true|false)", row["notes"], re.IGNORECASE)
            if constant_match:
                notes["legacy_constant"] = constant_match.group(1).strip()
            if available_match:
                notes["available"] = available_match.group(1).lower() == "true"
        constant = notes.get("legacy_constant")
        move_notes_by_id[row["id_or_name"]] = notes
        if constant:
            constant_text = str(constant)
            moves_by_constant[constant_text].append(row)
            dictionary_key = re.search(r"\[\s*(['\"])([^'\"]+)\1\s*\]", constant_text)
            if dictionary_key:
                moves_by_constant[dictionary_key.group(2)].append(row)
        if notes.get("available") is True or str(notes.get("available", "")).lower() == "true":
            available_move_ids.add(row["id_or_name"])

    def tier_siblings(constant: str) -> list[str]:
        if re.search(r"_t\d+$", constant):
            stem = re.sub(r"_t\d+$", "", constant)
            siblings = [
                candidate for candidate in moves_by_constant
                if candidate == constant or re.fullmatch(re.escape(stem) + r"_t\d+", candidate)
            ]
            return sorted(siblings, key=lambda candidate: int(re.search(r"_t(\d+)$", candidate).group(1)))
        return [constant]

    move_binding_dedup: set[tuple[str, str, str, str]] = set()
    mapped_available_moves: set[str] = set()
    missing_move_constants: set[str] = set()

    def record_move_binding(
        base_constant: str,
        visual_name: str,
        channel: str,
        evidence: str,
        evidence_line: int,
        visual_assignment_line: int | None = None,
    ) -> None:
        if visual_name not in visual_constants:
            return
        source_ref = source_location(base_moves_label, evidence_line)
        for tier_constant in tier_siblings(base_constant):
            target_rows = moves_by_constant.get(tier_constant, [])
            if not target_rows:
                missing_move_constants.add(tier_constant)
                continue
            for target in target_rows:
                dedup_key = (target["id_or_name"], channel, visual_name, source_ref)
                if dedup_key in move_binding_dedup:
                    continue
                move_binding_dedup.add(dedup_key)
                if target["id_or_name"] in available_move_ids:
                    mapped_available_moves.add(target["id_or_name"])
                family_assets = family_asset_details.get(visual_name, [])
                add_row(
                    rows,
                    kind="move_visual_binding",
                    id_or_name=f"{target['id_or_name']}/visual/{channel}/{visual_name}/{evidence_line}",
                    source=source_ref,
                    recovery=f"{base_moves_recovery}_move_to_visual_id",
                    conversion="Godot_move_visual_binding_not_connected",
                    validation="visual_family_recovered" if visual_name in dispatch_cases or visual_name == "VISUALS_SameAsClass" else "source_visual_falls_through_to_test_visual",
                    notes={
                        "move_content_id": target["id_or_name"],
                        "legacy_move_constant": move_notes_by_id[target["id_or_name"]].get("legacy_constant", tier_constant),
                        "normalized_legacy_move_key": tier_constant,
                        "visual_channel": channel,
                        "visual_id_name": visual_name,
                        "numeric_visual_id": visual_constants[visual_name]["value"],
                        "animation_family_id": f"base:animation_family/{visual_name}",
                        "resolved_visual_asset_ids": sorted({asset["exported_image_id"] for asset in family_assets if asset["exported_image_id"]}),
                        "source_evidence": evidence,
                        "visual_assignment_source": source_location(base_moves_label, visual_assignment_line) if visual_assignment_line else None,
                        "tier_mapping": "source_tier1_visual_inherited_by_copy_or_helper_family" if tier_constant != base_constant else "explicit_source_tier1_visual_assignment",
                    },
                )
                counts["move_visual_binding"] += 1

    move_code_raw = base_moves_path.read_text(encoding="utf-8-sig")
    move_code = strip_comments(move_code_raw)
    move_call_pattern = re.compile(r"\b(?:this\s*\.\s*)?CreateMove\s*\(")
    for match in move_call_pattern.finditer(move_code):
        if re.search(r"\bfunction\s*$", move_code[max(0, match.start() - 24):match.start()]):
            continue
        opening = move_code.find("(", match.start())
        try:
            closing = matching_delimiter(move_code, opening, "(", ")")
        except ValueError:
            continue
        arguments = split_actionscript_arguments(move_code[opening + 1:closing])
        if len(arguments) < 7:
            continue
        move_expression = arguments[3]
        move_match = re.search(r"MoveDict\s*\[\s*(['\"])([^'\"]+)\1\s*\]", move_expression)
        if not move_match:
            move_match = re.search(r"MinionMoveID\.([A-Za-z_$][A-Za-z0-9_$]*)", move_expression)
            move_constant = move_match.group(1) if move_match else ""
        else:
            move_constant = move_match.group(2)
        visual_match = re.search(r"MinionVisualMoveID\.([A-Za-z_$][A-Za-z0-9_$]*)", arguments[6])
        if not move_constant or not visual_match:
            continue
        line = move_code_raw.count("\n", 0, match.start()) + 1
        record_move_binding(
            move_constant,
            visual_match.group(1),
            "primary",
            "CreateMove argument sets m_visualMoveID",
            line,
            visual_assignment_line=line,
        )

    # Group helpers set a first-tier ID once, then construct/copy each tier from
    # mutable m_currMinionMoveVisuals and optionally m_currMinionDOTMoveVisuals.
    first_move_pattern = re.compile(r"m_currFirstMinionMoveID\s*=\s*MinionMoveID\.([A-Za-z_$][A-Za-z0-9_$]*)\s*;")
    primary_visual_pattern = re.compile(r"m_currMinionMoveVisuals\s*=\s*MinionVisualMoveID\.([A-Za-z_$][A-Za-z0-9_$]*)\s*;")
    dot_visual_pattern = re.compile(r"m_currMinionDOTMoveVisuals\s*=\s*MinionVisualMoveID\.([A-Za-z_$][A-Za-z0-9_$]*)\s*;")
    move_methods = declared_actionscript_methods(move_code)
    methods_by_name = {method[0]: method for method in move_methods}
    constructor = methods_by_name.get("AllBaseMovesContainer")
    constructor_body = move_code[constructor[2]:constructor[3]] if constructor else ""
    constructor_calls = re.findall(
        r"\bthis\s*\.\s*(Create[A-Za-z_$][A-Za-z0-9_$]*)\s*\(", constructor_body
    )
    if not constructor_calls:
        constructor_calls = [method[0] for method in move_methods if method[0].startswith("Create")]

    # The source keeps the visual ID in a mutable field shared by factory calls.
    # Follow constructor order so a tier group without a local assignment (notably
    # passive moves) inherits the exact previous assignment instead of being lost.
    current_visual_name = visual_names_by_value.get(0)
    current_visual_line: int | None = None
    current_visual_method: str | None = None
    processed_group_methods: set[str] = set()
    for method_name in constructor_calls:
        method = methods_by_name.get(method_name)
        if method is None:
            continue
        processed_group_methods.add(method_name)
        body = move_code[method[2]:method[3]]
        assignments = list(first_move_pattern.finditer(body))
        cursor = 0
        for index, assignment in enumerate(assignments):
            end = assignments[index + 1].start() if index + 1 < len(assignments) else len(body)
            # Apply any carried visual-state write before this group.
            prior_visuals = list(primary_visual_pattern.finditer(body, cursor, assignment.start()))
            if prior_visuals:
                state = prior_visuals[-1]
                current_visual_name = state.group(1)
                current_visual_line = move_code_raw.count("\n", 0, method[2] + state.start()) + 1
                current_visual_method = method_name

            group_body = body[assignment.end():end]
            base_constant = assignment.group(1)
            primary = list(primary_visual_pattern.finditer(group_body))
            dot = list(dot_visual_pattern.finditer(group_body))
            group_line = move_code_raw.count("\n", 0, method[2] + assignment.start()) + 1
            if primary:
                state = primary[-1]
                current_visual_name = state.group(1)
                current_visual_line = move_code_raw.count("\n", 0, method[2] + assignment.end() + state.start()) + 1
                current_visual_method = method_name
            if dot:
                state = dot[-1]
                visual_line = move_code_raw.count("\n", 0, method[2] + assignment.end() + state.start()) + 1
                record_move_binding(
                    base_constant,
                    state.group(1),
                    "damage_over_time",
                    "m_currMinionDOTMoveVisuals initializer for tiered move helper",
                    group_line,
                    visual_assignment_line=visual_line,
                )
            if current_visual_name:
                evidence = (
                    "m_currMinionMoveVisuals initializer for tiered move helper"
                    if primary
                    else f"m_currMinionMoveVisuals retained from {current_visual_method or 'ActionScript int default'}; helper copies it to m_visualMoveID"
                )
                record_move_binding(
                    base_constant,
                    current_visual_name,
                    "primary",
                    evidence,
                    group_line,
                    visual_assignment_line=current_visual_line,
                )
            cursor = end

        # Carry writes after the final group into the next constructor-invoked factory.
        trailing_visuals = list(primary_visual_pattern.finditer(body, cursor))
        if trailing_visuals:
            state = trailing_visuals[-1]
            current_visual_name = state.group(1)
            current_visual_line = move_code_raw.count("\n", 0, method[2] + state.start()) + 1
            current_visual_method = method_name

    # Non-constructor helpers may still contain self-contained grouped move IDs.
    # Only map them when their own body sets a visual explicitly.
    for method in move_methods:
        if method[0] in processed_group_methods:
            continue
        body = move_code[method[2]:method[3]]
        assignments = list(first_move_pattern.finditer(body))
        for index, assignment in enumerate(assignments):
            end = assignments[index + 1].start() if index + 1 < len(assignments) else len(body)
            group_body = body[assignment.end():end]
            primary = list(primary_visual_pattern.finditer(group_body))
            dot = list(dot_visual_pattern.finditer(group_body))
            group_line = move_code_raw.count("\n", 0, method[2] + assignment.start()) + 1
            if primary:
                state = primary[-1]
                visual_line = move_code_raw.count("\n", 0, method[2] + assignment.end() + state.start()) + 1
                record_move_binding(
                    assignment.group(1), state.group(1), "primary",
                    "m_currMinionMoveVisuals initializer for non-constructor helper",
                    group_line, visual_assignment_line=visual_line,
                )
            if dot:
                state = dot[-1]
                visual_line = move_code_raw.count("\n", 0, method[2] + assignment.end() + state.start()) + 1
                record_move_binding(
                    assignment.group(1), state.group(1), "damage_over_time",
                    "m_currMinionDOTMoveVisuals initializer for non-constructor helper",
                    group_line, visual_assignment_line=visual_line,
                )

    unbound_moves = sorted(available_move_ids - mapped_available_moves)
    for move_id in unbound_moves:
        move_row = next(row for row in move_rows if row["id_or_name"] == move_id)
        move_notes = move_notes_by_id[move_id]
        add_row(
            rows,
            kind="move_visual_binding_missing",
            id_or_name=f"{move_id}/visual_binding_missing",
            source=move_row["source"],
            recovery="constructed_move_without_recovered_visual_assignment",
            conversion="visual_id_unmapped",
            validation="move_visual_source_join_gap",
            notes={"legacy_move_constant": move_notes.get("legacy_constant"), "available": True},
        )
        counts["move_visual_binding_missing"] += 1

    # Still images and symbolClass rows do not preserve timeline frame order,
    # labels, nested clip timing, transforms, or scripted visual sequencing.
    add_row(
        rows,
        kind="open_reachability_audit",
        id_or_name="animation_timeline_reconstruction",
        source="original.swf timeline tags; 1,884 symbolClass entries; exported visual symbols and source GetVisualMinionMove dispatch",
        recovery="qualified_visual_class_asset_and_content_ids_joined",
        conversion="frame_timing_nested_clip_and_timeline_label_export_not_recovered",
        validation="timeline_frames_nested_clips_and_scripted_sequences_not_reconstructed",
        notes={
            "timeline_frames_reconstructed": False,
            "limitation": "Flattened PNGs and symbolClass IDs establish visual identity, not the original SWF frame sequence, frame labels, nested clip timing, transforms, or code-driven sequencing.",
            "source_inventory_coverage": {
                "declared_visual_id_constants": len(visual_constants),
                "explicit_GetVisualMinionMove_cases": len(dispatch_cases),
                "constructed_move_visual_bindings": len(mapped_available_moves),
                "constructed_moves_without_visual_binding": unbound_moves,
                "unresolved_source_sprite_asset_keys": sorted(set(unresolved_visual_asset_keys)),
            },
        },
    )
    counts["open_reachability_audit"] += 1

    animation_mapping_complete = not unbound_moves and not unresolved_visual_asset_keys and visual_method is not None
    add_row(
        rows,
        kind="completed_reachability_audit" if animation_mapping_complete else "open_reachability_audit",
        id_or_name="animation_family_source_bindings",
        source="MinionVisualMoveID, StaticData.GetVisualMinionMove, AllBaseMovesContainer, SpriteHandler, SWF symbolClass, and exported image symbols",
        recovery="content_ids_visual_dispatch_classes_assets_and_sound_bindings_joined",
        conversion="Godot_animation_player_and_timeline_resources_not_connected",
        validation="source_level_animation_bindings_reconciled" if animation_mapping_complete else "source_animation_binding_gaps_listed",
        notes={
            "declared_visual_id_constants": len(visual_constants),
            "explicit_GetVisualMinionMove_cases": len(dispatch_cases),
            "animation_families": counts["animation_family"],
            "animation_asset_bindings": counts["animation_asset_binding"],
            "move_visual_bindings": counts["move_visual_binding"],
            "constructed_move_count": len(available_move_ids),
            "constructed_moves_mapped": len(mapped_available_moves),
            "constructed_moves_without_visual_binding": unbound_moves,
            "unresolved_source_sprite_asset_keys": sorted(set(unresolved_visual_asset_keys)),
            "fallback_visual_ids_without_explicit_cases": sorted(
                name for name in visual_constants if name not in dispatch_cases and name != "VISUALS_SameAsClass"
            ),
            "timeline_frame_data_remains_open": True,
        },
    )
    counts["completed_source_audit_animation"] = int(animation_mapping_complete)
    if not animation_mapping_complete:
        counts["open_reachability_audit"] += 1
    counts["animation_declared_visual_ids"] = len(visual_constants)
    counts["animation_dispatch_cases"] = len(dispatch_cases)
    counts["animation_constructed_moves"] = len(available_move_ids)
    counts["animation_constructed_moves_mapped"] = len(mapped_available_moves)
    return counts


def add_open_audits(rows: list[dict[str, str]]) -> Counter[str]:
    gaps = [
        ("rule_toggles_and_modes", "eight menu groups, the complete StaticData flag registry, exact access/guard sites, toggle restrictions, persistence/rebuild timing, and Infinite Tower mode values", "The source rule surface is now enumerated below; this remains open until the Godot pending/active configuration, content availability restrictions, and special-mode flows are converted and connected."),
    ]
    for name, source, note in gaps:
        add_row(
            rows,
            kind="open_reachability_audit",
            id_or_name=name,
            source=source,
            recovery="source_classes_or_payloads_recovered",
            conversion="not_converted",
            validation="inventory_gap_explicit",
            notes=note,
        )
    return Counter({"open_reachability_audit": len(gaps)})


def build(output: Path, force: bool) -> int:
    if output.exists() and not force:
        print(f"Refusing to overwrite existing manifest without --force: {output}", file=sys.stderr)
        return 2

    rows: list[dict[str, str]] = []
    counts: Counter[str] = Counter()
    add_source_classes(rows)
    counts["source_class_rows"] = len(rows)
    counts.update(add_menu_navigation_inventory(rows))
    counts.update(add_staged_definitions(rows))
    counts.update(add_rooms(rows))
    counts.update(add_room_dispatch_map(rows))
    counts.update(add_trainers(rows))
    counts.update(add_trainer_room_bindings(rows))
    counts.update(add_original_assets(rows))
    counts.update(add_edited_source_assets(rows))
    counts.update(add_audio_inventory(rows))
    counts.update(add_animation_inventory(rows))
    counts.update(add_mod_groups(rows))
    counts.update(add_rule_toggle_inventory(rows))
    counts.update(add_progression_flow_inventory(rows))
    counts.update(add_open_audits(rows))

    counts["room_object_family"] = sum(row["kind"] == "room_object_family" for row in rows)
    counts["source_room_object_instances"] = sum(row["kind"] == "source_room_object_instance" for row in rows)

    keys = [(row["kind"], row["id_or_name"]) for row in rows]
    duplicate_keys = [key for key, total in Counter(keys).items() if total > 1]
    if duplicate_keys:
        print(f"Duplicate (kind, id) entries found: {duplicate_keys[:10]}", file=sys.stderr)
        return 1

    missing_resources = [
        row for row in rows if row["kind"] in {"type", "type_chart", "minion", "minion_presentation", "move", "talent_tree"}
        and row["conversion"] == "missing_resource"
    ]
    if missing_resources:
        print(f"Warning: {len(missing_resources)} staged content rows lack a maintained Resource.", file=sys.stderr)

    rows.sort(key=lambda row: (row["kind"], row["id_or_name"], row["source"]))
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=FIELDS, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {len(rows)} unique rows to {output.relative_to(ROOT).as_posix() if output.is_relative_to(ROOT) else output}")
    for kind, count in sorted(counts.items()):
        print(f"{kind}: {count}")
    print(f"explicit_open_audits: {counts['open_reachability_audit']}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help="CSV destination (default: development/inventory/reachable_content_manifest.csv)")
    parser.add_argument("--force", action="store_true", help="overwrite a previously generated manifest")
    args = parser.parse_args()
    output = args.output if args.output.is_absolute() else ROOT / args.output
    return build(output.resolve(), args.force)


if __name__ == "__main__":
    raise SystemExit(main())
