class_name NtscrtEffect
extends Control
## Add content to get_source_viewport(); keep crisp menus in a sibling CanvasLayer.
signal renderer_error(message: String)
const PROFILE = preload("res://addons/ntscrt/profile.gd")
const PRESENTER = preload("res://addons/ntscrt/internal/ntscrt_gpu_presenter.gd")
const SEQUENCES = preload("res://addons/ntscrt/internal/ntscrt_glitch_sequences.gd")
enum Fault { TRACKING, COLOR_UNLOCK, DROPOUT, RF_STATIC, SYNC_SLIP }

@export var profile: NtscrtProfile:
	set(value):
		if profile!=null and profile.changed.is_connected(_queue_configuration):
			profile.changed.disconnect(_queue_configuration)
		profile = value
		if profile!=null: profile.changed.connect(_queue_configuration)
		_queue_configuration()

var source: SubViewport
var presenter: TextureRect
var _container: SubViewportContainer
var _grain: ColorRect
var _configuration_pending := false
var _base_signal: Dictionary = {}
var _fault: Dictionary = {}
var _fault_elapsed := 0.0
var _fault_duration := 0.0
var _entity := {"entity_x":0.5,"entity_y":0.5,"entity_radius":0.0,"entity_amount":0.0}
var _reported_error := ""
var _supported := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_PASS
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_container)
	source = SubViewport.new()
	source.name = "RecordedContent"
	source.own_world_3d = true
	source.use_hdr_2d = get_viewport().use_hdr_2d
	source.audio_listener_enable_3d = true
	source.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_container.add_child(source)
	var grain_layer := CanvasLayer.new()
	grain_layer.layer = 128
	source.add_child(grain_layer)
	_grain = ColorRect.new()
	_grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var grain_material := ShaderMaterial.new()
	grain_material.shader = preload("res://addons/ntscrt/shaders/film_grain.gdshader")
	_grain.material = grain_material
	grain_layer.add_child(_grain)
	source.size_changed.connect(_resize_world)
	_supported = RenderingServer.get_rendering_device()!=null
	if _supported:
		presenter = PRESENTER.new()
		presenter.source = source
		presenter.visible = false
		add_child(presenter)
	else:
		_reported_error = "NTSCRT requires Godot's Forward+ or Mobile renderer. Showing unfiltered content."
		renderer_error.emit(_reported_error)
	if profile==null: profile = PROFILE.new()
	SEQUENCES.prepare()
	_apply_configuration()

func get_source_viewport() -> SubViewport:
	return source

func add_content(content: Node) -> void:
	assert(source!=null,"Add NtscrtEffect to the scene tree before adding content.")
	assert(content.get_parent()==null,"Add a fresh scene; do not reparent a running game.")
	source.add_child(content)

func is_supported() -> bool:
	return _supported

func get_error() -> String:
	return presenter.last_error if presenter!=null and not presenter.last_error.is_empty() else _reported_error

func _queue_configuration() -> void:
	if not is_node_ready() or _configuration_pending: return
	_configuration_pending = true
	_apply_configuration.call_deferred()

func _apply_configuration() -> void:
	_configuration_pending = false
	if source==null or profile==null: return
	_resize_world()
	_grain.visible = _supported and (profile.film_grain>0.0 or profile.color_saturation!=1.0 or profile.color_temperature!=0.0 or profile.color_shadow_lift>0.0)
	(_grain.material as ShaderMaterial).set_shader_parameter("intensity",profile.film_grain)
	(_grain.material as ShaderMaterial).set_shader_parameter("color_saturation",profile.color_saturation)
	(_grain.material as ShaderMaterial).set_shader_parameter("color_temperature",profile.color_temperature)
	(_grain.material as ShaderMaterial).set_shader_parameter("color_shadow_lift",profile.color_shadow_lift)
	(_grain.material as ShaderMaterial).set_shader_parameter("linear_source",source.use_hdr_2d)
	if presenter==null: return
	presenter.visible = profile.tape!=PROFILE.Tape.OFF or profile.crt_enabled or profile.receiver_enabled
	presenter.signal_enabled = profile.tape!=PROFILE.Tape.OFF
	presenter.receiver_enabled = profile.receiver_enabled
	presenter.configure_ambient_faults(profile.ambient_fault_rate,profile.ambient_fault_strength*profile.tape_damage*2.0,
		profile.ambient_fault_kind,profile.reduced_flashing or not presenter.signal_enabled)
	presenter.preset_name = profile.active_crt()
	presenter.parameters = profile.active_crt_parameters()
	presenter.signal_extent = PROFILE.SIGNAL_SIZES[profile.quality]
	presenter.output_height_limit = PROFILE.OUTPUT_HEIGHTS[profile.quality]
	presenter.signal_size_mode = profile.signal_size_mode
	presenter.signal_width = profile.signal_width
	presenter.downscale_method = profile.downscale_filter-1
	presenter.source_resolution = profile.source_resolution
	presenter.presentation_scale = profile.presentation_scale
	_base_signal = profile.signal_settings()
	presenter.signal_settings = _base_signal.duplicate(true)
	presenter.receiver_settings = profile.receiver_settings()
	if not presenter.signal_enabled or profile.reduced_flashing or profile.tape_damage<=0.0:
		clear_glitch()
	_update_signal(0.0)

