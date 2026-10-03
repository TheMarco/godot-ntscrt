extends "res://addons/ntscrt/workshop.gd"
## Demo layout. Profile editing, A/B and capture stay in the reusable workshop.
var _split: HSplitContainer
var _preview_slot: Control
var _preview_column: VBoxContainer
var _inspector: PanelContainer
var _pages: Array[Button] = []
var _look_buttons: Array[Button] = []
var _current_title: Label
var _save_dialog: Window
var _focus_preview: Button

func _ready() -> void:
	super._ready()
	_reveal_selected_look.call_deferred()

func select_curated(index: int) -> void:
	super.select_curated(index)
	_reveal_selected_look.call_deferred()

func _reveal_selected_look() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _library_index>=0 and _library_index<_look_buttons.size():
		_browser_space.ensure_control_visible(_look_buttons[_library_index])

func _build_ui() -> void:
	theme = _studio_theme()
	var background := ColorRect.new()
	background.color = Color("16191c")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+edge,14)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation",12)
	margin.add_child(root)
	var toolbar := _row(root)
	_label(toolbar,"NTSCRT",23).autowrap_mode = TextServer.AUTOWRAP_OFF
	var subtitle := _label(toolbar,"Look studio",16)
	subtitle.modulate = Color("a5b0b7")
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_focus_preview = _button(toolbar,"Expand preview",_toggle_inspector)
	_focus_preview.size_flags_horizontal = 0
	_button(toolbar,"Load…",_choose_preset).size_flags_horizontal = 0
	_button(toolbar,"Save preset…",func(): _save_dialog.popup_centered(Vector2i(480,260))).size_flags_horizontal = 0
	_split = HSplitContainer.new()
	_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_split.add_theme_constant_override("separation",16)
	_split.dragger_visibility = SplitContainer.DRAGGER_VISIBLE
	_split.tooltip_text = "Drag the divider to give the preview or controls more room."
	root.add_child(_split)
	_preview_column = VBoxContainer.new()
	_preview_column.custom_minimum_size.x = 300
	_preview_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_column.size_flags_stretch_ratio = 1.4
	_preview_column.add_theme_constant_override("separation",12)
	_split.add_child(_preview_column)
	var comparison := _row(_preview_column)
	_label(comparison,"Preview",17).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(comparison,"Keep as A",store_reference).size_flags_horizontal = 0
	_compare = _button(comparison,"Show A",func(): show_reference(not _showing_reference))
	_compare.size_flags_horizontal = 0
	_compare.disabled = true
	_preview_slot = Control.new()
	_preview_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_slot.custom_minimum_size.y = 180
	_preview_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_column.add_child(_preview_slot)
	var playback: HBoxContainer = build_source_controls.call(_preview_column)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation",5)
	_preview_column.add_child(details)
	_current_title = _label(details,"",20)
	_look_description = _note(details,"")
	_look_description.custom_minimum_size.y = 42
	_look_route = _note(details,"")
	_look_route.add_theme_font_size_override("font_size",12)
	_look_route.modulate = Color("a5b0b7")
	_status = _note(details,"")
	_status.visible = false
	_inspector = PanelContainer.new()
	_inspector.custom_minimum_size.x = 430
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector.add_theme_stylebox_override("panel",_surface(Color("20252a"),16))
	_split.add_child(_inspector)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation",12)
	_inspector.add_child(rows)
	var browser := _row(rows)
	var previous := _button(browser,"‹",func(): _cycle_look(-1))
	previous.custom_minimum_size.x = 36
	previous.size_flags_horizontal = 0
	previous.tooltip_text = "Previous look"
	_library_select = OptionButton.new()
	_library_select.fit_to_longest_item = false
	_library_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_library_select.add_item("Custom / loaded look")
	for index in LIBRARY.LOOKS.size():
		_library_select.add_item("%02d  %s" % [index+1,LIBRARY.LOOKS[index].name])
	_library_select.item_selected.connect(func(index: int):
		if index>0: select_curated(index-1))
	browser.add_child(_library_select)
	var next := _button(browser,"›",func(): _cycle_look(1))
	next.custom_minimum_size.x = 36
	next.size_flags_horizontal = 0
	next.tooltip_text = "Next look"
	_browse_buttons.assign([previous,next])
	var navigation := _row(rows)
	navigation.add_theme_constant_override("separation",4)
	for title in ["Looks","Adjust","CRT","Signal","Output"]:
		var index := _pages.size()
		var button := _button(navigation,title,func(): _select_page(index))
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size",14)
		_pages.append(button)
	_fine_tune = CheckButton.new()
	_fine_tune.hide()
	_fine_tune.toggled.connect(func(_on: bool): _sync_editor_visibility())
	add_child(_fine_tune)
	_browser_space = _build_library(rows)
	_browser_space.resized.connect(_reveal_selected_look)
	_tabs = TabContainer.new()
	_tabs.tabs_visible = false
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	rows.add_child(_tabs)
	_build_look(_tab("Adjust"))
	_build_crt(_tab("CRT"))
	_build_signal(_tab("Signal"))
	_build_output(_tab("Output"))
	_tabs.tab_changed.connect(func(_index: int): _sync_editor_visibility())
	_damage_preview = _button(playback,"Test glitch",func():
		if preview_damage.is_valid(): preview_damage.call())
	_message = _note(root,"Select a look. Drag the divider to resize the preview and controls.")
	_message.autowrap_mode = TextServer.AUTOWRAP_OFF
	_message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_message.custom_minimum_size.y = 20
	_message.modulate = Color("b4c0c5")
	_build_save_dialog()
	_load_dialog = FileDialog.new()
	_load_dialog.title = "Load NTSCRT preset"
	_load_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_load_dialog.add_filter("*.json","NTSCRT preset")
	_load_dialog.file_selected.connect(load_preset)
	add_child(_load_dialog)
	_sync_editor_visibility()
	resized.connect(_fit_workspace)
	_fit_workspace.call_deferred()

