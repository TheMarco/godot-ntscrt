extends RefCounted
## Original Slang shader chains, executed entirely on the RenderingDevice.
## All methods except load_presets() must run on the rendering thread.
## The caller owns the input texture; this object owns its output/intermediates.

const MANIFEST := "res://addons/ntscrt/third_party/slang/presets.json"
const TEXTURE_ROOT := "res://addons/ntscrt/third_party/slang/upstream/"
var error := ""
var output := RID()
var source_size := Vector2i.ZERO
var output_size := Vector2i.ZERO
var parameters: Dictionary = {}
var pass_extents: Array[Vector2i] = []
var _rd: RenderingDevice
var _passes: Array[Dictionary] = []
var _textures: Dictionary = {}
var _owned: Array[RID] = []
var _vertex_array := RID()
var _vertex_format := 0
var _frame := 0
var _uniform_sets: Dictionary = {}
var _set_ids: Dictionary = {}
var _samplers: Dictionary = {}
var _mip_shader := RID()
var _mip_targets: Dictionary = {}
var _mip_pipelines: Dictionary = {}

static func load_presets() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return data.get("presets", {}) if data is Dictionary else {}

func _own(rid: RID) -> RID:
	if rid.is_valid(): _owned.append(rid)
	return rid

func _own_set(rid: RID) -> RID:
	if rid.is_valid(): _set_ids[rid.get_id()] = true
	return _own(rid)

