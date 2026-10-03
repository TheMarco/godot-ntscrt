extends RefCounted
## Port of NTSCRT Receiver.swift / GlitchStage.swift; upstream authors retain copyright.
## Source revision, descriptors and provenance: tools/ntscrt/receiver_schema.json.
## GPU owns gate measurements and color recurrence; CPU only evolves timing metadata.
## Call on the rendering thread. Never submits, synchronizes or reads scene pixels.
const H = 63.556
const RATE = 60000.0 / 1001.0
const B0 = 20.0 / 92.5
const BI = 0.5446390350150271
const BQ = -0.8386705679454240
const SEED = 0x4E5453435254
var output = RID()
var error = ""
var extent = Vector2i.ZERO
var _rd: RenderingDevice
var _owned: Array[RID] = []
var _shaders: Array[RID] = []
var _pipelines: Array[RID] = []
var _sets: Dictionary = {}
var _buffers: Array[RID] = []
var _sampler = RID()
var _params: Array = []
var _last_frame = -1
var _settings = {}
var k = {}
var L = 0
var vbi = 0
var eq = 0
var scale = 1.0
var us_second = 0.0
var cap = 0
var nominal = 0
var r = 0
var theta = 0.0
var integ = 0.0
var vp = 0.0
var vi = 0.0
var va = false
var gate_err = 0.0
var triggers: Array[int] = []
var theta_log = PackedFloat64Array()
var gate_log = PackedFloat64Array()

func _own(id: RID) -> RID:
	if id.is_valid(): _owned.append(id)
	return id

func setup(rd: RenderingDevice, size: Vector2i) -> bool:
	dispose()
	_rd = rd
	error = ""
	extent = size
	if size.x < 1 or size.y < 1:
		error = "Receiver extent must be positive"
		return false
	_params = JSON.parse_string(FileAccess.get_file_as_string("res://addons/ntscrt/third_party/receiver_schema.json")).parameters
	vbi = maxi(12, roundi(size.y * 20.0 / 242.5))
	L = size.y + vbi
	scale = float(L) / 262.5
	eq = maxi(1, roundi(3 * scale))
	us_second = H * L * RATE
	cap = 4 * L + 64
	theta_log.resize(cap)
	gate_log.resize(cap)
	var tf = RDTextureFormat.new()
	tf.width = size.x
	tf.height = size.y
	tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	output = _own(rd.texture_create(tf, RDTextureView.new()))
	_sampler = _own(rd.sampler_create(RDSamplerState.new()))
	for bytes in [size.y * 48,128,size.y * 8,size.y * 16,64 * 16]:
		_buffers.append(_own(rd.storage_buffer_create(bytes)))
	for name in ["gate","chroma","compose"]:
		var shader_path = "res://addons/ntscrt/shaders/ntscrt_receiver_gpu/"+name+".glsl"
		var spv: RDShaderSPIRV
		if FileAccess.file_exists(shader_path):
			var source = RDShaderSource.new()
			source.source_compute = FileAccess.get_file_as_string(shader_path).replace("#[compute]", "")
			spv = rd.shader_compile_spirv_from_source(source)
		else:
			# Godot exports GLSL as imported RDShaderFile resources. Source is
			# available in development but may be omitted from the packed game.
			var shader_file = load(shader_path) as RDShaderFile
			if shader_file == null:
				error = "Missing receiver compute shader: " + shader_path
				return false
			spv = shader_file.get_spirv()
		var message = spv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		if not message.is_empty():
			error = name + ": " + message
			return false
		var shader = _own(rd.shader_create_from_spirv(spv))
		_shaders.append(shader)
		_pipelines.append(_own(rd.compute_pipeline_create(shader)))
	_reset()
	_knobs({})
	_advance(0.0)
	nominal = posmod(triggers[-1], L) if not triggers.is_empty() else eq + 2
	_reset()
	return output.is_valid() and _pipelines.size() == 3

func _reset() -> void:
	r = 0; theta = 0.0; integ = 0.0; vp = 0.0; vi = 0.0; va = false; gate_err = 0.0
	triggers.clear()
	theta_log.fill(0.0)
	gate_log.fill(0.0)

