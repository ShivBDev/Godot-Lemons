extends Node

# Google test ID: used for every debug build.
const TEST_BANNER_ID_IOS : String = "ca-app-pub-3940256099942544/2934735716"
const BOTTOM_BANNER_ID_IOS : String = "ca-app-pub-2940196659565673/5380211301"
const TOP_BANNER_ID_IOS : String = "ca-app-pub-2940196659565673/7400073245"

var _top_banner: AdView
var _lower_banner: AdView

func _ready() -> void:
	MobileAds.initialize()
	_load_banners()
	hide_lower_banner()

func _load_banners() -> void:
	var unit_id := TEST_BANNER_ID_IOS
	if _top_banner:
		_top_banner.destroy()
	_top_banner = AdView.new(unit_id, AdSize.BANNER, AdPosition.TOP)
	_lower_banner = AdView.new(unit_id, AdSize.BANNER, AdPosition.BOTTOM)

	var listener := AdListener.new()
	listener.on_ad_loaded = func(): print("[Ads] banner loaded")
	listener.on_ad_failed_to_load = func(error: LoadAdError):
		push_warning("[Ads] banner failed: %s" % error.message)
	_top_banner.ad_listener = listener
	_top_banner.load_ad(AdRequest.new())

	var listener2 : AdListener = AdListener.new()
	listener2.on_ad_loaded = func(): print("[Ads] banner loaded")
	listener2.on_ad_failed_to_load = func(error: LoadAdError):
		push_warning("[Ads] banner failed: %s" % error.message)
	_lower_banner.ad_listener = listener2
	_lower_banner.load_ad(AdRequest.new())

func show_lower_banner():
	if _lower_banner: _lower_banner.show()

func hide_lower_banner():
	if _lower_banner: _lower_banner.hide()
