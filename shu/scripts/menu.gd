extends CanvasLayer

# 启动菜单:标题页(开始/退出) → 选择模式(加减乘除) → 选择关卡

signal start_game(mode: String, level_index: int)

const LevelData := preload("res://scripts/level_data.gd")
const Progress := preload("res://scripts/progress.gd")
const Solvability := preload("res://scripts/solvability.gd")
const PlayerScene := preload("res://scenes/player.tscn")

# 模式列表:id 与 levels.json 里的 mode 对应,顺序即菜单显示顺序
const MODES := [
	{"id": "tutorial", "name": "教学"},
	{"id": "add", "name": "加法"},
	{"id": "sub", "name": "减法"},
	{"id": "mul", "name": "乘法"},
	{"id": "div", "name": "除法"},
	{"id": "op", "name": "运算符"},
	{"id": "memory", "name": "记忆翻牌"},
	{"id": "endless", "name": "无尽模式"},
]

# 中文字体候选:优先微软雅黑(粗体),逐级回退到其它常见系统字体
const TITLE_FONTS: PackedStringArray = [
	"Microsoft YaHei UI", "Microsoft YaHei", "微软雅黑",
	"PingFang SC", "Noto Sans CJK SC", "Source Han Sans SC",
	"SimHei", "黑体",
]

var _root: Control
var _main_page: Control
var _mode_page: Control
var _level_page: Control
var _level_list: VBoxContainer
var _mode_grid: GridContainer
var _selected_mode: String = "add"

var _font: SystemFont
var _hero_pivot: Node3D
var _title_label: Label
var _floaters: Array = []


func _ready() -> void:
	_font = _make_font()
	_build()


func _process(delta: float) -> void:
	if _hero_pivot and is_instance_valid(_hero_pivot):
		_hero_pivot.rotate_y(delta * 0.8)
	_update_floaters(delta)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_build_main_page()
	_build_mode_page()
	_build_level_page()
	_show_main()


# 标题页:大标题「数跃者」 + 主角 3D 展示 + 开始游戏 / 退出游戏
func _build_main_page() -> void:
	_main_page = Control.new()
	_main_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_main_page)
	_add_background(_main_page)
	_add_floaters(_main_page)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	_main_page.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "数跃者"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_title_label.add_theme_font_override("font", _font)
	_title_label.add_theme_font_size_override("font_size", 108)
	_title_label.add_theme_color_override("font_color", Color("#ff5d8f"))
	_title_label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.95))
	_title_label.add_theme_constant_override("outline_size", 16)
	_title_label.add_theme_color_override("font_shadow_color", Color(0.85, 0.3, 0.48, 0.35))
	_title_label.add_theme_constant_override("shadow_offset_x", 0)
	_title_label.add_theme_constant_override("shadow_offset_y", 8)
	_title_label.add_theme_constant_override("shadow_outline_size", 10)
	vbox.add_child(_title_label)
	_title_label.pivot_offset = _title_label.get_combined_minimum_size() / 2.0
	var breathe := create_tween().set_loops()
	breathe.tween_property(_title_label, "scale", Vector2(1.05, 1.05), 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	breathe.tween_property(_title_label, "scale", Vector2.ONE, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var subtitle := Label.new()
	subtitle.text = "数学跳一跳 · 益智闯关"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_override("font", _font)
	subtitle.add_theme_font_size_override("font_size", 30)
	subtitle.add_theme_color_override("font_color", Color("#5a4a66"))
	vbox.add_child(subtitle)

	# 主角展示(独立 3D 视口,缓慢旋转)
	var hero_center := CenterContainer.new()
	hero_center.add_child(_build_hero())
	vbox.add_child(hero_center)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	vbox.add_child(row)

	var start_btn := _make_button("开始游戏", Color("#ff7aa2"))
	start_btn.pressed.connect(_on_start_pressed)
	row.add_child(start_btn)

	var quit_btn := _make_button("退出游戏", Color("#9a8aa9"))
	quit_btn.pressed.connect(_on_quit_pressed)
	row.add_child(quit_btn)


# 选择模式页:加法 / 减法 / 乘法 / 除法
func _build_mode_page() -> void:
	_mode_page = Control.new()
	_mode_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_mode_page)
	_add_background(_mode_page)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	_mode_page.add_child(vbox)

	var header := Label.new()
	header.text = "选择模式"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_override("font", _font)
	header.add_theme_font_size_override("font_size", 56)
	header.add_theme_color_override("font_color", Color("#5a4a66"))
	vbox.add_child(header)

	_mode_grid = GridContainer.new()
	_mode_grid.columns = 2
	_mode_grid.add_theme_constant_override("h_separation", 28)
	_mode_grid.add_theme_constant_override("v_separation", 20)
	_populate_modes()
	var cgrid := CenterContainer.new()
	cgrid.add_child(_mode_grid)
	vbox.add_child(cgrid)

	var back_btn := _make_button("返回", Color("#9a8aa9"))
	back_btn.pressed.connect(_on_back_pressed)
	var c2 := CenterContainer.new()
	c2.add_child(back_btn)
	vbox.add_child(c2)


# 按当前解锁进度重建模式按钮:未解锁的章节显示 🔒 并禁用
func _populate_modes() -> void:
	for child in _mode_grid.get_children():
		child.queue_free()
	for m in MODES:
		var unlocked := Progress.is_mode_unlocked(m["id"])
		var label := ("🔒 " if not unlocked else "") + str(m["name"])
		var btn := _make_button(label, Color("#7fb0d1") if m["id"] == "endless" else Color("#ff7aa2"))
		if unlocked:
			btn.pressed.connect(_on_mode_pressed.bind(m["id"]))
		else:
			btn.disabled = true
			btn.add_theme_stylebox_override("disabled", _locked_style())
			btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.7))
		_mode_grid.add_child(btn)


