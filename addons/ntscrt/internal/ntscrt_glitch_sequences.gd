extends RefCounted
## Original NTSCRT timeline tracks, adapted to a short readable game cue.
## Shader, resolution and receiver settings are deliberately not animated.
const PATH := "res://addons/ntscrt/third_party/glitch_sequences.json"
const LIMITS := {
	"bandwidth_scale": Vector2(0.65,1.3),
	"composite_preemphasis": Vector2(0.3,1.3),
	"vertical_scale": Vector2(0.7,1.7),
	"vhs_chroma_loss": Vector2(0.0,0.1),
	"vhs_edge_wave": Vector2(0.0,4.0),
	"vhs_edge_wave_frequency": Vector2(0.02,0.32),
	"vhs_edge_wave_speed": Vector2(1.0,10.0),
	"vhs_edge_wave_detail": Vector2(1.0,3.0),
}
static var _sequences: Dictionary = {}

static func prepare() -> void:
	if not _sequences.is_empty(): return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if data is Dictionary: _sequences = data.get("sequences",{})

static func _ease(kind: String, u: float) -> float:
	match kind:
		"Ease in": return u*u
		"Ease out": return 1.0-(1.0-u)*(1.0-u)
		"Ease in-out": return 2.0*u*u if u<0.5 else 1.0-pow(-2.0*u+2.0,2.0)/2.0
		"Hold": return 0.0
	return u

## The original outgoing-key easing and integer/toggle rules are retained.
static func sample(identifier: String, phase: float) -> Dictionary:
	prepare()
	var keys: Array = _sequences.get(identifier,{}).get("keys",[])
	if keys.is_empty(): return {}
	var a: Dictionary = keys[0]
	var b: Dictionary = a
	for key: Dictionary in keys:
		if float(key.t)<=phase:
			a = key; b = key
		else:
			b = key; break
	var span := float(b.t)-float(a.t)
	var u := _ease(str(a.easing),clampf((phase-float(a.t))/span,0.0,1.0)) if span>0.0 else 0.0
	var result: Dictionary = {}
	for key: String in a.ntsc:
		var value: Variant = a.ntsc[key]
		if value is bool:
			result[key] = value
		else:
			var blended := lerpf(float(value),float(b.ntsc.get(key,value)),u)
			result[key] = roundi(blended) if key == "vhs_edge_wave_detail" else blended
	return result

## Overlay on a fresh copy of the active preset, never saved settings. This
## guarantees a complete restore at the end or when comfort/stage gates close.
static func apply_to(base: Dictionary, identifier: String, phase: float, strength: float) -> void:
	if phase<=0.0 or phase>=1.0 or strength<=0.0: return
	var blend := clampf(strength,0.0,1.0)*smoothstep(0.0,0.06,phase)*(1.0-smoothstep(0.88,1.0,phase))
	var values := sample(identifier,phase)
	for key: String in values:
		var value: Variant = values[key]
		if not base.has(key): continue
		if value is bool:
			if blend>=0.5: base[key] = value
		elif LIMITS.has(key):
			var bounds: Vector2 = LIMITS[key]
			var next := lerpf(float(base[key]),clampf(float(value),bounds.x,bounds.y),blend)
			base[key] = roundi(next) if key == "vhs_edge_wave_detail" else next
