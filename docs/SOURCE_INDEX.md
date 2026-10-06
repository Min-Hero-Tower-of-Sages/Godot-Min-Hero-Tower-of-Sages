# Source-to-subsystem index

This index avoids rescanning the full reference tree during each implementation
slice. Paths are relative to `MinHeroMods/source/scripts`.

| Port subsystem | Primary edited reference | Notes |
|---|---|---|
| Startup/services | `Main.as`, `Utilities/Singleton.as` | Replace global graph with application composition root. |
| Static content | `PresistentData/StaticData.as` | Type chart, floor arrays, mod-derived IDs, levels. |
| Save/campaign state | `PresistentData/DynamicData.as` | Three-save behavior and special modes need capture. |
| Minions | `Minions/AllMinionsContainer.as`, `BaseMinion.as` | Definition values and conditional registrations. |
| Moves | `Minions/MinionMove/AllBaseMovesContainer.as`, `BaseMinionMove.as` | Tier copying/setters require explicit importer handling. |
| Runtime minion | `Minions/OwnedMinion.as` | Split persistent and battle-local properties. |
| Scheduling | `BattleSystems/BattleScreen.as` | Tie side, phases, win/loss, rewards. |
| Move resolution | `BattleSystems/Other/BaseMoveSystem.as` | Numeric and effect ordering authority. |
| Player targeting | `BattleSystems/Other/PlayerMoveSystem.as` | Random slot selection and shield exclusions. |
| AI | `BattleSystems/Other/AIMoveSystem.as` | Port selection logic without generic substitution. |
| Battle presentation | `BattleSystems/Visuals/**` | Keep timing downstream of recorded events. |
| Rooms | `TopDown/Levels/BaseTopDownLevel.as` | Compressed XML and `AddObject` dispatch. |
| Visible edited rooms | `TopDown/Levels/**` | Only a small subset is visible; SWF recovery required. |
| Interactions | `TopDown/LevelObjects/**` | Reusable room components and persistent IDs. |
| Exploration | `TopDown/TopDownMovementScreen.as`, `Utilities/CollisionController.as` | Preserve 30 Hz behavior explicitly. |
| Trainers | `TopDown/Trainers/TrainerSystem.as` | Floors, Ice Floor, Infinite Tower. |
| Menus | `MainMenu/**`, `TopDown/Menus/**`, `LevelSelect/**` | Screen router registrations. |
| Mods | `MainMenu/ModMenu.as`, `TopDown/Menus/SettingsMenu.as` | Active/pending reload boundary and disable restrictions. |
| Sprite extraction | `Utilities/SpriteHandler.as`, `source/symbolClass/` | Timeline context is part of identity. |
