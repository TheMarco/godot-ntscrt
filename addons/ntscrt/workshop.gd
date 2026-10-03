extends Control
const PROFILE = preload("res://addons/ntscrt/profile.gd")
const PRESETS = preload("res://addons/ntscrt/preset_io.gd")
const LIBRARY = preload("res://addons/ntscrt/preset_library.gd")
const FULL_CONTROLS = preload("res://addons/ntscrt/internal/ntscrt_full_controls.gd")
const PANEL_WIDTH := 440
const PRESET_DIRECTORY := "user://presets"
const MODEL_TITLES := ["Automatic (follows budget)","Aperture","EasyMode","Glow Gaussian","Glow Lanczos","Hyllian","Royale","Crtsim"]
## Host callbacks keep this editor independent of game ownership and rendering.
var apply_profile: Callable
var capture_image: Callable
var capture_context: Callable
var restore_context: Callable
var renderer_error: Callable
var play_glitch: Callable
var preview_damage: Callable
var _damage_preview: Button
var select_test_image: Callable
## Optional demo-owned source/playback controls, shown above the look browser.
var build_source_controls: Callable
var allow_close := false
signal closed
var profile: NtscrtProfile
var _reference: NtscrtProfile
var _reference_name := ""
var _editing_name := ""
var _loaded_context: Dictionary = {}
var _reference_context: Dictionary = {}
var _editing_context: Dictionary = {}
var _showing_reference := false
var _capturing := false
var _status: Label
var _message: Label
var _name: LineEdit
var _compare: Button
var _capture_button: Button
var _tabs: TabContainer
var _load_dialog: FileDialog
var _fixture: OptionButton
var _recording_toggle: CheckButton
var _last_tape := 1
var _controls: Dictionary = {}
var _signal_controls: VBoxContainer
var _crt_rows: VBoxContainer
var _crt_title: Label
var _crt_controls: Dictionary = {}
var _crt_model := ""
var _crt_filter: LineEdit
var _library_select: OptionButton
var _library_index := -1
var _look_description: Label
var _look_route: Label
var _fine_tune: CheckButton
var _browser_space: Control
var _library_snapshot: Dictionary = {}
var _browse_buttons: Array[Button] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if profile==null: profile = PROFILE.new()
	_build_ui()
	_library_index = LIBRARY.matching_index(profile)
	if _library_index>=0:
		_library_select.select(_library_index+1)
		_name.text = LIBRARY.LOOKS[_library_index].name
		_library_snapshot = PRESETS.encode(profile).settings
	profile.changed.connect(_refresh)
	_refresh()

func close() -> void:
	if _capturing: return
	if _showing_reference: show_reference(false)
	closed.emit()

