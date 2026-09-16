extends Node3D

const TileScene := preload("res://scenes/tile.tscn")
const PlayerScene := preload("res://scenes/player.tscn")
const EquationScript := preload("res://scripts/equation.gd")
const LevelData := preload("res://scripts/level_data.gd")
const HudScript := preload("res://scripts/hud.gd")
const MenuScript := preload("res://scripts/menu.gd")
const Progress := preload("res://scripts/progress.gd")
const Solvability := preload("res://scripts/solvability.gd")

# 运算模式的展示顺序与名称(用于通关后提示进入下一运算)
const MODE_ORDER := ["add", "sub", "mul", "div", "op", "sign", "memory"]
const MODE_NAMES := {"add": "加法", "sub": "减法", "mul": "乘法", "div": "除法", "op": "运算符", "sign": "翻转符号", "memory": "记忆翻牌"}

const SPACING := 2.2
const TILE_HEIGHT := 0.55  # 棋子圆柱的高度,顶面即主角的站立面

var equation
var active_slot: int = -1
var level_index: int = 0
var current_mode: String = "add"
var levels: Array = []

var player: Node3D
var tiles: Dictionary = {}
var hud: CanvasLayer
var menu: CanvasLayer
var camera: Camera3D

var _busy: bool = false
var _memory_mode: bool = false
var _sign_flip_mode: bool = false
var _last_land_slot: int = -1
var _revealed_tile: Node3D = null


func _ready() -> void:
	_create_camera()
	_create_lights()
	_create_environment()
	hud = HudScript.new()
	add_child(hud)
	hud.pause_pressed.connect(_on_pause)
	hud.resume_pressed.connect(_on_resume)
	hud.quit_pressed.connect(_on_quit_to_menu)
	hud.next_mode_pressed.connect(_on_next_mode_pressed)
	hud.menu_pressed.connect(_on_next_menu_pressed)
	# 启动菜单:标题 → 选择模式 → 选择关卡 → 进入对应关卡
	menu = MenuScript.new()
	menu.layer = 10
	add_child(menu)
	menu.start_game.connect(_on_menu_start)


# 菜单选中某模式某关后进入
func _on_menu_start(mode: String, level_idx: int) -> void:
	if menu:
		menu.queue_free()
		menu = null
	current_mode = mode
	levels = LevelData.levels_of_mode(mode)
	_load_level(level_idx)


# ---- 暂停 / 返回菜单 -------------------------------------------------------

func _on_pause() -> void:
	get_tree().paused = true


func _on_resume() -> void:
	get_tree().paused = false


func _on_quit_to_menu() -> void:
	get_tree().paused = false
	_return_to_menu()


# 退出到主界面:清空当前关卡,重建启动菜单
func _return_to_menu() -> void:
	_clear_grid()
	_busy = false
	equation = null
	menu = MenuScript.new()
	menu.layer = 10
	add_child(menu)
	menu.start_game.connect(_on_menu_start)


func _process(_delta: float) -> void:
	if _busy or menu != null:
		return
	if player and is_instance_valid(player) and player.is_falling():
		return  # 坠落动画中,冻结光标/重置输入
	if Input.is_action_just_pressed("cursor_left"):
		_move_cursor(-1)
	elif Input.is_action_just_pressed("cursor_right"):
		_move_cursor(1)
	if Input.is_action_just_pressed("reset"):
		_manual_reset()
	_update_charge_ui()


func _update_charge_ui() -> void:
	if player and is_instance_valid(player):
		hud.set_charge(player.charge_progress(), player.charge_tiles(), player.is_stomping())


# ---- 场景搭建 -------------------------------------------------------------

func _create_camera() -> void:
	camera = Camera3D.new()
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 46.0
	camera.position = Vector3(9.0, 9.5, 10.0)
	camera.look_at(Vector3(0, 0, 1.0), Vector3.UP)
	camera.make_current()


func _create_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#fff6e6")
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-52, -32, 0)
	add_child(sun)


func _create_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#a8d8ff")
	sky_mat.sky_horizon_color = Color("#e8f6ff")
	sky_mat.ground_bottom_color = Color("#c9e4c5")
	sky_mat.ground_horizon_color = Color("#eef7ea")
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#ffffff")
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


# ---- 关卡 -----------------------------------------------------------------

func _load_level(idx: int) -> void:
	level_index = idx
	_busy = false
	_clear_grid()
	_revealed_tile = null
	_last_land_slot = -1
	var data: Dictionary = levels[idx]
	_memory_mode = bool(data.get("memory", false))
	_sign_flip_mode = bool(data.get("sign_flip", false))
	if _memory_mode:
		data["grid"] = _shuffled_solvable_grid(data)
	var check := Solvability.check(data["grid"], data["start"], data["equation"], _sign_flip_mode)
	if not check["solvable"]:
		# 安全网:菜单已按校验置灰,正常到不了这里;若被直接加载,报错并跳到下一关
		push_error("关卡 %d 不可解:%s" % [idx + 1, check["reason"]])
		if idx + 1 < levels.size():
			_load_level(idx + 1)
		return
	equation = EquationScript.new(data["equation"])
	active_slot = 0
	hud.set_level(idx + 1)
	hud.set_tokens(data["equation"])
	hud.set_active(0)
	hud.set_hint(_hint_text())
	_spawn_grid()
	_spawn_player()