func _build_look(rows: VBoxContainer) -> void:
	_recording_toggle = CheckButton.new()
	_recording_toggle.text = "Recording effects"
	_recording_toggle.tooltip_text = "Bypass tape softness and damage without resetting the look. Camera color, grain and CRT stay as configured."
	_recording_toggle.toggled.connect(func(on: bool): profile.tape = _last_tape if on else PROFILE.Tape.OFF)
	rows.add_child(_recording_toggle)
	_number(rows,"tape_damage","Tape damage",0,1,0.01)
	_number(rows,"film_grain","Grain / sensor noise",0,1,0.01)
	_label(rows,"Camera color",17)
	_number(rows,"color_saturation","Saturation",0,1.5,0.01)
	_number(rows,"color_temperature","White balance: cool / warm",-1,1,0.01)
	_number(rows,"color_shadow_lift","Shadow detail",0,0.12,0.001)
	_label(rows,"Occasional defects",17)
	_number(rows,"ambient_fault_rate","Defects per minute",0,20,0.5)
	_number(rows,"ambient_fault_strength","Defect strength",0,1,0.01)
	_choice(rows,"ambient_fault_kind","Defect type",["Tracking","Color unlock","Dropout","RF static","Sync slip"])
	var cues := _row(rows)
	_button(cues,"Glitch pop",func(): _play_glitch("glitch_pop",0.53))
	_button(cues,"Two blips",func(): _play_glitch("two_blips",1.1))
	_note(rows,"Glitches need recording effects and tape damage. Reduced flashing, on Output, suppresses them.")

func _build_crt(rows: VBoxContainer) -> void:
	_toggle(rows,"crt_enabled","CRT screen")
	_choice(rows,"crt_model","Screen model",MODEL_TITLES)
	super._build_crt(rows)

func _build_signal(rows: VBoxContainer) -> void:
	super._build_signal(rows)
	_controls.receiver_enabled.text = "Analog signal instability (receiver)"
	_controls.receiver_enabled.tooltip_text = "Simulate a TV losing and recovering signal lock: rolling, tearing, color loss and interference. This advanced simulation adds CPU cost."

func _build_output(rows: VBoxContainer) -> void:
	_choice(rows,"quality","Graphics budget",["Low","Medium","High","Ultra"])
	_toggle(rows,"reduced_flashing","Reduced flashing")
	super._build_output(rows)

func _build_library(parent: VBoxContainer) -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	parent.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",6)
	scroll.add_child(rows)
	var previous_group := ""
	for index in LIBRARY.LOOKS.size():
		var look: Dictionary = LIBRARY.LOOKS[index]
		if look.group!=previous_group:
			var heading := _label(rows,look.group,14)
			heading.custom_minimum_size.y = 32
			heading.modulate = Color("a5b0b7")
			previous_group = look.group
		var button := _button(rows,"%02d   %s" % [index+1,look.name],func(): select_curated(index))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = look.description
		button.toggle_mode = true
		button.custom_minimum_size.y = 40
		_look_buttons.append(button)
	return scroll