func _apply_visible() -> void:
	if apply_profile.is_valid(): apply_profile.call(_visible_profile())

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -PANEL_WIDTH
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.045,0.055,0.07,1.0)
	panel.add_theme_stylebox_override("panel",background)
	add_child(panel)
	var margin := MarginContainer.new()
	for edge in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+edge,16)
	panel.add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation",8)
	margin.add_child(rows)
	var heading := _row(rows)
	_label(heading,"CHOOSE A LOOK",21).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if allow_close: _button(heading,"Done",close).size_flags_horizontal = 0
	if build_source_controls.is_valid(): build_source_controls.call(rows)
	var browser := _row(rows)
	var previous := _button(browser,"‹",func(): _cycle_look(-1))
	previous.size_flags_horizontal = 0
	previous.tooltip_text = "Previous look"
	_library_select = OptionButton.new()
	_library_select.fit_to_longest_item = false
	_library_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_library_select.add_item("Current look / loaded preset")
	for index in LIBRARY.LOOKS.size():
		_library_select.add_item("%02d  %s" % [index+1,LIBRARY.LOOKS[index].name])
	_library_select.item_selected.connect(func(index: int):
		if index>0: select_curated(index-1))
	browser.add_child(_library_select)
	var next := _button(browser,"›",func(): _cycle_look(1))
	next.size_flags_horizontal = 0
	next.tooltip_text = "Next look"
	_browse_buttons.assign([previous,next])
	_look_description = _note(rows,"Browse 20 camera, tape and TV looks with the arrows. Choose a favorite, then Capture preset to save it.")
	_look_route = _note(rows,"Browsing keeps your graphics budget and reduced-flashing preference.")
	_damage_preview = _button(rows,"Preview this look's tape damage",func():
		if preview_damage.is_valid(): preview_damage.call())
	_name = LineEdit.new()
	_name.placeholder_text = "Preset name"
	_name.text = "My recording look"
	rows.add_child(_name)
	var save_row := _row(rows)
	_capture_button = _button(save_row,"Capture preset",func(): await capture_preset())
	_button(save_row,"Load preset…",_choose_preset)
	var share_row := _row(rows)
	_button(share_row,"Open captures",_open_captures)
	_button(share_row,"Copy JSON",func():
		DisplayServer.clipboard_set(JSON.stringify(PRESETS.encode(_visible_profile(),_visible_name(),_capture_context()),"\t"))
		_message.text = "Visible look copied as preset JSON.")
	var compare_row := _row(rows)
	_button(compare_row,"Keep as A",store_reference)
	_compare = _button(compare_row,"Show A",func(): show_reference(not _showing_reference))
	_compare.disabled = true
	_message = _note(rows,"Capture saves JSON + a Godot .tres + a preview PNG.")
	_message.custom_minimum_size.y = 38
	_fine_tune = CheckButton.new()
	_fine_tune.text = "Fine-tune this look"
	_fine_tune.toggled.connect(func(_enabled: bool): _sync_editor_visibility())
	rows.add_child(_fine_tune)
	_browser_space = Control.new()
	_browser_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(_browser_space)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(_tabs)
	_build_look(_tab("Look"))
	_build_crt(_tab("CRT tuning"))
	_build_signal(_tab("Signal"))
	_build_output(_tab("Output"))
	_sync_editor_visibility()
	_status = _note(rows,"")
	_load_dialog = FileDialog.new()
	_load_dialog.title = "Load NTSCRT preset"
	_load_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_load_dialog.add_filter("*.json","NTSCRT preset")
	_load_dialog.file_selected.connect(load_preset)
	add_child(_load_dialog)

func _build_look(rows: VBoxContainer) -> void:
	if select_test_image.is_valid():
		_fixture = _options(rows,"Test image",["TV test card","Animated chart"])
		_fixture.item_selected.connect(func(index: int): select_test_image.call(index==0))
	_toggle(rows,"crt_enabled","CRT screen")
	_label(rows,"CRT model")
	var models := _row(rows)
	_button(models,"‹",func(): _cycle_model(-1)).size_flags_horizontal = 0
	var select := OptionButton.new()
	select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select.fit_to_longest_item = false
	for title in MODEL_TITLES: select.add_item(title)
	select.item_selected.connect(func(index: int): profile.crt_model=index)
	models.add_child(select)
	_controls.crt_model = select
	_button(models,"›",func(): _cycle_model(1)).size_flags_horizontal = 0
	_note(rows,"Arrows cycle the seven CRTs. Switch Recording effects off to judge just the CRT. Automatic uses Aperture on Low/Medium and Royale on High/Ultra. Fine-tune on the CRT tuning tab.")
	_recording_toggle = CheckButton.new()
	_recording_toggle.text = "Recording effects"
	_recording_toggle.toggled.connect(func(on: bool):
		profile.tape = _last_tape if on else PROFILE.Tape.OFF)
	rows.add_child(_recording_toggle)
	_note(rows,"Bypass tape softness and damage without resetting this look. CRT, camera color and grain stay as configured.")
	_number(rows,"tape_damage","Tape damage",0,1,0.01)
	_number(rows,"film_grain","Grain / sensor noise",0,1,0.01)
	_number(rows,"color_saturation","Camera color saturation",0,1.5,0.01)
	_number(rows,"color_temperature","White balance: cool / warm",-1,1,0.01)
	_number(rows,"color_shadow_lift","Shadow detail lift",0,0.12,0.001)
	_number(rows,"ambient_fault_rate","Brief defects per minute",0,20,0.5)
	_number(rows,"ambient_fault_strength","Defect strength",0,1,0.01)
	_choice(rows,"ambient_fault_kind","Defect type",["Tracking","Color unlock","Dropout","RF static","Sync slip"])
	_choice(rows,"quality","Graphics budget",["Low","Medium","High","Ultra"])
	_toggle(rows,"reduced_flashing","Reduced flashing")
	var cues := _row(rows)
	_button(cues,"Glitch pop",func(): _play_glitch("glitch_pop",0.53))
	_button(cues,"Two blips",func(): _play_glitch("two_blips",1.1))
	_note(rows,"Cues need tape and nonzero damage. Reduced flashing suppresses them. Captures save the look with any active cue cleared.")

