extends Node3D

signal landed(col: int, row: int, content: Dictionary)
signal departed(col: int, row: int)  # 真正跳离当前格时发出(记忆玩法用)
signal stomped(col: int, row: int)   # 蓄满翻转:原地跳一下(翻转符号玩法用)
signal fell_off(from_col: int, from_row: int)  # 蓄力过多跃出格子(惩罚:掉下去重来)

enum State { IDLE, CHARGING, JUMPING, STOMPING, FALLING }

const MAX_CHARGE := 1.2
const MAX_TILES := 3
const JUMP_DURATION := 0.32
const JUMP_HEIGHT := 1.4
const FALL_DURATION := 0.55  # 坠落(下坠+缩小+翻滚)时长

# 测试模式:鼠标点击弹跳垫设定角度,按住蓄力(力度),松开沿抛体轨迹跳跃
const TEST_MAX_CHARGE := 1.5   # 蓄满所需秒数
const TEST_GRAVITY := 8.0      # 抛体重力(越小弧线越平缓)
const TEST_MAX_SPEED := 6.5    # 满蓄力时的初速度
const TEST_PERFECT_CHARGE := 0.9  # 该蓄力比例下初速度刚好命中目标垫(0..1)

var grid: Node = null
var grid_col: int = 1
var grid_row: int = 3
var state: int = State.IDLE
var charge_dir: Vector2i = Vector2i.ZERO
var charge_time: float = 0.0
var _ground_y: float = 0.0  # 站立面高度(圆柱顶面),阴影贴在这里
var test_mode: bool = false

# 测试模式:瞄准状态(点击弹跳垫后设定)
var _aim_active: bool = false
var _aim_dir: Vector3 = Vector3.FORWARD  # 水平瞄准方向(单位向量)
var _aim_angle: float = 0.0              # 发射仰角(弧度)
var _aim_angle_deg: float = 0.0          # 发射仰角(度)
var _land_pad: Dictionary = {}           # 本次跳跃的落点垫
var _land_point: Vector3 = Vector3.ZERO  # 本次跳跃的落点世界坐标

@onready var _body: Node3D = $Body
@onready var _model: Node3D = $Body/Model
@onready var _shadow: MeshInstance3D = $Shadow
@onready var _charge_ring: MeshInstance3D = $ChargeRing

# 瞄准/轨迹可视化(代码动态创建)
var _aim_line: MeshInstance3D
var _angle_arc: MeshInstance3D
var _angle_label: Label3D
var _traj_line: MeshInstance3D
var _land_marker: MeshInstance3D


func _ready() -> void:
	# 棋子模型 glb 原始尺寸过大(高约 4.16),统一缩到 0.3 以匹配棋子格
	_model.scale = Vector3(0.3, 0.3, 0.3)
	# 蓄力环是 TorusMesh,默认就平躺(XZ 平面、中心轴沿 Y),无需旋转
	# 给棋子模型加一圈描边,让主角在深蓝格子上更突出
	_add_outline()
	_create_aim_visuals()


# 倒置外壳描边:复制模型网格,正面剔除 + 沿法线外扩,只留一圈深色轮廓
func _add_outline() -> void:
	var mesh_inst := _find_mesh_instance(_model)
	if mesh_inst == null or mesh_inst.mesh == null:
		return
	var outline := MeshInstance3D.new()
	outline.name = "Outline"
	outline.mesh = mesh_inst.mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	mat.grow = true
	mat.grow_amount = 0.12  # 局部空间外扩量,乘 0.3 缩放后约 0.036 世界单位
	mat.albedo_color = Color("#000000")
	outline.material_override = mat
	mesh_inst.add_child(outline)


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found:
			return found
	return null


func setup(controller: Node, col: int, row: int) -> void:
	grid = controller
	grid_col = col
	grid_row = row
	position = grid.grid_to_world(col, row)
	_ground_y = position.y


# 答错后把主角送回起始弹跳垫,并清空蓄力/跳跃状态
func reset_to(col: int, row: int) -> void:
	grid_col = col
	grid_row = row
	position = grid.grid_to_world(col, row)
	_ground_y = position.y
	state = State.IDLE
	charge_time = 0.0
	charge_dir = Vector2i.ZERO
	clear_aim()
	_charge_ring.visible = false
	_body.scale = Vector3.ONE
	_body.rotation = Vector3.ZERO


func face_toward(world_pos: Vector3) -> void:
	var d := world_pos - global_position
	d.y = 0.0
	if d.length() > 0.001:
		rotation.y = atan2(d.x, d.z)


