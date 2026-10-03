@tool
extends EditorPlugin
const EXPORTER = preload("res://addons/ntscrt/export_plugin.gd")
var _exporter: EditorExportPlugin
func _enter_tree() -> void:
	_exporter = EXPORTER.new()
	add_export_plugin(_exporter)
func _exit_tree() -> void:
	remove_export_plugin(_exporter)
	_exporter = null
