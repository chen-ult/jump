extends Node3D

const Style := preload("res://scripts/theme.gd")

# 格子内容:kind ∈ {"num", "op"},value 为对应值(数字 int / 运算符 String)。
# "num" 且 value==0 表示自由垫(起点),不显示数字。
var kind: String = "num"
var value: Variant = 0

# 记忆玩法:数字默认隐藏,跳上去才 reveal,离开再 hide
var _memory: bool = false
var _revealed: bool = false

@onready var _base: MeshInstance3D = $Base
@onready var _label: Label3D = $NumberLabel


func _ready() -> void:
	_start_float()


# 数字在格子正上方轻轻上下浮动,让可跳落的数字更直观
func _start_float() -> void:
	var base_y := _label.position.y
	var tween := create_tween().set_loops()
	tween.tween_property(_label, "position:y", base_y + 0.1, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_label, "position:y", base_y, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# 由 main 在实例化后调用:设置内容(类型 + 值)并刷新颜色/文字。
func set_content(k: String, v) -> void:
	kind = k
	value = v
	_refresh_color()
	_refresh_label()


func _refresh_color() -> void:
	if _base:
		_base.material_override = Style.toon_material(_color_for(), 0.4)


func _refresh_label() -> void:
	if not _label:
		return
	if _should_show_label():
		_label.visible = true
		_label.text = str(value)
	else:
		_label.visible = false


# 是否显示文字:运算符恒显;数字格值≠0 显示;记忆模式未 reveal 时隐藏
func _should_show_label() -> bool:
	if _memory and not _revealed:
		return false
	if kind == "op":
		return true
	return (value is int) and value != 0


func _color_for() -> Color:
	if kind == "op":
		return Color("#b06aa0")  # 与 HUD 运算符色一致
	var n: int = value if (value is int) else 0
	if n < 0:
		return Color("#ff6b6b")  # 负数用红色,和正数/自由垫区分
	return Style.tile_color(n)


# 蓄满翻转符号:正数变负数、负数变正数。返回新值;不可翻(运算符/0)返回 0。
func flip_sign() -> int:
	if kind != "num" or not (value is int) or value == 0:
		return 0
	value = -value
	_refresh_color()
	_refresh_label()
	return value


# 记忆玩法:开启后隐藏数字,reveal() 才显示,离开后 hide_label() 再隐藏
func set_memory(b: bool) -> void:
	_memory = b
	_revealed = false
	_refresh_label()


func reveal() -> void:
	_revealed = true
	_refresh_label()


func hide_label() -> void:
	_revealed = false
	_refresh_label()


func play_land_feedback() -> void:
	var t := create_tween()
	t.tween_property(self, "scale", Vector3(1.12, 0.9, 1.12), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