# 选择关卡页:标题 + 关卡列表(按所选模式动态填充) + 返回
func _build_level_page() -> void:
	_level_page = Control.new()
	_level_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_level_page)
	_add_background(_level_page)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 28)
	_level_page.add_child(vbox)

	var header := Label.new()
	header.text = "选择关卡"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_override("font", _font)
	header.add_theme_font_size_override("font_size", 56)
	header.add_theme_color_override("font_color", Color("#5a4a66"))
	vbox.add_child(header)

	_level_list = VBoxContainer.new()
	_level_list.alignment = BoxContainer.ALIGNMENT_CENTER
	_level_list.add_theme_constant_override("separation", 18)
	vbox.add_child(_level_list)

	var back_btn := _make_button("返回", Color("#9a8aa9"))
	back_btn.pressed.connect(_on_level_back_pressed)
	var c2 := CenterContainer.new()
	c2.add_child(back_btn)
	vbox.add_child(c2)


# 按模式重建关卡按钮:未解锁置灰 🔒,几何不可解置灰 ⚠️
func _populate_levels(mode: String) -> void:
	for child in _level_list.get_children():
		child.queue_free()
	var mode_levels := LevelData.levels_of_mode(mode)
	var unlocked := Progress.unlocked_count(mode)
	for i in mode_levels.size():
		var locked: bool = i >= unlocked
		var b := _make_button("第 %d 关" % (i + 1), Color("#ff7aa2"))
		var c := CenterContainer.new()
		c.add_child(b)
		_level_list.add_child(c)
		var is_test := bool(mode_levels[i].get("test", false))
		var check: Dictionary = {}
		var broken := false
		if not is_test:
			check = Solvability.check(mode_levels[i]["grid"], mode_levels[i]["start"], mode_levels[i]["equation"], bool(mode_levels[i].get("sign_flip", false)))
			broken = not check["solvable"]
		if locked:
			b.text = "🔒 第 %d 关" % (i + 1)
			b.disabled = true
			b.add_theme_stylebox_override("disabled", _locked_style())
			b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.7))
		elif broken:
			b.text = "⚠️ 第 %d 关" % (i + 1)
			b.disabled = true
			b.add_theme_stylebox_override("disabled", _locked_style())
			b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.7))
			push_warning("关卡 %d 不可解:%s" % [i + 1, check["reason"]])
		else:
			b.pressed.connect(_on_level_pressed.bind(i))


