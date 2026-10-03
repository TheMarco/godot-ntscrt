extends SceneTree
const ROOM = preload("res://demo/sample_room.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	root.size = Vector2i(720,540)
	root.content_scale_size = Vector2i(720,540)
	root.msaa_3d = Viewport.MSAA_4X
	var output := "user://sample-footage-frames"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="): output = argument.trim_prefix("--output-dir=")
	for kind in ["hallway","security"]:
		var room := ROOM.new()
		room.security = kind=="security"
		root.add_child(room)
		for warmup in 3:
			await process_frame
			RenderingServer.force_draw()
		var path: String = output.path_join(kind)
		DirAccess.make_dir_recursive_absolute(path)
		for frame in (1 if OS.get_cmdline_user_args().has("--preview") else 240):
			room.set_time(float(frame)/30.0)
			await process_frame
			RenderingServer.force_draw()
			root.get_texture().get_image().save_png(path.path_join("%04d.png" % frame))
			if frame%60==0: print(kind," ",frame,"/240")
		room.queue_free()
		await process_frame
	print("SAMPLE_FOOTAGE PASS")
	quit()
