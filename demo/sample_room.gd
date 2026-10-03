extends Node3D
## Original, deterministic source footage. No video effects are baked in.
var security := false
var camera: Camera3D
var cart: Node3D
var fan: Node3D

func material(color: Color, roughness := 0.8, glow := false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	if glow:
		result.emission_enabled = true
		result.emission = color
		result.emission_energy_multiplier = 2.0
	return result

func box(parent: Node3D, size: Vector3, at: Vector3, surface: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = surface
	node.position = at
	parent.add_child(node)
	return node

func sign_text(text: String, at: Vector3, size := 64, color := Color(0.12,0.15,0.16)) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.005
	label.modulate = color
	label.outline_size = 0
	label.position = at
	add_child(label)

func _ready() -> void:
	var wall := material(Color(0.63,0.66,0.61))
	var floor_mat := material(Color(0.28,0.30,0.28),0.5)
	var trim := material(Color(0.18,0.22,0.21))
	var steel := material(Color(0.35,0.4,0.41),0.3)
	var dark := material(Color(0.045,0.06,0.06))
	var wood := material(Color(0.40,0.24,0.12))
	box(self,Vector3(8,0.2,16),Vector3(0,-0.1,0),floor_mat)
	box(self,Vector3(8,0.2,16),Vector3(0,3.5,0),wall)
	box(self,Vector3(0.2,3.5,16),Vector3(-4,1.75,0),wall)
	box(self,Vector3(0.2,3.5,16),Vector3(4,1.75,0),wall)
	box(self,Vector3(8,3.5,0.2),Vector3(0,1.75,-8),wall)
	for x in [-3.88,3.88]: box(self,Vector3(0.04,0.16,16),Vector3(x,0.08,0),trim)
	# Fine floor and ceiling lines reveal softness, ringing and motion trails.
	for x in range(-4,5):
		box(self,Vector3(0.015,0.004,16),Vector3(x,0.005,0),trim)
		box(self,Vector3(0.025,0.02,16),Vector3(x,3.38,0),trim)
	for z in range(-8,9):
		box(self,Vector3(8,0.004,0.015),Vector3(0,0.006,z),trim)
		box(self,Vector3(8,0.02,0.025),Vector3(0,3.38,z),trim)
	for z in [-5,0,5]:
		var lamp_color := Color(0.75,0.85,0.9) if security else Color(1,0.89,0.69)
		box(self,Vector3(1.0,0.05,1.3),Vector3(0,3.34,z),material(lamp_color,1,true))
		var light := OmniLight3D.new()
		light.position = Vector3(0,2.9,z)
		light.light_color = lamp_color
		light.light_energy = (0.45 if z==-5 else 0.13) if security else 1.3
		light.omni_range = 7
		light.shadow_enabled = true
		add_child(light)
	# Door, window grid and signage give recognizable neutral detail.
	box(self,Vector3(2.1,2.8,0.12),Vector3(-1,1.4,-7.82),trim)
	box(self,Vector3(1.8,2.6,0.12),Vector3(-1,1.3,-7.72),wood)
	box(self,Vector3(0.13,0.09,0.14),Vector3(-0.35,1.2,-7.6),steel)
	box(self,Vector3(2.2,1.5,0.06),Vector3(2,2.0,-7.8),dark)
	for x in [1.1,1.7,2.3,2.9]:
		for y in [1.6,2.2]:
			box(self,Vector3(0.54,0.54,0.06),Vector3(x,y,-7.74),material(Color(0.08,0.16,0.20),0.15))
	box(self,Vector3(1.3,0.32,0.05),Vector3(-1,3.03,-7.7),material(Color(0.04,0.25,0.14),1,true))
	sign_text("EXIT",Vector3(-1,3.02,-7.64),50,Color(0.86,1,0.86))
	sign_text("STORAGE  /  04",Vector3(-1,2.3,-7.63),26,Color(0.9,0.88,0.75))
	# Metal shelving with saturated objects to reveal color bleed.
	for z in [-5.0,-1.4]:
		for x in [-3.55,-2.25]:
			for dz in [-0.7,0.7]: box(self,Vector3(0.055,2.5,0.055),Vector3(x,1.25,z+dz),steel)
		for y in [0.3,1.1,1.9]:
			box(self,Vector3(1.4,0.06,1.55),Vector3(-2.9,y,z),steel)
			for item in 3:
				var colors := [Color(0.55,0.12,0.055),Color(0.04,0.25,0.43),Color(0.63,0.49,0.14)]
				box(self,Vector3(0.34,0.48,0.55),Vector3(-3.35+item*0.43,y+0.27,z),material(colors[item]))
	# Desk, bright monitor and papers exercise highlights against shadow detail.
	box(self,Vector3(1.7,0.12,1.4),Vector3(2.8,0.85,-3.3),wood)
	for x in [2.1,3.5]:
		for z in [-3.8,-2.8]: box(self,Vector3(0.07,0.85,0.07),Vector3(x,0.42,z),steel)
	box(self,Vector3(0.75,0.58,0.45),Vector3(2.8,1.25,-3.6),dark)
	box(self,Vector3(0.62,0.44,0.025),Vector3(2.8,1.28,-3.36),material(Color(0.1,0.46,0.4),1,true))
	box(self,Vector3(0.5,0.01,0.36),Vector3(2.5,0.922,-2.9),material(Color(0.88,0.86,0.78)))
	box(self,Vector3(1.1,1.6,0.04),Vector3(2.1,1.8,-7.6),wood)
	# Moving cart creates lateral motion even with the security camera fixed.
	cart = Node3D.new()
	add_child(cart)
	box(cart,Vector3(1.05,0.12,0.8),Vector3(0,0.25,0),steel)
	box(cart,Vector3(0.76,0.64,0.64),Vector3(0,0.63,0),material(Color(0.45,0.3,0.16)))
	for x in [-0.43,0.43]:
		for z in [-0.3,0.3]:
			var wheel := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.1; mesh.bottom_radius = 0.1; mesh.height = 0.06
			wheel.mesh = mesh; wheel.material_override = dark
			wheel.rotation.z = PI/2
			wheel.position = Vector3(x,0.12,z)
			cart.add_child(wheel)
	fan = Node3D.new()
	fan.position = Vector3(0.5,3.12,-1.8)
	add_child(fan)
	box(fan,Vector3(1.6,0.045,0.16),Vector3.ZERO,trim)
	box(fan,Vector3(0.16,0.045,1.6),Vector3.ZERO,trim)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.04,0.05,0.05)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(0.45,0.51,0.6)
	world.environment.ambient_light_energy = 0.12 if security else 0.6
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(world)
	camera = Camera3D.new()
	camera.fov = 64
	camera.current = true
	add_child(camera)
	set_time(0)

func set_time(seconds: float) -> void:
	var phase := TAU*seconds/8.0
	cart.position = Vector3(1.25*sin(phase),0,-4.6)
	cart.rotation.y = 0.15*sin(phase)
	fan.rotation.y = phase*4
	if security:
		camera.position = Vector3(3.7,3.05,4.9)
		camera.look_at(Vector3(-0.7,0.9,-3.5))
	else:
		camera.position = Vector3(0.45*sin(phase),1.65+0.025*sin(phase*8),2.2+1.6*cos(phase))
		camera.look_at(Vector3(0.3*sin(phase),1.4,-5.7))
