class_name InfoPanel
extends PanelContainer
## PanelContainer with an InfoCard tooltip (technology tree chips).
## Example: var chip := InfoPanel.new(); chip.info = {"text": tr("Loom")}; chip.tooltip_text = tr("Loom")

## Card contents; see InfoCard. Empty -> the default text tooltip.
var info: Dictionary = {}
## Whether the card lists PC keyboard shortcuts (false on touch screens).
var show_keys := true


func _make_custom_tooltip(_for_text: String) -> Object:
	if info.is_empty():
		return null
	return InfoCard.build(info, show_keys, false)