func setup(rd: RenderingDevice, preset: Dictionary, input_extent: Vector2i, display_extent: Vector2i) -> bool:
	_rd = rd
	source_size = input_extent
	output_size = display_extent
	for key in preset.parameters: parameters[key] = preset.parameters[key].default
	var vertices := PackedFloat32Array([
		-1,-1,0,1, 0,0, 1,-1,0,1, 1,0, -1,1,0,1, 0,1,
		-1,1,0,1, 0,1, 1,-1,0,1, 1,0, 1,1,0,1, 1,1])
	var vertex_buffer := _own(rd.vertex_buffer_create(vertices.size()*4, vertices.to_byte_array()))
	var position := RDVertexAttribute.new()
	position.location = 0
	position.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	position.stride = 24
	var uv := RDVertexAttribute.new()
	uv.location = 1
	uv.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	uv.offset = 16
	uv.stride = 24
	_vertex_format = rd.vertex_format_create([position,uv])
	_vertex_array = _own(rd.vertex_array_create(6,_vertex_format,[vertex_buffer,vertex_buffer]))
	var mip_source := RDShaderSource.new()
	mip_source.source_vertex = """#version 450
layout(location=0) out vec2 uv;
void main() {
    uv=vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
    gl_Position=vec4(uv*2.0-1.0,0.0,1.0);
}"""
	mip_source.source_fragment = """#version 450
layout(location=0) in vec2 uv;
layout(location=0) out vec4 colour;
layout(set=0,binding=0) uniform sampler2D source;
void main() { colour=textureLod(source,uv,0.0); }
"""
	_mip_shader = _own(rd.shader_create_from_spirv(rd.shader_compile_spirv_from_source(mip_source)))
	for name in preset.textures:
		var info: Dictionary = preset.textures[name]
		var path := TEXTURE_ROOT + str(info.path)
		var image: Image
		if FileAccess.file_exists(path):
			image = Image.new()
			if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK: return _fail("Cannot decode LUT " + name)
		else:
			var imported := load(path) as Texture2D
			if imported != null: image = imported.get_image()
		if image == null or image.is_empty(): return _fail("Cannot load LUT " + name)
		if image.is_compressed() and image.decompress() != OK: return _fail("Cannot decompress LUT " + name)
		image.convert(Image.FORMAT_RGBA8)
		if info.mipmap: image.generate_mipmaps()
		var format := RDTextureFormat.new()
		format.width = image.get_width()
		format.height = image.get_height()
		format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
		format.mipmaps = image.get_mipmap_count()+1
		format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		var texture := _own(rd.texture_create(format,RDTextureView.new(),[image.get_data()]))
		_textures[name] = {"texture": texture, "size": image.get_size(), "sampler": _sampler(info.linear,info.wrap,info.mipmap)}
	var extent := input_extent
	for index in preset.passes.size():
		var description: Dictionary = preset.passes[index]
		var options: Dictionary = description.options
		extent = _pass_size(options,extent,index == preset.passes.size()-1)
		pass_extents.append(extent)
		var shader_source := RDShaderSource.new()
		shader_source.source_vertex = description.vertex
		shader_source.source_fragment = description.fragment
		var spirv := rd.shader_compile_spirv_from_source(shader_source)
		for stage in [RenderingDevice.SHADER_STAGE_VERTEX,RenderingDevice.SHADER_STAGE_FRAGMENT]:
			var message := spirv.get_stage_compile_error(stage)
			if not message.is_empty(): return _fail(str(description.path) + ": " + message)
		var shader := _own(rd.shader_create_from_spirv(spirv))
		if not shader.is_valid(): return _fail("Cannot create shader " + str(description.path))
		var format := _format(description)
		# Only passes referenced by feedback need two copies. Both start black.
		var feedback := false
		for next in preset.passes:
			for binding in next.bindings.values():
				if binding.kind == "sampler" and binding.name == "PassFeedback%d" % index: feedback = true
		var outputs: Array[RID] = []
		var framebuffers: Array[RID] = []
		var needs_mips: bool = index+1 < preset.passes.size() and preset.passes[index+1].options.get("mipmap_input","false") == "true"
		for copy in (2 if feedback else 1):
			var texture := _target(extent,format,needs_mips,description.options.get("storage_output","false") == "true")
			outputs.append(texture)
			var attachment := texture
			if needs_mips: attachment = _mip_targets[texture.get_id()][0].view
			framebuffers.append(_own(rd.framebuffer_create([attachment])))
			_rd.texture_clear(texture,Color(0,0,0,0),0,1,0,1)
		var blend := RDPipelineColorBlendState.new()
		blend.attachments = [RDPipelineColorBlendStateAttachment.new()]
		var pipeline := _own(rd.render_pipeline_create(shader,rd.framebuffer_get_format(framebuffers[0]),_vertex_format,
			RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,RDPipelineRasterizationState.new(),RDPipelineMultisampleState.new(),RDPipelineDepthStencilState.new(),blend))
		if not pipeline.is_valid(): return _fail("Cannot create pipeline " + str(description.path))
		var buffers := {}
		for binding in description.bindings:
			var info: Dictionary = description.bindings[binding]
			if info.kind == "buffer": buffers[binding] = _own(rd.uniform_buffer_create(int(info.size)))
		_passes.append({"description":description,"shader":shader,"pipeline":pipeline,"outputs":outputs,"framebuffers":framebuffers,"buffers":buffers,
			"sampler":_sampler(options.get("filter_linear","false") == "true",options.get("wrap_mode","clamp_to_border"),options.get("mipmap_input","false") == "true")})
	output = _passes[-1].outputs[0]
	return true

