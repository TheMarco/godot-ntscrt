extends SceneTree
const EFFECT = preload("res://addons/ntscrt/effect.gd")
const PROFILE = preload("res://addons/ntscrt/profile.gd")
const PRESETS = preload("res://addons/ntscrt/preset_io.gd")
var failures: Array[String] = []
var effect: NtscrtEffect
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok: failures.append(label); printerr(label)
func frames(count := 8) -> void:
	for frame in count: await process_frame
	RenderingServer.force_draw()
func _run() -> void:
	if RenderingServer.get_rendering_device()==null:
		printerr("Native Forward+ or Mobile renderer required")
		quit(1)
		return
	root.size = Vector2i(1280,720)
	var demo: Node = load("res://demo/demo.tscn").instantiate()
	root.add_child(demo)
	effect = demo.effect
	var profile: NtscrtProfile = effect.profile
	check(effect.get_source_viewport().has_node("RecordedScene"),"Public source viewport missing demo content")
	await frames(15)
	var capture_dir := "user://test-captures"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	check(root.get_texture().get_image().save_png(capture_dir.path_join("demo.png"))==OK,"Demo capture failed")
	check(effect.presenter.ready_frames>0 and effect.get_error().is_empty(),"First native frame failed: "+effect.get_error())
	await _footage(demo,capture_dir)
	await _library(demo.workshop,capture_dir)
	await _workshop(demo.workshop,capture_dir)
	profile = demo.profile
	profile.crt_model = 0
	profile.quality = PROFILE.Quality.HIGH
	profile.select_tape(PROFILE.Tape.WORN_TAPE)
	await frames(12)
	check(effect.presenter.preset_name=="royale" and effect.presenter.signal_enabled,"Worn tape plus Royale failed")
	profile.tape = PROFILE.Tape.OFF
	await frames()
	check(effect.presenter.visible and not effect.presenter.signal_enabled and effect.presenter.preset_name=="royale","CRT-only route failed")
	profile.crt_enabled = false
	profile.film_grain = 0.0
	await frames()
	check(not effect.presenter.visible and not effect._grain.visible,"Clean bypass left a filter active")
	profile.select_tape(PROFILE.Tape.FOUND_FOOTAGE)
	await frames()
	check(effect.presenter.visible and effect.presenter.signal_enabled and effect.presenter.preset_name=="none","Tape-only route failed")
	profile.receiver_enabled = true
	await frames()
	check(effect.presenter.receiver_enabled and effect.get_error().is_empty(),"Receiver route failed")
	profile.receiver_enabled = false
	effect.trigger_fault(EFFECT.Fault.RF_STATIC,0.3)
	await frames(2)
	check(float(effect.presenter.game_state.get("fault_amount",0.0))>0.0,"Procedural fault did not reach GPU")
	var elapsed := effect._fault_elapsed
	paused = true
	await frames(3)
	check(effect._fault_elapsed==elapsed,"Pause spent the glitch duration")
	paused = false
	effect.trigger_glitch("two_blips",0.15)
	await create_timer(0.25).timeout
	await frames()
	check(effect._fault.is_empty() and effect.presenter.signal_settings==effect._base_signal,"Glitch did not restore selected look")
	profile.reduced_flashing = true
	await frames()
	effect.trigger_glitch()
	check(effect._fault.is_empty(),"Reduced flashing allowed glitch")
	profile.auto_world_resolution = false
	effect.source.scaling_3d_scale = 0.55
	profile.tape_damage = 0.4
	await frames()
	check(is_equal_approx(effect.source.scaling_3d_scale,0.55),"Profile change overwrote caller-owned resolution")
	root.size = Vector2i(900,600)
	await frames()
	check(effect.source.size==Vector2i(effect.size),"Resize did not reach source viewport")
	check(effect.get_error().is_empty(),effect.get_error())
	demo.queue_free()
	await frames(5)
	print("SMOKE_AUDIT ","PASS" if failures.is_empty() else "FAIL", " — standalone demo, tape/CRT, receiver, cues, pause, resize and cleanup")
	quit(0 if failures.is_empty() else 1)

