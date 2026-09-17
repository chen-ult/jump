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

# 测试模式:按住方向键蓄力(蓄力时间决定跳跃距离),松开沿该方向跳出
const TEST_MAX_CHARGE := 1.5   # 蓄满所需秒数

var grid: Node = null
var grid_col: int = 1
var grid_row: int = 3
var state: int = State.IDLE
var charge_dir: Vector2i = Vector2i.ZERO
var charge_time: float = 0.0
var _ground_y: float = 0.0  # 站立面高度(圆柱顶面),阴影贴在这里
var test_mode: bool = false

@onready var _body: Node3D = $Body
@onready var _model: Node3D = $Body/Model
@onready var _shadow: MeshInstance3D = $Shadow
@onready var _charge_ring: MeshInstance3D = $ChargeRing


func _ready() -> void:
	# 棋子模型 glb 原始尺寸过大(高约 4.16),统一缩到 0.3 以匹配棋子格
	_model.scale = Vector3(0.3, 0.3, 0.3)
	# 蓄力环是 TorusMesh,默认就平躺(XZ 平面、中心轴沿 Y),无需旋转
	# 给棋子模型加一圈描边,让主角在深蓝格子上更突出
	_add_outline()


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


# 测试模式:按住方向键蓄力(蓄力时间决定距离),松开沿该方向跳出
func _process_test(delta: float) -> void:
	match state:
		State.IDLE:
			var d := _held_dir()
			if d != Vector2i.ZERO and _just_pressed(d):
				charge_dir = d
				state = State.CHARGING
				charge_time = 0.0
		State.CHARGING:
			charge_time += delta
			_update_squash()
			if _just_released(charge_dir):
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


# ---- 测试模式:方向 + 蓄力 -> 距离 -----------------------------------------

# 蓄力时间 -> 跳跃距离(满蓄力刚好跳过 3 个垫子到终点)
func _test_distance() -> float:
	var spacing: float = grid.test_spacing()
	return clampf(charge_time / TEST_MAX_CHARGE, 0.0, 1.0) * spacing * 3.0


# 测试模式跳跃:按蓄力算距离,沿 charge_dir 方向跳出;落点有垫则站上去,没有则坠落
func _do_test_jump() -> void:
	_charge_ring.visible = false
	_body.scale = Vector3.ONE
	var from := Vector2i(grid_col, grid_row)
	var dist := _test_distance()
	var dir3 := Vector3(charge_dir.x, 0.0, charge_dir.y)
	var land_end := position + dir3 * dist
	var land: Dictionary = grid.test_pad_at(land_end.x, land_end.z)
	state = State.JUMPING
	if land.is_empty():
		_test_jump_miss(from, position, land_end, dist)
	else:
		grid_col = int(land["col"])
		grid_row = int(land["row"])
		_test_jump_arc(position, land_end, land["content"], dist)


# 落在垫子上:跳到精确落点(不吸附到垫中心),落地后发 landed
func _test_jump_arc(start: Vector3, end: Vector3, content: Dictionary, dist: float) -> void:
	var tiles: float = dist / grid.test_spacing()
	var mid := (start + end) * 0.5 + Vector3(0, JUMP_HEIGHT * tiles, 0)
	_body.scale = Vector3(0.9, 1.15, 0.9)
	var t := create_tween()
	t.tween_method(_jump_pos.bind(start, mid, end), 0.0, 1.0, JUMP_DURATION * maxf(tiles, 0.6))
	t.tween_callback(_on_test_land.bind(content))


# 落在空处:先跳到那个点(和正常跳一样的弧线),再坠落(下坠+缩小+翻滚),发 fell_off
func _test_jump_miss(from: Vector2i, start: Vector3, end: Vector3, dist: float) -> void:
	var tiles: float = dist / grid.test_spacing()
	var mid := (start + end) * 0.5 + Vector3(0, JUMP_HEIGHT * tiles, 0)
	_body.scale = Vector3(0.9, 1.15, 0.9)
	var jump := create_tween()
	jump.tween_method(_jump_pos.bind(start, mid, end), 0.0, 1.0, JUMP_DURATION * maxf(tiles, 0.6))
	await jump.finished
	state = State.FALLING
	var fall := create_tween()
	fall.tween_property(self, "position:y", _ground_y - 1.4, FALL_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.parallel().tween_property(_body, "scale", Vector3(0.25, 0.25, 0.25), FALL_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.parallel().tween_property(_body, "rotation:y", _body.rotation.y + TAU, FALL_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await fall.finished
	fell_off.emit(from.x, from.y)


# 测试模式落地:停在精确落点(不吸附到垫中心)
func _on_test_land(content: Dictionary) -> void:
	state = State.IDLE
	_body.scale = Vector3(1.35, 0.6, 1.35)
	var t := create_tween()
	t.tween_property(_body, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_ground_y = position.y
	landed.emit(grid_col, grid_row, content)


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
