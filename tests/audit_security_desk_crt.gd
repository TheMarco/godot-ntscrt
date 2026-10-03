extends SceneTree
## A feedback shader must preserve contrast over time and let bright trails fade.
const CHAIN = preload("res://addons/ntscrt/internal/ntscrt_slang_chain.gd")
const LIBRARY = preload("res://addons/ntscrt/preset_library.gd")
const EXTENT := Vector2i(160,120)
var _done := false
var _failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	RenderingServer.call_on_render_thread(_render)
	while not _done: await process_frame
	for failure in _failures: printerr(failure)
	print("SECURITY_DESK_CRT ","PASS" if _failures.is_empty() else "FAIL")
	quit(0 if _failures.is_empty() else 1)

func _texture(rd: RenderingDevice, image: Image) -> RID:
	var format := RDTextureFormat.new()
	format.width = EXTENT.x
	format.height = EXTENT.y
	format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	return rd.texture_create(format,RDTextureView.new(),[image.get_data()])

func _sample(rd: RenderingDevice, output: RID) -> PackedFloat32Array:
	var image := Image.create_from_data(EXTENT.x,EXTENT.y,false,Image.FORMAT_RGBA8,rd.texture_get_data(output,0))
	var result := PackedFloat32Array()
	for x in [20,60,100,140]: result.append(image.get_pixel(x,60).r)
	return result

func _render() -> void:
	var rd := RenderingServer.get_rendering_device()
	if rd==null:
		_failures.append("Native GPU required")
		_done = true
		return
	var source := Image.create(EXTENT.x,EXTENT.y,false,Image.FORMAT_RGBA8)
	for x in EXTENT.x:
		var level: float = [0.08,0.25,0.5,0.75][x/40]
		for y in EXTENT.y: source.set_pixel(x,y,Color(level,level,level,1.0))
	var dark := Image.create(EXTENT.x,EXTENT.y,false,Image.FORMAT_RGBA8)
	dark.fill(Color(0.02,0.02,0.02,1.0))
	var input := _texture(rd,source)
	var dark_input := _texture(rd,dark)
	var chain := CHAIN.new()
	var profile := LIBRARY.make_profile(19)
	if chain.setup(rd,CHAIN.load_presets()[profile.selected_crt_model()],EXTENT,EXTENT):
		var knobs := profile.active_crt_parameters()
		var initial := PackedFloat32Array()
		for frame in 120:
			var output: RID = chain.render(input,knobs)
			if frame in [0,29,119]:
				var levels := _sample(rd,output)
				print("FRAME ",frame+1," gray patches=",levels)
				if frame==0: initial = levels
				if levels[0]>0.15 or levels[3]>0.85 or levels[3]-levels[0]<0.5:
					_failures.append("Lost contrast / feedback brightened to white at frame %d" % (frame+1))
				for patch in levels.size():
					if absf(levels[patch]-initial[patch])>0.02:
						_failures.append("Stationary picture brightness drifted at frame %d" % (frame+1))
		for frame in 30:
			var output: RID = chain.render(dark_input,knobs)
			if frame in [0,29]:
				var levels := _sample(rd,output)
				print("DECAY ",frame+1," gray patches=",levels)
				if frame==0 and levels[3]<0.1: _failures.append("Phosphor persistence disappeared")
				if frame==29 and levels[3]>0.04: _failures.append("Phosphor trail never faded")
	else: _failures.append(chain.error)
	chain.dispose()
	rd.free_rid(input)
	rd.free_rid(dark_input)
	_done = true
