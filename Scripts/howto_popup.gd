class_name HowToPopup
extends CanvasLayer

# ===========================================================================
#  HOW-TO POPUP  (v2 — tabbed)
#
#  A modal card that shows a scenario's explanation on demand and freezes the
#  whole sim while it's open. v2 adds TABS, so one popup can hold both
#  "Why" (the science) and "How" (the mechanics + what to do).
#
#  Freezing is done with get_tree().paused = true. That stops every node in
#  the tree that has the default process_mode (INHERIT) — the blobs, the
#  physics, and the scenario's _process, which is where sim_time is added.
#  So the timer, the graph, ageing, and breeding all stop dead. This layer
#  sets its own process_mode to ALWAYS so its buttons still work.
#
#  USAGE (from any DriftPreset subclass):
#      HowToPopup.open(self, title, bbcode)                 # one tab
#      HowToPopup.open_tabs(self, title, [
#          {"label": "Why", "bbcode": science_text},
#          {"label": "How", "bbcode": howto_text},
#      ])                                                    # several tabs
#
#  SETUP:
#    Save this file as  res://Scripts/howto_popup.gd  (any folder works —
#    class_name registers it globally). No scene needed.
# ===========================================================================

const DIM := Color(0.0, 0.0, 0.0, 0.62)
const PANEL_BG := Color(0.14, 0.14, 0.17)
const ACCENT := Color(1.0, 0.55, 0.42)
const TAB_ACCENT := Color(0.95, 0.78, 0.38)

var _was_paused: bool = false
var _body: RichTextLabel
var _scroll: ScrollContainer
var _tab_buttons: Array = []
var _tabs: Array = []

# Backwards-compatible single-tab entry point.
static func open(host: Node, title: String, bbcode: String) -> void:
	open_tabs(host, title, [{"label": "How to play", "bbcode": bbcode}])

# Only one popup at a time. Opening while one is up is a no-op.
static func open_tabs(host: Node, title: String, tabs: Array) -> void:
	if host.get_tree().get_first_node_in_group("howto_popup") != null:
		return
	if tabs.is_empty():
		return
	var p := HowToPopup.new()
	p.add_to_group("howto_popup")
	p.layer = 100
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(p)
	p._build(title, tabs)
	p._was_paused = host.get_tree().paused
	host.get_tree().paused = true

func _build(title: String, tabs: Array) -> void:
	_tabs = tabs

	# Full-screen dimmer. Eats clicks so nothing underneath gets them.
	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = PANEL_BG
	ps.set_corner_radius_all(16)
	ps.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.9)
	ps.border_width_left = 5
	ps.content_margin_left = 26
	ps.content_margin_right = 22
	ps.content_margin_top = 18
	ps.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", ps)
	panel.custom_minimum_size = Vector2(680, 0)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	# --- header: PAUSED chip + title + close ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	col.add_child(header)

	var chip := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.18)
	cs.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.75)
	cs.set_border_width_all(1)
	cs.set_corner_radius_all(9)
	cs.content_margin_left = 10
	cs.content_margin_right = 10
	cs.content_margin_top = 3
	cs.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", cs)
	var chip_lbl := Label.new()
	chip_lbl.text = "PAUSED"
	chip_lbl.add_theme_font_size_override("font_size", 13)
	chip_lbl.add_theme_color_override("font_color", ACCENT)
	chip.add_child(chip_lbl)
	header.add_child(chip)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 21)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title_lbl)

	var close := Button.new()
	close.text = "Close  (Esc)"
	close.custom_minimum_size = Vector2(130, 38)
	close.add_theme_font_size_override("font_size", 15)
	close.add_theme_stylebox_override("normal", _rounded(Color(0.78, 0.38, 0.30)))
	close.add_theme_stylebox_override("hover", _rounded(Color(0.78, 0.38, 0.30).lightened(0.1)))
	close.add_theme_stylebox_override("pressed", _rounded(Color(0.78, 0.38, 0.30).darkened(0.12)))
	close.add_theme_stylebox_override("focus", _rounded(Color(0.78, 0.38, 0.30)))
	close.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	close.pressed.connect(_close)
	header.add_child(close)

	# --- tab row (only when there is more than one tab) ---
	if tabs.size() > 1:
		var tab_row := HBoxContainer.new()
		tab_row.add_theme_constant_override("separation", 8)
		col.add_child(tab_row)
		for i in range(tabs.size()):
			var d: Dictionary = tabs[i]
			var b := Button.new()
			b.text = str(d["label"])
			b.custom_minimum_size = Vector2(120, 34)
			b.add_theme_font_size_override("font_size", 15)
			b.toggle_mode = true
			b.pressed.connect(_select_tab.bind(i))
			tab_row.add_child(b)
			_tab_buttons.append(b)

	var note := Label.new()
	note.text = "The sim and its timer are frozen while this is open."
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.62, 0.62, 0.68))
	col.add_child(note)

	col.add_child(HSeparator.new())

	# --- scrollable body ---
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 380)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_style_scrollbar(_scroll)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.custom_minimum_size = Vector2(620, 0)
	_body.add_theme_font_size_override("normal_font_size", 15)
	_body.add_theme_font_size_override("bold_font_size", 15)
	_body.add_theme_font_size_override("italics_font_size", 15)
	_body.add_theme_color_override("default_color", Color(0.86, 0.86, 0.92))
	_scroll.add_child(_body)

	_select_tab(0)

