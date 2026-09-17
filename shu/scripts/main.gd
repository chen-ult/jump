extends Node3D

const TileScene := preload("res://scenes/tile.tscn")
const PlayerScene := preload("res://scenes/player.tscn")
const EquationScript := preload("res://scripts/equation.gd")
const LevelData := preload("res://scripts/level_data.gd")
const HudScript := preload("res://scripts/hud.gd")
const MenuScript := preload("res://scripts/menu.gd")
const Progress := preload("res://scripts/progress.gd")
const Solvability := preload("res://scripts/solvability.gd")
const LevelGenerator := preload("res://scripts/level_generator.gd")

const SPACING := 2.2
const TILE_HEIGHT := 0.55  # 棋子圆柱的高度,顶面即主角的站立面
const PLAYER_RADIUS := 0.2  # 主角"碰撞"半径(棋子底盘),落地判定时身体碰垫即算落上

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
var _test_mode: bool = false
var _test_target: String = ""
var _endless_mode: bool = false
var _endless_level: int = 1
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
	hud.slot_clicked.connect(_on_slot_clicked)
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
	if mode == "endless":
		_start_endless()
		return
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
	_endless_mode = false
	_busy = false
	equation = null
	menu = MenuScript.new()
	menu.layer = 10
	add_child(menu)
	menu.start_game.connect(_on_menu_start)


# 一章(模式)通关后:退回章节选择界面
func _return_to_mode_select() -> void:
	_return_to_menu()
	if menu:
		menu.show_mode_page()


func _process(_delta: float) -> void:
	if _busy or menu != null:
		return
	if player and is_instance_valid(player) and player.is_falling():
		return  # 坠落动画中,冻结光标/重置输入
	if _test_mode:
		_test_handle_target_input()
	else:
		if Input.is_action_just_pressed("cursor_left"):
			_move_cursor(-1)
		elif Input.is_action_just_pressed("cursor_right"):
			_move_cursor(1)
	if Input.is_action_just_pressed("reset"):
		_manual_reset()
	_update_charge_ui()


func _update_charge_ui() -> void:
	if player and is_instance_valid(player):
		if _test_mode:
			hud.set_charge_power(player.charge_progress())
		else:
			hud.set_charge(player.charge_progress(), player.charge_tiles(), player.is_stomping())


# 测试模式:方向键在候选垫子间循环选目标(跳过脚下垫子),adv>0 朝终点
func _test_handle_target_input() -> void:
	if player == null or not is_instance_valid(player) or player.is_airborne():
		return
	var adv := 0
	if Input.is_action_just_pressed("jump_up") or Input.is_action_just_pressed("jump_right") \
			or Input.is_action_just_pressed("cursor_right"):
		adv = 1
	elif Input.is_action_just_pressed("jump_down") or Input.is_action_just_pressed("jump_left") \
			or Input.is_action_just_pressed("cursor_left"):
		adv = -1
	if adv != 0:
		_test_cycle_target(adv)


# 按 row 降序返回所有垫子 key(start 在前,终点 high 在后)
func _test_pads_sorted() -> Array:
	var keys: Array = []
	for k in tiles.keys():
		var t = tiles[k]
		if is_instance_valid(t) and t.kind == "pad":
			keys.append(k)
	keys.sort_custom(_test_pad_row_desc)
	return keys


func _test_pad_row_desc(a: String, b: String) -> bool:
	return int(a.split(",")[1]) > int(b.split(",")[1])


func _test_is_player_pad(key: String) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	return key == "%d,%d" % [player.grid_col, player.grid_row]


# 循环切换目标垫,跳过脚下垫子
func _test_cycle_target(delta: int) -> void:
	var keys := _test_pads_sorted()
	if keys.size() < 2:
		return
	var n := keys.size()
	var idx := keys.find(_test_target)
	if idx < 0:
		idx = 0 if delta > 0 else n - 1
	for _i in range(n):
		idx = (idx + delta) % n
		if idx < 0:
			idx += n
		if not _test_is_player_pad(keys[idx]):
			break
	_test_set_target(keys[idx])


