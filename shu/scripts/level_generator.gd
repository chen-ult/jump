extends RefCounted

# 无尽模式关卡生成器:按难度(第几关)程序化生成数学跳格子关。
# 输出结构与 level_data._build_level 完全同构,可直接喂给 main._load_level 与 Solvability.check。

const Solvability := preload("res://scripts/solvability.gd")

const OPS := ["add", "sub", "mul", "div"]  # 四则运算(算术类)


# 生成第 difficulty 关(从 1 起)。mode 传 "mixed"/"endless" 时按难度曲线随机挑一种模式。
static func generate(mode: String, difficulty: int) -> Dictionary:
	var cfg := _difficulty_config(difficulty)
	if mode != "mixed" and mode != "endless":
		cfg["mode"] = mode  # 指定单一模式时覆盖随机选择
	for _attempt in range(200):
		var level := _try_generate(cfg["mode"], cfg["hi"], cfg["slots"])
		if not level.is_empty():
			level["tier"] = cfg["tier"]
			level["time_limit"] = cfg["time_limit"]
			return level
	var fb := _fallback(cfg["slots"])
	fb["tier"] = cfg["tier"]
	fb["time_limit"] = cfg["time_limit"]
	return fb


# 难度曲线:随关卡缓慢递增的模式池 / 数字上限 / 空位数 / tier / 限时
static func _difficulty_config(difficulty: int) -> Dictionary:
	var pool: Array = _mode_pool(difficulty)
	return {
		"mode": pool[randi() % pool.size()],
		"hi": mini(6 + int((difficulty - 1) / 2.0), 20),  # 数字上限缓慢增长
		"slots": 1 if difficulty < 6 else 2,
		"tier": _tier_for(difficulty),
		"time_limit": _time_limit_for(difficulty),
	}


# 可选模式池:逐段解锁,体现"缓慢递增"
static func _mode_pool(difficulty: int) -> Array:
	if difficulty <= 2:
		return ["add"]
	if difficulty <= 4:
		return ["add", "sub"]
	if difficulty <= 7:
		return ["add", "sub", "mul", "div"]
	if difficulty <= 10:
		return ["add", "sub", "mul", "div", "op"]
	return ["add", "sub", "mul", "div", "op", "memory"]


# 跳跃机制 tier:0 离散跳 → 1 距离吸附 → 2 精准落点 → 3 随机垫大小
static func _tier_for(difficulty: int) -> int:
	if difficulty < 5:
		return 0
	if difficulty < 9:
		return 1
	if difficulty < 14:
		return 2
	return 3


# 限时(秒):第 10 关起才计时,45s 起每关 -2s,下限 20s
static func _time_limit_for(difficulty: int) -> int:
	if difficulty < 10:
		return 0
	return clampi(45 - (difficulty - 10) * 2, 20, 45)


# 生成一关;不可解时返回 {} 触发重试
static func _try_generate(mode: String, hi: int, slots: int) -> Dictionary:
	if mode == "op":
		return _try_generate_op(hi)
	var memory := mode == "memory"
	if memory:
		mode = OPS[randi() % OPS.size()]  # 记忆翻牌 = 隐藏数字的四则运算关
	var a: int
	var b: int
	var c: int
	var op: String
	match mode:
		"add":
			a = randi_range(1, hi)
			b = randi_range(1, hi)
			if slots == 2:
				while b == a:  # 待捡数字不能重复(Solvability 防"同一数字捡两次")
					b = randi_range(1, hi)
			c = a + b
			op = "+"
		"sub":
			a = randi_range(2, hi)
			b = randi_range(1, a - 1)
			c = a - b
			op = "-"
		"mul":
			a = randi_range(2, mini(hi, 9))
			b = randi_range(2, mini(hi, 9))
			if slots == 2:
				while b == a:
					b = randi_range(2, mini(hi, 9))
			c = a * b
			op = "*"
		"div":
			b = randi_range(2, mini(hi, 9))
			c = randi_range(2, mini(hi, 9))
			a = b * c  # 保证整除
			op = "/"
		_:
			return {}

	# 待捡数字:两个空位捡 a、b;一个空位只捡 a(b 已写进等式)
	var grab: Array = [a, b] if slots == 2 else [a]
	var equation := _build_equation(op, a, b, c, slots)
	var grid := _build_grid(grab, hi)
	var start := {"c": 1, "r": 3}
	var check := Solvability.check(grid, start, equation, false)
	if not check["solvable"]:
		return {}
	return {
		"mode": "memory" if memory else mode,
		"equation": equation,
		"grid": grid,
		"start": start,
		"sign_flip": false,
		"memory": memory,
		"test": false,
	}