func _knobs(settings: Dictionary) -> void:
	_settings = {}
	for p in _params:
		var value = float(settings.get(p.id,p.default))
		if not is_finite(value): value = p.default
		_settings[p.id] = clampf(value,p.min,p.max)
	var s = _settings
	var strength = s.signal_strength
	var hk = absf(s.horizontal_hold)
	var kp = 0.04 * pow(10.0,s.afc_speed)
	var edge = 0.04 * pow(10.0,0.5) / TAU
	var hf = edge * pow(hk / 0.35,2) if hk <= 0.35 else edge + 0.0265 * (hk - 0.35) / 0.65
	k = {"sigma":maxf(0.0,100 * pow(10.0,-1.9 * strength) - 1.26 * pow(strength,4)),
		"agc":minf(1.0,strength / 0.45),"vt":0.002 + (-1 if s.vertical_hold < 0 else 1) * 0.10 * pow(absf(s.vertical_hold),1.37),
		"vc":asin(0.002 / 0.015) / TAU,"vb":1 - exp(-1 / (1.5 * scale)),
		"hr":(-1 if s.horizontal_hold < 0 else 1) * hf / scale,"kp":kp / scale,"ki":pow(kp / 1.4,2) / (scale * scale),
		"hum":s.hum * 60,"head":s.head_switch,"jitter":s.timebase_jitter,"crinkle":s.crinkle,"clog":s.head_clog,
		"search":s.search_speed,"tracking":s.tracking,"drops":s.dropouts,"captions":s.closed_captions >= 0.5,
		"ga":1-exp(-1/(6*scale)),"ca":1-exp(-1/(4*scale)),"acc":1-exp(-1/(8*scale)),"kk":1-exp(-1/(15*scale))}

# SplitMix64 exactly as upstream, using wrapping signed ints and logical shifts.
static func _shr(x: int, n: int) -> int:
	return (x >> n) & ((1 << (64-n))-1)
static func _mix(x: int) -> int:
	var z = x + -7046029254386353131
	z = (z ^ _shr(z,30)) * -4658895280553007687
	z = (z ^ _shr(z,27)) * -7723592293110705685
	return z ^ _shr(z,31)
static func _uni(p: int, a: int, b: int = 0) -> float:
	return float(_shr(_mix(SEED ^ _mix(p ^ _mix(a ^ _mix(b)))),11)) / 9007199254740992.0
static func _gauss(p: int, a: int, b: int = 0) -> float:
	return sqrt(-2 * log(maxf(1e-12,_uni(p,a,b)))) * cos(TAU * _uni(p+0x51,a,b))
static func _value(p: int, x: float) -> float:
	var i = floori(x)
	var f = x-i
	return lerpf(_uni(p,i)*2-1,_uni(p,i+1)*2-1,f*f*(3-2*f))
static func _phi(x: float) -> float:
	# Standard normal CDF, Abramowitz-Stegun error < 7.5e-8.
	var t = 1.0 / (1.0 + 0.2316419 * absf(x))
	var q = exp(-x*x/2) / sqrt(TAU) * t * (0.319381530 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))))
	return 1-q if x >= 0 else q

func _search(j: int) -> Vector2:
	var x = float(posmod(j,L))/L * (k.search-1) + fmod(_time(j)*0.23,1.0)
	var phase = x-floor(x)
	return Vector2(clampf((1-minf(phase,1-phase)/0.15)*1.2,0,1),floor(x))
func _time(j: int) -> float:
	return float(j)/(L*RATE)
func _crinkle(j: int) -> Vector2:
	var t = _time(j)
	var slot = floori(t/0.5)
	var best = Vector2.ZERO
	for q in range(slot-1,slot+1):
		if _uni(51,q) >= k.crinkle*0.6: continue
		var start = q*0.5 + _uni(52,q)*0.5
		var duration = 0.12+0.35*_uni(53,q)
		if t < start or t >= start+duration: continue
		var severity = 0.55+0.45*_uni(54,q)
		var progress = (t-start)/duration
		var envelope = sin(PI*progress)
		var center = fmod(_uni(56,q)+progress*(0.8+1.6*_uni(55,q)),1.0)
		var d = absf(float(posmod(j,L))/L-center)
		d = minf(d,1-d)
		var intensity = minf(1.0,severity*envelope*maxf(0,1-d/(0.05+0.08*severity))*1.4)
		if intensity > best.x: best = Vector2(intensity,envelope)
		elif envelope > best.y: best.y = envelope
	return best