func _workshop(demo: Node,capture_dir: String) -> void:
	var profile: NtscrtProfile = demo.profile
	demo._fine_tune.button_pressed = true
	# Every model exposes every actual knob; sentinel heading parameters are skipped.
	for model in range(1,8):
		profile.crt_model = model
		var expected := 0
		for descriptor: Dictionary in PROFILE.crt_descriptors(profile.selected_crt_model()).values():
			if descriptor.min!=descriptor.max: expected += 1
		check(demo._crt_controls.size()==expected,"Missing CRT controls: "+profile.selected_crt_model())
	profile.crt_model = 1
	profile.quality = PROFILE.Quality.MEDIUM
	var glow: SpinBox = demo._crt_controls["GLOW_HALATION"]
	glow.value = 0.32
	check(is_equal_approx(profile.active_crt_parameters().GLOW_HALATION,0.32),"CRT UI does not edit profile")
	demo._tabs.current_tab = 1
	await frames(12)
	check(is_equal_approx(effect.presenter.parameters.GLOW_HALATION,0.32),"CRT knob did not reach presenter")
	check(root.get_texture().get_image().save_png(capture_dir.path_join("crt-controls.png"))==OK,"CRT controls capture failed")
	demo._tabs.current_tab = 2
	demo._signal_controls.controls["ntscrs/luma_smear"].value = 0.71
	check(is_equal_approx(profile.signal_settings().luma_smear,0.71),"Signal UI does not edit profile")
	await frames(3)
	check(root.get_texture().get_image().save_png(capture_dir.path_join("signal-controls.png"))==OK,"Signal controls capture failed")
	demo._name.text = "Reference capture"
	demo.store_reference()
	profile.crt_parameters = {}
	profile.crt_model = 6
	profile.tape_damage = 0.19
	demo.show_reference(true)
	await frames(12)
	check(effect.profile!=profile and effect.presenter.preset_name=="aperture","A/B did not show reference A")
	check(profile.crt_model==6 and is_equal_approx(profile.tape_damage,0.19),"A/B overwrote editing B")
	var captured: Dictionary = await demo.capture_preset(capture_dir.path_join("saved-reference"))
	check(captured.error.is_empty(),"Preset capture failed: "+str(captured.error))
	check(captured.image_size.x<int(root.get_texture().get_width()),"Capture included menu")
	var restored := PRESETS.load_json(captured.directory.path_join("preset.json"))
	check(restored.error.is_empty(),"Saved preset did not load")
	if restored.error.is_empty():
		check(restored.profile.crt_model==1,"Capture saved B while A was visible")
		check(is_equal_approx(restored.profile.active_crt_parameters().GLOW_HALATION,0.32),"Capture lost CRT tuning")
		check(is_equal_approx(restored.profile.signal_settings().luma_smear,0.71),"Capture lost signal tuning")
	var resource: Resource = ResourceLoader.load(captured.directory.path_join("preset.tres"),"",ResourceLoader.CACHE_MODE_IGNORE)
	check(resource!=null and resource.crt_model==1,"Godot preset resource did not load")
	var png := Image.load_from_file(captured.directory.path_join("preview.png"))
	check(png!=null and png.get_size()==captured.image_size,"Preview PNG missing or wrong size")
	demo.show_reference(false)
	await frames(8)
	check(effect.profile==profile and effect.presenter.preset_name=="royale","A/B did not restore B")
	demo.load_preset(captured.directory.path_join("preset.json"))
	await frames(8)
	check(demo.profile.crt_model==1 and demo._controls.crt_model.selected==1,"Load did not refresh model UI")
	check(is_equal_approx(demo._crt_controls["GLOW_HALATION"].value,0.32),"Load did not refresh CRT knobs")
	# Removing a custom knob must send defaults rather than leave stale GPU values.
	demo.profile.crt_parameters = {}
	await frames(3)
	check(is_equal_approx(effect.presenter.parameters.GLOW_HALATION,0.1),"Reset retained old CRT value")
	demo._tabs.current_tab = 0
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--import-preset="): continue
		demo.load_preset(argument.trim_prefix("--import-preset="))
		await frames(8)
		check(demo._capture_context().get("game")=="liminal","Game rendering context lost on import")
		var shared: Dictionary = await demo.capture_preset(capture_dir.path_join("cross-project"))
		var document := PRESETS.load_json(shared.directory.path_join("preset.json"))
		check(document.error.is_empty() and document.capture.has("game_settings"),"Re-export lost game settings")

