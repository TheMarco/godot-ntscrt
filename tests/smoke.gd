extends SceneTree
const EFFECT = preload("res://addons/ntscrt/effect.gd")
const PROFILE = preload("res://addons/ntscrt/profile.gd")
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
	profile.quality = PROFILE.Quality.HIGH
	profile.select_tape(PROFILE.Tape.WORN_TAPE)
	await frames(12)
	check(effect.presenter.preset_name=="royale" and effect.presenter.signal_enabled,"Worn tape plus Royale failed")
	profile.tape = PROFILE.Tape.OFF
	await frames()
	check(effect.presenter.visible and not effect.presenter.signal_enabled and effect.presenter.preset_name=="royale","CRT-only route failed")
	profile.crt_enabled = false
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