func _tb(j: int) -> float:
	var e = 0.0
	if k.head > 0:
		var switch_line = L-roundi(3.5*scale)
		var f = floori(float(j)/L)
		var head = posmod(f+(1 if posmod(j,L)>=switch_line else 0),2)
		var hf = floori(float(j+roundi(3.5*scale))/L)
		e += (0.5 if head == 0 else -0.5)*k.head*(1+0.15*_gauss(31,hf))
	if k.jitter > 0: e += k.jitter*(_value(32,float(j)/scale/40)+_gauss(33,j)*0.35)
	if k.search > 1.05: e += 1.2*_gauss(36,floori(float(j)/L),int(_search(j).y))
	if k.crinkle > 0:
		var c = _crinkle(j)
		if c.x > 0: e += c.x*4*_value(34,float(j)/scale/3)+c.y*1.5*_value(35,float(j)/scale/60)
	return e
func _loss(j: int) -> float:
	var loss = 0.0
	if k.clog > 0:
		var f = floori(float(j)/L)
		loss = minf(1.0,0.85+0.15*_uni(42,f) if _uni(41,f)<k.clog*0.8 else 0.35*k.clog*k.clog)
	if k.crinkle > 0: loss = maxf(loss,_crinkle(j).x)
	if k.search > 1.05: loss = maxf(loss,_search(j).x)
	if k.tracking > 0:
		var center = 1-0.55*k.tracking+0.03*_value(37,_time(j)*1.7)
		var d = absf(float(posmod(j,L))/L-center)
		d = minf(d,1-d)
		loss = maxf(loss,minf(1.0,maxf(0.0,1-d/(0.02+0.10*k.tracking))*minf(1.0,0.4+k.tracking)))
	return loss
func _hum(tau: float) -> float:
	if k.hum <= 0: return 0.0
	var t = tau/us_second
	return k.hum*(0.8*sin(TAU*60*t)+0.3*sin(TAU*120*t+0.7))
func _sigma(loss: float) -> float:
	return sqrt(k.sigma*k.sigma+pow(loss*90,2))
func _signal(tau: float) -> Array:
	var j = floori(tau/H)
	if tau < j*H+_tb(j): j -= 1
	elif tau >= (j+1)*H+_tb(j+1): j += 1
	return [j,tau-(j*H+_tb(j))]
func _logged(logs: PackedFloat64Array, line: int, fallback: float) -> float:
	return logs[posmod(line,cap)] if line >= 0 and line < r and r-line <= cap else fallback
func _advance(time: float) -> void:
	var target = (time+2.0)*us_second
	while r*H+theta <= target: _step()
func _step() -> void:
	var tau = r*H+theta
	var j = roundi(tau/H)
	var edge = j*H+_tb(j)
	if tau-edge > H/2: j += 1; edge = j*H+_tb(j)
	elif edge-tau > H/2: j -= 1; edge = j*H+_tb(j)
	var jf = posmod(j,L)
	var loss = _loss(j)
	var sigma = _sigma(loss)*0.35
	var hum = _hum(tau)
	var sm = 20-0.4*hum
	var bm = 20+0.4*hum
	var pd = _phi(sm/sigma) if sigma > 0 else (1.0 if sm > 0 else 0.0)
	var pn = _phi(-bm/sigma) if sigma > 0 else (0.0 if bm > 0 else 1.0)
	var present = 1-minf(1,loss*loss*1.2)
	var detected = false
	var d0 = 0.0
	if _uni(11,r)<minf(1,10*pn): detected = true; d0 = (_uni(12,r)-0.5)*H*0.6
	elif _uni(13,r)<pd*present: detected = true; d0 = edge-tau+_gauss(14,r)*sigma*0.0125+hum*0.05
	var next = theta+H*k.hr+integ
	if detected:
		var d = H/TAU*sin(TAU*d0/H)
		next += k.kp*d
		if absf(d0)<=H/4: integ = 0.0 # upstream uMax is exactly zero
	var duty = (2*2.3/H if jf<eq or (jf>=2*eq and jf<3*eq) else (2*27.1/H if jf<2*eq else 4.7/H))*present
	var measured = duty*pd+(1-duty)*pn
	var variance = (duty*pd*(1-pd)+(1-duty)*pn*(1-pn))/60
	if variance>0: measured += _gauss(15,r)*sqrt(variance)
	vi += (measured-vi)*k.vb
	var vsync = false
	if va:
		if vi<0.25: va = false
	elif vi>=0.45: va = true; vsync = true
	vp += 1+(next-theta)/H
	var period = L*(1+k.vt)
	if vsync:
		var e = vp/period-k.vc
		e -= round(e)
		vp -= 0.015*period*sin(TAU*e)
	if vp>=period:
		vp -= period
		triggers.append(r)
		if triggers.size()>16: triggers.pop_front()
	if detected:
		var d = edge-tau-gate_err
		d -= H*round(d/H)
		gate_err += k.ga*d
		gate_err -= H*round(gate_err/H)
	theta_log[posmod(r,cap)] = theta
	gate_log[posmod(r,cap)] = gate_err
	theta = next
	r += 1