func _library(panel: Control,capture_dir: String) -> void:
	check(not panel._tabs.visible,"Preset browser starts with advanced controls")
	panel.profile.quality = PROFILE.Quality.LOW
	panel.profile.reduced_flashing = false
	for index in panel.LIBRARY.LOOKS.size():
		panel.select_curated(index)
		await frames(8)
		check(panel.profile.quality==0 and not panel.profile.reduced_flashing,"Library changed quality or comfort")
		check(effect.get_error().is_empty(),"Library GPU failure: "+panel.LIBRARY.LOOKS[index].name)
		check(effect.presenter.preset_name==panel.profile.active_crt(),"Wrong library CRT")
		check(is_equal_approx(effect._grain.material.get_shader_parameter("color_saturation"),panel.profile.color_saturation),"Camera response did not reach shader")
	panel.profile.reduced_flashing = true
	panel.select_curated(8)
	await frames(3)
	check(effect.presenter._ambient_rate==0.0 and panel._damage_preview.disabled,"Comfort did not suppress preset defects")
	panel.profile.quality = PROFILE.Quality.HIGH
	panel.profile.reduced_flashing = false
	panel.select_curated(8)
	await frames(8)
	root.get_texture().get_image().save_png(capture_dir.path_join("preset-browser.png"))
	var capture: Dictionary = await panel.capture_preset(capture_dir.path_join("curated-look"))
	var restored := PRESETS.load_json(capture.directory.path_join("preset.json"))
	check(restored.error.is_empty() and is_equal_approx(restored.profile.color_saturation,0.72),"Curated color response lost in capture")
	panel.select_curated(0)
	await frames()
	check(not effect._grain.visible and not effect.presenter.visible,"Clean left prior effects active")
	panel.profile.crt_enabled = true

func _footage(demo: Node,capture_dir: String) -> void:
	check(demo._source_index==0 and demo._video.visible,"Demo must open on moving footage")
	var position: float = demo._video.stream_position
	await frames(8)
	check(demo._video.stream_position>position,"Footage does not advance")
	demo._set_paused(true)
	await frames(2)
	var still: PackedByteArray = demo._video.get_video_texture().get_image().get_data()
	demo.workshop.store_reference()
	demo.workshop.select_curated(11)
	demo.workshop.show_reference(true)
	await frames(8)
	check(demo._video.get_video_texture().get_image().get_data()==still,"Paused A/B restarted or changed the video frame")
	demo.workshop.show_reference(false)
	demo._set_paused(false)
	for source_index in [1,2,3,4,0]:
		demo._select_source(source_index)
		await frames(12)
		check(demo._card.visible==(source_index in [2,3]),"Source selector did not switch video/chart")
		var image: Image = await demo._capture_image()
		image.save_png(capture_dir.path_join("source-%d.png" % source_index))
		check(image.get_width()>0,"Source capture missing")
	demo._restore_context({"preview_source":"abandoned_mall","footage_paused":false})
	await frames(12)
	check(demo._video.visible and demo._video.is_playing(),"Mall footage did not play after restoring capture context")
	check(demo._capture_context().preview_source=="abandoned_mall","Mall source was lost in capture context")
	check(demo._video.get_video_texture().get_size()==Vector2(1280,720),"Mall footage lost its original resolution")
	check(is_equal_approx(demo._video.size.x/demo._video.size.y,16.0/9.0),"Mall footage was stretched")
	demo._open_video(ProjectSettings.globalize_path("res://demo/assets/security.ogv"))
	await frames(12)
	check(demo._source_index==demo.SOURCE_IDS.size() and demo._video.is_playing(),"External OGV did not play")
	check(not JSON.stringify(demo._capture_context()).contains("/"),"Capture exposed an external file path")
	demo._select_source(0)
	var loops: Array[bool] = []
	demo._video.finished.connect(func(): loops.append(true),CONNECT_ONE_SHOT)
	await create_timer(8.5).timeout
	check(not loops.is_empty() and demo._video.is_playing(),"Bundled footage did not loop")
	demo._set_paused(true)
	demo._replay()
	await frames(2)
	check(demo._video.paused and demo._video.stream_position<0.1,"Replay did not preserve paused state")
	demo._set_paused(false)
