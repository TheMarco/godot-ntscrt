extends RefCounted
## GPU translation of ntsc-rs add90f5bf1bf7e3c573e4e945a16f44a82941b51.
## Call only on the render thread, using the global RenderingDevice.
## Settings are canonical flat JSON keys; absent values use NtscEffect::default.
## No pixel readback, submit, or sync occurs in this runtime object.
const DEFAULTS := {
	"chroma_lowpass_in": 2,
	"composite_preemphasis": 1.0,
	"video_scanline_phase_shift": 2,
	"video_scanline_phase_shift_offset": 0,
	"composite_noise_intensity": 0.05,
	"chroma_noise_intensity": 0.1,
	"snow_intensity": 0.00025,
	"chroma_phase_noise_intensity": 0.001,
	"chroma_delay_horizontal": 0.0,
	"chroma_delay_vertical": 0,
	"chroma_lowpass_out": 2,
	"head_switching": true,
	"head_switching_height": 8,
	"head_switching_offset": 3,
	"head_switching_horizontal_shift": 72.0,
	"tracking_noise": true,
	"tracking_noise_height": 12,
	"tracking_noise_wave_intensity": 15.0,
	"tracking_noise_snow_intensity": 0.025,
	"ringing": true,
	"ringing_frequency": 0.45,
	"ringing_power": 4.0,
	"ringing_scale": 4.0,
	"vhs_settings": true,
	"vhs_tape_speed": 2,
	"vhs_chroma_vert_blend": true,
	"vhs_chroma_loss": 2.5e-05,
	"vhs_sharpen": 0.25,
	"vhs_edge_wave": 0.5,
	"vhs_edge_wave_speed": 4.0,
	"use_field": 4,
	"tracking_noise_noise_intensity": 0.25,
	"bandwidth_scale": 1.0,
	"chroma_demodulation": 1,
	"snow_anisotropy": 0.5,
	"tracking_noise_snow_anisotropy": 0.25,
	"random_seed": 0,
	"chroma_phase_error": 0.0,
	"input_luma_filter": 2,
	"vhs_edge_wave_enabled": true,
	"vhs_edge_wave_frequency": 0.05,
	"vhs_edge_wave_detail": 2,
	"chroma_noise": true,
	"chroma_noise_frequency": 0.05,
	"chroma_noise_detail": 2,
	"luma_smear": 0.5,
	"filter_type": 1,
	"vhs_sharpen_enabled": true,
	"vhs_sharpen_frequency": 1.0,
	"head_switching_start_mid_line": true,
	"head_switching_mid_line_position": 0.95,
	"head_switching_mid_line_jitter": 0.03,
	"composite_noise": true,
	"composite_noise_frequency": 0.5,
	"composite_noise_detail": 1,
	"luma_noise": true,
	"luma_noise_frequency": 0.5,
	"luma_noise_intensity": 0.01,
	"luma_noise_detail": 1,
	"vertical_scale": 1.0,
	"scale_with_video_size": false,
	"scale_settings": true,
}
const KEYS := [
	"chroma_lowpass_in",
	"composite_preemphasis",
	"video_scanline_phase_shift",
	"video_scanline_phase_shift_offset",
	"composite_noise_intensity",
	"chroma_noise_intensity",
	"snow_intensity",
	"chroma_phase_noise_intensity",
	"chroma_delay_horizontal",
	"chroma_delay_vertical",
	"chroma_lowpass_out",
	"head_switching",
	"head_switching_height",
	"head_switching_offset",
	"head_switching_horizontal_shift",
	"tracking_noise",
	"tracking_noise_height",
	"tracking_noise_wave_intensity",
	"tracking_noise_snow_intensity",
	"ringing",
	"ringing_frequency",
	"ringing_power",
	"ringing_scale",
	"vhs_settings",
	"vhs_tape_speed",
	"vhs_chroma_vert_blend",
	"vhs_chroma_loss",
	"vhs_sharpen",
	"vhs_edge_wave",
	"vhs_edge_wave_speed",
	"use_field",
	"tracking_noise_noise_intensity",
	"bandwidth_scale",
	"chroma_demodulation",
	"snow_anisotropy",
	"tracking_noise_snow_anisotropy",
	"random_seed",
	"chroma_phase_error",
	"input_luma_filter",
	"vhs_edge_wave_enabled",
	"vhs_edge_wave_frequency",
	"vhs_edge_wave_detail",
	"chroma_noise",
	"chroma_noise_frequency",
	"chroma_noise_detail",
	"luma_smear",
	"filter_type",
	"vhs_sharpen_enabled",
	"vhs_sharpen_frequency",
	"head_switching_start_mid_line",
	"head_switching_mid_line_position",
	"head_switching_mid_line_jitter",
	"composite_noise",
	"composite_noise_frequency",
	"composite_noise_detail",
	"luma_noise",
	"luma_noise_frequency",
	"luma_noise_intensity",
	"luma_noise_detail",
	"vertical_scale",
	"scale_with_video_size",
	"scale_settings",
]
var output := RID()
var error := ""
var _rd: RenderingDevice
var _extent := Vector2i.ZERO
var _shader := RID()
var _pipeline := RID()
var _planes: Array[RID] = []
var _settings := RID()
var _sets: Array[RID] = []
var _input := RID()
var _history := RID()
var _last_frame := -1
var _last_field := -1
var _history_parity := -1

