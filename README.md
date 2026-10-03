# Godot NTSCRT

GPU NTSC/VHS tape processing and seven original CRT shader chains for Godot.
Extracted from the working Liminal port of [NTSCRT](https://github.com/finnmckenty/NTSCRT), with a standalone API and a self-contained demo.

Tape and CRT are independent: use a damaged recording, a clean image on a CRT, both together, or neither. Put the game and recorded HUD inside the effect; put crisp menus outside it.

**Licensing status:** this port is not a license-cleared release. Public availability does not resolve upstream licensing. The pinned NTSCRT checkout has no repository-wide license. Its receiver, downscaler, sizing and preset-derived material need license clarification before redistribution. CRT shaders retain their own licenses, including GPL. See [LICENSING.md](LICENSING.md); the integration's MIT license does not override upstream rights.

## Try the demo

Open `project.godot` with **Godot 4.7+**, select **Forward+** or **Mobile**, and press F6 on `demo/demo.tscn` (or F5 for the project).

For a fresh checkout, let Godot import the scripts and shaders first:

```sh
godot --editor --path . --import
godot --path .
```

Tested with Godot **4.7.2**, Forward+/Metal, on an Apple M3 Max. Vulkan, Windows, Linux, mobile devices and low-end GPUs have not been verified. Compatibility/OpenGL and Web do not support this compute pipeline; the wrapper displays the source unchanged and reports that limitation.

The demo has four tape choices, independent CRT, quality, reduced flashing, and two glitch buttons. Advanced controls expose the original NTSC/receiver settings and CRT model selection. The demo includes the supplied TV test card and an original animated chart. No Liminal assets, media downloads, Rust runtime, Swift application, or external service is required. The supplied image has its own provenance note in `demo/assets/README.md`; it is not required by the addon.

## Add it to a project

1. Copy **`addons/ntscrt/`** into the same location in your Godot project.
2. Enable **NTSCRT** under Project Settings → Plugins. The plugin packages JSON, lookup images, source and license notices when exporting.
3. Use Forward+ or Mobile. Add a full-rect `Control` with `effect.gd` attached, and assign a `NtscrtProfile` resource.
4. Instantiate your game under the effect's source viewport. Keep menus on a sibling `CanvasLayer` above the effect.

```gdscript
extends Control

const EFFECT = preload("res://addons/ntscrt/effect.gd")
const PROFILE = preload("res://addons/ntscrt/profile.gd")
const GAME = preload("res://game.tscn")

func _ready() -> void:
    var recording := PROFILE.new()
    recording.select_tape(PROFILE.Tape.WORN_TAPE)
    recording.crt_enabled = true
    recording.quality = PROFILE.Quality.HIGH

    var video := EFFECT.new()
    video.profile = recording
    add_child(video) # Creates its SubViewport before adding game content.
    video.add_content(GAME.instantiate())
```

Expected scene ownership:

```text
Root Control
├── NtscrtEffect
│   └── RecordedContent (SubViewport, created by the effect)
│       └── Game scene, including the HUD you want filtered
└── CanvasLayer (layer 10)
    └── Title / pause / settings / subtitles you want crisp
```

`get_source_viewport()` exposes the recorded viewport for cameras, viewport textures and explicit project configuration. Attach a fresh game instance; do not reparent a live game. The effect preserves its source viewport when toggling models. Nodes inside it receive Godot's normal SubViewportContainer input routing. A dedicated photo viewport remains independent unless you explicitly render it through another effect.

Profiles are ordinary Resources. Save a `.tres` with `ResourceSaver`, duplicate with `duplicate(true)` for independent instances, or share one resource deliberately. Scalar setters notify the effect automatically. For dictionary parameters, assign a new dictionary or call `emit_changed()` after editing it in place.

## Trigger glitches

```gdscript
video.trigger_glitch("glitch_pop", 0.53) # Brief authored cue.
video.trigger_glitch("two_blips", 1.1)
video.trigger_fault(NtscrtEffect.Fault.RF_STATIC, 0.25, 0.8)
video.clear_glitch()
```

Five procedural faults are included: tracking, colour unlock, dropout, RF static and sync slip. The two authored cues retain selected upstream timeline tracks and readability limits. The diagonal scrolling-static defect from the initial port is fixed: fields receive independent noise.

The addon does **not** spawn enemies, schedule random faults, alter gameplay timing or decide when danger occurs. Call a cue before your own encounter, damage or transition event. Cues pause with the effect, return to the selected tape settings afterward, and are suppressed by Tape Off, zero tape damage, or Reduced flashing. CRT can remain enabled throughout.

Optional local interference: `video.set_entity_interference(normalized_position, radius, amount)`. Reset its amount to zero when the event ends.

## Quality and performance

| Quality | Automatic tape buffer | Processed output ceiling | Automatic CRT |
| --- | --- | --- | --- |
| Low | 360×240 | 720p | Aperture |
| Medium | 540×360 | 1080p | Aperture |
| High | 720×480 | 1440p | Royale |
| Ultra | 720×480 | Window size | Royale |

The final image fills the effect rectangle. The tape sizes preserve the original port's anamorphic convention. Use custom width to derive the signal height from your source aspect instead.

With `auto_world_resolution` enabled, 3D rendering is capped at 480p for CRT, 720p for tape/receiver without CRT, and 360p on Low. With everything off the viewport returns to full scale. Set `auto_world_resolution = false` if your game controls its own 3D resolution; then configure the source viewport yourself. Lighting, shadows and anti-aliasing remain your project's responsibility.

GPU presentation adds **one frame of latency**. The optional receiver still performs CPU timing work; leave it off for the lighter gameplay path. Source-resolution processing and original supersampling can be expensive. The quality tiers are practical budgets, not guarantees for every GPU. Opening a shader model for the first time can compile pipelines.

## Advanced API

`NtscrtProfile` exposes all canonical **62 NTSC** and **17 receiver** settings through `ntsc_overrides` and `receiver_overrides`. Keys and ranges come from the bundled schemas. CRT parameters are grouped by model:

```gdscript
recording.ntsc_overrides = {"vhs_edge_wave": 1.0, "luma_smear": 0.4}
recording.receiver_enabled = true
recording.receiver_overrides = {"tracking": 0.08}
recording.crt_model = 6 # Royale, fixed across quality levels.
recording.crt_parameters = {"royale": {"lcd_gamma": 2.8}}
```

CRT model IDs: 0 Automatic, 1 Aperture, 2 EasyMode, 3 Glow Gaussian, 4 Glow Lanczos, 5 Hyllian, 6 Royale, 7 Crtsim. Automatic switches between Aperture and Royale; explicit choices remain fixed. Default Aperture/Royale calibration preserves dark-room detail; override their parameters for the upstream defaults or your own look.

Other profile options cover film grain, field-history weave, source-resolution processing, custom signal width, six original resize filters, original supersampling and integer fit. The original NTSC/receiver widget can be instantiated with `addons/ntscrt/controls.gd`. It is optional; your game does not need to expose these technical settings to players.

Use `is_supported()`, `get_error()` and the `renderer_error(message)` signal to report rendering failures. Connect the signal before adding the effect to the tree to catch an unsupported renderer immediately.

## Validation and maintenance

See [tests/README.md](tests/README.md) for focused checks, including native shader compilation, the diagonal-noise regression, standalone routing, and exported-pack assets. The [validation record](docs/VALIDATION.md) lists the tested configuration and results. See [docs/PORTING.md](docs/PORTING.md) for the source revisions and extraction boundaries.

Only the addon directory is needed at runtime. `demo/`, `tests/` and `tools/` are examples, verification and optional upstream-regeneration tools.