# 测试模式:开启连续距离跳(并关闭空格蓄满翻转)
func set_test_mode(b: bool) -> void:
	test_mode = b


func _process(delta: float) -> void:
	_update_shadow()
	if grid and grid.is_busy():
		return
	if test_mode:
		_process_test(delta)
		return

	match state:
		State.IDLE:
			var d := _held_dir()
			if d != Vector2i.ZERO and _just_pressed(d):
				charge_dir = d
				state = State.CHARGING
				charge_time = 0.0
			elif Input.is_action_just_pressed("stomp"):
				state = State.STOMPING
				charge_time = 0.0
		State.CHARGING:
			charge_time += delta
			_update_squash()
			if _just_released(charge_dir):
				_do_jump()
		State.STOMPING:
			charge_time += delta
			_update_squash()
			if Input.is_action_just_released("stomp"):
				_do_stomp()
		State.JUMPING:
			pass
		State.FALLING:
			pass


# 测试模式:点击弹跳垫后,按住任意方向键蓄力(力度),松开跳跃
func _process_test(delta: float) -> void:
	match state:
		State.IDLE:
			if _aim_active and _any_dir_just_pressed():
				state = State.CHARGING
				charge_time = 0.0
		State.CHARGING:
			charge_time += delta
			_update_squash()
			_update_preview(clampf(charge_time / TEST_MAX_CHARGE, 0.0, 1.0))
			if _any_dir_just_released():
				_do_test_jump()
		State.JUMPING:
			pass
		State.FALLING:
			pass


func _update_shadow() -> void:
	_shadow.global_position = Vector3(global_position.x, _ground_y + 0.02, global_position.z)
	_charge_ring.position = Vector3(0, 0.06, 0)


func _update_squash() -> void:
	var p := clampf(charge_time / _max_charge(), 0.0, 1.0)
	_body.scale = Vector3(1.0 + 0.3 * p, 1.0 - 0.35 * p, 1.0 + 0.3 * p)
	_charge_ring.visible = true
	_charge_ring.scale = Vector3.ONE * (0.3 + 0.7 * p)
	# 蓄满后蓄力环变金色,提示"已经到最大距离"
	var rm := _charge_ring.material_override as StandardMaterial3D
	if rm:
		rm.emission = Color("#ffd166") if p >= 1.0 else Color("#ff7aa2")


# 蓄力时长 -> 跳跃格数(1..MAX_TILES)
func _charge_distance() -> int:
	var f := clampf(charge_time / MAX_CHARGE, 0.0, 1.0)
	return clampi(ceili(f * MAX_TILES), 1, MAX_TILES)


# 当前蓄力对应的最长时长(测试模式用更长的蓄满时间)
func _max_charge() -> float:
	return TEST_MAX_CHARGE if test_mode else MAX_CHARGE


# 供 HUD 读取:当前蓄力进度(0..1),非蓄力时为 0
func charge_progress() -> float:
	if state != State.CHARGING and state != State.STOMPING:
		return 0.0
	return clampf(charge_time / _max_charge(), 0.0, 1.0)


# 供 HUD 读取:当前蓄力对应的跳跃格数(1..MAX_TILES),非蓄力时为 0
func charge_tiles() -> int:
	if state != State.CHARGING and state != State.STOMPING:
		return 0
	return _charge_distance()


# 供 HUD 读取:当前是否在蓄力翻转(空格)
func is_stomping() -> bool:
	return state == State.STOMPING


# 供 main 读取:当前是否在坠落动画(冻结光标/重置输入用)
func is_falling() -> bool:
	return state == State.FALLING


# 供 main 读取:当前是否在空中(跳跃/坠落动画),用于禁用选点
func is_airborne() -> bool:
	return state == State.JUMPING or state == State.FALLING


# 落地按"蓄力对应的格"精确判定:落点不在格子(跃出/空洞)则掉下去,交给 main 惩罚
func _do_jump() -> void:
	_charge_ring.visible = false
	_body.scale = Vector3.ONE
	var from := Vector2i(grid_col, grid_row)
	var dist := _charge_distance()
	var target := Vector2i(grid_col + charge_dir.x * dist, grid_row + charge_dir.y * dist)
	if not grid.is_walkable(target.x, target.y):
		_fall_off(from, target)
		return
	departed.emit(from.x, from.y)
	grid_col = target.x
	grid_row = target.y
	state = State.JUMPING
	_jump_arc(position, grid.grid_to_world(target.x, target.y), dist)


