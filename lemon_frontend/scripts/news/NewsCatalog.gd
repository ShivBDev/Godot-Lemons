extends Node

# Todays's headlines. News items are stored resource objects. DaySimulation rolls one at the
# end of each day, stores it on PlayerData.news_id, and applies it to the next
# day only. The ticker shows it while shopping and hides once the day starts.

var _news_items : Dictionary[String, NewsItem] = {}
func _init() -> void:
	const folder_path: String = "res://scripts/news/news_items/"
	var files = ResourceLoader.list_directory(folder_path)
	for file in files:
		# Filter for resource extensions (e.g., .tres, .res)
		if file.get_extension() == "tres" or file.get_extension() == "res":
			var full_path = folder_path.path_join(file)
			var res : NewsItem = ResourceLoader.load(full_path)
			if res:
				_news_items[res.newsId] = res

func all() -> Dictionary[String, NewsItem]:
	return _news_items

func count() -> int:
	return _news_items.size()

func get_item(id: String) -> NewsItem:
	if _news_items.has(id):
		return _news_items[id]
	return null

func roll() -> String:
	if _news_items.is_empty():
		return ""
	var news: NewsItem = _news_items.values()[randi() % _news_items.size()]
	return news.newsId

func headline(id: String) -> String:
	return _news_items[id].text

func applies_to_area(id: String, area_id: MapArea.AreaID) -> bool:
	var newsTarget: String = str(_news_items[id].data)
	if newsTarget.is_empty():
		return true
	return newsTarget.to_upper() == MapArea.ID2Str(area_id).to_upper()

func sale_multiplier(id: String, field: String) -> float:
	var news : NewsItem = _news_items[id]
	if news.effects != NewsItem.EffectTarget.sale:
		return 1.0
	var newsField : String = str(news.data)
	if not newsField.is_empty() and newsField != field:
		return 1.0
	return maxf(0.1, news.value)

func recipe_shift(id: String) -> Dictionary:
	var news: NewsItem = _news_items[id]
	if news.effects != NewsItem.EffectTarget.recipe:
		return {}
	var recipe: Variant = news.data
	if typeof(recipe) != TYPE_DICTIONARY:
		return {}
	return recipe
