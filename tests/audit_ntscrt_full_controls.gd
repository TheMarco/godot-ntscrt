extends SceneTree

const Settings = preload("res://addons/ntscrt/internal/ntscrt_full_settings.gd")
const Controls = preload("res://addons/ntscrt/internal/ntscrt_full_controls.gd")
var failures: Array[String] = []
var events: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var defaults := Settings.ntsc_defaults()
	var receiver := Settings.receiver_defaults()
	_check(defaults.size() == 62, "Expected 62 NTSC defaults")
	_check(receiver.size() == 17, "Expected 17 receiver defaults")
	_check(defaults.get("filter_type") == 1 and defaults.get("luma_smear") == 0.5, "Current defaults, not legacy defaults")
	_check(defaults.get("chroma_noise_detail") == 2, "Current noise default")
	var clean := Settings.sanitize_ntsc({"random_seed": 9e20, "use_field": 5, "luma_smear": NAN, "composite_noise": false, "composite_noise_intensity": 0.75, "unknown": 2})
	_check(clean.size() == 62 and not clean.has("unknown"), "Unknown keys rejected")
	_check(clean["random_seed"] == 2147483647, "Integer clamp")
	_check(clean["use_field"] == 5, "Enum ID retained")
	_check(clean["luma_smear"] == defaults["luma_smear"], "NaN rejected")
	_check(clean["composite_noise"] == false and clean["composite_noise_intensity"] == 0.75, "Disabled group values retained")
	var invalid := Settings.sanitize_ntsc({"use_field": 99, "filter_type": 0.5, "luma_smear": "2", "head_switching": 1, "snow_intensity": INF, "random_seed": true})
	for key: String in ["use_field", "filter_type", "luma_smear", "head_switching", "snow_intensity", "random_seed"]:
		_check(invalid[key] == defaults[key], "Wrong type/value rejected: " + key)
	var receiver_clean := Settings.sanitize_receiver({"closed_captions": false, "dropout_compensation": 0.0, "ghost_delay": 99.0, "hum": -1.0})
	_check(receiver_clean["closed_captions"] == false, "Receiver boolean accepted")
	_check(receiver_clean["dropout_compensation"] == true, "Receiver numeric boolean rejected")
	_check(receiver_clean["ghost_delay"] == 12.0 and receiver_clean["hum"] == 0.0, "Receiver numeric clamp")
	_check(Settings.sanitize_ntsc(null) == defaults, "Invalid settings object defaults")
	var ui := Controls.new()
	root.add_child(ui)
	ui.value_changed.connect(func(engine: String, key: String, value: Variant) -> void: events.append([engine, key, value]))
	ui.setup()
	_check(ui.controls.size() == 79, "79 controls exposed")
	for key: String in defaults:
		_check(ui.controls.has("ntscrs/" + key), "NTSC control coverage: " + key)
	for key: String in receiver:
		_check(ui.controls.has("receiver/" + key), "Receiver control coverage: " + key)
	_check(events.is_empty(), "Setup must not emit changes")
	ui.refresh(clean, receiver_clean)
	_check(events.is_empty(), "Refresh must not emit changes")
	var number: SpinBox = ui.controls["ntscrs/composite_noise_intensity"]
	_check(not number.editable and is_equal_approx(number.value, 0.75), "Disabled child retains value")
	var select: OptionButton = ui.controls["ntscrs/use_field"]
	_check(select.get_selected_id() == 5, "Refresh selects actual enum ID")
	_check(select.get_item_id(1) == 1 and select.get_item_id(3) == 4, "Authoritative field option order")
	select.item_selected.emit(3)
	_check(events.back() == ["ntscrs", "use_field", 4], "Event emits actual enum ID, not position")
	var toggle: CheckButton = ui.controls["ntscrs/composite_noise"]
	toggle.button_pressed = true
	_check(number.editable and is_equal_approx(number.value, 0.75), "Reenabled group retains child value")
	_check(events.back() == ["ntscrs", "composite_noise", true], "Boolean event propagation")
	number.value = 0.5
	_check(events.back() == ["ntscrs", "composite_noise_intensity", 0.5], "Numeric event propagation")
	ui.refresh(defaults, receiver)
	var nested: SpinBox = ui.controls["ntscrs/vhs_sharpen_frequency"]
	var outer: CheckButton = ui.controls["ntscrs/vhs_settings"]
	outer.button_pressed = false
	_check(not nested.editable, "Nested descendants disabled by outer group")
	ui.free()
	if failures.is_empty():
		print("PASS: 79 controls; defaults, sanitization, enum IDs, events, silent refresh, nested disabled groups")
	quit(0 if failures.is_empty() else 1)
