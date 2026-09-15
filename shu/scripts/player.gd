extends Node3D

signal landed(col: int, row: int, number: int)

enum State { IDLE, CHARGING, JUMPING }

const MAX_CHARGE := 1.2
const MAX_TILES := 3
const JUMP_DURATION := 0.32
const JUMP_HEIGHT := 1.4

var grid: Node = null
var grid_col: int = 1
var grid_row: int = 3
var state: int = State.IDLE
var charge_dir: Vector2i = Vector2i.ZERO
var charge_time: float = 0.0
var _ground_y: float = 0.0  # 站立面高度(圆柱顶面),阴影贴在这里

@onready var _body: Node3D = $Body
@onready var _model: Node3D = $Body/Model
@onready var _shadow: MeshInstance3D = $Shadow
@onready var _charge_ring: MeshInstance3D = $ChargeRing


func _ready() -> void:
	# 棋子模型 glb 原始尺寸过大(高约 4.16),统一缩到 0.3 以匹配棋子格
	_model.scale = Vector3(0.3, 0.3, 0.3)
	# 蓄力环是 TorusMesh(默认竖直),转 90° 让它平躺在地面
	_charge_ring.rotation_degrees = Vector3(90, 0, 0)
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


func face_toward(world_pos: Vector3) -> void:
	var d := world_pos - global_position
	d.y = 0.0
	if d.length() > 0.001:
		rotation.y = atan2(d.x, d.z)


func _process(delta: float) -> void:
	_update_shadow()
	if grid and grid.is_busy():
		return

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
				_do_jump()
		State.JUMPING:
			pass


func _update_shadow() -> void:
	_shadow.global_position = Vector3(global_position.x, _ground_y + 0.02, global_position.z)
	_charge_ring.position = Vector3(0, 0.06, 0)


func _update_squash() -> void:
	var p := clampf(charge_time / MAX_CHARGE, 0.0, 1.0)
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


# 供 HUD 读取:当前蓄力进度(0..1),非蓄力时为 0
func charge_progress() -> float:
	if state != State.CHARGING:
		return 0.0
	return clampf(charge_time / MAX_CHARGE, 0.0, 1.0)


# 供 HUD 读取:当前蓄力对应的跳跃格数(1..MAX_TILES),非蓄力时为 0
func charge_tiles() -> int:
	if state != State.CHARGING:
		return 0
	return _charge_distance()


# 解析实际落点:优先落到蓄力对应的格;若该格不可达(边缘/空洞),退到该方向最近的可达格
func _resolve_target() -> Vector2i:
	var dist := _charge_distance()
	for k in range(dist, 0, -1):
		var c := grid_col + charge_dir.x * k
		var r := grid_row + charge_dir.y * k
		if grid.is_walkable(c, r):
			return Vector2i(c, r)
	return Vector2i(grid_col, grid_row)


func _do_jump() -> void:
	_charge_ring.visible = false
	_body.scale = Vector3.ONE
	var from := Vector2i(grid_col, grid_row)
	var target := _resolve_target()
	if target == from:
		# 该方向一个可达格都没有,原地弹一下取消
		state = State.IDLE
		_cancel_boing()
		return
	var tiles := maxi(absi(target.x - from.x), absi(target.y - from.y))
	grid_col = target.x
	grid_row = target.y
	state = State.JUMPING
	_jump_arc(position, grid.grid_to_world(target.x, target.y), tiles)


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
	landed.emit(grid_col, grid_row, grid.tile_number_at(grid_col, grid_row))


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
