extends Node3D

const Style := preload("res://scripts/theme.gd")

# 格子内容:kind ∈ {"num", "op"},value 为对应值(数字 int / 运算符 String)。
# "num" 且 value==0 表示自由垫(起点),不显示数字。
var kind: String = "num"
var value: Variant = 0

# 记忆玩法:数字默认隐藏,跳上去才 reveal,离开再 hide
var _memory: bool = false
var _revealed: bool = false

# 测试模式垫子:半径(用于落地判定)、顶面高度与是否为终点垫
var _radius: float = 0.85
var _top_y: float = 0.55
var _goal: bool = false

@onready var _base: MeshInstance3D = $Base
@onready var _label: Label3D = $NumberLabel

# 数字标签高度:记忆玩法竖直悬浮 / 其余玩法平躺在弹跳垫顶面
const FLOAT_LABEL_Y := 2.5
const FLAT_LABEL_Y := 0.59

# 测试模式:默认垫半径 + 矮中高三种垫顶面高度
const BASE_RADIUS := 0.85
const BASE_HEIGHT := 0.55
const TEST_PAD_HEIGHTS := {"low": 0.85, "medium": 1.25, "high": 1.65}


func _ready() -> void:
	_apply_label_layout()


# 数字在格子正上方轻轻上下浮动(仅记忆玩法用),让跳上去才显示的数字更直观
func _start_float() -> void:
	var base_y := _label.position.y
	var tween := create_tween().set_loops()
	tween.tween_property(_label, "position:y", base_y + 0.1, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_label, "position:y", base_y, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# 记忆玩法:数字竖直悬浮(billboard),跳上去才显示;其余玩法:数字平躺在弹跳垫顶面
func _apply_label_layout() -> void:
	if _memory:
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.rotation_degrees = Vector3.ZERO
		_label.position.y = FLOAT_LABEL_Y
		_start_float()
	else:
		_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		_label.rotation_degrees = Vector3(-90, 0, 0)
		_label.position.y = FLAT_LABEL_Y


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


# 测试模式垫子:按高度设圆柱高度/颜色,goal 为终点垫(金色),不显示数字
func set_test_pad(height: String, goal: bool) -> void:
	kind = "pad"
	value = 0
	_goal = goal
	_radius = BASE_RADIUS
	var h: float = TEST_PAD_HEIGHTS.get(height, 0.85)
	_top_y = h
	_base.scale = Vector3(1.0, h / BASE_HEIGHT, 1.0)
	_base.position.y = h * 0.5
	_base.material_override = Style.toon_material(_test_pad_color(height, goal), 0.4)
	_label.visible = false


# 测试模式起点垫:默认大小/高度 + 起点色
func set_start_pad() -> void:
	kind = "pad"
	value = 0
	_goal = false
	_radius = BASE_RADIUS
	_top_y = BASE_HEIGHT
	_base.scale = Vector3.ONE
	_base.position.y = BASE_HEIGHT * 0.5
	_base.material_override = Style.toon_material(Style.tile_color(0), 0.4)
	_label.visible = false


func radius() -> float:
	return _radius


# 测试模式垫子顶面的世界高度(圆柱顶面)
func top_height() -> float:
	return _top_y


func is_goal() -> bool:
	return _goal


func _test_pad_color(height: String, goal: bool) -> Color:
	if goal:
		return Color("#ffd166")  # 金色终点垫
	match height:
		"low":
			return Color("#7fd1b9")
		"medium":
			return Color("#7fb0d1")
		"high":
			return Color("#c9a0e6")
	return Color("#7fb0d1")


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
	_apply_label_layout()
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
