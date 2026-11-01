# Lobby transitions and prompt controls

The lobby elevator and floor-selector Return now use the recovered
`ScreenController.SetSceneTo` timing: fade to black for 0.5 seconds, switch at
opaque, hold for 0.2 seconds and reveal for 0.5 seconds. Room movement, floor
selection and close requests are blocked during the transition. Switching
Standard/Hard inside the selector refreshes its contents without another
cross-screen fade. Selecting a floor retains its existing handoff/save guards.

The existing Tips preference is now labeled **Tutorials**. Turning it off
suppresses the early room/battle instructions, move-selection hint, first-defeat
help, bonus-floor explanation and tutorial reminders. Scheduling rechecks the
preference after delays, so queued prompts do not appear after it is disabled.
It does not rewrite tutorial history or skip required battle/reward decisions.
Bonus-floor reveal state still saves, and actual save failures still offer retry.

**Exit Check** independently controls the floor/hatchery return-to-lobby
confirmation. Both options default to on. Old preferences retain their existing
Tips choice and default to confirming exits. Tutorials can be disabled while
the progress-reset warning remains enabled.

The Type Guide adds a source-art **Type Hints** toggle at the top right, sharing
the settings instance with its battle or Pedia caller. The single-target report
was corrected by the tester: previews remain hover-based, so automatic target
selection does not hide a separate confirmation-stage preview.

The guarded `tests/tutorial_settings_lobby_flow_smoke.gd` covers real preference
persistence, default migration, suppression, save retry, independent exit
confirmation and timed lobby transitions. Enabled tutorial behavior, floor-entry
rollback/input restoration, and the guide's shared setting are covered by the
existing focused fixtures. Rendered captures live under ignored `build/`.
