extends Node2D
## User-supplied TV card plus an original animated procedural fixture.
const TV_CARD = preload("res://demo/assets/tv-test-card.png")
var use_tv_card := true
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
var _clock := 0.0
func _process(delta: float) -> void:
	_clock += delta
	queue_redraw()
func _draw() -> void:
	var extent := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO,extent),Color(0.025,0.034,0.045))
	if use_tv_card:
		var available := Vector2(maxf(1.0,extent.x-388.0),maxf(1.0,extent.y-122.0))
		var factor := minf(available.x/TV_CARD.get_width(),available.y/TV_CARD.get_height())
		var card_size := TV_CARD.get_size()*factor
		draw_texture_rect(TV_CARD,Rect2(Vector2(24,98)+(available-card_size)*0.5,card_size),false)
		return
	var colours := [Color.WHITE,Color.YELLOW,Color.CYAN,Color.GREEN,Color.MAGENTA,Color.RED,Color.BLUE]
	for index in colours.size():
		draw_rect(Rect2(index*extent.x/7.0,0,extent.x/7.0+1,extent.y*0.3),colours[index]*0.85)
	for index in 16:
		var value := float(index)/15.0
		draw_rect(Rect2(index*extent.x/16.0,extent.y*0.3,extent.x/16.0+1,extent.y*0.16),Color(value,value,value))
	for x in range(0,int(extent.x),32):
		draw_line(Vector2(x,extent.y*0.5),Vector2(x,extent.y),Color(0.12,0.21,0.26),1)
	for y in range(int(extent.y*0.5),int(extent.y),32):
		draw_line(Vector2(0,y),Vector2(extent.x,y),Color(0.12,0.21,0.26),1)
	var center := Vector2(extent.x*(0.5+0.26*sin(_clock*0.45)),extent.y*0.71)
	draw_circle(center,extent.y*0.13,Color(0.9,0.42,0.12))
	draw_circle(center,extent.y*0.11,Color(0.018,0.025,0.035))
	draw_line(center-Vector2(70,0),center+Vector2(70,0),Color.WHITE,2)
	draw_line(center-Vector2(0,70),center+Vector2(0,70),Color.WHITE,2)
