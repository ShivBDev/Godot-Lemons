class_name StaffMember
extends Resource

enum STAFF_ID { server, advertiser }
@export var id : STAFF_ID = STAFF_ID.server
@export_file var icon : String = ""
@export var name : String = ""
@export var wage : float = 0.0
@export_multiline var blurb : String = ""
