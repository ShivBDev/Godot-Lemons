extends Node

# Real IDs: only used in release (non-debug) exports.
const REAL_BANNER_ID_IOS := "ca-app-pub-XXXXXXXXXXXXXXXX/ZZZZZZZZZZ"
# Google test ID: used for every debug build.
const TEST_BANNER_ID_IOS := "ca-app-pub-3940256099942544/2934735716"

var ad_view: AdView

func _ready() -> void:
	MobileAds.initialize()
	_load_banner()

func _load_banner() -> void:
	var unit_id := TEST_BANNER_ID_IOS
	if ad_view:
		ad_view.destroy()
	ad_view = AdView.new(unit_id, AdSize.BANNER, AdPosition.TOP)

	var listener := AdListener.new()
	listener.on_ad_loaded = func(): print("[Ads] banner loaded")
	listener.on_ad_failed_to_load = func(error: LoadAdError):
		push_warning("[Ads] banner failed: %s" % error.message)
	ad_view.ad_listener = listener
	ad_view.load_ad(AdRequest.new())
