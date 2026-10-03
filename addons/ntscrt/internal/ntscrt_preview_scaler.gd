extends RefCounted
## Exact sizing policy from NTSCRT Sources/CrtCore/PreviewScaling.swift.
## Original authors retain copyright. Integer display uses even multiples;
## rendering independently meets the six-row scanline floor when budget allows.
const MIN_RENDER_MULTIPLE := 6

static func plan(input_size: Vector2i, drawable_size: Vector2i,
		integer_scale: bool, min_render_multiple: int = MIN_RENDER_MULTIPLE,
		max_long_edge: int = 4096) -> Dictionary:
	var drawable := Vector2i(maxi(1,drawable_size.x),maxi(1,drawable_size.y))
	if input_size.x<=0 or input_size.y<=0:
		return _fill(drawable,max_long_edge)
	if not integer_scale:
		var multiple := _render_multiple(1,input_size,min_render_multiple,max_long_edge)
		if multiple>1 and multiple%2==1: multiple -= 1
		if maxi(input_size.x,input_size.y)*multiple>max_long_edge:
			return _fill(drawable,max_long_edge)
		return _result(input_size*multiple,drawable,0,multiple)
	var display_multiple := maxi(1,mini(drawable.x/input_size.x,drawable.y/input_size.y))
	if display_multiple>1 and display_multiple%2==1: display_multiple -= 1
	if input_size.x*display_multiple>drawable.x or input_size.y*display_multiple>drawable.y:
		var fit_scale := minf(float(drawable.x)/input_size.x,float(drawable.y)/input_size.y)
		var fit := Vector2i(maxi(1,roundi(input_size.x*fit_scale)),maxi(1,roundi(input_size.y*fit_scale)))
		var multiple := _render_multiple(1,input_size,min_render_multiple,max_long_edge)
		return _result(input_size*multiple,fit,0,multiple)
	var render_multiple := _render_multiple(display_multiple,input_size,min_render_multiple,max_long_edge)
	return _result(input_size*render_multiple,input_size*display_multiple,display_multiple,render_multiple)

static func _render_multiple(display_multiple: int, input_size: Vector2i,
		min_render_multiple: int, max_long_edge: int) -> int:
	var long_edge := maxi(input_size.x,input_size.y)
	var factor := maxi(1,ceili(float(min_render_multiple)/display_multiple))
	while factor>1 and long_edge*display_multiple*factor>max_long_edge: factor -= 1
	# Deliberately preserves upstream: the budget limits supersampling; an
	# input/display already larger than it can still exceed it in integer mode.
	return display_multiple*factor

static func _fill(drawable: Vector2i, max_long_edge: int) -> Dictionary:
	var fit_scale := minf(1.0,float(max_long_edge)/maxi(drawable.x,drawable.y))
	return _result(Vector2i(maxi(64,int(drawable.x*fit_scale)),maxi(64,int(drawable.y*fit_scale))),drawable,0,0)

static func _result(render: Vector2i, display: Vector2i, display_multiple: int, render_multiple: int) -> Dictionary:
	return {"render_size":render,"display_size":display,
		"display_multiple":display_multiple,"render_multiple":render_multiple,
		"needs_downsample":render!=display}
