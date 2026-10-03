class_name NtscrtProfile
extends Resource
## Portable settings. Sharing one resource intentionally updates all its effects.
const SETTINGS = preload("res://addons/ntscrt/internal/ntscrt_full_settings.gd")
enum Tape { OFF, HOME_VIDEO, FOUND_FOOTAGE, WORN_TAPE }
enum Quality { LOW, MEDIUM, HIGH, ULTRA }
const CRT_NAMES := ["automatic", "aperture", "easymode", "glow_gauss", "glow_lanczos", "hyllian", "royale", "sim"]
const SIGNAL_SIZES := [Vector2i(360,240), Vector2i(540,360), Vector2i(720,480), Vector2i(720,480)]
const OUTPUT_HEIGHTS := [720,1080,1440,0]
const CRT_CALIBRATION := {
	"aperture": {"SCANLINE_SIZE_MIN":1.0,"MASK_STRENGTH":0.2,"GAMMA_OUTPUT":2.6},
	"royale": {"lcd_gamma":2.8,"beam_min_sigma":0.12},
}

@export var tape: Tape = Tape.FOUND_FOOTAGE:
	set(value):
		tape = clampi(value,0,3) as Tape
		emit_changed()
@export_range(0.0,1.0,0.01) var tape_damage := 0.35:
	set(value):
		tape_damage = clampf(value,0.0,1.0) if is_finite(value) else 0.35
		emit_changed()
@export_range(0.0,1.0,0.01) var film_grain := 0.12:
	set(value):
		film_grain = clampf(value,0.0,1.0) if is_finite(value) else 0.12
		emit_changed()
@export var crt_enabled := false:
	set(value):
		crt_enabled = value
		emit_changed()
@export var quality: Quality = Quality.MEDIUM:
	set(value):
		quality = clampi(value,0,3) as Quality
		emit_changed()
@export var reduced_flashing := false:
	set(value):
		reduced_flashing = value
		emit_changed()
@export_enum("Automatic","Aperture","EasyMode","Glow Gaussian","Glow Lanczos","Hyllian","Royale","Crtsim") var crt_model := 0:
	set(value):
		crt_model = clampi(value,0,7)
		emit_changed()
@export var receiver_enabled := false:
	set(value):
		receiver_enabled = value
		emit_changed()
@export var field_history := false:
	set(value):
		field_history = value
		emit_changed()
@export var source_resolution := false:
	set(value):
		source_resolution = value
		emit_changed()
@export_enum("Fast bilinear","Nearest","Nearest+","Bilinear","Bicubic","Lanczos3","Area") var downscale_filter := 0:
	set(value):
		downscale_filter = clampi(value,0,6)
		emit_changed()
@export_enum("Automatic","Custom width","Source size") var signal_size_mode := 0:
	set(value):
		signal_size_mode = clampi(value,0,2)
		emit_changed()
@export_range(16,4096,2) var signal_width := 720:
	set(value):
		signal_width = clampi(value,16,4096)
		emit_changed()
@export_enum("Quality budget","Original supersampling","Original integer fit") var presentation_scale := 0:
	set(value):
		presentation_scale = clampi(value,0,2)
		emit_changed()
@export var auto_world_resolution := true:
	set(value):
		auto_world_resolution = value
		emit_changed()
## Canonical overrides. Assign a new dictionary or call emit_changed() after editing in place.
@export var ntsc_overrides: Dictionary = {}:
	set(value):
		ntsc_overrides = value.duplicate(true)
		emit_changed()
@export var receiver_overrides: Dictionary = {}:
	set(value):
		receiver_overrides = value.duplicate(true)
		emit_changed()
## A dictionary per CRT model, e.g. {"royale": {"lcd_gamma": 2.8}}.
@export var crt_parameters: Dictionary = {}:
	set(value):
		crt_parameters = value.duplicate(true)
		emit_changed()

func select_tape(look: Tape) -> void:
	tape = look
	tape_damage = [0.0,0.5,0.35,0.65][tape]
	film_grain = [0.0,0.4,0.12,0.2][tape]
	ntsc_overrides = {}
	# The independent CRT and receiver choices are preserved.

func active_crt() -> String:
	if not crt_enabled: return "none"
	return ("royale" if quality>=Quality.HIGH else "aperture") if crt_model==0 else CRT_NAMES[crt_model]

func canonical_ntsc_settings() -> Dictionary:
	var knobs := SETTINGS.ntsc_defaults()
	if tape==Tape.WORN_TAPE:
		knobs.merge({"vhs_edge_wave":1.1,"tracking_noise_height":24,
			"tracking_noise_wave_intensity":20.0,"tracking_noise_noise_intensity":0.35,
			"chroma_noise_intensity":0.14,"vhs_chroma_loss":0.00008,"snow_intensity":0.0008},true)
	knobs.merge(ntsc_overrides,true)
	return SETTINGS.sanitize_ntsc(knobs)

func signal_settings() -> Dictionary:
	var knobs := canonical_ntsc_settings()
	if signal_size_mode==0 and not source_resolution and quality<Quality.HIGH:
		knobs["scale_with_video_size"] = true
	for key in ["composite_noise_intensity","luma_noise_intensity","chroma_noise_intensity","snow_intensity","chroma_phase_noise_intensity","vhs_edge_wave","vhs_chroma_loss","head_switching_horizontal_shift","tracking_noise_wave_intensity","tracking_noise_snow_intensity","tracking_noise_noise_intensity"]:
		knobs[key] = float(knobs[key])*tape_damage*2.0
	knobs["field_history"] = field_history and not reduced_flashing
	if reduced_flashing:
		knobs["use_field"] = 3
		for key in ["head_switching","tracking_noise","vhs_edge_wave_enabled","composite_noise","luma_noise","chroma_noise"]: knobs[key] = false
		for key in ["snow_intensity","vhs_chroma_loss","chroma_phase_noise_intensity"]: knobs[key] = 0.0
	return knobs

func receiver_settings() -> Dictionary:
	var knobs := SETTINGS.sanitize_receiver(receiver_overrides)
	if reduced_flashing:
		for key in ["head_switch","timebase_jitter","crinkle","head_clog","tracking","dropouts","horizontal_hold","vertical_hold","hum"]: knobs[key] = 0.0
		knobs["signal_strength"] = 1.0
	return knobs

func active_crt_parameters() -> Dictionary:
	var model := active_crt()
	var result: Dictionary = CRT_CALIBRATION.get(model,{}).duplicate(true)
	if crt_parameters.get(model,{}) is Dictionary:
		result.merge(crt_parameters.get(model,{}),true)
	return result