func _select_tab(i: int) -> void:
	i = clampi(i, 0, _tabs.size() - 1)
	var d: Dictionary = _tabs[i]
	_body.text = str(d["bbcode"])
	if _scroll:
		_scroll.scroll_vertical = 0
	for j in range(_tab_buttons.size()):
		var b: Button = _tab_buttons[j]
		var on: bool = (j == i)
		b.button_pressed = on
		var bg := Color(TAB_ACCENT.r, TAB_ACCENT.g, TAB_ACCENT.b, 0.28 if on else 0.08)
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_color = Color(TAB_ACCENT.r, TAB_ACCENT.g, TAB_ACCENT.b, 0.9 if on else 0.35)
		s.set_border_width_all(2)
		s.set_corner_radius_all(8)
		s.content_margin_left = 12
		s.content_margin_right = 12
		s.content_margin_top = 4
		s.content_margin_bottom = 4
		for slot in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(str(slot), s)
		b.add_theme_color_override("font_color", TAB_ACCENT if on else Color(0.80, 0.80, 0.84))
		b.add_theme_color_override("font_hover_color", TAB_ACCENT)
		b.add_theme_color_override("font_pressed_color", TAB_ACCENT)
		b.add_theme_color_override("font_focus_color", TAB_ACCENT if on else Color(0.80, 0.80, 0.84))

# A scrollbar you can actually see. The default one is 4px of near-nothing.
static func _style_scrollbar(scroll: ScrollContainer) -> void:
	var vbar: VScrollBar = scroll.get_v_scroll_bar()
	if vbar == null:
		return
	vbar.custom_minimum_size = Vector2(12, 0)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.06)
	track.set_corner_radius_all(6)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(1, 1, 1, 0.32)
	grab.set_corner_radius_all(6)
	var grab_hi := StyleBoxFlat.new()
	grab_hi.bg_color = Color(1, 1, 1, 0.48)
	grab_hi.set_corner_radius_all(6)
	vbar.add_theme_stylebox_override("scroll", track)
	vbar.add_theme_stylebox_override("grabber", grab)
	vbar.add_theme_stylebox_override("grabber_highlight", grab_hi)
	vbar.add_theme_stylebox_override("grabber_pressed", grab_hi)

func _rounded(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(19)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()

func _close() -> void:
	get_tree().paused = _was_paused
	queue_free()
