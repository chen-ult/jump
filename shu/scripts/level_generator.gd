extends RefCounted

# 无尽模式关卡生成器:按难度(第几关)程序化生成数学跳格子关。
# 输出结构与 level_data._build_level 完全同构,可直接喂给 main._load_level 与 Solvability.check。

const Solvability := preload("res://scripts/solvability.gd")

const OPS := ["add", "sub", "mul", "div"]


# 生成第 difficulty 关(从 1 起)。mode 传 "mixed"/"endless" 时每关随机挑一种运算。
static func generate(mode: String, difficulty: int) -> Dictionary:
	if mode == "mixed" or mode == "endless":
		mode = OPS[randi() % OPS.size()]
	var hi := mini(5 + difficulty, 20)       # 数字上限:第 1 关 ≤6,第 15 关封顶 20
	var slots := 1 if difficulty < 4 else 2  # 空位数:第 4 关起两个空位
	for _attempt in range(200):
		var level := _try_generate(mode, hi, slots)
		if not level.is_empty():
			return level
	return _fallback(slots)


# 生成一关;不可解时返回 {} 触发重试
static func _try_generate(mode: String, hi: int, slots: int) -> Dictionary:
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
		"mode": mode,
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
