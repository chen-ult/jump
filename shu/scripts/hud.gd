extends CanvasLayer

# 等式 HUD:关卡标签 + 等式 token + 圆圈高亮 + 结算横幅 + 暂停

signal pause_pressed
signal resume_pressed
signal quit_pressed
signal next_mode_pressed
signal menu_pressed

const SLOT_SIZE := 76.0
const BORDER_DEFAULT := Color("#e6d9ef")
const BORDER_ACTIVE := Color("#ff7aa2")
const BORDER_WRONG := Color("#ff4d6d")

var _root: Control
var _level_label: Label
var _eq_box: HBoxContainer
var _banner: CenterContainer
var _banner_label: Label
var _charge_root: Control
var _charge_bar: ProgressBar
var _charge_label: Label
var _fill_sb: StyleBoxFlat
var _pause_btn: Button
var _pause_overlay: Control
var _next_overlay: Control
var _next_btn: Button
var _next_menu_btn: Button

var slot_labels: Array = []
var slot_styles: Array = []
var _active_index: int = -1
var _pulse_tween: Tween
var _hint_label: Label


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# 左上角:关卡标签
	_level_label = _make_label("", 34, Color("#5a4a66"))
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_level_label.anchor_left = 0.0
	_level_label.anchor_top = 0.0
	_level_label.anchor_right = 0.0
	_level_label.anchor_bottom = 0.0
	_level_label.offset_left = 22.0
	_level_label.offset_top = 14.0
	_level_label.offset_right = 300.0
	_level_label.offset_bottom = 62.0
	_root.add_child(_level_label)

	# 顶部居中:题目 + 操作提示(一起靠顶)
	var top := VBoxContainer.new()
	top.anchor_left = 0.0
	top.anchor_right = 1.0
	top.anchor_top = 0.0
	top.offset_top = 10.0
	top.add_theme_constant_override("separation", 10)
	_root.add_child(top)

	_eq_box = HBoxContainer.new()
	_eq_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_eq_box.add_theme_constant_override("separation", 16)
	var c2 := CenterContainer.new()
	c2.add_child(_eq_box)
	top.add_child(c2)

	_hint_label = _make_label("W A S D 蓄力跳 · ← → 移动圆圈", 20, Color("#9a8aa9"))
	var c3 := CenterContainer.new()
	c3.add_child(_hint_label)
	top.add_child(c3)

	_banner = CenterContainer.new()
	_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner.visible = false
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_label = _make_label("", 96, Color("#ffffff"))
	_banner_label.add_theme_color_override("font_outline_color", Color("#ff9aa2"))
	_banner_label.add_theme_constant_override("outline_size", 28)
	_banner.add_child(_banner_label)
	_root.add_child(_banner)

	_build_charge_ui()
	_build_pause_ui()
	_build_next_overlay()


func _make_label(txt: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


# 底部居中的蓄力条:显示进度 + 跳跃格数,蓄满变金色
func _build_charge_ui() -> void:
	_charge_root = Control.new()
	_charge_root.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_charge_root.offset_top = -130.0
	_charge_root.offset_bottom = -44.0
	_charge_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_charge_root.visible = false
	_root.add_child(_charge_root)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_charge_root.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)

	_charge_label = _make_label("跳 1 格", 24, Color("#5a4a66"))
	box.add_child(_charge_label)

	_charge_bar = ProgressBar.new()
	_charge_bar.custom_minimum_size = Vector2(300, 28)
	_charge_bar.min_value = 0.0
	_charge_bar.max_value = 1.0
	_charge_bar.value = 0.0
	_charge_bar.show_percentage = false
	_charge_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.25)
	bg.set_corner_radius_all(14)
	_charge_bar.add_theme_stylebox_override("background", bg)
	_fill_sb = StyleBoxFlat.new()
	_fill_sb.bg_color = Color("#ff7aa2")
	_fill_sb.set_corner_radius_all(14)
	_charge_bar.add_theme_stylebox_override("fill", _fill_sb)
	box.add_child(_charge_bar)


