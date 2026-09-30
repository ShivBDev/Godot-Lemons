extends Node

var _areas : Dictionary[MapArea.AreaID, MapArea] = {}
const _defaultArea : MapArea.AreaID = MapArea.AreaID.Neighborhood
var _currTeamPair: Array[int] = [0, 1]
func _init() -> void:
	roll_new_team_themes()
	const folder_path: String = "res://scripts/menus/areas/areas"
	var files = ResourceLoader.list_directory(folder_path)
	for file in files:
		if file.get_extension() == "tres" or file.get_extension() == "res":
			var full_path = folder_path.path_join(file)
			var area: MapArea = ResourceLoader.load(full_path)
			if area:
				_areas[area.id] = area

func all() -> Array[MapArea]:
	var areas: Array[MapArea] = _areas.values().duplicate()
	areas.sort_custom(func(a: MapArea, b: MapArea): return a.id < b.id)
	return areas

func get_area(id: MapArea.AreaID) -> MapArea:
	return _areas.get(id, null)

func has_area(id: MapArea.AreaID) -> bool:
	return _areas.has(id)

func roll_new_team_themes() -> void:
	var count: int = MapArea.TEAM_THEMES.size()
	var first: int = randi() % count
	var second: int = randi() % count
	while second == first:
		second = randi() % count
	_currTeamPair = [first, second]

func get_team_theme() -> Array[Dictionary]:
	return [MapArea.TEAM_THEMES[_currTeamPair[0]], MapArea.TEAM_THEMES[_currTeamPair[1]]]
