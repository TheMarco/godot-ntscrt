extends TextureRect
## Presents the world and gameplay HUD through the original CRT chain.
## A completed source frame is processed after drawing and shown on the next
## frame. This explicit one-frame history avoids sampling our own presentation.
const CHAIN = preload("res://addons/ntscrt/internal/ntscrt_slang_chain.gd")
const SCALER = preload("res://addons/ntscrt/internal/ntscrt_preview_scaler.gd")
var source: SubViewport
var preset_name := "aperture"
var signal_extent := Vector2i(720,480)
var signal_size_mode := 0
var signal_width := 720
var downscale_method := -1
var source_resolution := false
var presentation_scale := 0
var output_height_limit := 0
var parameters: Dictionary = {}
var signal_enabled := false
var receiver_enabled := false
var signal_settings: Dictionary = {}
var receiver_settings: Dictionary = {}
var game_state: Dictionary = {}
var ready_frames := 0
var last_error := ""
var cpu_usec := 0
var timestamp_samples: Array[Dictionary] = []
var _presets: Dictionary
var _input_chain: RefCounted
var _crt_chain: RefCounted
var _signal_stage: RefCounted
var _receiver_stage: RefCounted
var _downscale_stage: RefCounted
var _texture: Texture2DRD
var _signature := ""
var _retired: Array[Dictionary] = []
var _running := false
var _clock := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_presets = CHAIN.load_presets()
	_presets["none"] = _preparation(false)
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
render_mode unshaded;
// Canvas TEXTURE automatically decodes UNORM colour in HDR viewports. Sample
// through an unhinted uniform so only the explicit conversion below runs.
uniform sampler2D video_texture : filter_linear, repeat_disable;
uniform bool encoded_output = true;
uniform bool linear_destination = true;
uniform vec2 display_fraction = vec2(1.0);
vec3 encode_srgb(vec3 value) {
    return mix(value*12.92,1.055*pow(max(value,vec3(0.0)),vec3(1.0/2.4))-0.055,step(vec3(0.0031308),value));
}
vec3 decode_srgb(vec3 value) {
    return mix(value/12.92,pow((max(value,vec3(0.0))+0.055)/1.055,vec3(2.4)),step(vec3(0.04045),value));
}
void fragment() {
    vec2 sample_uv=(UV-0.5)/display_fraction+0.5;
    vec4 sample_colour=texture(video_texture,clamp(sample_uv,vec2(0.0),vec2(1.0)));
    vec3 value=sample_colour.rgb;
    if (linear_destination && encoded_output) value=decode_srgb(value);
    if (!linear_destination && !encoded_output) value=encode_srgb(value);
    float inside=step(0.0,sample_uv.x)*step(sample_uv.x,1.0)*step(0.0,sample_uv.y)*step(sample_uv.y,1.0);
    COLOR=vec4(value*inside,1.0);
}"""
	var presentation := ShaderMaterial.new()
	presentation.shader = shader
	material = presentation
	presentation.set_shader_parameter("linear_destination",get_viewport().use_hdr_2d)
	_running = true
	RenderingServer.frame_post_draw.connect(_queue_frame)

func _process(delta: float) -> void:
	if is_visible_in_tree(): _clock += minf(delta,0.1)

func render_target_size(display: Vector2i, signal_size: Vector2i) -> Vector2i:
	var target := display
	if output_height_limit > 0 and target.y > output_height_limit:
		var scale := float(output_height_limit)/target.y
		target = Vector2i(maxi(1,roundi(target.x*scale)),output_height_limit)
	# Original CRT shaders require at least one output row per signal row.
	if preset_name != "none": target = Vector2i(maxi(target.x,signal_size.x),maxi(target.y,signal_size.y))
	return target

func _queue_frame() -> void:
	if not _running or not is_visible_in_tree() or not is_instance_valid(source) or not _presets.has(preset_name): return
	var display := Vector2i(size)
	if display.x < 1 or display.y < 1: return
	var signal_size := signal_extent
	if signal_size_mode == 1:
		signal_size = Vector2i(signal_width,maxi(16,2*roundi(float(signal_width)*source.size.y/maxi(1,source.size.x)/2.0)))
	elif signal_size_mode == 2: signal_size = source.size
	var target := render_target_size(display,signal_size)
	var shown := display
	# Explicit developer supersampling/integer-fit requests retain their sizing.
	if presentation_scale > 0:
		var plan := SCALER.plan(signal_size,display,presentation_scale == 2)
		target = plan.render_size
		shown = plan.display_size
	(material as ShaderMaterial).set_shader_parameter("display_fraction",Vector2(shown)/Vector2(display))
	RenderingServer.call_on_render_thread(_render_frame.bind(source.get_texture().get_rid(),source.size,source.use_hdr_2d,
		target,signal_size,preset_name,parameters.duplicate(),signal_enabled,receiver_enabled,
		signal_settings.duplicate(),receiver_settings.duplicate(),int(_clock*60000.0/1001.0),game_state.duplicate(),source_resolution,downscale_method))

func _render_frame(source_texture: RID, extent: Vector2i, linear: bool, display: Vector2i, signal_size: Vector2i, selected: String, knobs: Dictionary,
		use_signal: bool, use_receiver: bool, signal_knobs: Dictionary, receiver_knobs: Dictionary, field: int, state: Dictionary, source_first: bool, filter_method: int) -> void:
	if not _running: return
	var started := Time.get_ticks_usec()
	var rd := RenderingServer.get_rendering_device()
	if rd == null: return
	var input := RenderingServer.texture_get_rd_texture(source_texture)
	if not input.is_valid(): return
	source_first = source_first and use_signal
	var prepared_size := extent if source_first or filter_method >= 0 else signal_size
	var signal_work_size := extent if source_first else signal_size
	var signature := str([extent,linear,display,signal_size,selected,use_signal,use_receiver,source_first,prepared_size])
	if signature != _signature:
		var prepared := CHAIN.new()
		var crt := CHAIN.new()
		var signal_stage: RefCounted = load("res://addons/ntscrt/internal/ntscrs_gpu.gd").new() if use_signal else null
		var receiver_stage: RefCounted = load("res://addons/ntscrt/internal/ntscrt_receiver_gpu.gd").new() if use_receiver else null
		var downscale_stage: RefCounted = load("res://addons/ntscrt/internal/ntscrt_downscale_gpu.gd").new() if prepared_size != signal_size else null
		var bundle := {"input":prepared,"signal":signal_stage,"receiver":receiver_stage,"crt":crt,"downscale":downscale_stage,"age":0}
		var valid := prepared.setup(rd,_preparation(linear),extent,prepared_size) and crt.setup(rd,_presets[selected],signal_size,display)
		if valid and signal_stage != null: valid = signal_stage.setup(rd,signal_work_size)
		if valid and receiver_stage != null: valid = receiver_stage.setup(rd,signal_size)
		if valid and downscale_stage != null: valid = downscale_stage.setup(rd,prepared_size,signal_size)
		if not valid:
			last_error = prepared.error + crt.error + (signal_stage.error if signal_stage != null else "") + (receiver_stage.error if receiver_stage != null else "") + (downscale_stage.error if downscale_stage != null else "")
			_dispose_bundle(bundle)
			return
		if _input_chain != null: _retired.append({"input":_input_chain,"signal":_signal_stage,"receiver":_receiver_stage,"crt":_crt_chain,"downscale":_downscale_stage,"age":0})
		_input_chain = prepared
		_crt_chain = crt
		_signal_stage = signal_stage
		_receiver_stage = receiver_stage
		_downscale_stage = downscale_stage
		_signature = signature
		last_error = ""
		# The unhinted canvas sampler uses the raw view, including for sRGB
		# render targets. Every final preset stores display-encoded RGB.
		_publish.call_deferred(_crt_chain.output,true)
	var prepared: RID = _input_chain.render(input,state if use_signal else {})
	if _downscale_stage != null and not source_first: prepared = _downscale_stage.render(prepared,maxi(0,filter_method))
	if _signal_stage != null: prepared = _signal_stage.render(prepared,field,signal_knobs)
	if _downscale_stage != null and source_first: prepared = _downscale_stage.render(prepared,filter_method if filter_method >= 0 else 2)
	if not prepared.is_valid():
		last_error = "Signal stage did not produce a texture"
		return
	if _receiver_stage != null: prepared = _receiver_stage.render(prepared,field,receiver_knobs)
	if not prepared.is_valid():
		last_error = "Receiver stage did not produce a texture"
		return
	_crt_chain.render(prepared,knobs)
	ready_frames += 1
	cpu_usec = Time.get_ticks_usec()-started
	# The render server consumes deferred Texture2DRD changes before these old
	# allocations are retired. Keep two frames for queued canvas references.
	for entry in _retired: entry.age += 1
	while not _retired.is_empty() and int(_retired[0].age) >= 3:
		var entry: Dictionary = _retired.pop_front()
		_dispose_bundle(entry)
	var sample := {}
	for index in rd.get_captured_timestamps_count():
		var label := rd.get_captured_timestamp_name(index)
		if label.begins_with("NTSCRT/"): sample[label] = rd.get_captured_timestamp_gpu_time(index)
	if not sample.is_empty():
		timestamp_samples.append(sample)
		if timestamp_samples.size() > 300: timestamp_samples.pop_front()

func _publish(texture_rid: RID, encoded: bool) -> void:
	if not _running: return
	_texture = Texture2DRD.new()
	_texture.texture_rd_rid = texture_rid
	texture = _texture
	(material as ShaderMaterial).set_shader_parameter("video_texture",_texture)
	(material as ShaderMaterial).set_shader_parameter("encoded_output",encoded)

static func _preparation(linear: bool) -> Dictionary:
	return {"parameters":{"entity_x":{"default":0.5},"entity_y":{"default":0.5},"entity_radius":{"default":0.0},"entity_amount":{"default":0.0},"field_index":{"default":0.0},"fault_kind":{"default":0.0},"fault_amount":{"default":0.0},"fault_phase":{"default":0.0},"fault_origin":{"default":0.5}},"textures":{},"passes":[{
		"path":"game frame to SDR signal", "format":"R8G8B8A8_UNORM", "options":{"scale_type":"viewport","filter_linear":"true","storage_output":"true"},
		"bindings":{"0":{"kind":"sampler","name":"Source"},"1":{"kind":"buffer","name":"params","size":64,"fields":[
			{"name":"OutputSize","type":"vec4","offset":0},{"name":"entity_x","type":"float","offset":16},{"name":"entity_y","type":"float","offset":20},
			{"name":"entity_radius","type":"float","offset":24},{"name":"entity_amount","type":"float","offset":28},{"name":"field_index","type":"float","offset":32},
			{"name":"fault_kind","type":"float","offset":36},{"name":"fault_amount","type":"float","offset":40},{"name":"fault_phase","type":"float","offset":44},{"name":"fault_origin","type":"float","offset":48}]}},
		"vertex":"""#version 450