# 右上角暂停按钮 + 暂停弹层(继续游戏 / 退出)
func _build_pause_ui() -> void:
	_pause_btn = Button.new()
	_pause_btn.text = "⏸"
	_pause_btn.add_theme_font_size_override("font_size", 30)
	_pause_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_pause_btn.offset_left = -76.0
	_pause_btn.offset_top = 14.0
	_pause_btn.offset_right = -16.0
	_pause_btn.offset_bottom = 62.0
	_pause_btn.pressed.connect(_on_pause_btn_pressed)
	_root.add_child(_pause_btn)

	# 弹层 process_mode=ALWAYS,保证 get_tree().paused 时仍可点击
	_pause_overlay = Control.new()
	_pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_overlay.visible = false
	_root.add_child(_pause_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.5)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_overlay.add_child(dim)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 26)
	_pause_overlay.add_child(vbox)

	var title := Label.new()
	title.text = "暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color("#ffffff"))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("outline_size", 10)
	vbox.add_child(title)

	var resume_btn := _make_pause_button("继续游戏", Color("#ff7aa2"))
	resume_btn.pressed.connect(_on_resume_btn_pressed)
	var c1 := CenterContainer.new()
	c1.add_child(resume_btn)
	vbox.add_child(c1)

	var quit_btn := _make_pause_button("退出", Color("#9a8aa9"))
	quit_btn.pressed.connect(_on_quit_btn_pressed)
	var c2 := CenterContainer.new()
	c2.add_child(quit_btn)
	vbox.add_child(c2)


func _make_pause_button(txt: String, color: Color) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(220, 60)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", Color("#ffffff"))
	b.add_theme_color_override("font_hover_color", Color("#ffffff"))
	b.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.set_corner_radius_all(30)
	b.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = color.lightened(0.15)
	hover.set_corner_radius_all(30)
	b.add_theme_stylebox_override("hover", hover)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = color.darkened(0.15)
	pressed.set_corner_radius_all(30)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


func _on_pause_btn_pressed() -> void:
	_pause_overlay.visible = true
	pause_pressed.emit()


func _on_resume_btn_pressed() -> void:
	_pause_overlay.visible = false
	resume_pressed.emit()


func _on_quit_btn_pressed() -> void:
	_pause_overlay.visible = false
	quit_pressed.emit()


func set_charge(progress: float, tiles: int, stomp: bool = false) -> void:
	if progress <= 0.0 or tiles <= 0:
		_charge_root.visible = false
		return
	_charge_root.visible = true
	_charge_bar.value = progress
	_charge_label.text = "蓄力翻转" if stomp else "跳 %d 格" % tiles
	var full: bool = progress >= 1.0
	_fill_sb.bg_color = Color("#ffd166") if full else Color("#ff7aa2")
	_charge_label.add_theme_color_override("font_color", Color("#b07a2f") if full else Color("#5a4a66"))


func set_level(n: int) -> void:
	_level_label.text = "第 %d 关" % n


func set_hint(txt: String) -> void:
	if _hint_label:
		_hint_label.text = txt


func set_tokens(tokens: Array) -> void:
	for c in _eq_box.get_children():
		c.queue_free()
	slot_labels.clear()
	slot_styles.clear()
	_active_index = -1
	for tok in tokens:
		match tok["type"]:
			"num":
				_eq_box.add_child(_make_label(str(tok["value"]), 54, Color("#5a4a66")))
			"op":
				_eq_box.add_child(_make_label(str(tok["value"]), 54, Color("#b06aa0")))
			"slot":
				var s := _make_slot()
				_eq_box.add_child(s)
				slot_labels.append(s)


