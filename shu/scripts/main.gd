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
const TEST_SPACING := 2.6  # 测试模式弹跳垫之间的间距(略大于普通格子)
const TILE_HEIGHT := 0.55  # 棋子圆柱的高度,顶面即主角的站立面
const PLAYER_RADIUS := 0.2  # 主角"碰撞"半径(棋子底盘),落地判定时身体碰垫即算落上
const PAD_SIZES := ["large", "medium", "small"]  # 教学 tier 3 随机分布的大中小档位
const SNAP_TOLERANCE := SPACING * 0.8  # tier 1 吸附落点容差(宽容,允许略微偏离)
const PAD_GAP_RATIO := 0.25  # tier 3 相邻垫子中心距 = 半径和 × (1 + 此值);0 = 刚好相切无间隙

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
var _tier: int = 0  # 教学三级难度档位(0=经典离散跳,1=连续距离跳,2=精准落点,3=变尺寸)
var _endless_mode: bool = false
var _endless_level: int = 1
var _score: int = 0
var _time_limit: float = 0.0
var _time_left: float = 0.0
var _current_level_mode: String = "add"
var _last_land_slot: int = -1
var _revealed_tile: Node3D = null
var _col_x: Dictionary = {}       # tier 3 按尺寸算出的每列 x 坐标(col -> x)
var _row_z: Dictionary = {}       # tier 3 按尺寸算出的每行 z 坐标(row -> z)
var _effective_spacing: float = 0.0  # tier 3 相邻垫平均间距(跳跃距离标定用)


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


func _process(delta: float) -> void:
	if _busy or menu != null:
		return
	if player and is_instance_valid(player) and player.is_falling():
		return  # 坠落动画中,冻结光标/重置输入
	if not _test_mode:
		if Input.is_action_just_pressed("cursor_left"):
			_move_cursor(-1)
		elif Input.is_action_just_pressed("cursor_right"):
			_move_cursor(1)
	if Input.is_action_just_pressed("reset"):
		_manual_reset()
	_update_charge_ui()
	_update_countdown(delta)


func _update_charge_ui() -> void:
	if player and is_instance_valid(player):
		if _test_mode or _tier >= 1:
			hud.set_charge_power(player.charge_progress())
		else:
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
	_test_mode = bool(data.get("test", false))
	_tier = int(data.get("tier", 0))
	_time_limit = float(data.get("time_limit", 0.0))
	_time_left = _time_limit
	_current_level_mode = str(data.get("mode", "add"))
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
	if _endless_mode:
		hud.set_score(_score)
		hud.set_time_left(_time_left, _time_limit)
	else:
		hud.hide_score()
		hud.set_time_left(0.0, 0.0)
	_spawn_grid()
	_spawn_player()


# 测试模式:无等式,铺设起点垫 + 大中小三个跳跃垫,交给连续距离跳
func _load_test_level(_data: Dictionary) -> void:
	equation = null
	active_slot = -1
	hud.set_level_text("测试模式")
	hud.setup_test_mode()
	hud.set_hint(_hint_text())
	_spawn_test_grid()
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
	_col_x = {}
	_row_z = {}
	_effective_spacing = 0.0
	var data: Dictionary = levels[level_index]
	var cells: Array = []  # 记录 (c,r,tile),tier 3 按尺寸摆位用
	for entry in data["grid"]:
		var c: int = entry["c"]
		var r: int = entry["r"]
		var tile = TileScene.instantiate()
		add_child(tile)
		tile.set_content(entry["type"], entry["value"])
		if _tier >= 3:
			tile.set_size(_random_pad_size())
		if _memory_mode:
			tile.set_memory(true)
		tiles["%d,%d" % [c, r]] = tile
		cells.append({"c": c, "r": r, "tile": tile})
	# 起点垫(value=0,不填数字)
	var start: Dictionary = data["start"]
	var sc: int = start["c"]
	var sr: int = start["r"]
	var spad = TileScene.instantiate()
	add_child(spad)
	spad.set_content("num", 0)
	if _memory_mode:
		spad.set_memory(true)
	tiles["%d,%d" % [sc, sr]] = spad
	cells.append({"c": sc, "r": sr, "tile": spad})
	# tier 3:按垫子大小重排列/行间距,避免大垫子连在一起
	if _tier >= 3:
		_layout_cells(cells)
	for cell in cells:
		cell["tile"].position = tile_base_world(cell["c"], cell["r"])


# 教学 tier 3:随机返回一个大/中/小档位
func _random_pad_size() -> String:
	return PAD_SIZES[randi() % PAD_SIZES.size()]


# tier 3:根据每列/每行的最大垫半径把网格拉开,相邻垫子边缘间隙按半径比例留
func _layout_cells(cells: Array) -> void:
	var col_radius := {}
	var row_radius := {}
	for cell in cells:
		var c: int = cell["c"]
		var r: int = cell["r"]
		var rad: float = cell["tile"].radius()
		col_radius[c] = maxf(col_radius.get(c, 0.0), rad)
		row_radius[r] = maxf(row_radius.get(r, 0.0), rad)
	_col_x = _center_map(_cumulative_positions(col_radius))
	_row_z = _center_map(_cumulative_positions(row_radius))
	_effective_spacing = (_average_gap(_col_x) + _average_gap(_row_z)) * 0.5