func _build_crt(rows: VBoxContainer) -> void:
	_crt_title = _label(rows,"")
	_note(rows,"Original shader controls. Hover a value for its parameter name and range. Values are kept separately for each CRT model.")
	_button(rows,"Reset this CRT's tuning",func():
		var values := profile.crt_parameters.duplicate(true)
		values.erase(profile.selected_crt_model())
		profile.crt_parameters = values)
	_crt_filter = LineEdit.new()
	_crt_filter.placeholder_text = "Find a CRT setting…"
	_crt_filter.text_changed.connect(func(_text: String): _filter_crt())
	rows.add_child(_crt_filter)
	_crt_rows = VBoxContainer.new()
	_crt_rows.add_theme_constant_override("separation",12)
	rows.add_child(_crt_rows)

func _build_signal(rows: VBoxContainer) -> void:
	_toggle(rows,"receiver_enabled","Receiver simulation")
	_toggle(rows,"receiver_tape_coupling","Scale receiver wear with tape damage")
	_note(rows,"NTSC controls apply when tape is on; receiver controls need the switch above. Tape damage scales noise and wear after these values. Receiver timing can add CPU cost.")
	_signal_controls = FULL_CONTROLS.new()
	rows.add_child(_signal_controls)
	_signal_controls.setup()
	_signal_controls.value_changed.connect(func(engine: String,key: String,value: Variant):
		var values := profile.ntsc_overrides.duplicate() if engine=="ntscrs" else profile.receiver_overrides.duplicate()
		values[key] = value
		if engine=="ntscrs": profile.ntsc_overrides=values
		else: profile.receiver_overrides=values)

func _build_output(rows: VBoxContainer) -> void:
	_note(rows,"These settings change processing cost and the detail that reaches the CRT. They are included in your preset.")
	_choice(rows,"signal_size_mode","Signal resolution",["Automatic (graphics budget)","Custom width","Source size"])
	_number(rows,"signal_width","Custom signal width",16,4096,2)
	_choice(rows,"downscale_filter","Resize filter",["Fast bilinear","Nearest","Nearest+","Bilinear","Bicubic","Lanczos3","Area"])
	_choice(rows,"presentation_scale","Output sizing",["Graphics budget","Original supersampling","Original integer fit"])
	_toggle(rows,"source_resolution","Process tape at full source resolution")
	_note(rows,"Full-source processing and supersampling can be expensive. Custom width is usually the better tuning starting point.")
	_toggle(rows,"field_history","Blend previous video field")
	_toggle(rows,"auto_world_resolution","Automatically lower 3D resolution")
	_note(rows,"The 3D option affects game content, not this 2D test chart. Reduced flashing disables previous-field history.")

func _refresh() -> void:
	for key: String in _controls:
		var control: Control = _controls[key]
		var value: Variant = profile.get(key)
		if control is CheckButton: control.set_pressed_no_signal(value)
		elif control is OptionButton: control.select(int(value))
		elif control is SpinBox: control.set_value_no_signal(float(value))
	if profile.tape!=PROFILE.Tape.OFF: _last_tape = profile.tape
	_recording_toggle.set_pressed_no_signal(profile.tape!=PROFILE.Tape.OFF)
	_controls.tape_damage.editable = profile.tape!=PROFILE.Tape.OFF
	_controls.signal_width.editable = profile.signal_size_mode==1
	_signal_controls.refresh(profile.canonical_ntsc_settings(),PROFILE.SETTINGS.sanitize_receiver(profile.receiver_overrides))
	_refresh_crt()
	_refresh_library_description()
	_apply_visible()

