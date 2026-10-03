extends SceneTree
## Asset-only audit, also runnable from a minimal exported pack without a GPU.
## Copy as res://audit.gd into the staged project so tools/* exclusion remains real.
var failures: Array[String] = []
var checked = 0
var lut_hashes = {}
var baseline = {}
func _check(ok: bool, label: String) -> void:
	checked += 1
	if not ok: failures.append(label); push_error(label)
func _initialize() -> void:
	_check(FileAccess.file_exists("res://addons/ntscrt/third_party/LICENSE.ntsc-rs.txt"),"Packaged ntsc-rs Apache license exists")
	var baseline_path = "res://addons/ntscrt/third_party/audit_lut_hashes.json"
	if FileAccess.file_exists(baseline_path): baseline = JSON.parse_string(FileAccess.get_file_as_string(baseline_path))
	for path in ["res://addons/ntscrt/third_party/receiver_schema.json","res://addons/ntscrt/third_party/ntsc_schema.json","res://addons/ntscrt/third_party/glitch_sequences.json"]:
		_check(FileAccess.file_exists(path),"Packed schema exists: "+path)
		if FileAccess.file_exists(path): _check(JSON.parse_string(FileAccess.get_file_as_string(path))!=null,"Packed schema parses: "+path)
	for path in ["res://addons/ntscrt/shaders/ntscrt_downscale_gpu/pipeline.glsl","res://addons/ntscrt/shaders/ntscrs_gpu/pipeline.glsl","res://addons/ntscrt/shaders/ntscrt_receiver_gpu/gate.glsl","res://addons/ntscrt/shaders/ntscrt_receiver_gpu/chroma.glsl","res://addons/ntscrt/shaders/ntscrt_receiver_gpu/compose.glsl"]:
		var shader = load(path) as RDShaderFile
		_check(shader!=null,"Packed RDShaderFile loads: "+path)
		if shader!=null:
			_check(shader.get_spirv().compile_error_compute.is_empty(),"Packed SPIR-V has no compile error: "+path)
			_check(not shader.get_spirv().bytecode_compute.is_empty(),"Packed SPIR-V contains bytecode: "+path)
		print("EXPORT_SHADER ",path," raw_source=",FileAccess.file_exists(path)," imported=",shader!=null)
	var manifest = "res://addons/ntscrt/third_party/slang/presets.json"
	_check(FileAccess.file_exists(manifest),"Packed Slang manifest exists")
	if FileAccess.file_exists(manifest):
		var data = JSON.parse_string(FileAccess.get_file_as_string(manifest))
		_check(data is Dictionary and data.has("presets"),"Packed Slang manifest parses")
		if data is Dictionary and data.has("presets"):
			var seen = {}
			for preset in data.presets.values():
				for shader_pass in preset.passes:
					_check(not str(shader_pass.vertex).is_empty() and not str(shader_pass.fragment).is_empty(),"Slang pass source embedded: "+str(shader_pass.path))
				for lut in preset.textures.values():
					var path = "res://addons/ntscrt/third_party/slang/upstream/"+str(lut.path)
					if seen.has(path): continue
					seen[path] = true
					var image: Image
					if FileAccess.file_exists(path):
						image = Image.new()
						_check(image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))==OK,"Raw LUT decodes: "+path)
					else:
						var texture = load(path) as Texture2D
						if texture!=null: image = texture.get_image()
					_check(image!=null and not image.is_empty(),"Packed LUT decodes through source/import fallback: "+path)
					if image!=null and not image.is_empty():
						if image.is_compressed(): _check(image.decompress()==OK,"Packed LUT decompresses: "+path)
						image.convert(Image.FORMAT_RGBA8)
						var hash = HashingContext.new()
						hash.start(HashingContext.HASH_SHA256)
						hash.update(image.get_data())
						lut_hashes[path] = hash.finish().hex_encode()
						if baseline.has(path): _check(lut_hashes[path]==baseline[path],"Packed LUT pixels match original PNG: "+path)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--write-baseline="):
			var file = FileAccess.open(arg.trim_prefix("--write-baseline="),FileAccess.WRITE)
			file.store_string(JSON.stringify(lut_hashes))
	print("NTSCRT_EXPORT_AUDIT ","PASS" if failures.is_empty() else "FAIL", " checks=",checked," failures=",failures)
	quit(0 if failures.is_empty() else 1)
