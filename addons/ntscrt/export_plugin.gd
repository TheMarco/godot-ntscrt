@tool
extends EditorExportPlugin
## JSON and source/license files are not ordinary Godot resources. Include them
## explicitly so manifests, canonical controls and attribution survive export.
func _get_name() -> String:
	return "NtscrtAssets"
func _export_begin(_features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
	_pack_directory("res://addons/ntscrt/third_party")
	for name: String in ["LICENSE","LICENSING.md"]:
		var file := "res://addons/ntscrt/"+name
		add_file(file,FileAccess.get_file_as_bytes(file),false)
func _pack_directory(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory==null:
		push_error("Missing NTSCRT export assets: " + path)
		return
	for name in directory.get_directories():
		if not name.begins_with("."): _pack_directory(path.path_join(name))
	for name in directory.get_files():
		if name.ends_with(".import") or name.ends_with(".uid") or name.begins_with("."): continue
		# Preserve original bytes of LUTs, source and licenses in the pack.
		var file := path.path_join(name)
		add_file(file,FileAccess.get_file_as_bytes(file),false)