func _clear_grid() -> void:
	for t in tiles.values():
		if is_instance_valid(t):
			t.queue_free()
	tiles.clear()
	if player and is_instance_valid(player):
		player.queue_free()
	player = null


# 记忆玩法:把数字格的值随机打乱,并保证打乱后仍可解(最多重试 500 次,概率上几乎必中)
func _shuffled_solvable_grid(data: Dictionary) -> Array:
	var grid: Array = data["grid"]
	for _attempt in range(500):
		var shuffled := _shuffle_grid_numbers(grid)
		if Solvability.check(shuffled, data["start"], data["equation"], _sign_flip_mode)["solvable"]:
			return shuffled
	# 兜底:随机多次仍未可解(概率极低),退回原布局(菜单已确认可解)
	return grid


# 收集所有数字格的值,打乱后按原位填回(运算符格/空格不受影响)
func _shuffle_grid_numbers(grid: Array) -> Array:
	var out: Array = []
	var vals: Array = []
	for e in grid:
		out.append(e.duplicate())
		if e["type"] == "num" and e["value"] is int and e["value"] != 0:
			vals.append(e["value"])
	vals.shuffle()
	var i := 0
	for e in out:
		if e["type"] == "num" and e["value"] is int and e["value"] != 0:
			e["value"] = vals[i]
			i += 1
	return out


func _spawn_grid() -> void:
	var data: Dictionary = levels[level_index]
	for entry in data["grid"]:
		var c: int = entry["c"]
		var r: int = entry["r"]
		var tile = TileScene.instantiate()
		add_child(tile)
		tile.position = tile_base_world(c, r)
		tile.set_content(entry["type"], entry["value"])
		if _memory_mode:
			tile.set_memory(true)
		tiles["%d,%d" % [c, r]] = tile
	# 起点垫(value=0,不填数字)
	var start: Dictionary = data["start"]
	var sc: int = start["c"]
	var sr: int = start["r"]
	var spad = TileScene.instantiate()
	add_child(spad)
	spad.position = tile_base_world(sc, sr)
	spad.set_content("num", 0)
	if _memory_mode:
		spad.set_memory(true)
	tiles["%d,%d" % [sc, sr]] = spad


func _spawn_player() -> void:
	player = PlayerScene.instantiate()
	add_child(player)
	var start: Dictionary = levels[level_index]["start"]
	player.setup(self, start["c"], start["r"])
	player.face_toward(camera.global_position)
	player.landed.connect(_on_player_landed)
	player.departed.connect(_on_player_departed)
	player.stomped.connect(_on_player_stomped)
	player.fell_off.connect(_on_player_fell_off)


# ---- 网格接口(player 调用) ------------------------------------------------

# 格子"站立点"的世界坐标(圆柱顶面):主角位置与跳跃落点都用它
func grid_to_world(col: int, row: int) -> Vector3:
	return Vector3((col - 1) * SPACING, TILE_HEIGHT, (row - 1) * SPACING)


# 格子"基座"的世界坐标(底面贴地):只在铺格子时用
func tile_base_world(col: int, row: int) -> Vector3:
	return Vector3((col - 1) * SPACING, 0.0, (row - 1) * SPACING)


func is_walkable(col: int, row: int) -> bool:
	return tiles.has("%d,%d" % [col, row])


func cell_content_at(col: int, row: int) -> Dictionary:
	var t = tiles.get("%d,%d" % [col, row])
	if t:
		return {"type": t.kind, "value": t.value}
	return {}


func is_busy() -> bool:
	return _busy


# ---- 玩法逻辑 -------------------------------------------------------------

func _on_player_landed(col: int, row: int, content: Dictionary) -> void:
	var tile = tiles.get("%d,%d" % [col, row])
	if tile:
		tile.play_land_feedback()
		_reveal_tile(tile)
	if _busy or content.is_empty():
		return
	match content.get("type", ""):
		"num":
			var val = content.get("value", 0)
			if not (val is int) or val == 0:
				return  # 起点垫 / 0 值自由格(负数可捡)
			equation.set_slot(active_slot, val)
			hud.set_slot_value(active_slot, val)
			_last_land_slot = active_slot
		"op":
			var op = content.get("value", "")
			if not (op is String) or op == "":
				return
			equation.set_slot(active_slot, op)
			hud.set_slot_value(active_slot, op)
			_last_land_slot = active_slot
		_:
			return
	if equation.is_complete():
		if equation.is_correct():
			_win()
		else:
			_wrong()


func _move_cursor(delta: int) -> void:
	var n: int = equation.slots_count()
	if n <= 0:
		return
	active_slot = (active_slot + delta) % n
	if active_slot < 0:
		active_slot += n
	hud.set_active(active_slot)


