# Focused checks

Use the Godot executable available on your machine. Import the project in the editor once before running tests, so compute shaders and global classes have their normal import metadata. GPU tests require native Forward+ or Mobile; do not add `--headless` to them.

```sh
# Every profile field, all model parameters, JSON/resource roundtrips and sanitation.
godot --headless --path . --script tests/audit_profile.gd

# Canonical control descriptors, UI signals and disabled groups.
godot --headless --path . --script tests/audit_ntscrt_full_controls.gd

# Native demo, all model controls, A/B, captured JSON/.tres/PNG, loading, stage
# toggles, pause, resize and cleanup. Saves user://test-captures/ (or -- --capture-dir=/path).
godot --path . --audio-driver Dummy --script tests/smoke.gd --quit-after 1500

# All original CRT chains compile and produce a nonblank GPU image.
godot --path . --script tests/audit_ntscrt_slang.gd --quit-after 1500 -- --preset=all

# Consecutive static fields must not be translations of one fixed noise sheet.
godot --path . --script tests/audit_ntscrt_slang.gd --quit-after 600 -- --preset=glitch_noise

# Imported compute shaders, canonical JSON, licenses and CRT lookup images.
godot --headless --path . --script tests/audit_ntscrt_export.gd

# Original sizing policy, independent of a GPU.
godot --headless --path . --script tests/audit_ntscrt_preview_scaler.gd

# Source-path isolation and pinned CRT hashes.
python3 tests/check_portability.py
```

A `--quit-after` timeout is a hang guard, not evidence of passing. Check for the explicit PASS/OK message and no script errors. Tests do not read or write the game's profile; the one profile roundtrip uses a temporary file.

## Export regression

The example `Demo pack` export preset includes tests for verification. Enable the NTSCRT editor plugin before exporting. The pack can then be run independently of the source checkout:

```sh
mkdir -p build
godot --headless --editor --path . --export-pack "Demo pack" build/godot-ntscrt.pck
godot --headless --main-pack build/godot-ntscrt.pck --script res://tests/audit_ntscrt_export.gd
godot --main-pack build/godot-ntscrt.pck --audio-driver Dummy --script res://tests/smoke.gd --quit-after 1500
```

Native compute-shader imports must exist before exporting. Exporting the example pack needs the matching Godot export templates. For your game's production preset, exclude `tests/*` and `demo/*`; keep the NTSCRT export plugin enabled.
