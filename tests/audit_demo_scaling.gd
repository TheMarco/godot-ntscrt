extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok: failures.append(label); printerr(label)
func frames(count := 10) -> void:
	for frame in count: await process_frame
	RenderingServer.force_draw()
func click_at(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	root.push_input(motion)
	await process_frame
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.global_position = position
		event.pressed = pressed
		root.push_input(event)
		await process_frame
func _run() -> void:
	root.size = Vector2i(1280,800)
	var demo: Node = load("res://demo/demo.tscn").instantiate()
	root.add_child(demo)
	var studio: Control = demo.workshop
	demo._select_source(4)
	await frames(20)
	check(is_equal_approx(root.content_scale_factor,1.0),"Windowed UI no longer uses 1x layout")
	root.mode = Window.MODE_FULLSCREEN
	await create_timer(1.0).timeout
	await frames(15)
	var factor := maxf(1.0,minf(root.size.x/1440.0,root.size.y/900.0))
	print("Fullscreen: ",root.size," / logical ",root.get_visible_rect().size," / UI scale ",root.content_scale_factor)
	check(is_equal_approx(root.content_scale_factor,factor),"Fullscreen scale does not follow window size")
	if root.size.x>=3000 and root.size.y>=1800:
		check(root.content_scale_factor>=2.0,"High-resolution display still has tiny text")
	check(root.content_scale_mode==Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,"UI is not rendered at native resolution")
	var viewport := root.get_visible_rect()
	check(viewport.encloses(studio._inspector.get_global_rect()),"Fullscreen inspector leaves logical viewport")
	check(viewport.encloses(demo.effect.get_global_rect()),"Fullscreen preview leaves logical viewport")
	var point: Vector2 = root.get_final_transform()*studio._pages[1].get_global_rect().get_center()
	await click_at(point)
	await frames()
	check(studio._tabs.visible and studio._tabs.current_tab==0,"Scaled controls do not respond at their visible position")
	root.get_texture().get_image().save_png("/tmp/ntscrt-scaled-fullscreen.png")
	studio._save_dialog.popup_centered(Vector2i(480,320))
	await frames()
	check(studio._save_dialog.is_embedded(),"Save dialog does not inherit canvas scaling")
	var bounds := Rect2(Vector2.ZERO,Vector2(studio._save_dialog.size))
	check(bounds.encloses(studio._capture_button.get_global_rect()),"Capture button is outside the dialog")
	var files: Control = studio._capture_button.get_parent().get_child(-1)
	check(bounds.encloses(files.get_global_rect()),"Dialog clips Open captures / Copy JSON")
	root.get_texture().get_image().save_png("/tmp/ntscrt-scaled-save-dialog.png")
	studio._save_dialog.hide()
	studio._library_select.show_popup()
	await frames()
	check(studio._library_select.get_popup().is_embedded(),"Look dropdown does not inherit UI scaling")
	root.get_texture().get_image().save_png("/tmp/ntscrt-scaled-dropdown.png")
	studio._library_select.get_popup().hide()
	var capture: Dictionary = await studio.capture_preset("/tmp/ntscrt-scaled-capture")
	# ViewportTexture.get_size() can report stretch twice; the GPU image is the actual output.
	var pixels := Vector2(root.get_texture().get_image().get_size())/root.get_visible_rect().size
	check(capture.error.is_empty(),"Scaled capture failed: "+str(capture.error))

	check(capture.image_size==Vector2i(demo.effect.size*pixels),"Capture crop does not account for UI scaling")
	check(demo.effect.presenter.ready_frames>0 and demo.effect.get_error().is_empty(),"Scaled preview renderer failed")
	root.mode = Window.MODE_WINDOWED
	await create_timer(0.5).timeout
	root.size = Vector2i(1280,800)
	await frames(15)
	check(is_equal_approx(root.content_scale_factor,1.0),"UI scale did not reset on return to a small window")
	demo.queue_free()
	await frames(3)
	print("DEMO_SCALING ","PASS" if failures.is_empty() else "FAIL", " — fullscreen, click targets, dialogs, dropdowns, capture and windowed return")
	quit(0 if failures.is_empty() else 1)
