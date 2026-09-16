extends RefCounted

# 等式纯逻辑模型:token 数组 + 求值 + 判对错(不依赖场景)
# 槽位存 Variant(数字/负数/运算符皆可),null 表示"空槽"。
# 注意:不能用 -1 当空槽哨兵,否则"翻成负数"玩法下 -1 会和空槽撞车。

const TYPE_NUM := "num"
const TYPE_OP := "op"
const TYPE_SLOT := "slot"

var tokens: Array = []
var slot_values: Array = []
var _slot_indices: Array = []
var _eq_index: int = -1


func _init(t: Array) -> void:
	tokens = t
	for i in tokens.size():
		var tok: Dictionary = tokens[i]
		if tok["type"] == TYPE_SLOT:
			_slot_indices.append(i)
			slot_values.append(null)
		elif tok["type"] == TYPE_OP and tok.get("value", "") == "=":
			_eq_index = i


func slots_count() -> int:
	return _slot_indices.size()


func get_slot(i: int) -> Variant:
	return slot_values[i]


func is_filled(i: int) -> bool:
	return slot_values[i] != null


func set_slot(i: int, v) -> void:
	slot_values[i] = v


func clear_slots() -> void:
	for i in slot_values.size():
		slot_values[i] = null


func is_complete() -> bool:
	for v in slot_values:
		if v == null:
			return false
	return true


func is_correct() -> bool:
	if not is_complete() or _eq_index < 0:
		return false
	var left := _build_side(0, _eq_index)
	var right := _build_side(_eq_index + 1, tokens.size())
	if left == "" or right == "":
		return false
	var e1 := Expression.new()
	if e1.parse(left) != OK:
		return false
	var lv = e1.execute([])
	if e1.has_execute_failed():
		return false
	var e2 := Expression.new()
	if e2.parse(right) != OK:
		return false
	var rv = e2.execute([])
	if e2.has_execute_failed():
		return false
	return float(lv) == float(rv)


func _build_side(from: int, to: int) -> String:
	var s := ""
	for i in range(from, to):
		var tok: Dictionary = tokens[i]
		match tok["type"]:
			TYPE_NUM:
				s += str(tok["value"])
			TYPE_OP:
				s += " " + str(tok["value"]) + " "
			TYPE_SLOT:
				var idx: int = _slot_indices.find(i)
				if idx < 0 or slot_values[idx] == null:
					return ""
				var v = slot_values[idx]
				if v is String:
					# 运算符槽:归一化乘除符号再两边加空格,如 " * "
					var op := str(v).replace("×", "*").replace("÷", "/")
					s += " " + op + " "
				elif v is int and v < 0:
					# 负数加括号,让 Expression 正确解析 "5 + (-3)"
					s += "(" + str(v) + ")"
				else:
					s += str(v)
	return s.strip_edges()