func _resize_world() -> void:
	if source==null or profile==null: return
	if not profile.auto_world_resolution: return
	var height := 480.0 if profile.crt_enabled else (720.0 if profile.tape!=PROFILE.Tape.OFF or profile.receiver_enabled else 0.0)
	if height>0.0 and profile.quality==PROFILE.Quality.LOW: height = 360.0
	source.scaling_3d_scale = clampf(height/maxf(1.0,source.size.y),0.05,1.0) if height>0.0 else 1.0

## Procedural tape failure. Pausing this node pauses the cue; no automatic random events.
func trigger_fault(kind: Fault = Fault.TRACKING, duration := 0.3, strength := 1.0, origin := 0.6) -> void:
	if not is_finite(duration) or not is_finite(strength) or not is_finite(origin): return
	if profile==null or profile.tape==PROFILE.Tape.OFF or profile.reduced_flashing or profile.tape_damage<=0.0: return
	_fault = {"kind":clampi(kind,0,4),"strength":clampf(strength,0.0,1.0),"origin":clampf(origin,0.0,1.0),"sequence":""}
	_fault_elapsed = 0.0
	_fault_duration = maxf(duration,0.01)

## Adapted upstream animation identifiers: glitch_pop and two_blips.
func trigger_glitch(identifier := "glitch_pop", duration := 0.53, strength := 1.0) -> void:
	if identifier not in ["glitch_pop","two_blips"]: return
	trigger_fault(Fault.TRACKING,duration,strength)
	if not _fault.is_empty(): _fault["sequence"] = identifier

func clear_glitch() -> void:
	_fault.clear()
	_fault_duration = 0.0
	_fault_elapsed = 0.0
	if presenter!=null:
		presenter.signal_settings = _base_signal.duplicate(true)
		presenter.game_state = {}

## Optional local interference, independent of any enemy implementation.
func set_entity_interference(position: Vector2, radius: float, amount: float) -> void:
	_entity = {"entity_x":position.x,"entity_y":position.y,"entity_radius":maxf(radius,0.0),"entity_amount":clampf(amount,0.0,1.0)}

func _process(delta: float) -> void:
	_update_signal(delta)
	if presenter!=null and not presenter.last_error.is_empty() and presenter.last_error!=_reported_error:
		_reported_error = presenter.last_error
		renderer_error.emit(_reported_error)

func _update_signal(delta: float) -> void:
	if presenter==null or profile==null: return
	var state := _entity.duplicate()
	var allowed: bool = presenter.signal_enabled and not profile.reduced_flashing
	state["entity_amount"] = float(state.entity_amount)*profile.tape_damage*2.0 if allowed else 0.0
	state["field_index"] = floor(presenter._clock*60000.0/1001.0)
	if not _fault.is_empty():
		_fault_elapsed += delta
		var phase := clampf(_fault_elapsed/_fault_duration,0.0,1.0)
		if phase>=1.0 or not allowed:
			clear_glitch()
		else:
			var strength := float(_fault.strength)*profile.tape_damage*2.0
			state.merge({"fault_kind":float(_fault.kind),"fault_amount":minf(1.0,strength)*smoothstep(0.0,0.12,phase)*(1.0-smoothstep(0.25,1.0,phase)),"fault_phase":phase,"fault_origin":_fault.origin})
			var knobs := _base_signal.duplicate(true)
			SEQUENCES.apply_to(knobs,str(_fault.sequence),phase,strength)
			presenter.signal_settings = knobs
	presenter.game_state = state