# 自动选默认目标:朝终点方向(row 更小)最近的垫子;没有则朝起点方向最近
func _test_auto_target() -> String:
	if player == null or not is_instance_valid(player):
		return ""
	var best := ""
	var best_d := INF
	for k in tiles.keys():
		var t = tiles[k]
		if not is_instance_valid(t) or t.kind != "pad":
			continue
		var r := int(str(k).split(",")[1])
		if r >= player.grid_row:
			continue
		var d: int = player.grid_row - r
		if d < best_d:
			best_d = d
			best = k
	if best != "":
		return best
	best_d = INF
	for k in tiles.keys():
		var t = tiles[k]
		if not is_instance_valid(t) or t.kind != "pad":
			continue
		var r := int(str(k).split(",")[1])
		if r <= player.grid_row:
			continue
		var d: int = r - player.grid_row
		if d < best_d:
			best_d = d
			best = k
	return best


# 选中某垫子并让主角瞄准它(仰角自动算)
func _test_set_target(key: String) -> void:
	_test_target = key
	if key == "" or player == null or not is_instance_valid(player):
		return
	var t = tiles.get(key)
	if t == null or not is_instance_valid(t):
		return
	player.aim_at(Vector3(t.position.x, t.top_height(), t.position.z))


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
	_test_mode = bool(data.get("test", false))
	if _test_mode:
		_load_test_level(data)
		return
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
	if _endless_mode:
		hud.set_level_text("无尽 · 第 %d 关" % _endless_level)
	else:
		hud.set_level(idx + 1)
	hud.set_tokens(data["equation"])
	hud.set_active(0)
	hud.set_hint(_hint_text())
	_spawn_grid()
	_spawn_player()


# 测试模式:无等式,铺设起点垫 + 大中小三个跳跃垫,交给连续距离跳
func _load_test_level(data: Dictionary) -> void:
	equation = null
	active_slot = -1
	_test_target = ""
	hud.set_level_text("测试模式")
	hud.setup_test_mode()
	hud.set_hint(_hint_text())
	_spawn_test_grid()
	_spawn_player()
	_test_set_target(_test_auto_target())


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


# 测试模式:起点垫 + 矮中高三个跳跃垫(最后一个为终点)
func _spawn_test_grid() -> void:
	var data: Dictionary = levels[level_index]
	var start: Dictionary = data["start"]
	var spad = TileScene.instantiate()
	add_child(spad)
	spad.position = tile_base_world(start["c"], start["r"])
	spad.set_start_pad()
	tiles["%d,%d" % [start["c"], start["r"]]] = spad
	for p in data.get("pads", []):
		var t = TileScene.instantiate()
		add_child(t)
		t.position = tile_base_world(p["c"], p["r"])
		t.set_test_pad(p["height"], p["goal"])
		tiles["%d,%d" % [p["c"], p["r"]]] = t


# 测试模式:给定发射起点/水平方向/水平速度/竖直速度,求落点所在垫子
# 返回 {col,row,point,time,content};没落在任何垫上返回 {}
func test_landing_pad(start: Vector3, dir_h: Vector3, vx: float, vy: float, gravity: float) -> Dictionary:
	var best_t := INF
	var best: Dictionary = {}
	for key in tiles.keys():
		var t = tiles[key]
		if not is_instance_valid(t) or t.kind != "pad":
			continue
		var top: float = t.top_height()
		var dy: float = top - start.y
		var vy2: float = vy * vy
		if vy2 < 2.0 * gravity * dy:
			continue  # 这个速度到不了该垫顶面高度
		var tt: float
		if absf(dy) < 0.001:
			tt = 2.0 * vy / gravity
		else:
			tt = (vy + sqrt(vy2 - 2.0 * gravity * dy)) / gravity
		var land := start + Vector3(dir_h.x * vx * tt, 0.0, dir_h.z * vx * tt)
		land.y = top
		var dx: float = land.x - t.position.x
		var dz: float = land.z - t.position.z
		var reach: float = t.radius() + PLAYER_RADIUS
		if dx * dx + dz * dz <= reach * reach and tt < best_t:
			best_t = tt
			var parts := str(key).split(",")
			best = {
				"col": int(parts[0]),
				"row": int(parts[1]),
				"point": land,
				"time": tt,
				"content": {"type": "pad", "goal": t.is_goal()},
			}
	return best


# 测试模式:某水平坐标正下方的表面高度(最高的垫子顶面,没有垫子则地面 0)
# 供阴影投影用:飞行中阴影落到身体正下方,而不是一直钉在起跳垫
func ground_height_at(x: float, z: float) -> float:
	var best := 0.0
	for key in tiles.keys():
		var t = tiles[key]
		if not is_instance_valid(t):
			continue
		var dx: float = x - t.position.x
		var dz: float = z - t.position.z
		var r: float = t.radius()
		if dx * dx + dz * dz <= r * r:
			best = maxf(best, t.top_height())
	return best


