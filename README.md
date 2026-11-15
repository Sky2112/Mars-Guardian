# MarsGuardian

Mars navigation and hazard-safety app for crews and operators. Godot 4.7, GL Compatibility renderer.

**Status:** first integrated build. It was written and syntax-checked without the Godot editorz

## What it does

- **Map and places:** NASA Trek tile layers, about 100 places (missions, volcanoes, canyons, craters, plains), search and categories.
- **Safe route:** pick a start, a destination, a vehicle and a priority (safest, balanced, fastest). The route goes around restricted areas, reports what it avoided, the closest keep-out, risk and drive time, and lists turn-by-turn steps.
- **Simulated GPS drive:** follow the route with a simulated position that drifts and is corrected, with live guidance and keep-out alerts.
- **Restricted areas:** red hazard-tape outlines on the map. Caution zones are amber.

## Files

- `node_2d.gd`: the app and UI
- `nav_system.gd`: route planner, steps, simulated GPS (no UI)
- `hazard_data.gd`: restricted areas, caution hazards, extra places
- `tests/test_nav.gd`: headless tests
- `docs/`: [ARCHITECTURE](docs/ARCHITECTURE.md) (system design and Godot verdict), [HAZARDS](docs/HAZARDS.md) (research and avoidance), [DESIGN](docs/DESIGN.md) (tokens and handoff)

## Run and test

```
godot --path .
godot --headless --path . --script tests/test_nav.gd
```

## Windows build

`.github/workflows/build-windows.yml` builds `MarsGuardian.exe` on GitHub Actions. Run it from the Actions tab and download the artifact.

Designed by: Abdulrahman & Saleh


## Latest Release
The latest release included non-documented update, please do use that.
