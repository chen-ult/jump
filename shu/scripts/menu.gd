extends CanvasLayer

# 启动菜单:标题页(开始/退出) → 选择模式(加法) → 选择关卡(第1/2/3关)

signal start_game(level_index: int)

const LevelData := preload("res://scripts/level_data.gd")
const Progress := preload("res://scripts/progress.gd")

var _root: Control
var _main_page: Control
var _mode_page: Control
var _level_page: Control


func _ready() -> void:
	_build()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_build_main_page()
	_build_mode_page()
	_build_level_page()
	_show_main()


# 标题页:大标题 MathJumper + 开始游戏 / 退出游戏
func _build_main_page() -> void:
	_main_page = Control.new()
	_main_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_main_page)
	_add_background(_main_page)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 60)
	_main_page.add_child(vbox)

	var title := Label.new()
	title.text = "MathJumper"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Color("#1e3a8a"))
	title.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	title.add_theme_constant_override("outline_size", 12)
	vbox.add_child(title)

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


# 选择模式页:目前只有加法
func _build_mode_page() -> void:
	_mode_page = Control.new()
	_mode_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_mode_page)
	_add_background(_mode_page)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 40)
	_mode_page.add_child(vbox)

	var header := Label.new()
	header.text = "选择模式"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 56)
	header.add_theme_color_override("font_color", Color("#5a4a66"))
	vbox.add_child(header)

	var add_btn := _make_button("加法", Color("#ff7aa2"))
	add_btn.pressed.connect(_on_addition_pressed)
	var c1 := CenterContainer.new()
	c1.add_child(add_btn)
	vbox.add_child(c1)

	var back_btn := _make_button("返回", Color("#9a8aa9"))
	back_btn.pressed.connect(_on_back_pressed)
	var c2 := CenterContainer.new()
	c2.add_child(back_btn)
	vbox.add_child(c2)


# 选择关卡页:按"加法"模式动态列出第1/2/3关
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
	header.add_theme_font_size_override("font_size", 56)
	header.add_theme_color_override("font_color", Color("#5a4a66"))
	vbox.add_child(header)

	var add_levels := LevelData.levels_of_mode("add")
	var unlocked := Progress.unlocked_count("add")
	for i in add_levels.size():
		var locked: bool = i >= unlocked
		var b := _make_button("第 %d 关" % (i + 1), Color("#ff7aa2"))
		var c := CenterContainer.new()
		c.add_child(b)
		vbox.add_child(c)
		if locked:
			b.text = "🔒 第 %d 关" % (i + 1)
			b.disabled = true
			b.add_theme_stylebox_override("disabled", _locked_style())
			b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.7))
		else:
			b.pressed.connect(_on_level_pressed.bind(i))

	var back_btn := _make_button("返回", Color("#9a8aa9"))
	back_btn.pressed.connect(_on_level_back_pressed)
	var c2 := CenterContainer.new()
	c2.add_child(back_btn)
	vbox.add_child(c2)


func _add_background(page: Control) -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("#eaf4ff")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(bg)


func _make_button(txt: String, color: Color) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(200, 64)
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
	_main_page.visible = false
	_mode_page.visible = true
	_level_page.visible = false


func _show_levels() -> void:
	_main_page.visible = false
	_mode_page.visible = false
	_level_page.visible = true


func _on_start_pressed() -> void:
	_show_modes()


func _on_addition_pressed() -> void:
	_show_levels()


func _on_level_pressed(idx: int) -> void:
	start_game.emit(idx)


func _on_back_pressed() -> void:
	_show_main()


func _on_level_back_pressed() -> void:
	_show_modes()


func _on_quit_pressed() -> void:
	get_tree().quit()