func _spawn_player() -> void:
	player = PlayerScene.instantiate()
	add_child(player)
	var start: Dictionary = levels[level_index]["start"]
	player.setup(self, start["c"], start["r"])
	player.set_test_mode(_test_mode)
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
	if _busy:
		return
	if _test_mode:
		if content.get("goal", false):
			_win()
		else:
			_test_set_target(_test_auto_target())
		return
	if content.is_empty():
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
	if equation == null:
		return
	var n: int = equation.slots_count()
	if n <= 0:
		return
	active_slot = (active_slot + delta) % n
	if active_slot < 0:
		active_slot += n
	hud.set_active(active_slot)


# 鼠标左键点击等式圆圈:直接选中该空位
func _on_slot_clicked(idx: int) -> void:
	if _busy or menu != null:
		return
	if equation == null or idx < 0 or idx >= equation.slots_count():
		return
	active_slot = idx
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
	if _test_mode:
		_test_fall_off()
		return
	if _endless_mode:
		if _busy:
			return
		_busy = true
		hud.show_wrong("掉下去了～")
		await get_tree().create_timer(0.7).timeout
		await _end_game()
		return
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


# 测试模式坠空:没落在垫子上,提示并回起点重来(跌落动画播完才触发,文字随后显示)
func _test_fall_off() -> void:
	if _busy:
		return
	_busy = true
	hud.show_wrong("没有落在弹跳垫上")
	await get_tree().create_timer(0.7).timeout
	_reset_player()
	_test_set_target(_test_auto_target())
	_busy = false


# R 手动重置:清空等式并回到起点(记忆/翻转模式答错不自动重来的逃生口)
func _manual_reset() -> void:
	if _test_mode:
		_reset_player()
		_test_set_target(_test_auto_target())
		return
	if equation == null:
		return
	equation.clear_slots()
	hud.clear_slots()
	active_slot = 0
	hud.set_active(0)
	_reset_player()


func _hint_text() -> String:
	if _test_mode:
		return "W/S 或 ←/→ 选目标垫 · 空格按住蓄力 · 松开跳跃 · 依次跳过矮/中/高垫到金色终点 · R 重置"
	var base := "W A S D 蓄力跳 · ← → 或鼠标点击 移动圆圈 · R 重置"
	if _endless_mode:
		return base + " · 答错或掉落即结束"
	if _sign_flip_mode:
		return base + " · 空格 蓄满翻转符号"
	if _memory_mode:
		return base + " · 数字跳上去才显示"
	if current_mode == "op":
		return base + " · 紫色格子是运算符"
	return base


# ---- 无尽模式 --------------------------------------------------------------

func _start_endless() -> void:
	_endless_mode = true
	_endless_level = 1
	levels = [LevelGenerator.generate("mixed", _endless_level)]
	_load_level(0)


func _next_endless() -> void:
	_endless_level += 1
	levels.append(LevelGenerator.generate("mixed", _endless_level))
	_load_level(level_index + 1)


# 无尽模式结束:答错/掉落,结算到达关数并刷新最高分,退回模式选择
func _end_game() -> void:
	var level := _endless_level
	var prev_best := Progress.endless_best()
	Progress.set_endless_best(level)
	var is_record := level > prev_best
	_endless_mode = false
	if is_record:
		hud.show_endless_over("新纪录！到达第 %d 关" % level)
	else:
		hud.show_endless_over("到达第 %d 关 · 最高 %d 关" % [level, Progress.endless_best()])
	await get_tree().create_timer(2.2).timeout
	_return_to_mode_select()


func _win() -> void:
	_busy = true
	if not _endless_mode:
		Progress.on_level_passed(current_mode, level_index)
	hud.show_win()
	_spawn_confetti()
	await get_tree().create_timer(2.0).timeout
	if _endless_mode:
		_next_endless()
	elif level_index + 1 < levels.size():
		_load_level(level_index + 1)
	else:
		# 本章(模式)结束:退回章节选择界面
		_return_to_mode_select()


func _wrong() -> void:
	if _endless_mode:
		_busy = true
		await _end_game()
		return
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
