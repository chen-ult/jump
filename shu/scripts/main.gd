extends Node3D

const TileScene := preload("res://scenes/tile.tscn")
const PlayerScene := preload("res://scenes/player.tscn")
const EquationScript := preload("res://scripts/equation.gd")
const LevelData := preload("res://scripts/level_data.gd")
const HudScript := preload("res://scripts/hud.gd")

const SPACING := 2.2

var equation
var active_slot: int = -1
var level_index: int = 0
var levels: Array = []

var player: Node3D
var tiles: Dictionary = {}
var hud: CanvasLayer
var camera: Camera3D

var _busy: bool = false


func _ready() -> void:
	_create_camera()
	_create_lights()
	_create_environment()
	hud = HudScript.new()
	add_child(hud)
	levels = LevelData.all_levels()
	_load_level(0)


func _process(_delta: float) -> void:
	if _busy:
		return
	if Input.is_action_just_pressed("cursor_left"):
		_move_cursor(-1)
	elif Input.is_action_just_pressed("cursor_right"):
		_move_cursor(1)
	_update_charge_ui()


func _update_charge_ui() -> void:
	if player and is_instance_valid(player):
		hud.set_charge(player.charge_progress(), player.charge_tiles())


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
	var data: Dictionary = levels[idx]
	equation = EquationScript.new(data["equation"])
	active_slot = 0
	hud.set_level(idx + 1)
	hud.set_tokens(data["equation"])
	hud.set_active(0)
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


func _spawn_grid() -> void:
	var data: Dictionary = levels[level_index]
	for entry in data["grid"]:
		var c: int = entry["c"]
		var r: int = entry["r"]
		var n: int = entry["n"]
		var tile = TileScene.instantiate()
		add_child(tile)
		tile.position = grid_to_world(c, r)
		tile.set_number(n)
		tiles["%d,%d" % [c, r]] = tile
	# 起点垫(number=0,不填数字)
	var start: Dictionary = data["start"]
	var sc: int = start["c"]
	var sr: int = start["r"]
	var spad = TileScene.instantiate()
	add_child(spad)
	spad.position = grid_to_world(sc, sr)
	spad.set_number(0)
	tiles["%d,%d" % [sc, sr]] = spad


func _spawn_player() -> void:
	player = PlayerScene.instantiate()
	add_child(player)
	var start: Dictionary = levels[level_index]["start"]
	player.setup(self, start["c"], start["r"])
	player.face_toward(camera.global_position)
	player.landed.connect(_on_player_landed)


# ---- 网格接口(player 调用) ------------------------------------------------

func grid_to_world(col: int, row: int) -> Vector3:
	return Vector3((col - 1) * SPACING, 0.0, (row - 1) * SPACING)


func is_walkable(col: int, row: int) -> bool:
	return tiles.has("%d,%d" % [col, row])


func tile_number_at(col: int, row: int) -> int:
	var t = tiles.get("%d,%d" % [col, row])
	if t:
		return t.number
	return -1


func is_busy() -> bool:
	return _busy


# ---- 玩法逻辑 -------------------------------------------------------------

func _on_player_landed(col: int, row: int, number: int) -> void:
	var tile = tiles.get("%d,%d" % [col, row])
	if tile:
		tile.play_land_feedback()
	if _busy or number <= 0:
		return
	equation.set_slot(active_slot, number)
	hud.set_slot_value(active_slot, number)
	active_slot = _next_empty(active_slot)
	hud.set_active(active_slot)
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


func _next_empty(from: int) -> int:
	var n: int = equation.slots_count()
	if n <= 0:
		return -1
	for k in range(1, n + 1):
		var idx: int = (from + k) % n
		if equation.get_slot(idx) < 0:
			return idx
	return from


func _win() -> void:
	_busy = true
	hud.show_win()
	_spawn_confetti()
	await get_tree().create_timer(2.0).timeout
	if level_index + 1 < levels.size():
		_load_level(level_index + 1)
	else:
		hud.show_finish()
		_busy = false


func _wrong() -> void:
	_busy = true
	hud.show_wrong()
	await get_tree().create_timer(0.7).timeout
	equation.clear_slots()
	hud.clear_slots()
	active_slot = 0
	hud.set_active(0)
	_busy = false


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
