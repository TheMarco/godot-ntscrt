extends RefCounted
## GPU translation of NTSCRT Sources/CrtCore/Downscaler.swift.
## Original authors retain copyright. Call only on the global RD render thread.
## Methods: 0 nearest, 1 nearestAA, 2 bilinear, 3 bicubic, 4 lanczos, 5 area.
## Input is sampled gamma-domain SDR; scratch and output are RGBA8_UNORM.
## No runtime pixel readback, submit or sync.
var output := RID()
var error := ""
var _rd: RenderingDevice
var _source_size := Vector2i.ZERO
var _target_size := Vector2i.ZERO
var _shader := RID()
var _pipeline := RID()
var _sampler := RID()
var _scratch := RID()
var _vertical_set := RID()
var _direct_set := RID()
var _horizontal_set := RID()
var _input := RID()

func setup(rd: RenderingDevice, source_size: Vector2i, target_size: Vector2i) -> bool:
	dispose()
	error = ""
	_rd = rd
	_source_size = source_size
	_target_size = target_size
	if rd == null or source_size.x < 1 or source_size.y < 1 or target_size.x < 1 or target_size.y < 1:
		error = "Downscale requires a RenderingDevice and positive extents"
		return false
	var shader_path := "res://addons/ntscrt/shaders/ntscrt_downscale_gpu/pipeline.glsl"
	var spirv: RDShaderSPIRV
	if FileAccess.file_exists(shader_path):
		var source := RDShaderSource.new()
		source.source_compute = FileAccess.get_file_as_string(shader_path).replace("#[compute]", "")
		spirv = rd.shader_compile_spirv_from_source(source)
	else:
		var shader_file := load(shader_path) as RDShaderFile
		if shader_file == null:
			error = "Missing downscale compute shader"
			return false
		spirv = shader_file.get_spirv()
	error = spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not error.is_empty():
		return false
	_shader = rd.shader_create_from_spirv(spirv)
	_pipeline = rd.compute_pipeline_create(_shader)
	if not _pipeline.is_valid():
		error = "Downscale pipeline creation failed"
		return false
	var sampler_state := RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sampler = rd.sampler_create(sampler_state)
	output = _texture(target_size)
	_scratch = _texture(Vector2i(target_size.x, source_size.y))
	_vertical_set = _uniform_set(_scratch, output)
	if not output.is_valid() or not _scratch.is_valid() or not _vertical_set.is_valid():
		error = "Downscale resource allocation failed"
		return false
	return true

func _texture(extent: Vector2i) -> RID:
	var format := RDTextureFormat.new()
	format.width = extent.x
	format.height = extent.y
	format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	return _rd.texture_create(format, RDTextureView.new())

func _uniform_set(input: RID, destination: RID) -> RID:
	var sampled := RDUniform.new()
	sampled.binding = 0
	sampled.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	sampled.add_id(_sampler)
	sampled.add_id(input)
	var image := RDUniform.new()
	image.binding = 1
	image.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	image.add_id(destination)
	return _rd.uniform_set_create([sampled, image], _shader, 0)

func render(input: RID, method: int) -> RID:
	if not _pipeline.is_valid() or not input.is_valid():
		return RID()
	if method < 0 or method > 5:
		error = "Unknown downscale method: %d" % method
		return RID()
	if _input != input or not _rd.uniform_set_is_valid(_direct_set):
		for id in [_direct_set, _horizontal_set]:
			if id.is_valid() and _rd.uniform_set_is_valid(id):
				_rd.free_rid(id)
		_direct_set = _uniform_set(input, output)
		_horizontal_set = _uniform_set(input, _scratch)
		_input = input
	var separable := method > 0 and method < 5
	var push := PackedByteArray()
	push.resize(32)
	push.encode_s32(0, _source_size.x)
	push.encode_s32(4, _source_size.y)
	push.encode_s32(8, _target_size.x)
	push.encode_s32(12, _target_size.y)
	push.encode_s32(16, method)
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipeline)
	_rd.compute_list_bind_uniform_set(list, _horizontal_set if separable else _direct_set, 0)
	_rd.compute_list_set_push_constant(list, push, push.size())
	_rd.compute_list_dispatch(list, ceili(_target_size.x / 8.0), ceili((_source_size.y if separable else _target_size.y) / 8.0), 1)
	if separable:
		_rd.compute_list_add_barrier(list)
		push.encode_s32(20, 1)
		_rd.compute_list_bind_uniform_set(list, _vertical_set, 0)
		_rd.compute_list_set_push_constant(list, push, push.size())
		_rd.compute_list_dispatch(list, ceili(_target_size.x / 8.0), ceili(_target_size.y / 8.0), 1)
	_rd.compute_list_end()
	return output

func dispose() -> void:
	if _rd != null:
		for id in [_direct_set, _horizontal_set, _vertical_set]:
			if id.is_valid() and _rd.uniform_set_is_valid(id):
				_rd.free_rid(id)
		for id in [_scratch, output, _sampler, _pipeline, _shader]:
			if id.is_valid():
				_rd.free_rid(id)
	output = RID()
	_scratch = RID()
	_sampler = RID()
	_pipeline = RID()
	_shader = RID()
	_vertical_set = RID()
	_direct_set = RID()
	_horizontal_set = RID()
	_input = RID()
	_rd = null