func _play_glitch(identifier: String,duration: float) -> void:
	if play_glitch.is_valid(): play_glitch.call(identifier,duration)

func _refresh_crt() -> void:
	var model := profile.selected_crt_model()
	_crt_title.text = "%s tuning%s" % [MODEL_TITLES[PROFILE.CRT_NAMES.find(model)]," · CRT off" if not profile.crt_enabled else ""]
	if model!=_crt_model:
		_crt_model = model
		_crt_controls.clear()
		for child in _crt_rows.get_children():
			_crt_rows.remove_child(child)
			child.queue_free()
		var descriptors := PROFILE.crt_descriptors(model)
		for key: String in descriptors:
			var descriptor: Dictionary = descriptors[key]
			# Hyllian's zero-width parameters are headings rather than knobs.
			if float(descriptor.min)==float(descriptor.max): continue
			var box := VBoxContainer.new()
			_crt_rows.add_child(box)
			_label(box,str(descriptor.label).strip_edges())
			var number := SpinBox.new()
			number.min_value = float(descriptor.min)
			number.max_value = float(descriptor.max)
			number.step = maxf(0.000001,float(descriptor.step))
			number.tooltip_text = "%s\nRange %s … %s · upstream default %s" % [key,descriptor.min,descriptor.max,descriptor.default]
			box.add_child(number)
			number.value_changed.connect(func(value: float):
				var values := profile.crt_parameters.duplicate(true)
				var knobs: Dictionary = values.get(model,{}).duplicate()
				knobs[key] = value
				values[model] = knobs
				profile.crt_parameters = values)
			_crt_controls[key] = number
		_filter_crt()
	var values := profile.canonical_crt_parameters(model)
	for key: String in _crt_controls: _crt_controls[key].set_value_no_signal(values[key])

func _filter_crt() -> void:
	var query := _crt_filter.text.strip_edges().to_lower()
	var descriptors := PROFILE.crt_descriptors(_crt_model)
	for key: String in _crt_controls:
		_crt_controls[key].get_parent().visible = query.is_empty() or query in (key+" "+str(descriptors[key].label)).to_lower()

func _cycle_model(direction: int) -> void:
	var index := PROFILE.CRT_NAMES.find(profile.selected_crt_model())
	profile.crt_model = wrapi(index+direction,1,8)

func store_reference() -> void:
	_reference_context = _capture_context()
	_reference = _visible_profile().duplicate(true)
	_reference_name = _visible_name()
	_compare.disabled = false
	_message.text = "A stored: %s. Keep tuning B, then use Show A to compare." % _reference_name

func show_reference(enabled: bool) -> void:
	if enabled and not _showing_reference:
		_editing_name = _name.text
		_editing_context = _capture_context()
		if restore_context.is_valid(): restore_context.call(_reference_context)
	if not enabled and _showing_reference:
		_name.text = _editing_name
		if restore_context.is_valid(): restore_context.call(_editing_context)
	_showing_reference = enabled and _reference!=null
	if _showing_reference: _name.text = _reference_name
	_apply_visible()
	_sync_editor_visibility()
	_library_select.disabled = _showing_reference
	for button in _browse_buttons: button.disabled = _showing_reference
	_fine_tune.disabled = _showing_reference
	_name.editable = not _showing_reference
	_compare.text = "Back to B" if _showing_reference else "Show A"
	_refresh_library_description()
	if _showing_reference:
		_look_description.text = "Reference A: "+_reference_name
		_look_route.text = "CRT: "+_reference.active_crt()+". Back to B returns to the look you were browsing."
	_message.text = "Showing A: %s. Capture saves this reference look." % _reference_name if _showing_reference else "Editing B. Your A reference is unchanged."

func _visible_profile() -> NtscrtProfile:
	return _reference if _showing_reference else profile

func _visible_name() -> String:
	return _reference_name if _showing_reference else (_name.text.strip_edges() if not _name.text.strip_edges().is_empty() else "Untitled preset")

