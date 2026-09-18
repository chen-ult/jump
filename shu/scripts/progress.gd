extends RefCounted

# 关卡解锁进度:持久化到 user://progress.json,跨启动保留

const SAVE_PATH := "user://progress.json"


# 该模式当前解锁到第几关(1 = 只有第1关)
static func unlocked_count(mode: String) -> int:
	return int(_load().get(mode, 1))


# 通过某关后解锁下一关
static func on_level_passed(mode: String, level_index: int) -> void:
	var data := _load()
	var cur := int(data.get(mode, 1))
	data[mode] = maxi(cur, level_index + 2)
	_save(data)


# 无尽模式最高分:到达第几关(取历史最大)
static func endless_best() -> int:
	return int(_load().get("endless_best", 0))


static func set_endless_best(level: int) -> void:
	var data := _load()
	var cur := int(data.get("endless_best", 0))
	data["endless_best"] = maxi(cur, level)
	_save(data)


# 无尽模式最高得分(取历史最大)
static func endless_best_score() -> int:
	return int(_load().get("endless_best_score", 0))


static func set_endless_best_score(score: int) -> void:
	var data := _load()
	var cur := int(data.get("endless_best_score", 0))
	data["endless_best_score"] = maxi(cur, score)
	_save(data)


static func _load() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if parsed is Dictionary:
		return parsed
	return {}


static func _save(data: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
