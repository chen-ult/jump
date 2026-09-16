extends RefCounted

# 可解性校验器:复刻 player.gd 的直线跳规则,判断某关从起点出发能否捡满等式所需的数。
# 供关卡加载 / 选关界面调用,保证"必可解"。后续玩法(运算符格/负数/记忆)可复用同一套可达性 BFS。

const EquationScript := preload("res://scripts/equation.gd")

const MAX_JUMP := 3  # 与 player.gd 的 MAX_TILES 一致
const DIRS := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]


# grid_entries: [{"type","value","c","r"}, ...](value==0 表示自由垫,如起点)
# start: {"c","r"}
# equation_tokens: 与 equation.gd 相同的 token 数组
static func check(grid_entries: Array, start: Dictionary, equation_tokens: Array, sign_flip: bool = false) -> Dictionary:
	# 1. 建 (c,r) -> cell 映射;起点垫也算可站立格(即便 grid_entries 没包含它)
	var cells: Dictionary = {}
	for e in grid_entries:
		cells["%d,%d" % [e["c"], e["r"]]] = e
	cells["%d,%d" % [start["c"], start["r"]]] = {"type": "num", "value": 0, "c": start["c"], "r": start["r"]}

	var k := _slot_count(equation_tokens)
	if k == 0:
		var eq := EquationScript.new(equation_tokens)
		return {"solvable": eq.is_correct(), "reason": "无空位,直接判定等式", "reachable_values": []}

	var start_pos := Vector2i(int(start["c"]), int(start["r"]))
	var queue: Array = [[start_pos, []]]  # 元素:[位置 Vector2i, 已捡数字 Array]
	var head := 0
	var visited: Dictionary = {}
	var reachable_values: Dictionary = {}  # 可达的(可捡)数字集合,用于诊断

	while head < queue.size():
		var state: Array = queue[head]
		head += 1
		var pos: Vector2i = state[0]
		var grabbed: Array = state[1]
		if grabbed.size() == k:
			if _any_permutation_solves(equation_tokens, grabbed, sign_flip):
				return {"solvable": true, "reason": "可解", "reachable_values": reachable_values.keys()}
			continue
		for d in DIRS:
			for dist in range(1, MAX_JUMP + 1):
				var target := _farthest_walkable(cells, pos, d, dist)
				if target == pos:
					continue  # 该方向这个蓄力档够不到任何格
				var cell: Dictionary = cells["%d,%d" % [target.x, target.y]]
				var v = cell.get("value", 0)
				var new_grabbed: Array = grabbed.duplicate()
				if v is int and v > 0:
					if new_grabbed.size() >= k or int(v) in new_grabbed:
						continue  # 已达上限,或同一数字格已被捡过(防 "5+5" 这类假解)
					new_grabbed.append(int(v))
					reachable_values[int(v)] = true
				elif v is String and v != "":
					if new_grabbed.size() >= k or v in new_grabbed:
						continue
					new_grabbed.append(v)  # 运算符格:捡运算符
					reachable_values[v] = true
				elif v is int and v == 0:
					pass  # 自由垫,移动不捡
				else:
					continue
				var key := "%d,%d|%s" % [target.x, target.y, str(new_grabbed)]
				if visited.has(key):
					continue
				visited[key] = true
				queue.append([target, new_grabbed])

	return {
		"solvable": false,
		"reason": "无解:可达数字 %s 中没有任何组合能组成正确等式" % str(reachable_values.keys()),
		"reachable_values": reachable_values.keys(),
	}


static func _slot_count(tokens: Array) -> int:
	var n := 0
	for tok in tokens:
		if tok is Dictionary and tok.get("type", "") == "slot":
			n += 1
	return n


# 该方向内、距离 ≤ dist 的"最远可站立格"(可跳过中间格)。
# 玩家现按精确落点判定(蓄力对应格不在格内即掉下去),但"可站立落点集合"与此一致:
# 蓄 1/2/3 档分别能落到距离 1/2/3 的格,这里退回更近格只会重复已被更小档覆盖的落点,不影响可达集。
static func _farthest_walkable(cells: Dictionary, pos: Vector2i, d: Vector2i, dist: int) -> Vector2i:
	for k in range(dist, 0, -1):
		var p := Vector2i(pos.x + d.x * k, pos.y + d.y * k)
		if cells.has("%d,%d" % [p.x, p.y]):
			return p
	return pos


# 捡到的数顺序由玩家(←/→)自由决定,故枚举全排列填入槽,任一成立即可解。
# sign_flip 为 true 时,每个捡到的正数还可翻成负数(翻转符号玩法)。
static func _any_permutation_solves(tokens: Array, grabbed: Array, sign_flip: bool = false) -> bool:
	for p in _permutations(grabbed):
		if _try_fill(tokens, p):
			return true
		if sign_flip and _try_negations(tokens, p):
			return true
	return false


static func _try_fill(tokens: Array, p: Array) -> bool:
	var eq := EquationScript.new(tokens)
	for i in p.size():
		eq.set_slot(i, p[i])
	return eq.is_correct()


# 枚举每个数字槽 ±(运算符槽不动),看有没有一种符号组合能凑成等式
static func _try_negations(tokens: Array, p: Array) -> bool:
	var flip_idx: Array = []
	for i in p.size():
		if p[i] is int and p[i] != 0:
			flip_idx.append(i)
	if flip_idx.is_empty():
		return false
	var n := flip_idx.size()
	for mask in range(1, 1 << n):
		var q := p.duplicate()
		for b in n:
			if mask & (1 << b):
				var j: int = flip_idx[b]
				q[j] = -int(q[j])
		if _try_fill(tokens, q):
			return true
	return false


static func _permutations(a: Array) -> Array:
	if a.size() <= 1:
		return [a]
	var out := []
	for i in a.size():
		var rest := a.duplicate()
		rest.remove_at(i)
		for sub in _permutations(rest):
			var combo := [a[i]]
			combo.append_array(sub)
			out.append(combo)
	return out
