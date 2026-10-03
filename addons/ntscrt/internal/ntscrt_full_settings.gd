extends RefCounted
## Canonical settings shared by persistence, original controls, and the GPU port.
## Runtime schemas live outside tools/ so exported builds retain them.

static var _ntsc_schema: Dictionary = {}
static var _receiver_schema: Dictionary = {}


static func ntsc_descriptors() -> Array:
	if _ntsc_schema.is_empty():
		_ntsc_schema = _read_schema("res://addons/ntscrt/third_party/ntsc_schema.json")
	return _ntsc_schema.get("settings", []).duplicate(true)


static func receiver_descriptors() -> Array:
	if _receiver_schema.is_empty():
		_receiver_schema = _read_schema("res://addons/ntscrt/third_party/receiver_schema.json")
	var result: Array = []
	for source: Dictionary in _receiver_schema.get("parameters", []):
		var descriptor := source.duplicate(true)
		descriptor["name"] = source["id"]
		descriptor["type"] = "boolean" if source["kind"] == "toggle" else "float"
		descriptor["description"] = source.get("help", "")
		if descriptor["type"] == "boolean":
			descriptor["default"] = bool(source["default"])
		result.append(descriptor)
	return result


static func ntsc_defaults() -> Dictionary:
	return _defaults(ntsc_descriptors())


static func receiver_defaults() -> Dictionary:
	return _defaults(receiver_descriptors())


static func sanitize_ntsc(raw: Variant) -> Dictionary:
	return _sanitize(raw, ntsc_descriptors())


static func sanitize_receiver(raw: Variant) -> Dictionary:
	return _sanitize(raw, receiver_descriptors())


static func _read_schema(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("Unable to load canonical NTSCRT schema: " + path)
	return {}


static func _flatten(descriptors: Array) -> Array:
	var result: Array = []
	for descriptor: Dictionary in descriptors:
		result.append(descriptor)
		result.append_array(_flatten(descriptor.get("children", [])))
	return result


static func _defaults(descriptors: Array) -> Dictionary:
	var result: Dictionary = {}
	for descriptor: Dictionary in _flatten(descriptors):
		var value: Variant = descriptor["default"]
		if descriptor["type"] in ["int", "enum"]:
			value = int(value)
		result[descriptor["name"]] = value
	return result


static func _sanitize(raw: Variant, descriptors: Array) -> Dictionary:
	var result := _defaults(descriptors)
	if not raw is Dictionary:
		return result
	for descriptor: Dictionary in _flatten(descriptors):
		var key: String = descriptor["name"]
		if not raw.has(key):
			continue
		var value: Variant = raw[key]
		var kind: String = descriptor["type"]
		if kind in ["boolean", "group"]:
			if value is bool:
				result[key] = value
			continue
		if not (value is int or value is float) or not is_finite(float(value)):
			continue
		if kind == "enum":
			for option: Dictionary in descriptor["options"]:
				if float(value) == float(option["index"]):
					result[key] = int(value)
					break
		else:
			var minimum: float = float(descriptor.get("min", 0.0))
			var maximum: float = float(descriptor.get("max", 1.0))
			var bounded: float = clampf(float(value), minimum, maximum)
			result[key] = int(bounded) if kind == "int" else bounded
	return result
