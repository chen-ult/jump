extends RefCounted

# 主题/配色与材质工具。颜色从 levels/levels.json 读取,方便小白直接改色。

const TOON_SHADER := preload("res://shaders/toon.gdshader")
const CONFIG_PATH := "res://levels/levels.json"

static var _palette: Array = []
static var _start_color: Color = Color("#b5e6c3")
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if parsed is Dictionary:
		if parsed.get("tile_colors") is Array:
			for hex in parsed["tile_colors"]:
				_palette.append(Color(str(hex)))
		if parsed.has("start_color"):
			_start_color = Color(str(parsed["start_color"]))


static func toon_material(color: Color, rim_strength: float = 0.35) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON_SHADER
	m.set_shader_parameter("albedo_color", color)
	m.set_shader_parameter("rim_color", Color(1.0, 1.0, 1.0))
	m.set_shader_parameter("rim_strength", rim_strength)
	return m


static func tile_color(n: int) -> Color:
	_ensure_loaded()
	if n <= 0:
		return _start_color
	var i := int(n) - 1
	if i >= 0 and i < _palette.size():
		return _palette[i]
	return Color(0.9, 0.9, 0.9)
