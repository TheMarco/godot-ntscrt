extends SceneTree
const PROFILE = preload("res://addons/ntscrt/profile.gd")
const EFFECT = preload("res://addons/ntscrt/effect.gd")
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
	for message in failures: printerr(message)
	print("PROFILE_AUDIT ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