# ---- 测试模式:角度 + 蓄力 -> 抛体轨迹 -------------------------------------

# 点击弹跳垫后由 main 调用:设定发射角度(仰角)与水平瞄准方向
func aim_at(world_target: Vector3) -> void:
	var d := world_target - position
	var r := Vector2(d.x, d.z).length()
	if r < 0.05:
		clear_aim()
		return
	_aim_dir = Vector3(d.x, 0.0, d.z).normalized()
	var dy := world_target.y - position.y
	var speed := TEST_PERFECT_CHARGE * TEST_MAX_SPEED
	_aim_angle = _ballistic_angle(r, dy, speed)
	_aim_angle_deg = rad_to_deg(_aim_angle)
	_aim_active = true
	_refresh_aim_visual()


# 取消瞄准(重新选落点)
func clear_aim() -> void:
	_aim_active = false
	_refresh_aim_visual()
	_hide_preview()


# 求命中水平距离 r、高度差 dy 的目标点所需的发射仰角(高抛角),speed 为参考初速度
func _ballistic_angle(r: float, dy: float, speed: float) -> float:
	var a := TEST_GRAVITY * r * r / (2.0 * speed * speed)
	var disc := r * r - 4.0 * a * (dy + a)
	if disc < 0.0:
		# 目标超出满蓄力射程:退化为比视线更陡的高抛角(预览会显示落不到)
		return atan2(dy, r) + 0.7
	var tan_t := (r + sqrt(disc)) / (2.0 * a)
	return atan(tan_t)


# 测试模式跳跃:按当前蓄力算初速度,沿设定角度抛体飞出,落地判断所在垫子
func _do_test_jump() -> void:
	_charge_ring.visible = false
	_body.scale = Vector3.ONE
	if not _aim_active:
		state = State.IDLE
		return
	var aim_dir := _aim_dir
	var aim_angle := _aim_angle
	clear_aim()
	var power := clampf(charge_time / TEST_MAX_CHARGE, 0.0, 1.0)
	var speed := power * TEST_MAX_SPEED
	var vx := speed * cos(aim_angle)
	var vy := speed * sin(aim_angle)
	var v0 := Vector3(aim_dir.x * vx, vy, aim_dir.z * vx)
	var land: Dictionary = grid.test_landing_pad(position, aim_dir, vx, vy, TEST_GRAVITY)
	state = State.JUMPING
	_body.scale = Vector3(0.9, 1.15, 0.9)
	var dur: float
	var end: Vector3
	if land.is_empty():
		_land_pad = {}
		dur = 2.0 * vy / TEST_GRAVITY
		if dur <= 0.0:
			dur = 0.3
		end = position + _trajectory_points(v0, dur)["end"]
	else:
		_land_pad = land
		dur = land["time"]
		end = land["point"]
	_land_point = end
	var ctrl := position + v0 * (dur * 0.5)
	var t := create_tween()
	t.tween_method(_jump_pos.bind(position, ctrl, end), 0.0, 1.0, dur)
	t.tween_callback(_on_test_land)


