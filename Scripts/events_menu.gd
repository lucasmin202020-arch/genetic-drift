extends Control

# ===========================================================================
#  DRIFT EVENTS MENU
#
#  Same card system as the Presets menu, so the two modes feel like one lab.
#  The badge reads EVENT n instead of LESSON n, because these aren't a
#  difficulty curve — they're four different ways a population can get
#  shoved, and you can take them in any order.
#
#  The difference between this mode and the Playground's command buttons:
#  the Playground fires an event and leaves you to guess what it did. Every
#  event in here takes a reading before it fires and another one after, and
#  the results card puts them side by side.
#
#  CARD ANATOMY
#    [EVENT n] Title
#    The question this event answers.
#  An accent stripe runs down the left edge, the card brightens on hover,
#  and clicking anywhere on the card launches it (not just the Start button).
#
#  SETUP:
#    1. New scene, root = Control named "EventsMenu", attach this script.
#    2. Save as  res://Scenes/EventsMenu.tscn
#    3. In main_menu.gd:
#         func _on_events():
#             get_tree().change_scene_to_file("res://Scenes/EventsMenu.tscn")
# ===========================================================================

const MENU_SCENE := "res://Scenes/MainMenu.tscn"

const EVENTS := [
	{
		"title": "Bottleneck",
		"question": "If the population recovers, does its diversity recover too?",
		"scene": "res://Scenes/Bottleneck.tscn",
	},
	{
		"title": "Founder Effect",
		"question": "How does a new population lose diversity when nobody dies?",
		"scene": "res://Scenes/FounderEffect.tscn",
	},
	{
		"title": "Natural Disaster",
		"question": "Can something that ignores color still wipe out a color?",
		"scene": "res://Scenes/NaturalDisaster.tscn",
	},
	{
		"title": "One Unlucky Death",
		"question": "How small can a drift step be and still change everything?",
		"scene": "res://Scenes/UnluckyDeath.tscn",
	},
]

const EVENT_COLOR := Color(1.0, 0.55, 0.42)
const QUESTION_COLOR := Color(0.98, 0.84, 0.72)

func _ready():
	_fit_to_window()
	get_viewport().size_changed.connect(_fit_to_window)
	_build_ui()

func _fit_to_window():
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size

# ---------------------------------------------------------------------------
#  LAYOUT
# ---------------------------------------------------------------------------
func _build_ui():
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.10, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	col.add_child(header)

	var back := _make_button("← Menu", Color(0.25, 0.25, 0.28), Vector2(140, 44), 17)
	back.pressed.connect(_to_menu)
	header.add_child(back)

	var title := Label.new()
	title.text = "Drift Events"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)

	var sub := Label.new()
	sub.text = "Four ways a population gets shoved around. Each one takes a reading before it fires and another after, so you can see exactly what changed."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.62, 0.62, 0.68))
	col.add_child(sub)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for i in range(EVENTS.size()):
		list.add_child(_make_card(EVENTS[i], i + 1))