func _capture_context() -> Dictionary:
	var context := (_reference_context if _showing_reference else _loaded_context).duplicate(true)
	if capture_context.is_valid(): context.merge(capture_context.call(),true)
	context["resolved_crt"] = _visible_profile().active_crt()
	context["godot_version"] = Engine.get_version_info().string
	return context

## Hosts return the displayed picture without editor UI. Store complete base
## settings; output dimensions are context rather than a second application of wear.
func capture_preset(directory := "") -> Dictionary:
	if _capturing: return {"error":"A capture is already running."}
	if not capture_image.is_valid(): return {"error":"This host has no capture callback."}
	_capturing = true
	_capture_button.disabled = true
	var snapshot: NtscrtProfile = PRESETS.decode(PRESETS.encode(_visible_profile(),_visible_name())).profile
	var title := _visible_name()
	snapshot.resource_name = title
	var context := _capture_context()
	var old_mode := process_mode
	process_mode = Node.PROCESS_MODE_DISABLED
	if apply_profile.is_valid(): apply_profile.call(snapshot)
	var image: Image = await capture_image.call()
	process_mode = old_mode
	_apply_visible()
	var error: Error = ERR_CANT_CREATE
	var path := directory
	if path.is_empty():
		var slug := title.validate_filename().strip_edges().left(64)
		if slug.is_empty(): slug = "preset"
		path = PRESET_DIRECTORY.path_join("%s_%d" % [slug,int(Time.get_unix_time_from_system()*1000000)])
	if image!=null and not image.is_empty():
		context["png_width"] = image.get_width()
		context["png_height"] = image.get_height()
		error = DirAccess.make_dir_recursive_absolute(path)
		if error==OK: error = PRESETS.save_json(path.path_join("preset.json"),snapshot,title,context)
		if error==OK: error = ResourceSaver.save(snapshot,path.path_join("preset.tres"))
		if error==OK: error = image.save_png(path.path_join("preview.png"))
	_capturing = false
	_capture_button.disabled = false
	var absolute := ProjectSettings.globalize_path(path)
	_message.text = "Captured: %s. Use Open captures to find the three files." % title if error==OK else "Capture failed: %s. Check %s for partial files." % [error_string(error),absolute]
	return {"error":"" if error==OK else error_string(error),"directory":absolute,
		"image_size":image.get_size() if image!=null else Vector2i.ZERO}

func load_preset(path: String) -> void:
	var result := PRESETS.load_json(path)
	if not result.error.is_empty():
		_message.text = result.error
		return
	_library_index = -1
	_library_select.select(0)
	_replace_profile(result.profile,result.name)
	_loaded_context = result.capture.duplicate(true)
	if select_test_image.is_valid() and result.capture.get("test_image") in ["tv_test_card","animated_chart"]:
		var tv_card: bool = result.capture.test_image=="tv_test_card"
		select_test_image.call(tv_card)
		_fixture.select(0 if tv_card else 1)
	if restore_context.is_valid(): restore_context.call(result.capture)
	_refresh()
	_message.text = "Loaded: "+result.name


func _sync_editor_visibility() -> void:
	var editing := _fine_tune.button_pressed and not _showing_reference
	_tabs.visible = editing
	_browser_space.visible = not editing
	_look_description.visible = not editing
	_look_route.visible = not editing

func _replace_profile(value: NtscrtProfile,title: String) -> void:
	show_reference(false)
	profile.changed.disconnect(_refresh)
	profile = value
	profile.changed.connect(_refresh)
	_name.text = title

## Built-ins are appearance choices. Keep machine budget, comfort and the
## caller's world-resolution policy; file imports still restore full snapshots.
func select_curated(index: int) -> void:
	if index<0 or index>=LIBRARY.LOOKS.size() or _capturing: return
	var selected := LIBRARY.make_profile(index)
	selected.quality = profile.quality
	selected.reduced_flashing = profile.reduced_flashing
	selected.auto_world_resolution = profile.auto_world_resolution
	_replace_profile(selected,LIBRARY.LOOKS[index].name)
	_loaded_context = {}
	_library_index = index
	_library_select.select(index+1)
	_library_snapshot = PRESETS.encode(profile).settings
	_refresh()
	_message.text = "Look %d of %d. Capture saves all settings and a preview." % [index+1,LIBRARY.LOOKS.size()]

