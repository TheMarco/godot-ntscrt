# Extraction notes

The source was the working Godot port in Liminal on 2026-10-03. Its parent repository HEAD was `26c98e7c7265415031cb7dc852ec96ea4b4ba80b`; the extracted port included then-uncommitted work, including the independently seeded glitch-noise fix. That commit alone is not the complete port snapshot.

Pinned upstream revisions:

- NTSCRT: `644e01b8d0285bdd5143c42491256ce0a4d315ff`.
- ntsc-rs: `add90f5bf1bf7e3c573e4e945a16f44a82941b51`.
- libretro/slang-shaders: `cb01f2f238700eed7ec1c859be1737a9fbcdcb7c`.

## Included

The full GPU NTSC implementation (22 stages / 62 settings), all 17 receiver controls, seven original CRT models (38 passes), original downscale kernels, aspect/supersampling policy, optional previous-field history, selected authored glitch tracks, and the five procedural game-triggered fault types. The independent film-grain shader is included as part of the recorded image.

`internal/` retains the low-level port's algorithms. Source paths were moved under `addons/ntscrt/`, low-level global class registrations were removed, and the controls now use the host project's theme instead of Liminal's font. The LUT loader decodes packaged PNG bytes directly, with Godot's imported-texture fallback; it no longer emits a misleading raw-image export warning.

`NtscrtProfile` and `NtscrtEffect` replace Liminal's GameSettings, GraphicsQuality, PostProcessController and main-scene dependencies. The wrapper uses normal SubViewportContainer ownership and input routing; content is attached before play and stays attached when effects change. RenderingDevice work still runs on Godot's rendering thread.

## Deliberately outside the extraction

Liminal's game levels, assets, progress/settings files, enemy logic, random-event scheduler, title/pause UI, classic VHS shader and older approximate fallback renderer are not part of the reusable full NTSCRT pipeline. There is no dependency on the original game, a sibling checkout, Rust/Swift, or a running NTSCRT application. Optional importer tools accept upstream source directories only when explicitly run to regenerate bundled data.

No guarantee of pixel identity on all GPUs or hardware-wide performance is implied. Upstream shader algorithms and pinned source are preserved, while the existing gameplay presets, calibration, resolution budgets and readable glitch limits are adaptations.

## Regenerating vendored data

```sh
python3 tools/import_slang.py /path/to/pinned/slang-shaders
python3 tools/import_glitch_presets.py /path/to/pinned/NTSCRT
```

The Slang importer requires Python 3 and `clang` for preprocessing. Existing manifests are committed; neither importer is needed to run the addon. Generated metadata retains upstream file hashes. Read `LICENSING.md` before distributing regenerated or existing upstream material.
