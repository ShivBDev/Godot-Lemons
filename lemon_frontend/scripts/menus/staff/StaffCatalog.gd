extends RefCounted
class_name StaffCatalog

# Day hires. One entry per worker. The menu toggles them; DaySimulation reads
# the flags at the start of the day and charges the wage at the end of it.

const AD_TRAFFIC: float = 1.15

const _all_workers : Array[StaffMember] = [
	preload("uid://bw5uyesc5o3v3"), # Server
	preload("uid://c0jvqpyd7ia8j")  # Advertiser
]

static func all() -> Array[StaffMember]:
	return _all_workers

static func get_def(id: StaffMember.STAFF_ID) -> StaffMember:
	for worker in _all_workers:
		if worker.id == id:
			return worker
	return null;

static func has_worker(id: StaffMember.STAFF_ID) -> bool:
	return get_def(id) != null

static func daily_cost(id: StaffMember.STAFF_ID) -> float:
	var worker : StaffMember = get_def(id)
	if worker == null:
		return 0.0
	return worker.wage

static func name_of(id: StaffMember.STAFF_ID) -> String:
	var worker : StaffMember = get_def(id)
	if worker == null:
		return "Unknown"
	return worker.name
