extends RefCounted

# 关卡数据:从 res://levels/levels.json 读取(小白只需编辑那个 JSON 文件)。
# 这里负责把 JSON 里「易读的格式」转换成运行时需要的结构。

const LEVELS_PATH := "res://levels/levels.json"


static func all_levels() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(LEVELS_PATH))
	if not (parsed is Dictionary) or not (parsed.get("levels") is Array):
		push_error("levels.json 无法解析,已回退到内置关卡。请检查该文件是否为合法 JSON(逗号/引号/括号)。")
		return _fallback_levels()
	var out: Array = []
	for i in parsed["levels"].size():
		out.append(_build_level(parsed["levels"][i]))
	return out


# 按模式筛选关卡,例如 "add"(加法) / "sub"(减法)
static func levels_of_mode(mode: String) -> Array:
	var out: Array = []
	for lv in all_levels():
		if lv.get("mode", "add") == mode:
			out.append(lv)
	return out


static func _build_level(raw: Dictionary) -> Dictionary:
	return {
		"mode": str(raw.get("mode", "add")),
		"equation": _parse_equation(str(raw.get("equation", ""))),
		"grid": _parse_grid(raw.get("grid", [])),
		"start": _parse_start(raw.get("start", [1, 3])),
		"sign_flip": bool(raw.get("sign_flip", false)),
		"memory": bool(raw.get("memory", false)),
	}


# "? + ? = 3" -> [slot, op(+), slot, op(=), num(3)]
# 支持 + - ×(或 *) ÷(或 /),统一归一到 * / 供 Expression 求值
static func _parse_equation(s: String) -> Array:
	var tokens: Array = []
	# 先把乘除符号归一,再给所有运算符/问号两边加空格切分,容忍 "?+?=3" 这种没空格的写法
	var norm := s.replace("×", "*").replace("÷", "/")
	var spaced := norm.replace("+", " + ").replace("-", " - ").replace("*", " * ").replace("/", " / ").replace("=", " = ").replace("?", " ? ")
	for p in spaced.split(" ", false):
		if p == "?":
			tokens.append({"type": "slot"})
		elif p == "+" or p == "-" or p == "*" or p == "/":
			tokens.append({"type": "op", "value": p})
		elif p == "=":
			tokens.append({"type": "op", "value": "="})
		elif p.is_valid_int():
			tokens.append({"type": "num", "value": int(p)})
		else:
			push_warning("等式里有无法识别的片段,已忽略: " + p)
	return tokens


# [[1,2,3],[4,5,6],[7,8,9]] -> [{type,value,c,r}, ...]
# int/float(>0) → 数字格;String(如 "+") → 运算符格;0/null → 空格(跳过)
static func _parse_grid(g) -> Array:
	var out: Array = []
	if not (g is Array):
		return out
	for r in g.size():
		var row = g[r]
		if not (row is Array):
			continue
		for c in row.size():
			var cell = row[c]
			if cell is int or cell is float:
				var ni := int(cell)
				if ni > 0:
					out.append({"type": "num", "value": ni, "c": c, "r": r})
			elif cell is String and cell != "":
				out.append({"type": "op", "value": cell, "c": c, "r": r})
	return out


# [1, 3] -> {c:1, r:3}(列, 行)
static func _parse_start(s) -> Dictionary:
	var c := 1
	var r := 3
	if s is Array and s.size() >= 2:
		c = int(s[0])
		r = int(s[1])
	return {"c": c, "r": r}


# JSON 写错时兜底用的内置关卡,保证游戏还能跑
static func _fallback_levels() -> Array:
	return [
		{"mode": "add", "equation": [_slot(), _op("+"), _slot(), _eq(), _num(3)],  "grid": _std_grid(), "start": {"c": 1, "r": 3}},
		{"mode": "add", "equation": [_slot(), _op("+"), _slot(), _eq(), _num(10)], "grid": _std_grid(), "start": {"c": 1, "r": 3}},
		{"mode": "sub", "equation": [_slot(), _op("-"), _slot(), _eq(), _num(2)],  "grid": _std_grid(), "start": {"c": 1, "r": 3}},
		{"mode": "sub", "equation": [_slot(), _op("-"), _slot(), _eq(), _slot()],  "grid": _std_grid(), "start": {"c": 1, "r": 3}},
		{"mode": "add", "equation": [_slot(), _op("+"), _slot(), _eq(), _slot()],  "grid": _std_grid(), "start": {"c": 1, "r": 3}},
	]


static func _slot() -> Dictionary:
	return {"type": "slot"}


static func _num(v: int) -> Dictionary:
	return {"type": "num", "value": v}


static func _op(o: String) -> Dictionary:
	return {"type": "op", "value": o}


static func _eq() -> Dictionary:
	return {"type": "op", "value": "="}


static func _std_grid() -> Array:
	var out: Array = []
	var n := 1
	for r in 3:
		for c in 3:
			out.append({"type": "num", "value": n, "c": c, "r": r})
			n += 1
	return out
