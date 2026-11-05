class_name InfoButton
extends Button
## Button whose tooltip is an InfoCard (large preview, purpose, cost, missing
## requirements) instead of plain text. TouchTooltips shows the same card when
## a finger is held on it.
## Example: var b := InfoButton.new(); b.info = {"title": tr("House"), "cost": {"wood": 25}}; b.tooltip_text = InfoCard.plain(b.info)

## Card contents; see InfoCard. Empty -> the default text tooltip.
var info: Dictionary = {}
## Whether the card lists PC keyboard shortcuts (false on touch screens).
var show_keys := true


func _make_custom_tooltip(_for_text: String) -> Object:
	if info.is_empty():
		return null
	return InfoCard.build(info, show_keys, false)