func setup(rd: RenderingDevice, extent: Vector2i) -> bool:
	dispose()
	error = ""
	_rd = rd
	_extent = extent
	if rd == null or extent.x < 1 or extent.y < 1:
		error = "NtscrsGpu requires a RenderingDevice and positive extent"
		return false
	var spirv: RDShaderSPIRV
	var shader_path := "res://addons/ntscrt/shaders/ntscrs_gpu/pipeline.glsl"
	if FileAccess.file_exists(shader_path):
		var source := RDShaderSource.new()
		source.source_compute = FileAccess.get_file_as_string(shader_path).replace("#[compute]", "")
		spirv = rd.shader_compile_spirv_from_source(source)
	else:
		# Exported projects retain the imported RDShaderFile, not necessarily source.
		var shader_file := load(shader_path) as RDShaderFile
		if shader_file == null:
			error = "Missing ntsc-rs compute shader"
			return false
		spirv = shader_file.get_spirv()
	error = spirv.compile_error_compute
	if not error.is_empty():
		return false
	_shader = rd.shader_create_from_spirv(spirv)
	_pipeline = rd.compute_pipeline_create(_shader)
	if not _pipeline.is_valid():
		error = "ntsc-rs GPU pipeline creation failed"
		return false
	for i in 2:
		_planes.append(rd.storage_buffer_create(extent.x * extent.y * 3 * 4))
	_settings = rd.storage_buffer_create(62 * 4)
	var format := RDTextureFormat.new()
	format.width = extent.x
	format.height = extent.y
	format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	output = rd.texture_create(format, RDTextureView.new())
	_history = rd.texture_create(format, RDTextureView.new())
	return output.is_valid()

func _uniform(binding: int, type: int, id: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.binding = binding
	uniform.uniform_type = type
	uniform.add_id(id)
	return uniform

func render(input: RID, frame_number: int, settings: Dictionary) -> RID:
	if not _pipeline.is_valid() or not input.is_valid():
		return RID()
	if _input != input:
		for id in _sets:
			if _rd.uniform_set_is_valid(id):
				_rd.free_rid(id)
		_sets.clear()
		_input = input
		for i in 2:
			var uniforms: Array[RDUniform] = [
				_uniform(0, RenderingDevice.UNIFORM_TYPE_IMAGE, input),
				_uniform(1, RenderingDevice.UNIFORM_TYPE_IMAGE, output),
				_uniform(2, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, _planes[i]),
				_uniform(3, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, _planes[1-i]),
				_uniform(4, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, _settings),
				_uniform(5, RenderingDevice.UNIFORM_TYPE_IMAGE, _history)]
			_sets.append(_rd.uniform_set_create(uniforms, _shader, 0))
	var field := int(settings.get("use_field", 4))
	if field == 0:
		field = 2 if frame_number % 2 == 0 else 1
	var history_enabled := bool(settings.get("field_history",false)) and field in [1,2]
	if frame_number < _last_frame or not history_enabled:
		_history_parity = -1
	elif frame_number != _last_frame and _last_frame >= 0 and _last_field in [1,2]:
		_rd.texture_copy(output, _history, Vector3.ZERO, Vector3.ZERO, Vector3(_extent.x, _extent.y, 1), 0, 0, 0, 0)
		_history_parity = _last_field - 1 if _last_field in [1, 2] else -1
	var weave := history_enabled and _history_parity == (2 - field)
	_last_frame = frame_number
	_last_field = field
	var values := PackedFloat32Array()
	values.resize(62)
	for i in 62:
		values[i] = float(settings.get(KEYS[i], DEFAULTS[KEYS[i]]))
	_rd.buffer_update(_settings, 0, 62 * 4, values.to_byte_array())
	var push := PackedByteArray()
	push.resize(32)
	push.encode_s32(0, _extent.x)
	push.encode_s32(4, _extent.y)
	push.encode_s32(8, frame_number)
	push.encode_u32(16, int(settings.get("random_seed", 0)) & 0xffffffff)
	push.encode_s32(20, int(weave))
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipeline)
	for stage in 9:
		push.encode_s32(12, stage)
		_rd.compute_list_bind_uniform_set(list, _sets[stage % 2], 0)
		_rd.compute_list_set_push_constant(list, push, push.size())
		_rd.compute_list_dispatch(list, _extent.y, 1, 1)
		if stage < 8:
			_rd.compute_list_add_barrier(list)
	_rd.compute_list_end()
	return output

func dispose() -> void:
	if _rd != null:
		for id in _sets:
			if _rd.uniform_set_is_valid(id):
				_rd.free_rid(id)
		for id in _planes:
			_rd.free_rid(id)
		for id in [_settings, output, _history, _pipeline, _shader]:
			if id.is_valid():
				_rd.free_rid(id)
	_sets.clear()
	_planes.clear()
	output = RID()
	_settings = RID()
	_pipeline = RID()
	_shader = RID()
	_input = RID()
	_history = RID()
	_last_frame = -1
	_last_field = -1
	_history_parity = -1
	_rd = null