# 运算符关:两个数字 + 一个运算符(3 空位),如 "? ? ? = 7"
static func _try_generate_op(hi: int) -> Dictionary:
	var op: String = ["+", "-", "*"][randi() % 3]
	var a: int
	var b: int
	var c: int
	match op:
		"+":
			a = randi_range(1, hi)
			b = randi_range(1, hi)
			while b == a:
				b = randi_range(1, hi)
			c = a + b
		"-":
			a = randi_range(2, hi)
			b = randi_range(1, a - 1)
			c = a - b
		"*":
			a = randi_range(2, mini(hi, 9))
			b = randi_range(2, mini(hi, 9))
			while b == a:
				b = randi_range(2, mini(hi, 9))
			c = a * b
	var equation := [_slot(), _slot(), _slot(), _op("="), _num(c)]
	var grid := _build_op_grid(a, b, op, hi)
	var start := {"c": 1, "r": 3}
	var check := Solvability.check(grid, start, equation, false)
	if not check["solvable"]:
		return {}
	return {
		"mode": "op",
		"equation": equation,
		"grid": grid,
		"start": start,
		"sign_flip": false,
		"memory": false,
		"test": false,
	}


# 方程 token:与 level_data 同构。乘除用 * /(Expression 求值需要),HUD 与现有 mul/div 关一致。
static func _build_equation(op: String, a: int, b: int, c: int, slots: int) -> Array:
	if slots == 2:
		return [_slot(), _op(op), _slot(), _op("="), _num(c)]
	return [_slot(), _op(op), _num(b), _op("="), _num(c)]


# 3×3 满格:待捡数字随机散布(满格时全可达),其余填干扰数字
static func _build_grid(grab: Array, hi: int) -> Array:
	var positions: Array = []
	for r in 3:
		for c in 3:
			positions.append([c, r])
	positions.shuffle()
	var out: Array = []
	for i in 9:
		var val: int = grab[i] if i < grab.size() else randi_range(1, hi)
		out.append({"type": "num", "value": val, "c": positions[i][0], "r": positions[i][1]})
	return out


# 运算符关网格:2 个数字格 + 1 个运算符格 + 6 个干扰数字
static func _build_op_grid(a: int, b: int, op_str: String, hi: int) -> Array:
	var positions: Array = []
	for r in 3:
		for c in 3:
			positions.append([c, r])
	positions.shuffle()
	var out: Array = []
	out.append({"type": "num", "value": a, "c": positions[0][0], "r": positions[0][1]})
	out.append({"type": "num", "value": b, "c": positions[1][0], "r": positions[1][1]})
	out.append({"type": "op", "value": op_str, "c": positions[2][0], "r": positions[2][1]})
	for i in range(3, 9):
		out.append({"type": "num", "value": randi_range(1, hi), "c": positions[i][0], "r": positions[i][1]})
	return out


# 兜底:连续 200 次失败(理论上不会)时,给一个必可解的 1+1/1+2
static func _fallback(slots: int) -> Dictionary:
	var grid := [
		{"type": "num", "value": 1, "c": 1, "r": 2},
		{"type": "num", "value": 2, "c": 1, "r": 1},
		{"type": "num", "value": 3, "c": 1, "r": 0},
		{"type": "num", "value": 4, "c": 0, "r": 0},
		{"type": "num", "value": 5, "c": 2, "r": 0},
		{"type": "num", "value": 6, "c": 0, "r": 1},
		{"type": "num", "value": 7, "c": 2, "r": 1},
		{"type": "num", "value": 8, "c": 0, "r": 2},
		{"type": "num", "value": 9, "c": 2, "r": 2},
	]
	var equation: Array
	if slots == 2:
		equation = [_slot(), _op("+"), _slot(), _op("="), _num(3)]  # 1 + 2
	else:
		equation = [_slot(), _op("+"), _num(1), _op("="), _num(3)]  # 2 + 1
	return {
		"mode": "add",
		"equation": equation,
		"grid": grid,
		"start": {"c": 1, "r": 3},
		"sign_flip": false,
		"memory": false,
		"test": false,
	}


static func _slot() -> Dictionary:
	return {"type": "slot"}


static func _num(v: int) -> Dictionary:
	return {"type": "num", "value": v}


static func _op(o: String) -> Dictionary:
	return {"type": "op", "value": o}