# ---------------------------------------------------------------------------
#  EVENT CARD
# ---------------------------------------------------------------------------
func _make_card(data: Dictionary, event_no: int) -> PanelContainer:
	var scene_path: String = data["scene"]
	var unlocked: bool = scene_path != ""

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# --- CARD STYLE: accent stripe down the left edge ---
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.15, 0.15, 0.18) if unlocked else Color(0.12, 0.12, 0.14)
	cs.set_corner_radius_all(14)
	cs.border_color = Color(EVENT_COLOR.r, EVENT_COLOR.g, EVENT_COLOR.b, 0.9 if unlocked else 0.3)
	cs.border_width_left = 5
	cs.content_margin_left = 24
	cs.content_margin_right = 20
	cs.content_margin_top = 18
	cs.content_margin_bottom = 18
	card.add_theme_stylebox_override("panel", cs)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	card.add_child(row)

	var text_col := VBoxContainer.new()
	text_col.add_theme_constant_override("separation", 7)
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_col)

	# --- TITLE ROW: badge + name ---
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	text_col.add_child(title_row)

	title_row.add_child(_make_chip("EVENT %d" % event_no, EVENT_COLOR, unlocked))

	var name_lbl := Label.new()
	name_lbl.text = data["title"]
	name_lbl.add_theme_font_size_override("font_size", 21)
	name_lbl.add_theme_color_override("font_color",
		Color(0.95, 0.95, 0.95) if unlocked else Color(0.55, 0.55, 0.60))
	title_row.add_child(name_lbl)

	# --- THE QUESTION THIS EVENT ANSWERS ---
	var q := Label.new()
	q.text = data["question"]
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.custom_minimum_size = Vector2(400, 0)
	q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q.add_theme_font_size_override("font_size", 17)
	q.add_theme_color_override("font_color",
		QUESTION_COLOR if unlocked else Color(0.50, 0.48, 0.46))
	text_col.add_child(q)

	# --- RIGHT: action button ---
	var btn_wrap := CenterContainer.new()
	row.add_child(btn_wrap)

	if unlocked:
		var start := _make_button("Start", Color(0.78, 0.38, 0.30), Vector2(150, 46), 18)
		start.pressed.connect(_launch.bind(scene_path))
		btn_wrap.add_child(start)

		# Hover highlight + whole card clickable
		var hover_cs: StyleBoxFlat = cs.duplicate()
		hover_cs.bg_color = Color(0.19, 0.19, 0.23)
		card.mouse_entered.connect(func(): card.add_theme_stylebox_override("panel", hover_cs))
		card.mouse_exited.connect(func(): card.add_theme_stylebox_override("panel", cs))
		card.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_launch(scene_path))
	else:
		var soon := _make_button("Coming soon", Color(0.20, 0.20, 0.23), Vector2(150, 46), 15)
		soon.disabled = true
		soon.add_theme_color_override("font_disabled_color", Color(0.48, 0.48, 0.53))
		btn_wrap.add_child(soon)

	return card

func _make_chip(text: String, base: Color, unlocked: bool) -> PanelContainer:
	var chip := PanelContainer.new()
	var c: Color = base
	if not unlocked:
		c = c.darkened(0.45)

	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(c.r, c.g, c.b, 0.18)
	bs.border_color = Color(c.r, c.g, c.b, 0.75)
	bs.set_border_width_all(1)
	bs.set_corner_radius_all(9)
	bs.content_margin_left = 10
	bs.content_margin_right = 10
	bs.content_margin_top = 3
	bs.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", bs)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", c)
	chip.add_child(lbl)

	return chip

# ---------------------------------------------------------------------------
#  ACTIONS
# ---------------------------------------------------------------------------
func _launch(scene_path: String):
	if not ResourceLoader.exists(scene_path):
		push_error("EventsMenu: no scene found at '%s'. Right-click the .tscn in the FileSystem dock -> Copy Path, and paste it into the EVENTS array." % scene_path)
		print("EVENT LAUNCH FAILED — file not found: ", scene_path)
		return
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("EventsMenu: failed to load '%s' (error %d). The scene exists but couldn't be opened — usually a script error inside it." % [scene_path, err])
		print("EVENT LAUNCH FAILED — load error ", err, " on ", scene_path)

func _to_menu():
	get_tree().change_scene_to_file(MENU_SCENE)

# ---------------------------------------------------------------------------
#  BUTTON STYLING (matches the other menus)
# ---------------------------------------------------------------------------
func _make_button(text: String, base_color: Color, min_size: Vector2, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_stylebox_override("normal",   _rounded_style(base_color))
	b.add_theme_stylebox_override("hover",    _rounded_style(base_color.lightened(0.10)))
	b.add_theme_stylebox_override("pressed",  _rounded_style(base_color.darkened(0.12)))
	b.add_theme_stylebox_override("focus",    _rounded_style(base_color))
	b.add_theme_stylebox_override("disabled", _rounded_style(base_color))
	var text_col := Color(0.10, 0.10, 0.10) if base_color.get_luminance() > 0.5 else Color(0.93, 0.93, 0.93)
	b.add_theme_color_override("font_color", text_col)
	b.add_theme_color_override("font_hover_color", text_col)
	b.add_theme_color_override("font_pressed_color", text_col)
	b.add_theme_color_override("font_focus_color", text_col)
	return b

func _rounded_style(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(23)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s