func _build_save_dialog() -> void:
	_save_dialog = Window.new()
	_save_dialog.title = "Save your look"
	_save_dialog.transient = true
	_save_dialog.exclusive = true
	_save_dialog.unresizable = true
	_save_dialog.visible = false
	_save_dialog.close_requested.connect(_save_dialog.hide)
	add_child(_save_dialog)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel",_surface(Color("20252a"),20))
	_save_dialog.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation",12)
	panel.add_child(rows)
	_label(rows,"Preset name",17)
	_name = LineEdit.new()
	_name.text = "My recording look"
	_name.placeholder_text = "Name this look"
	rows.add_child(_name)
	_note(rows,"Saves every setting as JSON and a Godot resource, plus a PNG of the preview.")
	_capture_button = _button(rows,"Capture preset",func():
		_save_dialog.hide()
		await capture_preset())
	var files := _row(rows)
	_button(files,"Open captures",_open_captures)
	_button(files,"Copy JSON",func():
		DisplayServer.clipboard_set(JSON.stringify(PRESETS.encode(_visible_profile(),_visible_name(),_capture_context()),"\t"))
		_message.text = "Visible look copied as preset JSON."
		_save_dialog.hide())

func _select_page(index: int) -> void:
	if _showing_reference and index>0: return
	_fine_tune.set_pressed_no_signal(index>0)
	if index>0: _tabs.current_tab = index-1
	_sync_editor_visibility()

func _sync_editor_visibility() -> void:
	if _tabs==null: return
	var editing := _fine_tune.button_pressed and not _showing_reference
	_tabs.visible = editing
	_browser_space.visible = not editing
	for index in _pages.size():
		_pages[index].set_pressed_no_signal(index==(_tabs.current_tab+1 if editing else 0))
		_pages[index].disabled = _showing_reference and index>0
	for button in _look_buttons: button.disabled = _showing_reference

func _refresh_library_description() -> void:
	super._refresh_library_description()
	_current_title.text = _visible_name()
	for index in _look_buttons.size():
		_look_buttons[index].set_pressed_no_signal(index==_library_index and not _showing_reference)
	# Keep the description stable in height while browsing and tuning.
	_look_route.text = _look_route.text.replace("\n","  ·  ")

func _refresh_crt() -> void:
	var old_model := _crt_model
	super._refresh_crt()
	if old_model==_crt_model: return
	for control: SpinBox in _crt_controls.values():
		var box := control.get_parent()
		var label := box.get_child(0)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",12)
		box.add_child(row)
		label.reparent(row)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size",15)
		control.reparent(row)
		control.custom_minimum_size.x = 116

func _filter_crt() -> void:
	var query := _crt_filter.text.strip_edges().to_lower()
	var descriptors := PROFILE.crt_descriptors(_crt_model)
	for key: String in _crt_controls:
		var control: Control = _crt_controls[key]
		var box := control.get_parent()
		if box is HBoxContainer: box = box.get_parent()
		box.visible = query.is_empty() or query in (key+" "+str(descriptors[key].label)).to_lower()

func _number(parent: Node,key: String,title: String,minimum: float,maximum: float,step: float) -> void:
	var row := _row(parent)
	_label(row,title,15).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var number := SpinBox.new()
	number.custom_minimum_size.x = 116
	number.min_value = minimum
	number.max_value = maximum
	number.step = step
	number.value_changed.connect(func(value: float): profile.set(key,int(value) if profile.get(key) is int else value))
	row.add_child(number)
	_controls[key] = number

func _toggle_inspector() -> void:
	_inspector.visible = not _inspector.visible
	_focus_preview.text = "Show controls" if not _inspector.visible else "Expand preview"

func _fit_workspace() -> void:
	# At small sizes the inspector retains a usable width; the divider stays draggable.
	if _inspector==null: return
	_inspector.custom_minimum_size.x = 380 if size.x<1100 else 430
	_preview_column.custom_minimum_size.x = 240 if size.x<1100 else 300

func _process(delta: float) -> void:
	super._process(delta)
	if _preview_slot==null: return
	_message.tooltip_text = _message.text
	var error: String = renderer_error.call() if renderer_error.is_valid() else ""
	if not error.is_empty(): _message.text = error

func _surface(color: Color,padding := 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(5)
	for edge in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: style.set_content_margin(edge,padding)
	return style

func _studio_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 16
	for type in ["Button","OptionButton","LineEdit","CheckButton","Label"]:
		result.set_color("font_color",type,Color("e2e8e9"))
	for type in ["Button","OptionButton"]:
		result.set_stylebox("normal",type,_surface(Color("2c3339")))
		result.set_stylebox("hover",type,_surface(Color("39454a")))
		result.set_stylebox("pressed",type,_surface(Color("365851")))
		result.set_stylebox("disabled",type,_surface(Color("24292e")))
		var focus := _surface(Color(0,0,0,0))
		focus.set_border_width_all(2)
		focus.border_color = Color("9bc7b7")
		result.set_stylebox("focus",type,focus)
	result.set_stylebox("normal","LineEdit",_surface(Color("151a1e"),9))
	result.set_stylebox("focus","LineEdit",result.get_stylebox("focus","Button"))
	result.set_constant("scrollbar_width","VScrollBar",12)
	return result