# 测试模式落地:落在某垫上就站在那;没落在垫上则滑落坠下
func _on_test_land() -> void:
	state = State.IDLE
	if _land_pad.is_empty():
		_test_slide_off()
		return
	_body.scale = Vector3(1.35, 0.6, 1.35)
	var t := create_tween()
	t.tween_property(_body, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	grid_col = _land_pad["col"]
	grid_row = _land_pad["row"]
	_ground_y = _land_point.y
	landed.emit(grid_col, grid_row, _land_pad["content"])


# 测试模式坠空:滑落 + 前倾 + 下坠缩小翻滚,动画播完才发 fell_off
func _test_slide_off() -> void:
	state = State.FALLING
	var dir := _aim_dir
	var slide := create_tween()
	slide.tween_property(self, "position", position + dir * 0.2, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	slide.parallel().tween_property(_body, "rotation:x", -0.45, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await slide.finished
	var fall := create_tween()
	fall.tween_property(self, "position:y", _ground_y - 1.4, FALL_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.parallel().tween_property(_body, "scale", Vector3(0.25, 0.25, 0.25), FALL_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.parallel().tween_property(_body, "rotation:y", _body.rotation.y + TAU, FALL_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await fall.finished
	fell_off.emit(grid_col, grid_row)


# ---- 测试模式:瞄准 / 轨迹可视化 -------------------------------------------

# 创建瞄准线、角度弧、角度文字、轨迹预览线、落点标记
func _create_aim_visuals() -> void:
	_aim_line = _make_line_node()
	_angle_arc = _make_line_node()
	_traj_line = _make_line_node()

	_land_marker = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.3
	disc.bottom_radius = 0.3
	disc.height = 0.04
	_land_marker.mesh = disc
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_land_marker.material_override = mm
	_land_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_land_marker.visible = false
	add_child(_land_marker)

	_angle_label = Label3D.new()
	_angle_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_angle_label.font_size = 48
	_angle_label.pixel_size = 0.006
	_angle_label.outline_size = 10
	_angle_label.modulate = Color("#ffffff")
	_angle_label.outline_modulate = Color(0.05, 0.1, 0.25, 1)
	_angle_label.visible = false
	add_child(_angle_label)


func _make_line_node() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


# 用折线(LineStrip)重建一条 ImmediateMesh 线
func _draw_line(mi: MeshInstance3D, points: PackedVector3Array, color: Color) -> void:
	if points.size() < 2:
		mi.mesh = null
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in points:
		im.surface_add_vertex(p)
	im.surface_end()
	mi.mesh = im
	var mat := mi.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = color


# 瞄准线 + 角度弧 + 角度文字(全部以主角为原点,局部坐标)
func _refresh_aim_visual() -> void:
	if not _aim_active:
		_aim_line.visible = false
		_angle_arc.visible = false
		_angle_label.visible = false
		return
	var cos_a := cos(_aim_angle)
	var sin_a := sin(_aim_angle)
	var launch := Vector3(_aim_dir.x * cos_a, sin_a, _aim_dir.z * cos_a)
	# 发射方向线
	var ray := PackedVector3Array()
	ray.append(Vector3.ZERO)
	ray.append(launch * 2.8)
	_draw_line(_aim_line, ray, Color("#ffffff"))
	_aim_line.visible = true
	# 角度弧:从水平方向转到发射仰角
	var arc := PackedVector3Array()
	var radius := 0.8
	var n := 14
	for i in range(n + 1):
		var a := _aim_angle * (float(i) / float(n))
		arc.append(Vector3(_aim_dir.x * cos(a), sin(a), _aim_dir.z * cos(a)) * radius)
	_draw_line(_angle_arc, arc, Color("#ff7aa2"))
	_angle_arc.visible = true
	_angle_label.text = "%.0f°" % _aim_angle_deg
	_angle_label.position = launch * 1.2 + Vector3(0.0, 0.2, 0.0)
	_angle_label.visible = true


# 蓄力时:画轨迹抛物线 + 落点标记
func _update_preview(power: float) -> void:
	var speed := power * TEST_MAX_SPEED
	if speed <= 0.01 or not _aim_active:
		_hide_preview()
		return
	var vx := speed * cos(_aim_angle)
	var vy := speed * sin(_aim_angle)
	var v0 := Vector3(_aim_dir.x * vx, vy, _aim_dir.z * vx)
	var land: Dictionary = grid.test_landing_pad(position, _aim_dir, vx, vy, TEST_GRAVITY)
	var dur: float
	var end_local: Vector3
	if land.is_empty():
		dur = 2.0 * vy / TEST_GRAVITY
		if dur <= 0.0:
			dur = 0.3
		end_local = _trajectory_points(v0, dur)["end"]
	else:
		dur = land["time"]
		end_local = land["point"] - position
	var ctrl_local := v0 * (dur * 0.5)
	var pts := PackedVector3Array()
	var n := 24
	for i in range(n + 1):
		var k := float(i) / float(n)
		pts.append(_bezier_point(k, Vector3.ZERO, ctrl_local, end_local))
	_draw_line(_traj_line, pts, Color("#ffd166"))
	_traj_line.visible = true
	_land_marker.position = end_local
	var mm := _land_marker.material_override as StandardMaterial3D
	if mm:
		mm.albedo_color = Color("#7fd1b9") if not land.is_empty() else Color("#ff6b6b")
	_land_marker.visible = true


func _hide_preview() -> void:
	_traj_line.visible = false
	_land_marker.visible = false


# 由初速度与飞行时长算二次贝塞尔控制点与终点(相对发射点,局部坐标)
func _trajectory_points(v0: Vector3, dur: float) -> Dictionary:
	var ctrl := v0 * (dur * 0.5)
	var end := v0 * dur
	end.y -= 0.5 * TEST_GRAVITY * dur * dur
	return {"ctrl": ctrl, "end": end}


func _bezier_point(k: float, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ik := 1.0 - k
	return a * ik * ik + b * 2.0 * ik * k + c * k * k


func _any_dir_just_pressed() -> bool:
	return Input.is_action_just_pressed("jump_up") or Input.is_action_just_pressed("jump_down") \
		or Input.is_action_just_pressed("jump_left") or Input.is_action_just_pressed("jump_right")


func _any_dir_just_released() -> bool:
	return Input.is_action_just_released("jump_up") or Input.is_action_just_released("jump_down") \
		or Input.is_action_just_released("jump_left") or Input.is_action_just_released("jump_right")


# ---- 普通模式:格子跳 / 蓄力翻转 -------------------------------------------

# 跃出格子:先跳到那个"没有格子"的空位,再从空位坠落(下坠+缩小+翻滚),最后发 fell_off
func _fall_off(from: Vector2i, target: Vector2i) -> void:
	state = State.FALLING
	var start := position
	var target_world: Vector3 = grid.grid_to_world(target.x, target.y)
	var tiles := maxi(absi(target.x - from.x), absi(target.y - from.y))
	# 第一步:和正常跳一样的弧线,跳到空位(那里脚下没有格子)
	var mid := (start + target_world) * 0.5 + Vector3(0, JUMP_HEIGHT * tiles, 0)
	_body.scale = Vector3(0.9, 1.15, 0.9)
	var jump := create_tween()
	jump.tween_method(_jump_pos.bind(start, mid, target_world), 0.0, 1.0, JUMP_DURATION * tiles)
	await jump.finished
	# 第二步:从空位坠落
	var fall := create_tween()
	fall.tween_property(self, "position:y", target_world.y - 1.4, FALL_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.parallel().tween_property(_body, "scale", Vector3(0.25, 0.25, 0.25), FALL_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.parallel().tween_property(_body, "rotation:y", _body.rotation.y + TAU, FALL_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await fall.finished
	state = State.IDLE
	fell_off.emit(from.x, from.y)


# 蓄满后松开空格:原地跳一下,并翻转脚下格子的符号
func _do_stomp() -> void:
	_charge_ring.visible = false
	_body.scale = Vector3.ONE
	if charge_time < MAX_CHARGE:
		# 没蓄满就松手,只原地弹一下,不翻转
		state = State.IDLE
		_cancel_boing()
		return
	state = State.IDLE
	var t := create_tween()
	t.tween_property(self, "position:y", _ground_y + 0.7, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "position:y", _ground_y, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	stomped.emit(grid_col, grid_row)


func _jump_arc(start: Vector3, end: Vector3, tiles: int) -> void:
	var mid := (start + end) * 0.5 + Vector3(0, JUMP_HEIGHT * tiles, 0)
	_body.scale = Vector3(0.9, 1.15, 0.9)
	var t := create_tween()
	t.tween_method(_jump_pos.bind(start, mid, end), 0.0, 1.0, JUMP_DURATION * tiles)
	t.tween_callback(_on_land)


func _jump_pos(k: float, a: Vector3, b: Vector3, c: Vector3) -> void:
	var ik := 1.0 - k
	position = a * ik * ik + b * 2.0 * ik * k + c * k * k


func _on_land() -> void:
	state = State.IDLE
	_body.scale = Vector3(1.35, 0.6, 1.35)
	var t := create_tween()
	t.tween_property(_body, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	landed.emit(grid_col, grid_row, grid.cell_content_at(grid_col, grid_row))


func _cancel_boing() -> void:
	var t := create_tween()
	t.tween_property(_body, "scale", Vector3(0.9, 1.1, 0.9), 0.08)
	t.tween_property(_body, "scale", Vector3.ONE, 0.12)


func _held_dir() -> Vector2i:
	if Input.is_action_pressed("jump_up"):
		return Vector2i(0, -1)
	if Input.is_action_pressed("jump_down"):
		return Vector2i(0, 1)
	if Input.is_action_pressed("jump_left"):
		return Vector2i(-1, 0)
	if Input.is_action_pressed("jump_right"):
		return Vector2i(1, 0)
	return Vector2i.ZERO


func _action_for(d: Vector2i) -> String:
	if d == Vector2i(0, -1):
		return "jump_up"
	if d == Vector2i(0, 1):
		return "jump_down"
	if d == Vector2i(-1, 0):
		return "jump_left"
	if d == Vector2i(1, 0):
		return "jump_right"
	return ""


func _just_pressed(d: Vector2i) -> bool:
	return Input.is_action_just_pressed(_action_for(d))


func _just_released(d: Vector2i) -> bool:
	return Input.is_action_just_released(_action_for(d))
