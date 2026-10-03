extends RefCounted
## Versioned data-only presets. Loading JSON never loads scripts or resources.
const PROFILE = preload("res://addons/ntscrt/profile.gd")
const FORMAT := "godot-ntscrt-preset"
const VERSION := 1
const FIELDS := ["tape", "tape_damage", "film_grain", "crt_enabled", "quality",
	"reduced_flashing", "crt_model", "receiver_enabled", "receiver_tape_coupling", "field_history",
	"source_resolution", "downscale_filter", "signal_size_mode", "signal_width",
	"presentation_scale", "auto_world_resolution", "color_saturation", "color_temperature", "color_shadow_lift", "ambient_fault_rate", "ambient_fault_strength", "ambient_fault_kind"]

static func encode(profile: NtscrtProfile, title := "Untitled preset", context: Dictionary = {}) -> Dictionary:
	var settings := {}
	for key: String in FIELDS: settings[key] = profile.get(key)
	# Capture base values BEFORE wear, quality and comfort processing. They are
	# applied once on playback, and disabled stages retain their authored values.
	settings.ntsc_overrides = profile.canonical_ntsc_settings()
	settings.receiver_overrides = PROFILE.SETTINGS.sanitize_receiver(profile.receiver_overrides)
	settings.crt_parameters = {}
	for model: String in PROFILE.CRT_NAMES.slice(1):
		settings.crt_parameters[model] = profile.canonical_crt_parameters(model)
	var result := {"format":FORMAT,"version":VERSION,"name":title,"settings":settings}
	if not context.is_empty(): result["capture"] = context.duplicate(true)
	return result

static func decode(document: Variant) -> Dictionary:
	if not document is Dictionary or document.get("format")!=FORMAT:
		return {"error":"This is not a Godot NTSCRT preset."}
	var version: Variant = document.get("version")
	if not (version is int or version is float) or version!=VERSION:
		return {"error":"Unsupported preset version."}
	if not document.get("settings") is Dictionary:
		return {"error":"The preset has no settings object."}
	var profile := PROFILE.new()
	var settings: Dictionary = document.settings
	for key: String in FIELDS:
		if not settings.has(key): continue
		var value: Variant = settings[key]
		var original: Variant = profile.get(key)
		if original is bool:
			if not value is bool: return {"error":"Expected true/false for "+key}
		elif not (value is int or value is float) or not is_finite(float(value)):
			return {"error":"Expected a finite number for "+key}
		elif original is int:
			if float(value)!=floor(float(value)): return {"error":"Expected an integer for "+key}
			value = int(value)
		profile.set(key,value)
	for key: String in ["ntsc_overrides","receiver_overrides","crt_parameters"]:
		if settings.has(key) and not settings[key] is Dictionary:
			return {"error":"Expected a settings object for "+key}
	# Missing overrides preserve the selected look; present objects are sanitized.
	if settings.has("ntsc_overrides"):
		profile.ntsc_overrides = PROFILE.SETTINGS.sanitize_ntsc(settings.ntsc_overrides)
	if settings.has("receiver_overrides"):
		profile.receiver_overrides = PROFILE.SETTINGS.sanitize_receiver(settings.receiver_overrides)
	profile.crt_parameters = settings.get("crt_parameters",{})
	var crt := {}
	for model: String in PROFILE.CRT_NAMES.slice(1):
		crt[model] = profile.canonical_crt_parameters(model)
	profile.crt_parameters = crt
	return {"error":"","profile":profile,"name":str(document.get("name","Untitled preset")),
		"capture":document.get("capture",{}) if document.get("capture",{}) is Dictionary else {}}

static func load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null: return {"error":"Cannot open preset: "+error_string(FileAccess.get_open_error())}
	if file.get_length()>2*1024*1024: return {"error":"Preset file is too large."}
	var parser := JSON.new()
	if parser.parse(file.get_as_text())!=OK:
		return {"error":"Invalid JSON at line %d: %s" % [parser.get_error_line(),parser.get_error_message()]}
	return decode(parser.data)

static func save_json(path: String, profile: NtscrtProfile, title: String, context: Dictionary = {}) -> Error:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(encode(profile,title,context),"\t")+"\n")
	file.flush()
	return file.get_error()