func _dropouts(field: int) -> PackedByteArray:
	var data = PackedByteArray()
	var rate = k.drops
	if rate<=0: return data
	var mean = rate*rate*14
	var count = clampi(roundi(mean+sqrt(mean)*_gauss(61,field)),0,64)
	for i in count:
		var line = vbi+int(_uni(62,field,i)*extent.y)
		var start = 9.4+_uni(63,field,i)*52.656*0.95
		var length = clampf(-log(maxf(1e-6,_uni(64,field,i)))*(1.5+5*rate),0.4,30)
		var span = 1+int(pow(_uni(65,field,i),2)*4)
		for q in span:
			if data.size()>=64*16 or line+q>=L: break
			var offset = data.size()
			data.resize(offset+16)
			data.encode_s32(offset,line+q)
			data.encode_float(offset+4,start+_gauss(66,field,i*8+q)*0.8)
			data.encode_float(offset+8,length*(0.7+0.6*_uni(67,field,i*8+q)))
	return data
func _caption_char(field: int, index: int) -> int:
	var c = 0x20+int(_uni(71,field,index)*90)
	var ones = 0
	for bit in 7: ones += (c>>bit)&1
	return c | (0x80 if ones%2==0 else 0)

func _plan() -> Array:
	var offset = vbi-nominal
	var last = r-1
	var scan = last-offset-extent.y+1
	for index in range(triggers.size()-1,-1,-1):
		if triggers[index]+offset+extent.y-1<=last:
			scan = triggers[index]
			break
	var first = scan+offset
	var rows = PackedByteArray()
	rows.resize(extent.y*48)
	for y in extent.y:
		var line = first+y
		var tau = line*H+_logged(theta_log,line,theta)
		var signal_at = _signal(tau)
		var j = int(signal_at[0])
		var loss = _loss(j)
		var values = [signal_at[1],0,H+_tb(j)-_tb(j-1),H+_tb(j+1)-_tb(j),H+_tb(j+2)-_tb(j+1),k.sigma,_hum(tau),maxf(0,1-loss),clampf(loss,0,1),_logged(gate_log,line,gate_err),0,0]
		for c in 12: rows.encode_float(y*48+c*4,values[c])
		rows.encode_s32(y*48+4,posmod(j,L))
	var phase = 0.0
	var gain = 1.0
	var killer = 1.0
	var on = true
	for w in range(maxi(4,roundi(12*scale)),0,-1):
		var line = first-w
		var retrace = false
		for trigger in triggers:
			if line>=trigger and line<trigger+maxi(2,roundi(9*scale)): retrace = true; break
		if retrace: continue
		var signal_at = _signal(line*H+_logged(theta_log,line,theta))
		var j = int(signal_at[0])
		var gi = 0.0
		var gq = 0.0
		var g0 = signal_at[1]+_logged(gate_log,line,gate_err)
		if posmod(j,L)>=3*eq:
			var overlap = maxf(0,minf(g0+8.55,7.8)-maxf(g0+4.55,5.3))/2.5
			var amp = B0*overlap*k.agc*maxf(0,1-_loss(j))
			gi = amp*BI; gq = amp*BQ
		var noise = _sigma(_loss(j))/92.5*0.45
		if noise>0: gi += _gauss(21,line)*noise; gq += _gauss(22,line)*noise
		var mag = sqrt(gi*gi+gq*gq)
		var c = cos(-phase)
		var s = sin(-phase)
		var ri = gi*c-gq*s
		var rq = gi*s+gq*c
		if mag>0: phase += k.ca*minf(1,mag/B0)*atan2(BI*rq-BQ*ri,ri*BI+rq*BQ)
		c = cos(-phase); s = sin(-phase)
		var in_phase = (gi*c-gq*s)*BI+(gi*s+gq*c)*BQ
		gain = clampf(gain+k.acc*(B0/maxf(in_phase,0.25*B0)-gain),0.3,3)
		killer += k.kk*(clampf(in_phase/B0,-1,1)-killer)
		if on and killer<0.3: on = false
		elif not on and killer>0.5: on = true
	var top = _signal(first*H+_logged(theta_log,first,theta))
	var field = floori(float(top[0])/L)
	var drops = _dropouts(field)
	var bits = (4 | (_caption_char(field,0)<<3) | (_caption_char(field,1)<<11)) if k.captions else 0
	var uniforms = PackedByteArray()
	uniforms.resize(128)
	var upp = 52.656/extent.x
	var ints = [extent.x,extent.y,vbi,L,eq,2*eq,3*eq,1 if k.captions else 0,bits,scan&0xffffffff,0x9e3779b9,drops.size()/16,1 if _settings.dropout_compensation>=0.5 else 0,maxi(1,roundi(0.38/upp)),maxi(1,roundi(0.83/upp)),1 if on else 0]
	for i in 16: uniforms.encode_u32(i*4,int(ints[i]))
	var ghost_angle = -TAU*(315.0/88.0)*_settings.ghost_delay
	var floats = [upp,H,_settings.ghost_level,_settings.ghost_delay,cos(ghost_angle),sin(ghost_angle),_settings.brightness,_snap(k.agc,1),B0*k.agc,k.ca,k.acc,k.kk,_snap(phase,0),_snap(gain,1),_snap(killer,1),0.45]
	for i in 16: uniforms.encode_float(64+i*4,floats[i])
	drops.resize(64*16)
	return [rows,uniforms,drops]
