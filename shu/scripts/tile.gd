extends Node3D

const Style := preload("res://scripts/theme.gd")

var number: int = 0

@onready var _base: MeshInstance3D = $Base
@onready var _label: Label3D = $NumberLabel


# 由 main 在实例化后调用:设置数字 + 颜色。
# 数字决定颜色;若换成自带贴图的模型,可注释掉 material_override 那行。
func set_number(n: int) -> void:
	number = n
	if _base:
		_base.material_override = Style.toon_material(Style.tile_color(n), 0.4)
	if _label:
		_label.visible = n > 0
		if n > 0:
			_label.text = str(n)


func play_land_feedback() -> void:
	var t := create_tween()
	t.tween_property(self, "scale", Vector3(1.12, 0.9, 1.12), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