# 索引 -> 半径 累加得到 索引 -> 位置:相邻间距 = (前半径 + 后半径) × (1 + PAD_GAP_RATIO)
func _cumulative_positions(radius_by_index: Dictionary) -> Dictionary:
	var pos := {}
	var keys: Array = radius_by_index.keys()
	keys.sort()
	for i in keys.size():
		var k = keys[i]
		if i == 0:
			pos[k] = 0.0
		else:
			var prev = keys[i - 1]
			pos[k] = pos[prev] + (radius_by_index[prev] + radius_by_index[k]) * (1.0 + PAD_GAP_RATIO)
	return pos


# 把位置表整体平移,使其中心落在原点(保持网格居中)
func _center_map(pos: Dictionary) -> Dictionary:
	if pos.is_empty():
		return pos
	var vals: Array = pos.values()
	var center: float = (vals.min() + vals.max()) * 0.5
	for k in pos:
		pos[k] -= center
	return pos


# 相邻位置的平均间距(单列/单行时退回 SPACING)
func _average_gap(pos: Dictionary) -> float:
	var keys: Array = pos.keys()
	keys.sort()
	var total := 0.0
	var n := 0
	for i in range(1, keys.size()):
		total += abs(pos[keys[i]] - pos[keys[i - 1]])
		n += 1
	return total / n if n > 0 else SPACING


# 测试模式:起点垫 + 大中小三个跳跃垫(最后一个为终点),垫子沿 -Z 以更大的间距排布
func _spawn_test_grid() -> void:
	var data: Dictionary = levels[level_index]
	var start: Dictionary = data["start"]
	var spad = TileScene.instantiate()
	add_child(spad)
	spad.position = tile_base_world(start["c"], start["r"])
	spad.set_start_pad()
	tiles["%d,%d" % [start["c"], start["r"]]] = spad
	var base := tile_base_world(start["c"], start["r"])
	var pads: Array = data.get("pads", [])
	for i in pads.size():
		var p = pads[i]
		var t = TileScene.instantiate()
		add_child(t)
		t.position = base - Vector3(0, 0, TEST_SPACING * (i + 1))
		t.set_test_pad(p["size"], p["goal"])
		tiles["%d,%d" % [p["c"], p["r"]]] = t


# 某水平坐标落在哪个垫/格子上(半径内),返回 {col,row,content};没命中返回 {}
func pad_at(x: float, z: float) -> Dictionary:
	var best_d := INF
	var best_key := ""
	for key in tiles.keys():
		var t = tiles[key]
		if not is_instance_valid(t):
			continue
		var dx: float = x - t.position.x
		var dz: float = z - t.position.z
		var reach: float = t.radius() + PLAYER_RADIUS
		var d2: float = dx * dx + dz * dz
		if d2 <= reach * reach and d2 < best_d:
			best_d = d2
			best_key = key
	if best_key == "":
		return {}
	var t2 = tiles[best_key]
	var parts := str(best_key).split(",")
	return {
		"col": int(parts[0]),
		"row": int(parts[1]),
		"content": {"type": t2.kind, "value": t2.value, "goal": t2.is_goal()},
	}


# 距离 (x,z) 最近且落在容差内的垫/格子(教学 tier 1 吸附落点用);没命中返回 {}
func nearest_pad(x: float, z: float, tolerance: float) -> Dictionary:
	var best_d := INF
	var best_key := ""
	for key in tiles.keys():
		var t = tiles[key]
		if not is_instance_valid(t):
			continue
		var dx: float = x - t.position.x
		var dz: float = z - t.position.z
		var d: float = sqrt(dx * dx + dz * dz)
		if d < best_d:
			best_d = d
			best_key = key
	if best_key == "" or best_d > tolerance:
		return {}
	var t2 = tiles[best_key]
	var parts := str(best_key).split(",")
	return {
		"col": int(parts[0]),
		"row": int(parts[1]),
		"content": {"type": t2.kind, "value": t2.value, "goal": t2.is_goal()},
	}


func _spawn_player() -> void:
	player = PlayerScene.instantiate()
	add_child(player)
	var start: Dictionary = levels[level_index]["start"]
	player.setup(self, start["c"], start["r"])
	player.set_test_mode(_test_mode)
	player.set_jump_tier(3 if _test_mode else _tier)
	player.face_toward(camera.global_position)
	player.landed.connect(_on_player_landed)
	player.departed.connect(_on_player_departed)
	player.stomped.connect(_on_player_stomped)
	player.fell_off.connect(_on_player_fell_off)


# ---- 网格接口(player 调用) ------------------------------------------------

