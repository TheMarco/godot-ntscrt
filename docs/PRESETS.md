# Authoring and capturing presets

The standalone demo uses a resizable studio layout. Drag the divider to give the
preview or controls more space; **Expand preview** hides the controls until you
choose **Show controls**. Playback and A/B remain beside the picture. Menus stay
crisp, and captures include only the preview. On larger windows and fullscreen
displays, text, buttons, spacing and dialogs scale together automatically. Small
windows keep their responsive 1× layout instead of shrinking the text.

1. Browse the 20 complete looks on **Looks**, or use the arrows and dropdown at
   the top of the controls. The current look's description stays below the video.
2. Use **Adjust** for tape damage, grain, camera color and occasional defects.
   Switching **Recording effects** off bypasses tape processing without resetting
   its settings. **Test glitch**, beside playback, previews the look's defect.
3. Use **CRT** to enable the screen effect, choose a model and tune its original
   parameters. Search by label or parameter name; every model keeps its own values.
4. **Signal** exposes the detailed NTSC and receiver controls. **Output** holds
   graphics budget, reduced flashing, resolution and other processing options.
   Each page has one full-height scrolling area.
5. **Keep as A** stores a reference. Continue editing B, then use **Show A** /
   **Back to B** to compare. A is read-only while shown. Capturing A saves A.
6. **Save preset…** opens the naming dialog. **Capture preset** saves the files;
   **Open captures** opens their folder, and **Copy JSON** copies the visible look.
   Use **Load…** in the main toolbar to restore a captured JSON file.

The embeddable workshop keeps its compact overlay layout and **Fine-tune this
look** switch. Both layouts use the same profile editing and capture code.

Every capture creates a new folder under the application's `user://presets/`:

- `preset.json`: versioned, readable, portable settings and capture context.
- `preset.tres`: the complete video profile for use directly in that Godot
  project. Its script path belongs to the project that captured it.
- `preview.png`: the displayed picture, including its recorded HUD, without
  workshop controls. This is a still image, not a recording of animated noise.

The snapshot contains every exported profile setting, all NTSC and receiver
values, and parameter values for **all seven CRT models**, including inactive
ones. It also records tape strength, independent film grain, quality, resolution,
resizing, previous-field history, receiver/tape wear coupling and reduced
flashing. Base signal values are saved before quality, wear and comfort gates;
those gates are applied once when loaded. Active transient glitch cues are
cleared before capture.

Liminal's **Pause → Visual Effects → Preview & fine-tune looks** uses the same JSON format
with the actual game scene. Its captures additionally record game rendering,
HDR and camera settings. Loading that JSON in Liminal restores the game-specific
render settings as well. The standalone workshop preserves this extra context
when editing and re-exporting a game preset. It cannot reproduce the game's
lighting or world from the test chart. Use **JSON** to move presets between the
two projects; `.tres` is for direct integration within its originating project.

Source image, dimensions, renderer, motion and ambient lighting affect the final
picture. Captures save the complete configurable look, not the running game's
world state or an exact animation phase. PNG previews are ordinary SDR images.

## Code integration

```gdscript
const PRESETS = preload("res://addons/ntscrt/preset_io.gd")

var result := PRESETS.load_json("user://presets/my-look/preset.json")
if result.error.is_empty():
    video.profile = result.profile
else:
    push_warning(result.error)
```

`PRESETS.encode(profile, name)` returns a complete dictionary;
`PRESETS.decode(document)` validates one. JSON loading accepts data only and
never loads a script from the preset. Host metadata lives in optional `capture`.

`addons/ntscrt/workshop.gd` provides the optional editor. Assign a profile before
adding it to the tree. Supply `apply_profile(profile)`, async
`capture_image() -> Image`, and optional `capture_context() -> Dictionary`,
`restore_context(context)`, `renderer_error() -> String`,
`play_glitch(identifier, duration)` and `select_test_image(use_tv_card)` callbacks.
The host owns the scene, pause behavior and UI routing. Set `allow_close` and
connect `closed` for an in-game dialog. The demo is a complete host example.

## Start with a built-in look

The workshop opens with a simple [20-look browser](LOOKS.md). Use the dropdown or arrows;
**Fine-tune this look** is initially off. Descriptions identify camera captures
versus TV playback. Try 09 Found footage · original tape, 02 MiniDV · daylight,
12 Security camera · monochrome, and 15 VHS on the living-room TV first.
The final seven entries demonstrate all seven CRT models.