func render(input: RID, overrides: Dictionary = {}) -> RID:
	if not error.is_empty() or _passes.is_empty(): return RID()
	parameters.merge(overrides,true)
	var resources := _textures.duplicate()
	resources["Original"] = {"texture": input, "size": source_size}
	for index in _passes.size():
		var pass_data: Dictionary = _passes[index]
		var count: int = pass_data.outputs.size()
		resources["PassFeedback%d" % index] = {"texture":pass_data.outputs[(_frame+1)%count],"size":pass_extents[index]}
	var previous := input
	var previous_size := source_size
	for index in _passes.size():
		var pass_data: Dictionary = _passes[index]
		var description: Dictionary = pass_data.description
		resources["Source"] = {"texture":previous,"size":previous_size}
		var uniforms: Array[RDUniform] = []
		var cache_key := str(index)
		for binding in description.bindings:
			var info: Dictionary = description.bindings[binding]
			var uniform := RDUniform.new()
			uniform.binding = int(binding)
			if info.kind == "buffer":
				var buffer: RID = pass_data.buffers[binding]
				var data := _buffer_data(info,resources,pass_extents[index],description.options)
				_rd.buffer_update(buffer,0,data.size(),data)
				uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
				uniform.add_id(buffer)
			else:
				if not resources.has(info.name):
					_fail("Unresolved texture " + str(info.name))
					return RID()
				var resource: Dictionary = resources[info.name]
				uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
				uniform.add_id(resource.get("sampler",pass_data.sampler))
				uniform.add_id(resource.texture)
				cache_key += ":" + str(resource.texture.get_id())
			uniforms.append(uniform)
		if _uniform_sets.has(cache_key) and not _rd.uniform_set_is_valid(_uniform_sets[cache_key]): _uniform_sets.erase(cache_key)
		if not _uniform_sets.has(cache_key): _uniform_sets[cache_key] = _own_set(_rd.uniform_set_create(uniforms,pass_data.shader,0))
		var target_index: int = _frame % pass_data.outputs.size()
		_rd.capture_timestamp("NTSCRT/pass%d/begin" % index)
		var list := _rd.draw_list_begin(pass_data.framebuffers[target_index])
		_rd.draw_list_bind_render_pipeline(list,pass_data.pipeline)
		_rd.draw_list_bind_vertex_array(list,_vertex_array)
		_rd.draw_list_bind_uniform_set(list,_uniform_sets[cache_key],0)
		_rd.draw_list_draw(list,false,1)
		_rd.draw_list_end()
		_generate_mips(pass_data.outputs[target_index])
		_rd.capture_timestamp("NTSCRT/pass%d/end" % index)
		previous = pass_data.outputs[target_index]
		previous_size = pass_extents[index]
		var reference := {"texture":previous,"size":previous_size}
		resources["PassOutput%d" % index] = reference
		if description.options.has("alias"): resources[description.options.alias] = reference
	output = previous
	_frame += 1
	return output

func _buffer_data(info: Dictionary, resources: Dictionary, extent: Vector2i, options: Dictionary) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(int(info.size))
	for field in info.fields:
		var offset := int(field.offset)
		var name := str(field.name)
		match field.type:
			"mat4":
				for diagonal in 4: bytes.encode_float(offset+diagonal*20,1.0)
			"vec4":
				var size := extent
				if name != "OutputSize":
					var resource_name := name.trim_suffix("Size")
					if resources.has(resource_name): size = resources[resource_name].size
					else: _fail("Unresolved size " + name)
				bytes.encode_float(offset,float(size.x))
				bytes.encode_float(offset+4,float(size.y))
				bytes.encode_float(offset+8,1.0/maxi(1,size.x))
				bytes.encode_float(offset+12,1.0/maxi(1,size.y))
			"uint", "int":
				var value := _frame if name == "FrameCount" else int(parameters.get(name,0))
				var modulo := int(options.get("frame_count_mod",0))
				if name == "FrameCount" and modulo > 0: value %= modulo
				bytes.encode_u32(offset,value)
			"float": bytes.encode_float(offset,float(parameters.get(name,0.0)))
	return bytes

func _pass_size(options: Dictionary, previous: Vector2i, last: bool) -> Vector2i:
	var result := Vector2i.ZERO
	for axis in 2:
		var suffix := "_x" if axis == 0 else "_y"
		var kind := str(options.get("scale_type"+suffix,options.get("scale_type","viewport" if last else "source")))
		var scale := float(options.get("scale"+suffix,options.get("scale",1.0)))
		var base := 1.0 if kind == "absolute" else float(output_size[axis] if kind == "viewport" else previous[axis])
		result[axis] = maxi(1,int(floor(base*scale)))
	return result

func _format(description: Dictionary) -> int:
	var name := str(description.format)
	if name == "R16G16B16A16_SFLOAT" or description.options.get("float_framebuffer","false") == "true": return RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	if name == "R8G8B8A8_SRGB" or description.options.get("srgb_framebuffer","false") == "true": return RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB
	return RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM

func _target(extent: Vector2i, data_format: int, mipmaps := false, storage := false) -> RID:
	var format := RDTextureFormat.new()
	format.width = extent.x
	format.height = extent.y
	format.format = data_format
	if mipmaps: format.mipmaps = int(floor(log(float(maxi(extent.x,extent.y)))/log(2.0)))+1
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	if storage: format.usage_bits |= RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	var texture := _own(_rd.texture_create(format,RDTextureView.new()))
	if mipmaps:
		var levels: Array[Dictionary] = []
		for level in format.mipmaps:
			var view := _own(_rd.texture_create_shared_from_slice(RDTextureView.new(),texture,0,level))
			var framebuffer := _own(_rd.framebuffer_create([view]))
			var framebuffer_format := _rd.framebuffer_get_format(framebuffer)
			if not _mip_pipelines.has(framebuffer_format):
				var blend := RDPipelineColorBlendState.new()
				blend.attachments = [RDPipelineColorBlendStateAttachment.new()]
				_mip_pipelines[framebuffer_format] = _own(_rd.render_pipeline_create(_mip_shader,framebuffer_format,RenderingDevice.INVALID_ID,
					RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,RDPipelineRasterizationState.new(),RDPipelineMultisampleState.new(),RDPipelineDepthStencilState.new(),blend))
			var entry := {"view":view,"framebuffer":framebuffer,"pipeline":_mip_pipelines[framebuffer_format]}
			if level > 0:
				var uniform := RDUniform.new()
				uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
				uniform.binding = 0
				uniform.add_id(_sampler(true,"clamp_to_edge",false))
				uniform.add_id(levels[level-1].view)
				entry.uniforms = _own_set(_rd.uniform_set_create([uniform],_mip_shader,0))
			levels.append(entry)
		_mip_targets[texture.get_id()] = levels
	return texture

func _generate_mips(texture: RID) -> void:
	if not _mip_targets.has(texture.get_id()): return
	var levels: Array = _mip_targets[texture.get_id()]
	for level in range(1,levels.size()):
		var entry: Dictionary = levels[level]
		var list := _rd.draw_list_begin(entry.framebuffer)
		_rd.draw_list_bind_render_pipeline(list,entry.pipeline)
		_rd.draw_list_bind_uniform_set(list,entry.uniforms,0)
		_rd.draw_list_draw(list,false,1,3)
		_rd.draw_list_end()

func _sampler(linear: bool, wrap: String, mipmap: bool) -> RID:
	var key := str([linear,wrap,mipmap])
	if _samplers.has(key): return _samplers[key]
	var state := RDSamplerState.new()
	state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR if linear else RenderingDevice.SAMPLER_FILTER_NEAREST
	state.mag_filter = state.min_filter
	state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR if mipmap else RenderingDevice.SAMPLER_FILTER_NEAREST
	state.max_lod = 1000.0 if mipmap else 0.0
	state.repeat_u = {"repeat":RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT,"mirrored_repeat":RenderingDevice.SAMPLER_REPEAT_MODE_MIRRORED_REPEAT,"clamp_to_edge":RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE}.get(wrap,RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_BORDER)
	state.repeat_v = state.repeat_u
	var sampler := _own(_rd.sampler_create(state))
	_samplers[key] = sampler
	return sampler

func _fail(message: String) -> bool:
	error = message
	push_error("NTSCRT Slang: " + message)
	return false

func dispose() -> void:
	for index in range(_owned.size()-1,-1,-1):
		var rid := _owned[index]
		# Input viewport reallocations invalidate dependent sets automatically.
		if _set_ids.has(rid.get_id()) and not _rd.uniform_set_is_valid(rid): continue
		if rid.is_valid(): _rd.free_rid(rid)
	_owned.clear()
	_passes.clear()
	_textures.clear()
	_uniform_sets.clear()
	_set_ids.clear()
	_samplers.clear()
	_mip_targets.clear()
	_mip_pipelines.clear()
	output = RID()