# 格子"站立点"的世界坐标(圆柱顶面):主角位置与跳跃落点都用它
func grid_to_world(col: int, row: int) -> Vector3:
	var x: float = _col_x.get(col, (col - 1) * SPACING)
	var z: float = _row_z.get(row, (row - 1) * SPACING)
	return Vector3(x, TILE_HEIGHT, z)


# 相邻垫/格子的间距(连续距离跳的弧线缩放用):测试模式用更大的 TEST_SPACING,否则普通 SPACING
func jump_spacing() -> float:
	if _test_mode:
		return TEST_SPACING
	if _tier >= 3 and _effective_spacing > 0.0:
		return _effective_spacing
	return SPACING


# tier 1 吸附落点容差
func snap_tolerance() -> float:
	return SNAP_TOLERANCE


# 格子"基座"的世界坐标(底面贴地):只在铺格子时用
func tile_base_world(col: int, row: int) -> Vector3:
	var x: float = _col_x.get(col, (col - 1) * SPACING)
	var z: float = _row_z.get(row, (row - 1) * SPACING)
	return Vector3(x, 0.0, z)


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
	_busy = false


# R 手动重置:清空等式并回到起点(记忆/翻转模式答错不自动重来的逃生口)
func _manual_reset() -> void:
	if _test_mode:
		_reset_player()
		return
	if equation == null:
		return
	equation.clear_slots()
	hud.clear_slots()
	active_slot = 0
	hud.set_active(0)
	_reset_player()


func _is_teaching_mode(mode: String) -> bool:
	return mode == "add" or mode == "sub" or mode == "mul" or mode == "div"


func _hint_text() -> String:
	if _test_mode:
		return "W A S D 按住蓄力 · 蓄力时间决定距离 · 松开跳出 · 依次跳上大/中/小垫到金色终点 · R 重置"
	if _endless_mode:
		var base := "W A S D 蓄力跳 · ← → 或鼠标点击 移动圆圈 · R 重置"
		match _tier:
			1:
				base += " · 按住蓄力,时间越长跳得越远"
			2:
				base += " · 松开后精准落地,要落在垫子上"
			3:
				base += " · 垫子有大/中/小,瞄准精准落点"
			_:
				base += " · 按键跳一格"
		if _memory_mode:
			base += " · 数字跳上去才显示"
		elif _current_level_mode == "op":
			base += " · 紫色格子是运算符"
		if _time_limit > 0.0:
			base += " · ⏱ 限时"
		return base + " · 答错/掉落/超时即结束"
	if _is_teaching_mode(current_mode):
		var base := "W A S D 蓄力跳 · ← → 或鼠标点击 移动圆圈 · R 重置"
		match _tier:
			1:
				return base + " · 按住蓄力,时间越长跳得越远"
			2:
				return base + " · 松开后精准落地,要落在垫子上"
			3:
				return base + " · 垫子有大/中/小,瞄准精准落点"
		return base
	# 非教学关卡:仅保留模式专属玩法说明,去掉基础操控提示
	if _sign_flip_mode:
		return "空格 蓄满翻转符号"
	if _memory_mode:
		return "数字跳上去才显示"
	if current_mode == "op":
		return "紫色格子是运算符"
	return ""


# ---- 无尽模式 --------------------------------------------------------------

func _start_endless() -> void:
	_endless_mode = true
	_endless_level = 1
	_score = 0
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
	var prev_best_score := Progress.endless_best_score()
	Progress.set_endless_best(level)
	Progress.set_endless_best_score(_score)
	_endless_mode = false
	var txt := "分数 %d · 到达第 %d 关" % [_score, level]
	if level > prev_best:
		txt = "新纪录！" + txt
	elif _score > prev_best_score:
		txt = "新分数纪录！" + txt
	hud.show_endless_over(txt)
	await get_tree().create_timer(2.2).timeout
	_return_to_mode_select()


# 无尽模式过关得分:基础分随关数递增,限时关再按剩余秒数加分
func _award_score() -> void:
	var base := 100 + _endless_level * 10
	var time_bonus := int(ceil(_time_left)) * 5 if _time_limit > 0.0 else 0
	var gained := base + time_bonus
	_score += gained
	hud.set_score(_score)
	hud.show_score_gain(gained)


# 无尽模式倒计时:仅限时关运行;_process 在 _busy/暂停/坠落时提前 return,计时自动冻结
func _update_countdown(delta: float) -> void:
	if not _endless_mode or _time_limit <= 0.0:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_time_left = 0.0
		hud.set_time_left(_time_left, _time_limit)
		_on_timeout()
		return
	hud.set_time_left(_time_left, _time_limit)


# 倒计时归零:直接结束整局(与答错/掉落一致)
func _on_timeout() -> void:
	if _busy:
		return
	_busy = true
	hud.show_wrong("时间到！")
	await get_tree().create_timer(0.7).timeout
	await _end_game()


func _win() -> void:
	_busy = true
	if _endless_mode:
		_award_score()
	else:
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