# 记忆玩法:跳上格子 reveal,离开隐藏;同一时刻只显示最近跳上的格子
func _reveal_tile(tile) -> void:
	if not _memory_mode:
		return
	if _revealed_tile and _revealed_tile != tile and is_instance_valid(_revealed_tile):
		_revealed_tile.hide_label()
	_revealed_tile = tile
	tile.reveal()


func _on_player_departed(_col: int, _row: int) -> void:
	_hide_revealed()


func _hide_revealed() -> void:
	if _memory_mode and _revealed_tile and is_instance_valid(_revealed_tile):
		_revealed_tile.hide_label()
	_revealed_tile = null


# 蓄满翻转:翻转脚下格子符号,并同步最近一次落地填的槽
func _on_player_stomped(col: int, row: int) -> void:
	if _busy or not _sign_flip_mode:
		return
	var tile = tiles.get("%d,%d" % [col, row])
	if not tile:
		return
	var old_val = tile.value
	var new_val: int = tile.flip_sign()
	if new_val == 0:
		return
	if _last_land_slot >= 0 and equation.get_slot(_last_land_slot) == old_val:
		equation.set_slot(_last_land_slot, new_val)
		hud.set_slot_value(_last_land_slot, new_val)
	if equation.is_complete():
		if equation.is_correct():
			_win()
		else:
			_wrong()


# 蓄力过多跃出格子:惩罚,清空等式并回起点重来
func _on_player_fell_off(_col: int, _row: int) -> void:
	if _busy:
		return
	_busy = true
	hud.show_wrong("掉下去了～")
	await get_tree().create_timer(0.7).timeout
	equation.clear_slots()
	hud.clear_slots()
	active_slot = 0
	hud.set_active(0)
	_reset_player()
	_busy = false


# R 手动重置:清空等式并回到起点(记忆/翻转模式答错不自动重来的逃生口)
func _manual_reset() -> void:
	if equation == null:
		return
	equation.clear_slots()
	hud.clear_slots()
	active_slot = 0
	hud.set_active(0)
	_reset_player()


func _hint_text() -> String:
	var base := "W A S D 蓄力跳 · ← → 移动圆圈 · R 重置"
	if _sign_flip_mode:
		return base + " · 空格 蓄满翻转符号"
	if _memory_mode:
		return base + " · 数字跳上去才显示"
	if current_mode == "op":
		return base + " · 紫色格子是运算符"
	return base


func _win() -> void:
	_busy = true
	Progress.on_level_passed(current_mode, level_index)
	hud.show_win()
	_spawn_confetti()
	await get_tree().create_timer(2.0).timeout
	if level_index + 1 < levels.size():
		_load_level(level_index + 1)
	else:
		var next := _next_mode()
		if next != "":
			hud.show_next_mode(MODE_NAMES[next])
			# 保持 _busy=true 冻结玩家,等玩家点「进入下一运算」或「返回菜单」
		else:
			hud.show_finish()
			_busy = false


func _wrong() -> void:
	if _sign_flip_mode:
		# 翻转模式:答错不重置,让玩家继续翻符号/改数(R 可手动重置)
		hud.show_wrong()
		return
	_busy = true
	hud.show_wrong()
	await get_tree().create_timer(0.7).timeout
	equation.clear_slots()
	hud.clear_slots()
	active_slot = 0
	hud.set_active(0)
	_reset_player()
	_busy = false


# 答错后把主角送回起始弹跳垫
func _reset_player() -> void:
	_hide_revealed()
	if player == null or not is_instance_valid(player):
		return
	var start: Dictionary = levels[level_index]["start"]
	player.reset_to(start["c"], start["r"])
	player.face_toward(camera.global_position)


# 当前模式之后的下一运算 id;没有则返回 ""
func _next_mode() -> String:
	var i := MODE_ORDER.find(current_mode)
	if i >= 0 and i + 1 < MODE_ORDER.size():
		return MODE_ORDER[i + 1]
	return ""


# 通关提示里点「进入下一运算」:切到下一模式并进入其第 1 关
func _on_next_mode_pressed() -> void:
	hud.hide_next_overlay()
	var next := _next_mode()
	if next == "":
		_return_to_menu()
		return
	current_mode = next
	levels = LevelData.levels_of_mode(next)
	_load_level(0)


# 通关提示里点「返回菜单」
func _on_next_menu_pressed() -> void:
	hud.hide_next_overlay()
	_return_to_menu()


func _spawn_confetti() -> void:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 90
	p.lifetime = 2.2
	p.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 6.5
	pm.gravity = Vector3(0, -9.0, 0)
	pm.scale_min = 0.06
	pm.scale_max = 0.14
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color("#ff9aa2"), Color("#ffd166"), Color("#a2d2ff"), Color("#b5ead7")])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	ramp.width = 64
	pm.color_ramp = ramp
	p.process_material = pm
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.08, 0.08)
	p.draw_pass_1 = box
	p.position = Vector3(0, 2.5, 0)
	add_child(p)
	get_tree().create_timer(3.0).timeout.connect(p.queue_free)