# 渐变背景:顶部淡蓝 → 中部奶白 → 底部淡粉,替代原来的纯色
func _add_background(page: Control) -> void:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color("#b9dcff"), Color("#eef7ff"), Color("#ffe6f0")])
	grad.offsets = PackedFloat32Array([0.0, 0.52, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	var bg := TextureRect.new()
	bg.texture = tex
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(bg)


# 标题页装饰:漂浮的数字与运算符号(低透明度,缓慢上下浮动)
func _add_floaters(page: Control) -> void:
	var symbols := ["1", "2", "3", "5", "7", "9", "+", "−", "×", "÷", "="]
	var colors := [Color("#ff9aa2"), Color("#ffb7b2"), Color("#ffd166"), Color("#a2d2ff"), Color("#b5ead7"), Color("#c3b1e1")]
	var anchors := [
		Vector2(0.05, 0.06), Vector2(0.88, 0.05), Vector2(0.05, 0.40),
		Vector2(0.90, 0.38), Vector2(0.08, 0.80), Vector2(0.88, 0.80),
		Vector2(0.16, 0.18), Vector2(0.80, 0.20), Vector2(0.15, 0.64),
		Vector2(0.82, 0.66),
	]
	for i in anchors.size():
		var lbl := Label.new()
		lbl.text = symbols[i % symbols.size()]
		lbl.add_theme_font_override("font", _font)
		lbl.add_theme_font_size_override("font_size", 30 + (i * 11) % 40)
		lbl.add_theme_color_override("font_color", colors[i % colors.size()])
		lbl.modulate.a = 0.16
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.anchor_left = anchors[i].x
		lbl.anchor_right = anchors[i].x
		lbl.anchor_top = anchors[i].y
		lbl.anchor_bottom = anchors[i].y
		page.add_child(lbl)
		_floaters.append({"node": lbl, "t": i * 0.7, "phase": i * 1.1, "speed": 0.6 + (i % 5) * 0.14})


func _update_floaters(delta: float) -> void:
	for f in _floaters:
		var node: Label = f["node"]
		if not is_instance_valid(node):
			continue
		f["t"] = f["t"] + delta
		node.position.y = sin(f["t"] * f["speed"] + f["phase"]) * 14.0


# 主角展示:用 SubViewport 渲染真实的 3D 主角(黄色棋子),带底座与灯光,缓慢旋转
func _build_hero() -> Control:
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(300, 300)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sv := SubViewport.new()
	sv.transparent_bg = true
	sv.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	sv.size = Vector2i(600, 600)
	container.add_child(sv)

	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#ffffff")
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	sv.add_child(we)

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 30.0
	cam.look_at_from_position(Vector3(0.0, 1.0, 3.0), Vector3(0.0, 0.55, 0.0), Vector3.UP)
	sv.add_child(cam)

	var key := DirectionalLight3D.new()
	key.light_color = Color("#fff6e6")
	key.light_energy = 1.4
	key.rotation_degrees = Vector3(-48, -30, 0)
	sv.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#d8ecff")
	fill.light_energy = 0.8
	fill.rotation_degrees = Vector3(-28, 150, 0)
	sv.add_child(fill)

	# 底座圆台:给主角一个展示台
	var pedestal := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.85
	pc.bottom_radius = 0.98
	pc.height = 0.14
	pedestal.mesh = pc
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color("#ffd9e6")
	pm.roughness = 0.9
	pedestal.material_override = pm
	pedestal.position = Vector3(0, -0.07, 0)
	sv.add_child(pedestal)

	_hero_pivot = Node3D.new()
	sv.add_child(_hero_pivot)
	var player := PlayerScene.instantiate()
	_hero_pivot.add_child(player)

	return container


func _make_font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = TITLE_FONTS
	f.font_weight = 700
	return f


func _make_button(txt: String, color: Color) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(200, 64)
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", Color("#ffffff"))
	b.add_theme_color_override("font_hover_color", Color("#ffffff"))
	b.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	b.add_theme_color_override("font_focus_color", Color("#ffffff"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.set_corner_radius_all(32)
	b.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = color.lightened(0.15)
	hover.set_corner_radius_all(32)
	b.add_theme_stylebox_override("hover", hover)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = color.darkened(0.15)
	pressed.set_corner_radius_all(32)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


# 锁定关卡的灰色样式
func _locked_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#a8b0bd")
	sb.set_corner_radius_all(32)
	return sb


func _show_main() -> void:
	_main_page.visible = true
	_mode_page.visible = false
	_level_page.visible = false


func _show_modes() -> void:
	_populate_modes()
	_main_page.visible = false
	_mode_page.visible = true
	_level_page.visible = false


func _show_levels() -> void:
	_main_page.visible = false
	_mode_page.visible = false
	_level_page.visible = true


# 供外部直接跳到章节(模式)选择页:一章通关后回到这里
func show_mode_page() -> void:
	_show_modes()


func _on_start_pressed() -> void:
	_show_modes()


func _on_mode_pressed(mode: String) -> void:
	if mode == "endless":
		start_game.emit(mode, 0)  # 无尽模式直接开始,不走选关页
		return
	_selected_mode = mode
	_populate_levels(mode)
	_show_levels()


func _on_level_pressed(idx: int) -> void:
	start_game.emit(_selected_mode, idx)


func _on_back_pressed() -> void:
	_show_main()


func _on_level_back_pressed() -> void:
	_show_modes()


func _on_quit_pressed() -> void:
	get_tree().quit()