func _cycle_look(direction: int) -> void:
	var index := _library_index
	if index<0: index = -1 if direction>0 else 0
	select_curated(wrapi(index+direction,0,LIBRARY.LOOKS.size()))

func _refresh_library_description() -> void:
	var shown := _visible_profile()
	_damage_preview.visible = shown.ambient_fault_rate>0.0 and shown.ambient_fault_strength>0.0 and shown.tape_damage>0.0 and shown.tape!=PROFILE.Tape.OFF and not _showing_reference
	_damage_preview.disabled = shown.reduced_flashing or not preview_damage.is_valid()
	_damage_preview.tooltip_text = "Disabled by Reduced flashing" if shown.reduced_flashing else "Briefly previews the defect built into this look. It also happens occasionally during play."
	if _library_index<0:
		_look_description.text = "Browse 20 camera, tape and TV looks with the arrows. Choose a favorite, then Capture preset to save it."
		_look_route.text = "Browsing keeps your graphics budget and reduced-flashing preference."
		return
	var entry: Dictionary = LIBRARY.LOOKS[_library_index]
	_look_description.text = entry.description
	var modified: bool = PRESETS.encode(profile).settings!=_library_snapshot
	_look_route.text = entry.route + (" · modified" if modified else "")
	if profile.reduced_flashing: _look_route.text += "\nReduced flashing is suppressing tape noise and glitches."
	elif profile.ambient_fault_rate>0.0: _look_route.text += "\nBrief defects every ~%d seconds." % roundi(60.0/profile.ambient_fault_rate)

func _choose_preset() -> void:
	DirAccess.make_dir_recursive_absolute(PRESET_DIRECTORY)
	_load_dialog.current_dir = ProjectSettings.globalize_path(PRESET_DIRECTORY)
	_load_dialog.popup_centered_ratio(0.8)

func _open_captures() -> void:
	var error := DirAccess.make_dir_recursive_absolute(PRESET_DIRECTORY)
	if error==OK: error = OS.shell_open(ProjectSettings.globalize_path(PRESET_DIRECTORY))
	if error!=OK: _message.text = "Cannot open captures: "+error_string(error)

func _process(_delta: float) -> void:
	if _status==null: return
	var error: String = renderer_error.call() if renderer_error.is_valid() else ""
	_status.text = error if not error.is_empty() else "%s · Recording: %s · Screen: %s" % ["Reference A" if _showing_reference else "Current look","on" if _visible_profile().tape!=0 else "clean",_visible_profile().active_crt()]

func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation",12)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	return rows

func _row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	parent.add_child(row)
	return row

func _button(parent: Node,title: String,action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _options(parent: Node,title: String,items: Array) -> OptionButton:
	_label(parent,title)
	var options := OptionButton.new()
	options.fit_to_longest_item = false
	for item: String in items: options.add_item(item)
	parent.add_child(options)
	return options

func _choice(parent: Node,key: String,title: String,items: Array) -> void:
	var options := _options(parent,title,items)
	options.item_selected.connect(func(index: int):
		profile.set(key,index))
	_controls[key] = options

func _toggle(parent: Node,key: String,title: String) -> void:
	var toggle := CheckButton.new()
	toggle.text = title
	toggle.toggled.connect(func(on: bool): profile.set(key,on))
	parent.add_child(toggle)
	_controls[key] = toggle

func _number(parent: Node,key: String,title: String,minimum: float,maximum: float,step: float) -> void:
	_label(parent,title)
	var number := SpinBox.new()
	number.min_value = minimum
	number.max_value = maximum
	number.step = step
	number.value_changed.connect(func(value: float): profile.set(key,int(value) if profile.get(key) is int else value))
	parent.add_child(number)
	_controls[key] = number

func _label(parent: Node,text: String,size := 17) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",size)
	parent.add_child(label)
	return label

func _note(parent: Node,text: String) -> Label:
	return _label(parent,text,14)
