class_name HowToPopup
extends CanvasLayer

# ===========================================================================
#  HOW-TO POPUP
#
#  A modal card that shows a scenario's "How this simulation works" and
#  "What to do" text on demand, and freezes the whole sim while it's open.
#
#  Freezing is done with get_tree().paused = true. That stops every node in
#  the tree that has the default process_mode (INHERIT) — the blobs, the
#  physics, and the scenario's _process, which is where sim_time is added.
#  So the timer, the graph, ageing, and breeding all stop dead. This layer
#  sets its own process_mode to ALWAYS so its Close button still works.
#
#  USAGE (from any DriftEvent subclass):
#      HowToPopup.open(self, _preset_title(), _howto_bbcode())
#
#  SETUP:
#    Save this file as  res://Scripts/howto_popup.gd  (any folder works —
#    class_name registers it globally). No scene needed.
# ===========================================================================

const DIM := Color(0.0, 0.0, 0.0, 0.62)
const PANEL_BG := Color(0.14, 0.14, 0.17)
const ACCENT := Color(1.0, 0.55, 0.42)

var _was_paused: bool = false

# Only one popup at a time. Opening while one is up is a no-op.
static func open(host: Node, title: String, bbcode: String) -> void:
	if host.get_tree().get_first_node_in_group("howto_popup") != null:
		return
	var p := HowToPopup.new()
	p.add_to_group("howto_popup")
	p.layer = 100
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(p)
	p._build(title, bbcode)
	p._was_paused = host.get_tree().paused
	host.get_tree().paused = true

func _build(title: String, bbcode: String) -> void:
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

	var note := Label.new()
	note.text = "The sim and its timer are frozen while this is open."
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.62, 0.62, 0.68))
	col.add_child(note)

	col.add_child(HSeparator.new())

	# --- scrollable body ---
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size = Vector2(620, 0)
	body.add_theme_font_size_override("normal_font_size", 15)
	body.add_theme_font_size_override("bold_font_size", 15)
	body.add_theme_font_size_override("italics_font_size", 15)
	body.add_theme_color_override("default_color", Color(0.86, 0.86, 0.92))
	body.text = bbcode
	scroll.add_child(body)

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