static func _snap(value: float, target: float) -> float:
	return target if absf(value-target)<1e-6 else value

func render(input: RID, frame_number: int, settings: Dictionary) -> RID:
	if not error.is_empty() or not input.is_valid() or _pipelines.size()!=3: return RID()
	_knobs(settings)
	# Backwards seeks restart the deterministic timing simulation. Forward calls
	# evolve at NTSC field rate; a frame number denotes one supplied field.
	# Display frames can share a field while gameplay changes the knobs. Keep
	# the live clock/history in that case: rewarming here stalls the render
	# thread for two simulated seconds on every such change.
	if frame_number<_last_frame or frame_number-_last_frame>60:
		_reset()
		# Interactive seeks have no historic settings stream to replay. Settle
		# for the original two-second warmup at the requested absolute signal
		# position, bounding cost independently of the size of the jump.
		r = maxi(0,frame_number)*L
	_advance(maxf(0,frame_number/RATE))
	_last_frame = frame_number
	var plan = _plan()
	_rd.buffer_update(_buffers[0],0,plan[0].size(),plan[0])
	_rd.buffer_update(_buffers[1],0,128,plan[1])
	_rd.buffer_update(_buffers[4],0,plan[2].size(),plan[2])
	var key = input.get_id()
	if not _sets.has(key):
		var sets: Array[RID] = []
		for shader in _shaders:
			var uniforms: Array[RDUniform] = []
			for binding in 7:
				var u = RDUniform.new()
				u.binding = binding
				if binding<5:
					u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
					u.add_id(_buffers[binding])
				elif binding==5:
					u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
					u.add_id(_sampler); u.add_id(input)
				else:
					u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
					u.add_id(output)
				uniforms.append(u)
			sets.append(_own(_rd.uniform_set_create(uniforms,shader,0)))
		_sets[key] = sets
	var list = _rd.compute_list_begin()
	for i in 3:
		_rd.compute_list_bind_compute_pipeline(list,_pipelines[i])
		_rd.compute_list_bind_uniform_set(list,_sets[key][i],0)
		if i==0: _rd.compute_list_dispatch(list,ceili(extent.y/8.0),1,1)
		elif i==1: _rd.compute_list_dispatch(list,1,1,1)
		else: _rd.compute_list_dispatch(list,ceili(extent.x/8.0),ceili(extent.y/8.0),1)
		if i<2: _rd.compute_list_add_barrier(list)
	_rd.compute_list_end()
	return output

func dispose() -> void:
	if _rd!=null:
		for i in range(_owned.size()-1,-1,-1):
			if _owned[i].is_valid(): _rd.free_rid(_owned[i])
	_owned.clear(); _buffers.clear(); _shaders.clear(); _pipelines.clear(); _sets.clear()
	output = RID()
	_last_frame = -1
	_rd = null
