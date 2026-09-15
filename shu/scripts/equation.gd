extends RefCounted

# 等式纯逻辑模型:token 数组 + 求值 + 判对错(不依赖场景)

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
			slot_values.append(-1)
		elif tok["type"] == TYPE_OP and tok.get("value", "") == "=":
			_eq_index = i


func slots_count() -> int:
	return _slot_indices.size()


func get_slot(i: int) -> int:
	return slot_values[i]


func set_slot(i: int, v: int) -> void:
	slot_values[i] = v


func clear_slots() -> void:
	for i in slot_values.size():
		slot_values[i] = -1


func is_complete() -> bool:
	for v in slot_values:
		if v < 0:
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
				if idx < 0 or slot_values[idx] < 0:
					return ""
				s += str(slot_values[idx])
	return s.strip_edges()
