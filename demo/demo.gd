extends Control
const EFFECT = preload("res://addons/ntscrt/effect.gd")
const PROFILE = preload("res://addons/ntscrt/profile.gd")
const CARD = preload("res://demo/test_card.gd")
const FULL_CONTROLS = preload("res://addons/ntscrt/internal/ntscrt_full_controls.gd")
var effect: NtscrtEffect
var profile: NtscrtProfile
var _status: Label

func _ready() -> void:
	profile = PROFILE.new()
	profile.crt_enabled = true
	effect = EFFECT.new()
	effect.profile = profile
	add_child(effect)
	var recorded := Node2D.new()
	recorded.name = "RecordedScene"
	var card := CARD.new()
	recorded.add_child(card)
	var hud := Label.new()
	hud.text = "REC  ●   NTSCRT / GODOT\nThis label is inside the recording"
	hud.position = Vector2(28,20)
	hud.add_theme_font_size_override("font_size",22)
	hud.add_theme_color_override("font_color",Color(0.94,0.94,0.9))
	recorded.add_child(hud)
	effect.add_content(recorded)
	# Menus stay outside the recorded viewport, on their own canvas.
	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -340
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.045,0.055,0.07,1.0)
	panel.add_theme_stylebox_override("panel",background)
	ui.add_child(panel)
	var margin := MarginContainer.new()
	for edge in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+edge,18)
	panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",12)
	scroll.add_child(rows)
	_label(rows,"GODOT NTSCRT",26)
	_note(rows,"A standalone tape + CRT renderer. This menu stays crisp; the scene and REC label are filtered.")
	_label(rows,"Test image")
	var fixture := OptionButton.new()
	fixture.add_item("TV test card")
	fixture.add_item("Animated chart")
	fixture.item_selected.connect(func(index: int): card.use_tv_card=index==0)
	rows.add_child(fixture)
	_label(rows,"Tape look")
	var tape := OptionButton.new()
	for title in ["Off","Home video","Found footage","Worn tape"]: tape.add_item(title)
	tape.select(profile.tape)
	rows.add_child(tape)
	var damage := HSlider.new()
	damage.min_value = 0
	damage.max_value = 1
	damage.step = 0.01
	damage.value = profile.tape_damage
	tape.item_selected.connect(func(index: int):
		profile.select_tape(index)
		damage.set_value_no_signal(profile.tape_damage)
		damage.editable = index!=PROFILE.Tape.OFF)
	_label(rows,"Tape damage")
	rows.add_child(damage)
	damage.value_changed.connect(func(value: float): profile.tape_damage=value)
	var crt := CheckButton.new()
	crt.text = "CRT screen"
	crt.button_pressed = profile.crt_enabled
	crt.toggled.connect(func(on: bool): profile.crt_enabled=on)
	rows.add_child(crt)
	_note(rows,"Scanlines, glow and phosphor texture. Works with any tape look, including Off.")
	_label(rows,"Graphics budget")
	var quality := OptionButton.new()
	for title in ["Low","Medium","High","Ultra"]: quality.add_item(title)
	quality.select(profile.quality)
	quality.item_selected.connect(func(index: int): profile.quality=index)
	rows.add_child(quality)
	var reduced := CheckButton.new()
	reduced.text = "Reduced flashing"
	reduced.toggled.connect(func(on: bool): profile.reduced_flashing=on)
	rows.add_child(reduced)
	var buttons := HBoxContainer.new()
	rows.add_child(buttons)
	for name in ["Glitch pop","Two blips"]:
		var button := Button.new()
		button.text = name
		buttons.add_child(button)
		button.pressed.connect(func(): effect.trigger_glitch("glitch_pop" if name=="Glitch pop" else "two_blips",0.53 if name=="Glitch pop" else 1.1))
	_note(rows,"Cues are called by your game. Tape Off and Reduced flashing suppress them.")
	_status = _note(rows,"")
	var advanced_toggle := Button.new()
	advanced_toggle.text = "Advanced controls"
	advanced_toggle.toggle_mode = true
	rows.add_child(advanced_toggle)
	var advanced := VBoxContainer.new()
	advanced.visible = false
	rows.add_child(advanced)
	advanced_toggle.toggled.connect(func(on: bool): advanced.visible=on)
	_label(advanced,"CRT model")
	var models := OptionButton.new()
	for title in ["Automatic","Aperture","EasyMode","Glow Gaussian","Glow Lanczos","Hyllian","Royale","Crtsim"]: models.add_item(title)
	models.item_selected.connect(func(index: int): profile.crt_model=index)
	advanced.add_child(models)
	var receiver := CheckButton.new()
	receiver.text = "Receiver simulation"
	receiver.toggled.connect(func(on: bool): profile.receiver_enabled=on)
	advanced.add_child(receiver)
	_note(advanced,"Optional receiver timing can cost substantial CPU time. Off by default.")
	var controls := FULL_CONTROLS.new()
	advanced.add_child(controls)
	controls.setup()
	var refresh_controls := func(): controls.refresh(profile.canonical_ntsc_settings(),PROFILE.SETTINGS.sanitize_receiver(profile.receiver_overrides))
	profile.changed.connect(refresh_controls)
	refresh_controls.call()
	controls.value_changed.connect(func(engine: String,key: String,value: Variant):
		var knobs := profile.ntsc_overrides.duplicate() if engine=="ntscrs" else profile.receiver_overrides.duplicate()
		knobs[key]=value
		if engine=="ntscrs": profile.ntsc_overrides=knobs
		else: profile.receiver_overrides=knobs)

func _process(_delta: float) -> void:
	if effect==null or _status==null: return
	_status.text = effect.get_error() if not effect.get_error().is_empty() else "GPU: %s · %s signal\nRecorded scene + HUD; crisp menu" % [profile.active_crt(),PROFILE.SIGNAL_SIZES[profile.quality]]

func _label(parent: Node,text: String,size := 17) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",size)
	parent.add_child(label)
	return label

func _note(parent: Node,text: String) -> Label:
	var label := _label(parent,text,14)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