layout(location=0) in vec4 Position;
layout(location=1) in vec2 TexCoord;
layout(location=0) out vec2 uv;
void main() { gl_Position=Position; uv=TexCoord; }
""",
		"fragment":"""#version 450
layout(location=0) in vec2 uv;
layout(location=0) out vec4 colour;
layout(set=0,binding=0) uniform sampler2D Source;
layout(std140,set=0,binding=1) uniform Params { vec4 OutputSize; float entity_x; float entity_y; float entity_radius; float entity_amount; float field_index; float fault_kind; float fault_amount; float fault_phase; float fault_origin; } params;
vec3 encode_srgb(vec3 value) {
    return mix(value*12.92,1.055*pow(max(value,vec3(0.0)),vec3(1.0/2.4))-0.055,step(vec3(0.0031308),value));
}
float fault_hash(vec2 p) {
    vec3 q=fract(vec3(p.xyx)*0.1031); q+=dot(q,q.yzx+33.33);
    return fract((q.x+q.y)*q.z);
}
float fault_noise(uvec2 pixel, uint field) {
    // Hash the field independently: adding it to both pixel coordinates
    // translates a fixed noise sheet diagonally instead of refreshing static.
    uvec3 value=uvec3(pixel,field)*1664525u+1013904223u;
    value.x+=value.y*value.z; value.y+=value.z*value.x; value.z+=value.x*value.y;
    value^=value>>16u;
    value.x+=value.y*value.z; value.y+=value.z*value.x; value.z+=value.x*value.y;
    return float(value.x>>8u)*(1.0/16777216.0);
}
void main() {
    float halo=(1.0-smoothstep(params.entity_radius*0.3,max(params.entity_radius,0.001),length((uv-vec2(params.entity_x,params.entity_y))*vec2(1.5,1.0))))*params.entity_amount;
    float jitter=fract(sin(dot(vec2(floor(uv.y*params.OutputSize.y),params.field_index),vec2(12.9898,78.233)))*43758.5453)-0.5;
    vec2 sample_uv=uv+vec2(jitter*halo*5.0*params.OutputSize.z,0.0);
    float strength=params.fault_amount;
    int kind=int(params.fault_kind+0.5);
    float band=0.0;
    float grain=0.0;
    float row=floor(uv.y*params.OutputSize.y);
    if(strength>0.0) {
        float center=clamp(params.fault_origin+params.fault_phase*0.14,0.0,1.0);
        band=1.0-smoothstep(0.015,0.065,abs(uv.y-center));
        grain=fault_noise(uvec2(floor(uv.x*params.OutputSize.x),row),uint(params.field_index));
        if(kind==0 || kind==4) {
            sample_uv.x+=(jitter*0.075+0.025)*band*strength;
            if(kind==4) sample_uv.y+=sin(params.fault_phase*9.424778)*0.045*strength;
        }
    }
    vec3 value=texture(Source,clamp(sample_uv,vec2(0.0),vec2(1.0))).rgb;
    value=%s;
    if(strength>0.0) {
        float luma=dot(value,vec3(0.299,0.587,0.114));
        if(kind==0 || kind==4) {
            value=mix(value,vec3(grain*0.65),band*strength*0.75);
        } else if(kind==1) {
            value=mix(value,vec3(luma),strength);
        } else if(kind==2) {
            float line=fault_hash(vec2(floor(row/2.0),params.field_index));
            float start=fault_hash(vec2(floor(row/2.0)+41.0,params.field_index));
            float strip=step(0.86,line)*step(start,uv.x)*step(uv.x,start+0.12);
            value=mix(value,vec3(grain*0.75),strength*max(strip,band*0.45));
        } else if(kind==3) {
            value=mix(value,vec3(grain*0.7),strength*0.6);
        }
    }
    colour=vec4(value,1.0);
}
""" % ("encode_srgb(value)" if linear else "value")}]}

func _exit_tree() -> void:
	_running = false
	if RenderingServer.frame_post_draw.is_connected(_queue_frame): RenderingServer.frame_post_draw.disconnect(_queue_frame)
	(material as ShaderMaterial).set_shader_parameter("video_texture",null)
	texture = null
	_texture = null
	RenderingServer.call_on_render_thread(_dispose)

func _dispose() -> void:
	_dispose_bundle({"input":_input_chain,"signal":_signal_stage,"receiver":_receiver_stage,"crt":_crt_chain,"downscale":_downscale_stage})
	_input_chain = null
	_crt_chain = null
	_signal_stage = null
	_receiver_stage = null
	_downscale_stage = null
	for entry in _retired:
		_dispose_bundle(entry)
	_retired.clear()

func _dispose_bundle(bundle: Dictionary) -> void:
	for key in ["crt","receiver","signal","downscale","input"]:
		if bundle.get(key) != null: bundle[key].dispose()
