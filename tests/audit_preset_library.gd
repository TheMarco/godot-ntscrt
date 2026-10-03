extends SceneTree
const PRESENTER = preload("res://addons/ntscrt/internal/ntscrt_gpu_presenter.gd")
const LIBRARY = preload("res://addons/ntscrt/preset_library.gd")
const PANEL = preload("res://addons/ntscrt/workshop.gd")
const PROFILE = preload("res://addons/ntscrt/profile.gd")
const IO = preload("res://addons/ntscrt/preset_io.gd")
var failures: Array[String] = []
func check(value: bool,label: String) -> void:
	if not value: failures.append(label); printerr(label)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	_check_ambient_faults()
	check(LIBRARY.LOOKS.size()==20,"Expected 20 looks")
	var names := {}
	var signatures := {}
	var models := {}
	for index in LIBRARY.LOOKS.size():
		var entry: Dictionary = LIBRARY.LOOKS[index]
		var profile := LIBRARY.make_profile(index)
		check(not names.has(entry.id),"Duplicate look ID")
		names[entry.id] = true
		check(LIBRARY.matching_index(profile)==index,"Cannot recognize saved library look")
		var document := IO.encode(profile,entry.name)
		var restored := IO.decode(JSON.parse_string(JSON.stringify(document)))
		check(restored.error.is_empty(),"Cannot decode "+entry.name)
		check(IO.encode(restored.profile,entry.name)==document,"Roundtrip lost values: "+entry.name)
		check(document.settings.ntsc_overrides.size()==62 and document.settings.receiver_overrides.size()==17 and document.settings.crt_parameters.size()==7,"Incomplete snapshot")
		check(not profile.receiver_enabled and not profile.source_resolution and profile.presentation_scale==0 and profile.signal_size_mode==0,"Unexpected costly path: "+entry.name)
		for key: String in entry.get("signal",{}):
			check(profile.canonical_ntsc_settings().has(key) and profile.canonical_ntsc_settings().get(key)==entry.signal[key],"Invalid signal control: "+entry.name+" / "+key)
		for key: String in entry.get("knobs",{}):
			check(profile.active_crt_parameters().has(key) and is_equal_approx(profile.active_crt_parameters().get(key,INF),entry.knobs[key]),"Invalid CRT control: "+entry.name+" / "+key)
		if profile.crt_enabled: models[profile.active_crt()] = true
		var signature := JSON.stringify({"tape":profile.tape,"signal":profile.signal_settings() if profile.tape!=0 else {},
			"crt":profile.active_crt(),"knobs":profile.active_crt_parameters() if profile.crt_enabled else {},
			"defects":[profile.ambient_fault_rate,profile.ambient_fault_strength,profile.ambient_fault_kind],"grain":profile.film_grain,"saturation":profile.color_saturation,"temperature":profile.color_temperature,"lift":profile.color_shadow_lift})
		check(not signatures.has(signature),"Duplicate effective look: "+entry.name)
		signatures[signature] = true
	check(models.size()==7,"Library does not cover all seven CRT models")
	var panel := PANEL.new()
	root.add_child(panel)
	check(not panel._tabs.visible and not panel._fine_tune.button_pressed,"Detailed controls exposed by default")
	panel.profile.quality = 0
	panel.profile.reduced_flashing = true
	panel.profile.auto_world_resolution = false
	for index in LIBRARY.LOOKS.size():
		panel.select_curated(index)
		check(panel.profile.quality==0 and panel.profile.reduced_flashing and not panel.profile.auto_world_resolution,"Browsing changed budget or comfort")
		check(panel._name.text==LIBRARY.LOOKS[index].name and panel._library_select.selected==index+1,"Browser not synchronized")
		check(not panel._tabs.visible,"Browsing expanded controls")
	panel.select_curated(8)
	var recording_snapshot: Dictionary = IO.encode(panel.profile).settings
	panel._recording_toggle.button_pressed = false
	check(panel.profile.tape==0,"Recording bypass did not turn off the signal")
	panel._recording_toggle.button_pressed = true
	check(IO.encode(panel.profile).settings==recording_snapshot,"Recording bypass reset the selected look")
	panel.store_reference()
	panel.select_curated(11)
	panel.show_reference(true)
	check(panel._library_select.disabled and panel._visible_profile().color_saturation>0.0,"Reference lost or browser still active")
	panel.show_reference(false)
	check(panel.profile.color_saturation==0.0 and not panel._tabs.visible,"Returning to B lost look or expanded controls")
	panel._fine_tune.button_pressed = true
	check(panel._tabs.visible,"Cannot open fine tuning")
	panel.profile.color_saturation = 0.1
	check("modified" in panel._look_route.text,"Custom adjustment not identified")
	panel.select_curated(19)
	panel._cycle_look(1)
	check(panel._library_index==0,"Next did not wrap")
	panel._cycle_look(-1)
	check(panel._library_index==19,"Previous did not wrap")
	panel.free()
	print("CURATED_LIBRARY_AUDIT ","PASS" if failures.is_empty() else "FAIL", " — 20 unique looks, complete roundtrips, seven CRTs, budget/comfort, browser, A/B and scheduled defects")
	quit(0 if failures.is_empty() else 1)

func _check_ambient_faults() -> void:
	var presenter := PRESENTER.new()
	presenter.signal_enabled = true
	presenter.configure_ambient_faults(6.0,0.6,2,false)
	presenter.preview_ambient_fault()
	presenter._ambient_elapsed = presenter._ambient_started+presenter._ambient_duration*0.4
	var defect := presenter.effective_game_state()
	check(is_equal_approx(float(defect.get("fault_amount",0.0)),0.6) and defect.fault_kind==2.0,"Authored defect not present at peak")
	check(presenter.game_state.is_empty(),"Ambient cue changed saved/external state")
	presenter.game_state = {"fault_amount":0.8,"fault_kind":4.0,"entity_amount":0.3}
	check(presenter.effective_game_state()==presenter.game_state,"Ambient defect overrode an enemy cue")
	presenter.game_state = {}
	presenter._ambient_elapsed = presenter._ambient_started+presenter._ambient_duration+0.01
	check(presenter.effective_game_state().is_empty(),"Defect did not restore picture")
	presenter.configure_ambient_faults(6.0,0.6,2,true)
	presenter.preview_ambient_fault()
	check(presenter.effective_game_state().is_empty() and presenter._ambient_rate==0.0,"Comfort mode allowed a preset glitch")
	presenter.configure_ambient_faults(0.0,0.6,2,false)
	presenter.preview_ambient_fault()
	check(presenter.effective_game_state().is_empty(),"Clean recording produced a glitch")
	presenter.configure_ambient_faults(6.0,0.6,2,false)
	presenter.signal_enabled = false
	presenter.preview_ambient_fault()
	check(presenter.effective_game_state().is_empty(),"CRT-only picture allowed a tape glitch")
	presenter.free()
