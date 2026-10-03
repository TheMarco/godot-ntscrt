extends Control
const EFFECT = preload("res://addons/ntscrt/effect.gd")
const PROFILE = preload("res://addons/ntscrt/profile.gd")
const LIBRARY = preload("res://addons/ntscrt/preset_library.gd")
const WORKSHOP = preload("res://addons/ntscrt/workshop.gd")
const CARD = preload("res://demo/test_card.gd")
const CLIPS = {
	"hallway": preload("res://demo/assets/hallway.ogv"),
	"security": preload("res://demo/assets/security.ogv"),
	"abandoned_mall": preload("res://demo/assets/abandoned-mall.ogv")
}
const SOURCE_IDS := ["hallway","security","tv_test_card","animated_chart","abandoned_mall"]
const SOURCE_NAMES := ["Hallway walkthrough","Night security camera","TV test card","Motion & color chart","Abandoned mall walkthrough"]
const SOURCE_NOTES := [
	"Moving camera, colored objects and fine edges. Compare DV, Hi8 and VHS looks.",
	"Fixed camera, deep shadows and a moving subject. Compare CCTV noise and CRT trails.",
	"Static reference for sharpness, color and the CRT grille.",
	"Moving edges and gray steps reveal color bleed, trails and lost shadow detail.",
	"30-second mall walkthrough with original sound. Compare found footage, DV and VHS looks on detailed moving scenery."]
var effect: NtscrtEffect
var workshop: Control
var profile: NtscrtProfile:
	get: return workshop.profile if workshop!=null else null
var _card: Node2D
var _video: VideoStreamPlayer
var _source_select: OptionButton
var _source_note: Label
var _play_button: Button
var _open_dialog: FileDialog
var _source_index := 0
var _paused := false
var _external_path := ""
var _video_extent := Vector2i.ZERO

func _ready() -> void:
	effect = EFFECT.new()
	var initial := LIBRARY.make_profile(8)
	effect.profile = initial
	add_child(effect)
	effect.offset_right = -WORKSHOP.PANEL_WIDTH
	var recorded := Node2D.new()
	recorded.name = "RecordedScene"
	var backing := ColorRect.new()
	backing.color = Color.BLACK
	backing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	recorded.add_child(backing)
	_video = VideoStreamPlayer.new()
	_video.expand = true
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video.finished.connect(_replay)
	recorded.add_child(_video)
	_card = CARD.new()
	recorded.add_child(_card)
	effect.add_content(recorded)
	effect.source.size_changed.connect(_fit_video)
	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	workshop = WORKSHOP.new()
	workshop.profile = initial
	workshop.apply_profile = func(value: NtscrtProfile):
		effect.clear_glitch()
		effect.profile = value
	workshop.build_source_controls = _build_source_controls
	workshop.capture_image = _capture_image
	workshop.capture_context = _capture_context
	workshop.restore_context = _restore_context
	workshop.renderer_error = effect.get_error
	workshop.play_glitch = effect.trigger_glitch
	if effect.presenter!=null:
		workshop.preview_damage = effect.presenter.preview_ambient_fault
	ui.add_child(workshop)
	_select_source(0)

func _build_source_controls(rows: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "Preview footage"
	rows.add_child(title)
	_source_select = OptionButton.new()
	_source_select.fit_to_longest_item = false
	for source_name in SOURCE_NAMES: _source_select.add_item(source_name)
	_source_select.item_selected.connect(_select_source)
	rows.add_child(_source_select)
	var playback := HBoxContainer.new()
	rows.add_child(playback)
	for title_text in ["Pause footage","Replay","Open .ogv…"]:
		var button := Button.new()
		button.text = title_text
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		playback.add_child(button)
		match title_text:
			"Pause footage":
				_play_button = button
				button.pressed.connect(func(): _set_paused(not _paused))
			"Replay": button.pressed.connect(_replay)
			_: button.pressed.connect(func(): _open_dialog.popup_centered_ratio(0.8))
	_source_note = Label.new()
	_source_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_source_note.add_theme_font_size_override("font_size",13)
	rows.add_child(_source_note)
	var divider := HSeparator.new()
	rows.add_child(divider)
	_open_dialog = FileDialog.new()
	_open_dialog.title = "Preview your footage"
	_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.add_filter("*.ogv","Ogg Theora video")
	_open_dialog.file_selected.connect(_open_video)
	add_child(_open_dialog)

func _select_source(index: int) -> void:
	_source_index = index
	_source_select.select(index)
	var source_id: String = SOURCE_IDS[index] if index<SOURCE_IDS.size() else "external_video"
	var video_source := CLIPS.has(source_id) or source_id=="external_video"
	_card.visible = not video_source
	_card.set_process(not video_source and not _paused)
	_video.visible = video_source
	_video.stop()
	if video_source:
		if CLIPS.has(source_id): _video.stream = CLIPS[source_id]
		else:
			var stream := VideoStreamTheora.new()
			stream.file = _external_path
			_video.stream = stream
		_video.play()
		_video.paused = _paused
	else:
		_card.use_tv_card = source_id=="tv_test_card"
		_card.queue_redraw()
	_source_note.text = SOURCE_NOTES[index] if index<SOURCE_NOTES.size() else "Your local footage. Changing looks keeps this source."
	_play_button.disabled = source_id=="tv_test_card"
	_video_extent = Vector2i.ZERO
	_fit_video()

func _set_paused(value: bool) -> void:
	_paused = value
	_video.paused = value
	_card.set_process(not value and _card.visible)
	_play_button.text = "Play footage" if value else "Pause footage"

func _replay() -> void:
	if _video.visible:
		_video.stop()
		_video.play()
		_video.paused = _paused
	else:
		_card._clock = 0.0
		_card.queue_redraw()

func _open_video(path: String) -> void:
	_external_path = path
	if _source_select.item_count==SOURCE_IDS.size(): _source_select.add_item("Your footage")
	_select_source(SOURCE_IDS.size())

func _fit_video() -> void:
	if _video==null or effect.source==null: return
	var texture := _video.get_video_texture()
	var source_extent := Vector2(720,540)
	if texture!=null and texture.get_width()>0:
		source_extent = texture.get_size()
		_video_extent = Vector2i(source_extent)
	var available := Vector2(effect.source.size)
	_video.size = source_extent*minf(available.x/source_extent.x,available.y/source_extent.y)
	_video.position = (available-_video.size)*0.5

func _process(_delta: float) -> void:
	if _video==null or not _video.visible: return
	var texture := _video.get_video_texture()
	if texture!=null and Vector2i(texture.get_size())!=_video_extent: _fit_video()

func _capture_context() -> Dictionary:
	return {"preview_source":SOURCE_IDS[_source_index] if _source_index<SOURCE_IDS.size() else "external_video",
		"footage_paused":_paused,"preview_width":roundi(effect.size.x),"preview_height":roundi(effect.size.y)}

func _restore_context(context: Dictionary) -> void:
	# External file paths are deliberately not embedded or opened by preset JSON.
	var index := SOURCE_IDS.find(str(context.get("preview_source",context.get("test_image",""))))
	if index>=0 and index!=_source_index: _select_source(index)
	if context.get("footage_paused") is bool: _set_paused(context.footage_paused)

func _capture_image() -> Image:
	for frame in 4:
		await get_tree().process_frame
		RenderingServer.force_draw()
	var image := get_viewport().get_texture().get_image()
	var scale := Vector2(image.get_size())/get_viewport_rect().size
	return image.get_region(Rect2i(Vector2i(effect.global_position*scale),Vector2i(effect.size*scale)))
