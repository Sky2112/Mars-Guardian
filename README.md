# MarsGuardian

Mars navigation and hazard-safety system (Godot 4.5+, GL Compatibility).

**Status: work in progress.** This first commit adds the navigation core
(`nav_system.gd`), hazard data (`hazard_data.gd`) and headless tests. UI integration follows.

- `nav_system.gd`: hazard-aware route planner (A* on a hazard cost grid), turn-by-turn steps, simulated GPS.
- `hazard_data.gd`: restricted areas, caution hazards, extra places. Illustrative, not official NASA/ESA data.
- `tests/test_nav.gd`: `godot --headless --path . --script tests/test_nav.gd`

Designed by: Abdulrahman & Saleh
