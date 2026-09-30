class_name NewsItem
extends Resource

enum EffectTarget { traffic, price, patience, line, temp, rain, recipe, sale}

@export var newsId: String = ""
@export_multiline var text: String = ""
@export var effects: EffectTarget = EffectTarget.traffic
@export var value: float = 0.0
@export var data: Variant = null

func _init(
_newsId:String ="",
_text:String = "",
_effects:EffectTarget = EffectTarget.traffic,
_value:float = 0.0,
_data:Variant = null):
	newsId = _newsId
	text = _text
	effects = _effects
	value = _value
	data = _data
