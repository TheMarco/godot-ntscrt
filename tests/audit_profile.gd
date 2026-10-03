extends SceneTree
const PROFILE = preload("res://addons/ntscrt/profile.gd")
const EFFECT = preload("res://addons/ntscrt/effect.gd")
const PRESETS = preload("res://addons/ntscrt/preset_io.gd")
var failures: Array[String] = []
func check(ok: bool,label: String) -> void:
	if not ok: failures.append(label)
func _initialize() -> void:
	var profile := PROFILE.new()
	for enabled in [false,true]:
		profile.crt_enabled = enabled
		for tape in 4:
			profile.select_tape(tape)
			check(profile.crt_enabled==enabled,"Tape selection changed CRT")
			var before := profile.signal_settings()
			profile.crt_enabled = not enabled
			check(profile.tape==tape and profile.signal_settings()==before,"CRT changed tape settings")
			profile.crt_enabled = enabled
	profile.select_tape(PROFILE.Tape.WORN_TAPE)
	check(is_equal_approx(profile.canonical_ntsc_settings().vhs_edge_wave,1.1),"Canonical editor values lost Worn preset")
	check(is_equal_approx(profile.signal_settings().vhs_edge_wave,1.1*profile.tape_damage*2.0),"Tape strength applied more than once")
	profile.crt_enabled = true
	for quality in 4:
		profile.quality = quality
		check(profile.active_crt()==("aperture" if quality<2 else "royale"),"Wrong automatic CRT")
		check(profile.signal_settings().scale_with_video_size==(quality<2),"Wrong small-buffer normalization")
	profile.crt_model = 1
	profile.quality = PROFILE.Quality.ULTRA
	check(profile.active_crt()=="aperture","Explicit CRT changed with quality")
	profile.ntsc_overrides = {"luma_smear":0.7,"unknown":42}
	check(is_equal_approx(profile.signal_settings().luma_smear,0.7) and not profile.signal_settings().has("unknown"),"Signal override sanitation")
	profile.reduced_flashing = true
	check(not profile.signal_settings().field_history and profile.signal_settings().use_field==3,"Comfort gate")
	check(profile.receiver_settings().tracking==0.0,"Receiver comfort gate")
	var path := "/tmp/ntscrt-profile-%d.tres" % OS.get_process_id()
	check(ResourceSaver.save(profile,path)==OK,"Profile save failed")
	var restored: Resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(restored!=null and restored.tape==profile.tape and restored.crt_enabled==profile.crt_enabled and restored.ntsc_overrides==profile.ntsc_overrides,"Profile roundtrip failed")
	DirAccess.remove_absolute(path)
	_check_complete_presets()
	for message in failures: printerr(message)
	print("PROFILE_AUDIT ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _check_complete_presets() -> void:
	var profile := PROFILE.new()
	profile.select_tape(PROFILE.Tape.WORN_TAPE)
	profile.tape_damage = 0.73
	profile.film_grain = 0.27
	profile.crt_enabled = true
	profile.crt_model = 6
	profile.quality = PROFILE.Quality.HIGH
	profile.receiver_enabled = false
	profile.receiver_tape_coupling = true
	profile.field_history = true
	profile.source_resolution = true
	profile.downscale_filter = 5
	profile.signal_size_mode = 1
	profile.signal_width = 864
	profile.presentation_scale = 2
	profile.auto_world_resolution = false
	profile.ntsc_overrides = _custom_values(PROFILE.SETTINGS.ntsc_descriptors())
	profile.receiver_overrides = _custom_values(PROFILE.SETTINGS.receiver_descriptors())
	var models := {}
	for model: String in PROFILE.CRT_NAMES.slice(1):
		var values := {}
		var descriptors := PROFILE.crt_descriptors(model)
		for key: String in descriptors:
			var d: Dictionary = descriptors[key]
			values[key] = float(d.min)+0.37*(float(d.max)-float(d.min))
		models[model] = values
	profile.crt_parameters = models
	var document := PRESETS.encode(profile,"All settings test")
	for property: Dictionary in profile.get_property_list():
		if int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE and int(property.usage)&PROPERTY_USAGE_STORAGE:
			check(document.settings.has(property.name),"Exported field missing from preset: "+property.name)
	check(document.settings.ntsc_overrides.size()==62,"Capture missed NTSC settings")
	check(document.settings.receiver_overrides.size()==17,"Capture missed disabled receiver settings")
	check(document.settings.crt_parameters.size()==7,"Capture missed inactive CRT models")
	var json_path := "/tmp/ntscrt-complete-%d.json" % OS.get_process_id()
	check(PRESETS.save_json(json_path,profile,"All settings test")==OK,"JSON write failed")
	var loaded := PRESETS.load_json(json_path)
	check(loaded.error.is_empty(),"JSON load failed")
	if loaded.error.is_empty():
		check(loaded.name=="All settings test","Preset name lost")
		var restored: NtscrtProfile = loaded.profile
		for key: String in PRESETS.FIELDS: check(profile.get(key)==restored.get(key),"Scalar roundtrip: "+key)
		_compare_values(profile.signal_settings(),restored.signal_settings(),"signal")
		_compare_values(profile.receiver_settings(),restored.receiver_settings(),"receiver")
		for model: String in PROFILE.CRT_NAMES.slice(1):
			_compare_values(profile.canonical_crt_parameters(model),restored.canonical_crt_parameters(model),model)
		# Wear and reduced-flashing gates must be applied once, not baked into saved knobs.
		profile.reduced_flashing = true
		restored = PRESETS.decode(JSON.parse_string(JSON.stringify(PRESETS.encode(profile)))).profile
		_compare_values(profile.signal_settings(),restored.signal_settings(),"comfort signal")
		restored.reduced_flashing = false
		profile.reduced_flashing = false
		_compare_values(profile.signal_settings(),restored.signal_settings(),"restored disabled values")
	DirAccess.remove_absolute(json_path)
	for bad: Variant in [null,{}, {"format":PRESETS.FORMAT,"version":99,"settings":{}},
		{"format":PRESETS.FORMAT,"version":1,"settings":{"crt_enabled":1}},
		{"format":PRESETS.FORMAT,"version":1,"settings":{"tape_damage":"bad"}},
		{"format":PRESETS.FORMAT,"version":1,"settings":{"crt_parameters":[]}}]:
		check(not PRESETS.decode(bad).error.is_empty(),"Malformed preset accepted")
	profile.crt_parameters = {"royale":{"lcd_gamma":999,"crt_gamma":NAN,"unknown":1}}
	var clean := profile.canonical_crt_parameters("royale")
	check(clean.lcd_gamma==5.0 and clean.crt_gamma==2.5 and not clean.has("unknown"),"CRT bounds and invalid values")
	profile.crt_parameters = {}
	check(profile.active_crt_parameters().lcd_gamma==2.8,"CRT reset did not restore calibration")

func _custom_values(descriptors: Array) -> Dictionary:
	var result := {}
	for d: Dictionary in PROFILE.SETTINGS._flatten(descriptors):
		if d.type in ["boolean","group"]: result[d.name] = not bool(d.default)
		elif d.type=="enum": result[d.name] = d.options.back().index
		else:
			var minimum := float(d.get("min",0.0))
			var value := minimum+0.37*(float(d.get("max",1.0))-minimum)
			result[d.name] = int(value) if d.type=="int" else value
	return result

func _compare_values(expected: Dictionary,actual: Dictionary,label: String) -> void:
	check(expected.size()==actual.size(),label+" setting count")
	for key: String in expected:
		var value: Variant = expected[key]
		if value is float or value is int:
			check(actual.has(key) and is_equal_approx(float(value),float(actual[key])),label+" mismatch: "+key)
		else: check(actual.get(key)==value,label+" mismatch: "+key)
