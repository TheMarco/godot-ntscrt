extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok: failures.append(label); printerr(label)
func frames(count := 8) -> void:
	for frame in count: await process_frame
	RenderingServer.force_draw()
func _run() -> void:
	root.size = Vector2i(1280,800)
	var demo: Node = load("res://demo/demo.tscn").instantiate()
	root.add_child(demo)
	demo._select_source(4)
	var studio: Control = demo.workshop
	var folder := "/tmp/ntscrt-studio-layout"
	DirAccess.make_dir_recursive_absolute(folder)
	for extent in [Vector2i(1280,800),Vector2i(960,640),Vector2i(1440,900)]:
		root.size = extent
		await frames(12)
		for page in range(5):
			studio._select_page(page)
			await frames()
			var viewport := Rect2(Vector2.ZERO,Vector2(extent))
			var pane: Control = studio._browser_space if page==0 else studio._tabs
			check(viewport.encloses(studio._inspector.get_global_rect()),"Inspector leaves window: %s / %d" % [extent,page])
			check(viewport.encloses(demo.effect.get_global_rect()),"Preview leaves window: %s / %d" % [extent,page])
			check(pane.size.y>=extent.y*0.60,"Controls too short: %s / %d (%s)" % [extent,page,pane.size])
			check(demo.effect.size.x>=240 and demo.effect.size.y>=180,"Preview too small: %s / %d" % [extent,page])
			check(not demo.effect.get_global_rect().intersects(studio._inspector.get_global_rect()),"Controls overlap preview")
			check(studio._pages[page].button_pressed,"Navigation selection is stale")
			root.get_texture().get_image().save_png(folder.path_join("%dx%d-page%d.png" % [extent.x,extent.y,page]))
		studio._select_page(1)
		var before: float = demo.effect.size.x
		studio._split.split_offset -= 60
		await frames()
		check(demo.effect.size.x<before,"Divider did not resize preview")
		studio._toggle_inspector()
		await frames()
		check(demo.effect.size.x>extent.x*0.9,"Expand preview did not use available width")
		studio._toggle_inspector()
		await frames()
		check(studio._tabs.visible and studio._pages[1].button_pressed,"Returning from expanded preview lost editor page")
	studio.store_reference()
	studio.show_reference(true)
	check(studio._look_buttons[0].disabled and studio._pages[1].disabled,"A/B permits editing the reference")
	studio.show_reference(false)
	studio._select_page(2)
	studio._crt_filter.text = "GLOW_HALATION"
	studio._filter_crt()
	check(studio._crt_controls["GLOW_HALATION"].get_parent().get_parent().visible,"CRT search hides matching row")
	studio._save_dialog.popup_centered(Vector2i(480,260))
	await frames(4)
	check(studio._name.is_visible_in_tree() and studio._capture_button.is_visible_in_tree(),"Save controls are inaccessible")
	check(Rect2(Vector2.ZERO,Vector2(studio._save_dialog.size)).encloses(studio._capture_button.get_global_rect()),"Save button leaves dialog")
	studio._save_dialog.hide()
	var capture: Dictionary = await studio.capture_preset(folder.path_join("capture"))
	check(capture.error.is_empty(),"Studio capture failed")
	check(capture.image_size==Vector2i(demo.effect.size),"Capture is not limited to preview")
	check(demo.effect.presenter.ready_frames>0,"Studio never rendered a filtered frame")
	check(demo.effect.get_error().is_empty(),demo.effect.get_error())
	demo.queue_free()
	await frames(3)
	print("DEMO_LAYOUT ","PASS" if failures.is_empty() else "FAIL", " — pages, resizing, divider, preview, A/B, search, save and capture")
	quit(0 if failures.is_empty() else 1)
