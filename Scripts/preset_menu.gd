extends Control

# ===========================================================================
#  PRESET MENU
#  A scrollable list of the guided drift scenarios. Fully code-built.
#
#  SETUP:
#    1. New scene, root = Control named "PresetMenu", attach this script.
#    2. Save as  res://Scenes/PresetMenu.tscn
#    3. In main_menu.gd:
#         func _on_presets():
#             get_tree().change_scene_to_file("res://Scenes/PresetMenu.tscn")
#
#  Bottleneck / founder-effect style demos deliberately live in the DRIFT
#  EVENTS tab instead — presets here each teach a distinct idea about how
#  drift behaves, not a single event.
#
#  CARD ANATOMY
#    [LESSON n] Title [WARN chip, if any]
#    The question this preset answers.
#
#    LESSON n   the running order. The order IS the difficulty curve, so
#               nobody has to be told a scenario is "advanced".
#    warn       a red flag for any preset that deliberately breaks the lab's
#               no-selection rule. Right now that's Drift vs Selection only.
#               Leave it as "" on every other preset.
#
#  An accent stripe runs down the left edge, the card brightens on hover,
#  and clicking anywhere on the card launches it (not just the Start button).
#
#  TO ADD A PRESET LATER: add one entry to the PRESETS array below.
#  Leave "scene" as "" to show it as a greyed-out "Coming soon" card.
# ===========================================================================

const MENU_SCENE := "res://Scenes/MainMenu.tscn"

const PRESETS := [
	{
		"title": "Randomness: The Basis of Genetic Drift",
		"question": "Does a color have to be better to take over?",
		"warn": "",
		"scene": "res://Scenes/CoinFlip.tscn",
	},
	{
		"title": "The Long Shot",
		"question": "Can a rare color beat a common one on luck alone?",
		"warn": "",
		"scene": "res://Scenes/LongShot.tscn",
	},
	{
		"title": "Small vs Large",
		"question": "Why does population size change how fast drift works?",
		"warn": "",
		"scene": "res://Scenes/SmallVsLarge.tscn",
	},
	{
		"title": "Parallel Worlds",
		"question": "Same start, same rules — same ending?",
		"warn": "",
		"scene": "res://Scenes/ParallelWorlds.tscn",
	},
	{
		"title": "Gene Flow",
		"question": "What happens when two isolated groups start mixing?",
		"warn": "",
		"scene": "res://Scenes/GeneFlow.tscn",
	},
	{
		"title": "Drift vs Selection",
		"question": "How is a real advantage different from pure luck?",
		"warn": "Breaks the no-selection rule",
		"scene": "res://Scenes/DriftVsSelection.tscn",
	},
]

# --- CHIP COLORS ---
const LESSON_COLOR := Color(0.44, 0.60, 0.94)
const WARN_COLOR := Color(0.88, 0.38, 0.42)
const QUESTION_COLOR := Color(0.72, 0.80, 0.96)

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

	# --- HEADER ROW: back button + title ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	col.add_child(header)

	var back := _make_button("← Menu", Color(0.25, 0.25, 0.28), Vector2(140, 44), 17)
	back.pressed.connect(_to_menu)
	header.add_child(back)

	var title := Label.new()
	title.text = "Presets"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)

	# --- SUBTITLE ---
	var sub := Label.new()
	sub.text = "Six guided lessons, in order. Each one asks a question, runs on its own, then explains what happened."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.62, 0.62, 0.68))
	col.add_child(sub)

	# --- SCROLLABLE CARD LIST ---
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for i in range(PRESETS.size()):
		list.add_child(_make_card(PRESETS[i], i + 1))

# ---------------------------------------------------------------------------
#  PRESET CARD
# ---------------------------------------------------------------------------
func _make_card(data: Dictionary, lesson_no: int) -> PanelContainer:
	var scene_path: String = data["scene"]
	var unlocked: bool = scene_path != ""

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# --- CARD STYLE: accent stripe down the left edge ---
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.15, 0.15, 0.18) if unlocked else Color(0.12, 0.12, 0.14)
	cs.set_corner_radius_all(14)
	cs.border_color = Color(LESSON_COLOR.r, LESSON_COLOR.g, LESSON_COLOR.b, 0.9 if unlocked else 0.3)
	cs.border_width_left = 5
	cs.content_margin_left = 24
	cs.content_margin_right = 20
	cs.content_margin_top = 18
	cs.content_margin_bottom = 18
	card.add_theme_stylebox_override("panel", cs)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	card.add_child(row)

	# --- LEFT: text block ---
	var text_col := VBoxContainer.new()
	text_col.add_theme_constant_override("separation", 7)
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_col)

	# --- TITLE ROW: badge + name + warn ---
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	text_col.add_child(title_row)

	title_row.add_child(_make_chip("LESSON %d" % lesson_no, LESSON_COLOR, unlocked))

	var name_lbl := Label.new()
	name_lbl.text = data["title"]
	name_lbl.add_theme_font_size_override("font_size", 21)
	name_lbl.add_theme_color_override("font_color",
		Color(0.95, 0.95, 0.95) if unlocked else Color(0.55, 0.55, 0.60))
	title_row.add_child(name_lbl)

	# A preset that deliberately breaks the no-selection rule says so on the
	# same line as its name, where it can't be missed.
	var warn_text: String = str(data["warn"])
	if warn_text != "":
		title_row.add_child(_make_chip(warn_text.to_upper(), WARN_COLOR, unlocked))

	# --- THE QUESTION THIS PRESET ANSWERS ---
	var q := Label.new()
	q.text = data["question"]
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.custom_minimum_size = Vector2(400, 0)
	q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q.add_theme_font_size_override("font_size", 17)
	q.add_theme_color_override("font_color",
		QUESTION_COLOR if unlocked else Color(0.48, 0.50, 0.56))
	text_col.add_child(q)

	# --- RIGHT: action button ---
	var btn_wrap := CenterContainer.new()
	row.add_child(btn_wrap)

	if unlocked:
		var start := _make_button("Start", Color(0.36, 0.55, 0.95), Vector2(150, 46), 18)
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

# One chip style for every kind of tag, so they read as a single system.
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
# Loud about failures — a bad path or a scene with a script error would
# otherwise just look like "the button does nothing".
func _launch(scene_path: String):
	if not ResourceLoader.exists(scene_path):
		push_error("PresetMenu: no scene found at '%s'. Right-click the .tscn in the FileSystem dock -> Copy Path, and paste it into the PRESETS array." % scene_path)
		print("PRESET LAUNCH FAILED — file not found: ", scene_path)
		return
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("PresetMenu: failed to load '%s' (error %d). The scene exists but couldn't be opened — usually a script error inside it." % [scene_path, err])
		print("PRESET LAUNCH FAILED — load error ", err, " on ", scene_path)

func _to_menu():
	get_tree().change_scene_to_file(MENU_SCENE)

# ---------------------------------------------------------------------------
#  BUTTON STYLING (matches the main menu)
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
