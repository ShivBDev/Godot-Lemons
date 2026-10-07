class_name NewsItem
extends Resource

enum EffectTarget { traffic, price, patience, line, temp, rain, recipe, sale}

@export var newsId: String = ""
@export_multiline var text: String = ""
@export var effects: EffectTarget = EffectTarget.traffic
@export var value: float = 0.0
@export var data: Variant = null
# Weather the headline promises, on top of its main effect: 1 = hotter than the
# usual high, -1 = colder than the usual low, 0 = no promise. A "temp" headline
# takes its direction from the sign of value instead. Either way the day's
# temperature is forced outside the normal band (see Weather.headline_*_temp).
@export_range(-1, 1) var weather_push: int = 0

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