Browsing keeps the current graphics budget, reduced-flashing preference, and
world-resolution policy. Captures still contain the full actual settings,
including camera saturation, white balance and shadow lift. Imported files
restore their complete snapshot. A clean reference resets the camera response.
Color adjustments share the existing grain pass rather than adding a render pass.

These are source-inspired looks, not exact device or codec emulations. MiniDV is
an AV-cable capture rendition without DV macroblocks or frame-rate conversion;
IR-style CCTV uses a monochrome response without adding infrared lighting.
No built-in look enables the receiver, source-size tape processing or supersampling.

For code-driven selection, use the original authored library inside the addon:

```gdscript
const LOOKS = preload("res://addons/ntscrt/preset_library.gd")
var look = LOOKS.make_profile(8) # Zero-based: Found footage · original tape.
look.quality = NtscrtProfile.Quality.MEDIUM
video.profile = look
```

`tests/audit_preset_library.gd` validates all recipes, complete save/load, browser,
A/B and budget/comfort preservation. Native `tests/smoke.gd` renders all 20 looks
at Low budget, then verifies normal CRT/signal controls and captures. The actual
low-end hardware performance has not been measured.

### Complete looks and motion

The revised looks separate clean camera capture, visible low-light sensor noise,
color CCTV, monochrome surveillance, fresh VHS, worn dubs and poor TV reception.
They include three saved fields: `ambient_fault_rate` (events per minute),
`ambient_fault_strength`, and `ambient_fault_kind` (tracking/color unlock/dropout/
RF static/sync slip). Old presets default to no recurring defects.

Damaged looks preview a first short defect after about 1.6 seconds, then use
irregular quiet gaps. The simple browser offers **Preview this look’s tape
damage** for these looks. Reduced flashing suppresses them, and explicit cues
from `trigger_fault`/`trigger_glitch` take priority. CRT-only and clean looks do
not gain tape defects. This reuses the existing GPU input pass.

The optional Look tab uses a recording-effects bypass instead of a second tape-preset
picker. Switching it off and on preserves the complete look’s signal settings.


### Compare looks on moving footage

The demo opens on **Hallway walkthrough** with **09 Found footage · original
tape**. The five preview sources stay independent of the 20-look selector:

- Hallway walkthrough: compare clean MiniDV (02), noisy low-light DV (03), VHS-C (06), found tape (09) and archive copy (10).
- Night security camera: compare color CCTV (11), monochrome (12), IR-style gain (13) and the Security-desk CRT (20).
- TV test card: compare masks, scanlines, curvature and sharpness across the CRT looks.
- Motion & color chart: inspect trails, color bleed and shadow steps.
- Abandoned mall walkthrough: a supplied 30-second clip with sound, at 1280×720 and 60 fps. Compare DV (02–03), VHS-C (06), found tape (09) and archive copy (10) on detailed moving scenery.

**Pause footage** freezes the source frame while video noise and phosphor effects
continue, so A/B comparisons use the same picture. **Replay** restarts the source;
it retains paused state. **Open .ogv…** accepts a local Ogg Theora clip. Choosing
a different look does not switch or restart the footage. The sample-source choice
and pause state are included in captures; local file paths and video files are
not embedded in preset JSON. Loading a preset does not seek to an exact video frame.

The hallway and security clips are original synthetic scenes without baked-in
filters; the mall clip is supplied footage. See `demo/assets/README.md` for
provenance, conversion details and reproducible render commands.
The sample room, video files and browser stay in `demo/`, outside the runtime addon.

To filter video in your own Godot app, add a `VideoStreamPlayer` to the effect's
source viewport just as you would add game content:

```gdscript
var video := NtscrtEffect.new()
video.profile = preload("res://addons/ntscrt/preset_library.gd").make_profile(8)
add_child(video)
var footage := VideoStreamPlayer.new()
footage.stream = load("res://demo/assets/hallway.ogv")
footage.expand = true
video.add_content(footage)
footage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
footage.finished.connect(footage.play)
footage.play()
```

The minimal example fills the viewport; `demo/demo.gd` additionally letterboxes
the video to preserve its aspect ratio. Put application menus in a sibling
CanvasLayer so they stay crisp.
