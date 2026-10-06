# Original gameplay defects and investigation backlog

These observations are investigation items, not authorization to change behavior.

- `StaticData.CreateFinalInitialThings` assigns `NUM_OF_MOVES` from the instance
  `initMoveID` while local variables with the same conceptual role are advanced.
- Several chance checks use strict `chance > Math.random() * 100`; boundary
  behavior must be preserved even if it looks unconventional.
- Battle tie advantage is randomized once at activation rather than resolved by
  an obvious stable rule.
- Mod-enabled content uses dynamic numeric IDs, making values configuration-order
  dependent; the port must migrate to stable IDs without changing availability.
- Planning identified suspicious debug-like initialization values. Their precise
  locations and reachability still need source/SWF fixture evidence.
- Resolved for the port: `BaseTalentTreeContainer` uses dynamic dictionary keys
  for Mud Blast tiers 3–5 in `iSloth_Thaw`, but `StaticData` registers only the
  six `i*` move families. The accompanying source comment explicitly calls Mud
  Blast a temporary replacement for the unimplemented `iSland`; the port maps
  these exact three references to base Mud Blast IDs 182–184.
- Resolved for the port: edited source and compiled `default.swf` have Arkvian
  and Arkclaw request `MinionMoveID.holyLight_t1`, while the declared move is
  `holy_light_t1` (675). The two exact references are corrected to Holy Light.
  No general spelling or case fallback is enabled.
- Port compatibility correction: the source spells Arkvian as `holyBirb1` and
  `holyBirb2`, and `StaticData.SetupTheEggeryInfo` separately checks the
  unregistered capitalization variant `HolyBirb1`. Maintained Godot rule IDs,
  minion IDs, presentation IDs, and the talent-tree ID now use `holyBird1` /
  `holyBird2`; exact aliases map `holyBirb1`, `HolyBirb1`, and `holyBirb2` to
  those canonical IDs. Source sprite/class names remain only as provenance, and
  no generic case folding is enabled. The eggery service itself remains
  unconverted and must consume the canonical pack lookup when campaign
  progression is implemented. The original source is unchanged.