func _make_slot() -> Label:
	var l := Label.new()
	l.text = "?"
	l.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 44)
	l.add_theme_color_override("font_color", Color("#5a4a66"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.95)
	sb.set_corner_radius_all(int(SLOT_SIZE / 2.0))
	_set_border(sb, BORDER_DEFAULT, 5)
	l.add_theme_stylebox_override("normal", sb)
	slot_styles.append(sb)
	return l


func _set_border(sb: StyleBoxFlat, color: Color, w: int) -> void:
	sb.border_color = color
	sb.border_width_left = w
	sb.border_width_right = w
	sb.border_width_top = w
	sb.border_width_bottom = w


func set_active(i: int) -> void:
	if i < 0 or i >= slot_labels.size():
		return
	if _active_index >= 0 and _active_index < slot_styles.size():
		_set_border(slot_styles[_active_index], BORDER_DEFAULT, 5)
	_active_index = i
	_set_border(slot_styles[i], BORDER_ACTIVE, 7)
	_pulse(slot_labels[i])


func _pulse(l: Label) -> void:
	if _pulse_tween:
		_pulse_tween.kill()
	l.pivot_offset = Vector2(SLOT_SIZE / 2.0, SLOT_SIZE / 2.0)
	l.scale = Vector2.ONE
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(l, "scale", Vector2(1.12, 1.12), 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(l, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func set_slot_value(i: int, v) -> void:
	if i >= 0 and i < slot_labels.size():
		slot_labels[i].text = str(v)


func clear_slots() -> void:
	for l in slot_labels:
		l.text = "?"


func show_wrong(txt: String = "再试一次～") -> void:
	_show_banner(txt, 1.1)
	for sb in slot_styles:
		_set_border(sb, BORDER_WRONG, 6)
	var t := create_tween()
	t.tween_interval(0.55)
	t.tween_callback(_restore_borders)


func _restore_borders() -> void:
	for i in slot_styles.size():
		_set_border(slot_styles[i], BORDER_DEFAULT, 5)
	if _active_index >= 0 and _active_index < slot_styles.size():
		_set_border(slot_styles[_active_index], BORDER_ACTIVE, 7)


func show_win() -> void:
	_show_banner("🎉 太棒了！", 2.0)


func show_finish() -> void:
	_banner_label.text = "🎉 全部通关！"
	_banner_label.add_theme_color_override("font_color", Color("#ffd166"))
	_banner.visible = true


func _show_banner(txt: String, dur: float) -> void:
	_banner_label.text = txt
	_banner_label.add_theme_color_override("font_color", Color("#ffd166"))
	_banner.visible = true
	var t := create_tween()
	t.tween_interval(dur)
	t.tween_callback(func(): _banner.visible = false)


# 通关某模式全部关卡后弹出的「进入下一运算?」提示层
func _build_next_overlay() -> void:
	_next_overlay = Control.new()
	_next_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_next_overlay.visible = false
	_root.add_child(_next_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.5)
	_next_overlay.add_child(dim)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 26)
	_next_overlay.add_child(vbox)

	var title := _make_label("🎉 本模式全部通关！", 48, Color("#ffd166"))
	vbox.add_child(title)

	_next_btn = _make_pause_button("进入下一运算", Color("#ff7aa2"))
	_next_btn.custom_minimum_size = Vector2(300, 64)
	_next_btn.pressed.connect(_on_next_btn_pressed)
	var c1 := CenterContainer.new()
	c1.add_child(_next_btn)
	vbox.add_child(c1)

	_next_menu_btn = _make_pause_button("返回菜单", Color("#9a8aa9"))
	_next_menu_btn.pressed.connect(_on_next_menu_btn_pressed)
	var c2 := CenterContainer.new()
	c2.add_child(_next_menu_btn)
	vbox.add_child(c2)


func show_next_mode(mode_name: String) -> void:
	_next_btn.text = "进入下一运算：" + mode_name
	_next_overlay.visible = true


func hide_next_overlay() -> void:
	_next_overlay.visible = false


func _on_next_btn_pressed() -> void:
	next_mode_pressed.emit()


func _on_next_menu_btn_pressed() -> void:
	menu_pressed.emit()
