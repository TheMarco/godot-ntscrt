extends SceneTree
## Native GPU contract: original shader compilation and nonblank colour output.
## Readback is diagnostic only; the game chain returns a GPU texture RID.
const CHAIN = preload("res://addons/ntscrt/internal/ntscrt_slang_chain.gd")
const PRESENTER = preload("res://addons/ntscrt/internal/ntscrt_gpu_presenter.gd")
var _done := false
var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	RenderingServer.call_on_render_thread(_render)
	while not _done: await process_frame
	if _failures.is_empty(): print("PASS: NTSCRT original Slang GPU shader audit")
	else:
		for message in _failures: printerr(message)
	quit(0 if _failures.is_empty() else 1)

func _render() -> void:
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		_failures.append("A native RenderingDevice is required")
		_done = true
		return
	var image := Image.create(320,240,false,Image.FORMAT_RGBA8)
	for y in 240:
		for x in 320: image.set_pixel(x,y,Color(float(x)/319.0,float(y)/239.0,0.25,1.0))
	var format := RDTextureFormat.new()
	format.width = 320
	format.height = 240
	format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var input := rd.texture_create(format,RDTextureView.new(),[image.get_data()])
	var presets := CHAIN.load_presets()
	var selected := "aperture"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--preset="): selected = argument.trim_prefix("--preset=")
	if selected == "glitch_noise":
		_audit_glitch_noise(rd)
		rd.free_rid(input)
		_done = true
		return
	var names: Array = presets.keys() if selected == "all" else [selected]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/review/slang"))
	for name in names:
		var chain := CHAIN.new()
		if not chain.setup(rd,presets[name],Vector2i(320,240),Vector2i(640,480)):
			_failures.append(str(name) + ": " + chain.error)
			chain.dispose()
			continue
		var output: RID = chain.render(input)
		if not output.is_valid():
			_failures.append(str(name) + ": " + chain.error)
		else:
			var bytes := rd.texture_get_data(output,0)
			var result := Image.create_from_data(640,480,false,Image.FORMAT_RGBA8,bytes)
			var centre := result.get_pixel(320,240)
			if centre.r+centre.g+centre.b < 0.02: _failures.append(str(name) + ": output is black")
			result.save_png("res://build/review/slang/" + str(name) + ".png")
			print("SLANG ",name," passes=",chain.pass_extents.size()," centre=",centre," extents=",chain.pass_extents)
		chain.dispose()
	rd.free_rid(input)
	_done = true

## Compare rendered static across fields, including spatial offsets: different
## frames must not be translations of one fixed sheet of noise.
func _noise_correlation(a: Image, b: Image, dx: int, dy: int) -> float:
	var count := 0.0
	var sum_a := 0.0
	var sum_b := 0.0
	var square_a := 0.0
	var square_b := 0.0
	var product := 0.0
	for y in range(2, a.get_height()-2):
		for x in range(2, a.get_width()-2):
			var av := a.get_pixel(x+dx,y+dy).r
			var bv := b.get_pixel(x,y).r
			count += 1.0
			sum_a += av
			sum_b += bv
			square_a += av*av
			square_b += bv*bv
			product += av*bv
	return (count*product-sum_a*sum_b) / sqrt(maxf(
		(count*square_a-sum_a*sum_a)*(count*square_b-sum_b*sum_b), 0.000001))

func _audit_glitch_noise(rd: RenderingDevice) -> void:
	var extent := Vector2i(128,96)
	var black := Image.create(extent.x,extent.y,false,Image.FORMAT_RGBA8)
	black.fill(Color.BLACK)
	var format := RDTextureFormat.new()
	format.width = extent.x
	format.height = extent.y
	format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var input := rd.texture_create(format,RDTextureView.new(),[black.get_data()])
	for linear in [false,true]:
		var chain := CHAIN.new()
		if not chain.setup(rd,PRESENTER._preparation(linear),extent,extent):
			_failures.append("Glitch noise compilation: " + chain.error)
			chain.dispose()
			continue
		var fields: Array[Image] = []
		for field in [100,101,100,10000,10001]:
			var output := chain.render(input,{"fault_kind":3.0,"fault_amount":1.0,"field_index":float(field)})
			fields.append(Image.create_from_data(extent.x,extent.y,false,Image.FORMAT_RGBA8,rd.texture_get_data(output,0)))
		if fields[0].get_data()!=fields[2].get_data():
			_failures.append("Glitch noise must remain stable within one video field")
		var maximum := 0.0
		for pair in [[0,1],[3,4]]:
			for dy in range(-2,3):
				for dx in range(-2,3):
					maximum = maxf(maximum,absf(_noise_correlation(fields[pair[0]],fields[pair[1]],dx,dy)))
		if maximum > 0.1:
			_failures.append("Glitch static scrolls or repeats between fields (max correlation %.4f)" % maximum)
		var average := 0.0
		for y in extent.y:
			for x in extent.x: average += fields[0].get_pixel(x,y).r
		average /= float(extent.x*extent.y)
		if average < 0.18 or average > 0.24:
			_failures.append("Glitch noise lost its intended brightness/strength: %.4f" % average)
		var clean := chain.render(input,{"fault_amount":0.0})
		if rd.texture_get_data(clean,0)!=black.get_data():
			_failures.append("Inactive glitch changed the source image")
		print("GLITCH_NOISE linear=",linear," max_temporal_correlation=",maximum," mean=",average)
		chain.dispose()
	rd.free_rid(input)
