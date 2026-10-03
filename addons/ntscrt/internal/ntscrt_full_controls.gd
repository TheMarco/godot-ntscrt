extends VBoxContainer
## All original ntsc-rs and receiver controls, driven by their canonical schemas.

signal value_changed(engine: String, key: String, value: Variant)

const Settings = preload("res://addons/ntscrt/internal/ntscrt_full_settings.gd")


## Public control registry: engine + "/" + canonical setting name.
var controls: Dictionary = {}
var _descriptors: Dictionary = {}
var _dependencies: Dictionary = {}
var _values: Dictionary = {"ntscrs": {}, "receiver": {}}
var _refreshing := false


func setup() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	controls.clear()
	_descriptors.clear()
	_dependencies.clear()
	add_theme_constant_override("separation", 12)
	var signal_body := _section(self, "NTSC signal", true)
	for descriptor: Dictionary in Settings.ntsc_descriptors():
		_add_descriptor(signal_body, "ntscrs", descriptor, [])
	for group: String in ["reception", "tape"]:
		var title := "Receiver / reception" if group == "reception" else "Receiver / tape"
		var body := _section(self, title, false)
		for descriptor: Dictionary in Settings.receiver_descriptors():
			if descriptor["group"] == group:
				_add_descriptor(body, "receiver", descriptor, [])
	refresh(Settings.ntsc_defaults(), Settings.receiver_defaults())


func refresh(ntsc_values: Dictionary, receiver_values: Dictionary) -> void:
	_refreshing = true
	_values["ntscrs"] = Settings.sanitize_ntsc(ntsc_values)
	_values["receiver"] = Settings.sanitize_receiver(receiver_values)
	for path: String in controls:
		var control: Control = controls[path]
		var pieces := path.split("/", false, 1)
		var value: Variant = _values[pieces[0]][pieces[1]]
		if control is CheckButton:
			control.set_pressed_no_signal(bool(value))
		elif control is OptionButton:
			control.select(control.get_item_index(int(value)))
		elif control is SpinBox:
			control.set_value_no_signal(float(value))
	_update_disabled()
	_refreshing = false


func _section(parent: VBoxContainer, title: String, expanded: bool) -> VBoxContainer:
	var button := Button.new()
	button.text = title
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.toggle_mode = true
	button.set_pressed_no_signal(expanded)
	button.add_theme_font_size_override("font_size", 17)
	button.tooltip_text = "Expand or collapse " + title
	parent.add_child(button)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.visible = expanded
	parent.add_child(body)
	button.toggled.connect(func(open: bool) -> void: body.visible = open)
	return body


func _add_descriptor(parent: VBoxContainer, engine: String, descriptor: Dictionary, ancestors: Array) -> void:
	var key: String = descriptor["name"]
	var path := engine + "/" + key
	var kind: String = descriptor["type"]
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var label := Label.new()
	label.text = descriptor["label"]
	if not str(descriptor.get("unit", "")).is_empty():
		label.text += " (" + str(descriptor["unit"]) + ")"
	label.add_theme_font_size_override("font_size", 17)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 0
	row.add_child(label)
	var control: Control
	if kind in ["boolean", "group"]:
		var check := CheckButton.new()
		check.toggled.connect(func(value: bool) -> void: _changed(engine, key, value))
		control = check
	elif kind == "enum":
		var select := OptionButton.new()
		for option: Dictionary in descriptor["options"]:
			select.add_item(str(option["label"]), int(option["index"]))
			select.set_item_tooltip(select.item_count - 1, str(option.get("description", "")))
		select.item_selected.connect(func(index: int) -> void: _changed(engine, key, select.get_item_id(index)))
		select.get_popup().add_theme_font_size_override("font_size", 17)
		control = select
	else:
		var number := SpinBox.new()
		number.min_value = float(descriptor.get("min", 0.0))
		number.max_value = float(descriptor.get("max", 1.0))
		number.step = 1.0 if kind == "int" else 0.000001
		number.value_changed.connect(func(value: float) -> void: _changed(engine, key, int(value) if kind == "int" else value))
		number.get_line_edit().add_theme_font_size_override("font_size", 17)
		control = number
	control.add_theme_font_size_override("font_size", 17)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.tooltip_text = str(descriptor.get("description", ""))
	label.tooltip_text = control.tooltip_text
	row.add_child(control)
	controls[path] = control
	_descriptors[path] = descriptor
	_dependencies[path] = ancestors.duplicate()
	if kind == "group":
		var group_body := _section(parent, str(descriptor["label"]) + " settings", false)
		var nested := ancestors.duplicate()
		nested.append(key)
		for child: Dictionary in descriptor.get("children", []):
			_add_descriptor(group_body, engine, child, nested)


func _changed(engine: String, key: String, value: Variant) -> void:
	if _refreshing:
		return
	_values[engine][key] = value
	_update_disabled()
	value_changed.emit(engine, key, value)


func _update_disabled() -> void:
	for path: String in controls:
		var engine: String = path.get_slice("/", 0)
		var disabled := false
		for ancestor: String in _dependencies[path]:
			if not bool(_values[engine].get(ancestor, true)):
				disabled = true
		var control: Control = controls[path]
		if control is BaseButton:
			control.disabled = disabled
		elif control is SpinBox:
			control.editable = not disabled
		control.modulate.a = 0.45 if disabled else 1.0
