extends Control

# ===========================================================================
#  INFO MENU
#  A standalone scene. Two levels:
#    HUB   — three big cards (drift theory, how the lab works, scenarios)
#    PAGE  — sidebar of entries on the left, scrolling content on the right,
#            with Prev / Next at the bottom of every entry.
#
#  SETUP (once):
#    1. Scene -> New Scene -> "User Interface" (a Control root).
#    2. Rename the root to InfoMenu, attach this script.
#    3. Save as res://Scenes/InfoMenu.tscn
#    4. main_menu.gd's Info button now navigates here (INFO_MENU_SCENE).
#
#  CONTENT MODEL
#    Every entry is a function that returns an Array of "blocks":
#      {"t": bbcode}                          plain text block
#      {"f": Callable, "h": px, "c": caption} drawn figure
#      {"call": header, "body": bbcode, "col": Color}   callout box
#    To add an entry, write a _e_*() function and add one line to SECTIONS.
#    All figures are drawn in code — no image files, nothing to lose on
#    export. Set BLOB_TEXTURES to use real sprite art in the blob figures.
#
#  OVERLAY MODE (v2)
#    A running scenario can open this same scene ON TOP of itself, without
#    leaving the run. The scenario instantiates InfoMenu.tscn, sets
#    overlay_mode = true BEFORE adding it to the tree, connects the `closed`
#    signal, and pauses the tree. In overlay mode every "back to main menu"
#    button becomes "Close" and emits `closed` instead of changing scene.
#    See DriftPreset._on_info_pressed() in coin_flip.gd.
# ===========================================================================

signal closed

# Set by the host BEFORE add_child(). When true, exits emit `closed` instead
# of changing scene, and Esc closes the overlay.
var overlay_mode: bool = false

const MENU_SCENE := "res://Scenes/MainMenu.tscn"
const FONT_PATH := "res://Fonts/Nunito.ttf"

# OPTIONAL: real sprite art for figures that draw blobs. Leave "" for the
# procedural shapes.
const BLOB_TEXTURES := {
	"round": "",
	"star": "",
	"flower": "",
}

const SIDEBAR_W := 236.0
const PARTICLES := 42
const COL_BORDER := Color(0.26, 0.26, 0.31)
const COL_BORDER_HOT := Color(0.62, 0.62, 0.70)

const COL_RED := Color(0.90, 0.38, 0.38)
const COL_GREEN := Color(0.42, 0.80, 0.48)
const COL_BLUE := Color(0.42, 0.62, 0.95)
const COL_AMBER := Color(1.0, 0.78, 0.36)
const COL_GOLD := Color(1.0, 0.85, 0.30)
const COL_TEXT := Color(0.90, 0.90, 0.92)
const COL_DIM := Color(0.58, 0.58, 0.64)
const COL_GRID := Color(1.0, 1.0, 1.0, 0.10)
const COL_PLOT_BG := Color(0.07, 0.07, 0.09)
const COL_PANEL := Color(0.14, 0.14, 0.17)
const COL_PANEL_DARK := Color(0.11, 0.11, 0.14)
const COL_BG := Color(0.10, 0.10, 0.12)

var hub: Control
var page: Control
var page_title: Label
var sidebar_box: VBoxContainer
var content_box: VBoxContainer
var content_scroll: ScrollContainer

var current_section: int = -1
var current_entry: int = -1
var sidebar_buttons: Array = []

var _walk_cache: Dictionary = {}
var t: float = 0.0
var rng := RandomNumberGenerator.new()
var bg_canvas: Control
var glow_a: Sprite2D
var glow_b: Sprite2D
var particles: Array = []
var hub_cards: Array = []       # {"btn", "style", "cta"}
var icon_canvases: Array = []
var hub_title: Label
var hub_sub: Label
var _tex_cache: Dictionary = {}
var _font_file: FontFile = null
var _fonts: Dictionary = {}

# ---------------------------------------------------------------------------
#  SECTION TABLE
# ---------------------------------------------------------------------------
var SECTIONS: Array = []

func _build_section_table() -> void:
	SECTIONS = [
		{
			"title": "What is genetic drift?",
			"blurb": "The theory. Where drift comes from, what it does to a population, and how it differs from natural selection.",
			"icon": _icon_drift,
			"entries": [
				{"group": "", "title": "The basic idea", "blocks": _e_basic},
				{"group": "", "title": "Why it happens", "blocks": _e_why},
				{"group": "", "title": "Fixation and loss", "blocks": _e_fixation},
				{"group": "", "title": "Population size", "blocks": _e_popsize},
				{"group": "", "title": "Drift is not selection", "blocks": _e_not_selection},
				{"group": "", "title": "Isolated populations diverge", "blocks": _e_diverge},
				{"group": "", "title": "Gene flow pulls them back", "blocks": _e_geneflow},
				{"group": "", "title": "Bottlenecks and founders", "blocks": _e_bottleneck_theory},
				{"group": "", "title": "Drift in the real world", "blocks": _e_real_world},
			],
		},
		{
			"title": "How the lab works",
			"blurb": "The blobs, their lives, the tracker, the speed control, and the three modes.",
			"icon": _icon_lab,
			"entries": [
				{"group": "", "title": "The blobs", "blocks": _e_blobs},
				{"group": "", "title": "The life of a blob", "blocks": _e_life},
				{"group": "", "title": "The allele tracker", "blocks": _e_tracker},
				{"group": "", "title": "Speed and controls", "blocks": _e_speed},
				{"group": "", "title": "The three modes", "blocks": _e_modes},
			],
		},
		{
			"title": "Scenarios",
			"blurb": "Every preset lesson and drift event: what happens on screen, the concept it teaches, and what to watch for.",
			"icon": _icon_scenarios,
			"entries": [
				{"group": "PRESETS", "title": "L1  Randomness (Coin Flip)", "blocks": _e_coin_flip},
				{"group": "PRESETS", "title": "L2  The Long Shot", "blocks": _e_long_shot},
				{"group": "PRESETS", "title": "L3  Small vs Large", "blocks": _e_small_large},
				{"group": "PRESETS", "title": "L4  Parallel Worlds", "blocks": _e_parallel},
				{"group": "PRESETS", "title": "L5  Gene Flow", "blocks": _e_gene_flow},
				{"group": "PRESETS", "title": "L6  Drift vs Selection", "blocks": _e_drift_vs_sel},
				{"group": "DRIFT EVENTS", "title": "One Unlucky Death", "blocks": _e_unlucky},
				{"group": "DRIFT EVENTS", "title": "Natural Disaster", "blocks": _e_disaster},
				{"group": "DRIFT EVENTS", "title": "Bottleneck", "blocks": _e_bottleneck},
				{"group": "DRIFT EVENTS", "title": "Founder Effect", "blocks": _e_founder},
				{"group": "SANDBOX", "title": "Sandbox", "blocks": _e_sandbox},
			],
		},
	]

# ---------------------------------------------------------------------------
#  LIFECYCLE
# ---------------------------------------------------------------------------
func _ready():
	rng.randomize()
	_apply_font_theme()
	_fit_to_window()
	get_viewport().size_changed.connect(_fit_to_window)
	_build_section_table()
	_init_particles()
	_build_background()
	_build_hub()
	_build_page()
	_show_hub()

func _process(delta: float) -> void:
	t += delta
	_step_particles(delta)
	if bg_canvas:
		bg_canvas.queue_redraw()
	if hub.visible:
		for ic in icon_canvases:
			var c: Control = ic
			c.queue_redraw()
	if glow_a and glow_b:
		var s: Vector2 = get_viewport_rect().size
		glow_a.position = Vector2(s.x * 0.20 + sin(t * 0.13) * 70.0, s.y * 0.28 + cos(t * 0.11) * 40.0)
		glow_b.position = Vector2(s.x * 0.82 + sin(t * 0.09 + 2.0) * 70.0, s.y * 0.80 + cos(t * 0.14 + 1.0) * 40.0)

# ---------------------------------------------------------------------------
#  FONT (same setup as main_menu.gd)
# ---------------------------------------------------------------------------
func _ui_font(weight: int) -> Font:
	if _font_file == null:
		return ThemeDB.fallback_font
	if _fonts.has(weight):
		return _fonts[weight]
	var fv := FontVariation.new()
	fv.base_font = _font_file
	var ts: TextServer = TextServerManager.get_primary_interface()
	fv.variation_opentype = {ts.name_to_tag("wght"): float(weight)}
	_fonts[weight] = fv
	return fv

func _apply_font_theme() -> void:
	if ResourceLoader.exists(FONT_PATH):
		_font_file = load(FONT_PATH)
	var th := Theme.new()
	th.default_font = _ui_font(500)
	th.default_font_size = 16
	th.set_font("bold_font", "RichTextLabel", _ui_font(750))
	theme = th

func _fit_to_window():
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	glow_a = _make_glow(380, COL_BLUE, 0.07)
	glow_b = _make_glow(440, COL_RED, 0.05)
	add_child(glow_a)
	add_child(glow_b)

	bg_canvas = Control.new()
	bg_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_canvas.draw.connect(_draw_background)
	add_child(bg_canvas)

func _make_glow(radius: int, color: Color, alpha: float) -> Sprite2D:
	var px: int = radius * 2
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var centre := Vector2(radius, radius)
	for y in range(px):
		for x in range(px):
			var d: float = Vector2(x, y).distance_to(centre)
			if d <= radius:
				var k: float = 1.0 - smoothstep(0.0, float(radius), d)
				img.set_pixel(x, y, Color(color.r, color.g, color.b, k * k * alpha))
	var sp := Sprite2D.new()
	sp.texture = ImageTexture.create_from_image(img)
	return sp

func _init_particles() -> void:
	var cols: Array = [COL_RED, COL_GREEN, COL_BLUE, COL_BLUE, COL_DIM]
	var s: Vector2 = get_viewport_rect().size
	for i in range(PARTICLES):
		var depth: float = rng.randf()
		particles.append({
			"p": Vector2(rng.randf() * s.x, rng.randf() * s.y),
			"v": Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized() * (6.0 + 14.0 * depth),
			"r": 2.5 + 6.0 * depth,
			"a": 0.05 + 0.13 * depth,
			"col": cols[rng.randi() % cols.size()],
			"ph": rng.randf() * TAU,
		})

func _step_particles(delta: float) -> void:
	var s: Vector2 = get_viewport_rect().size
	for pt in particles:
		var d: Dictionary = pt
		var v: Vector2 = d["v"]
		var ph: float = float(d["ph"])
		v = v.rotated(sin(t * 0.35 + ph) * 0.35 * delta)
		var p: Vector2 = d["p"] + v * delta
		var m: float = 30.0
		if p.x < -m: p.x = s.x + m
		if p.x > s.x + m: p.x = -m
		if p.y < -m: p.y = s.y + m
		if p.y > s.y + m: p.y = -m
		d["p"] = p
		d["v"] = v

func _draw_background() -> void:
	var c: Control = bg_canvas
	for pt in particles:
		var d: Dictionary = pt
		var p: Vector2 = d["p"]
		var r: float = float(d["r"])
		var a: float = float(d["a"]) * (0.85 + 0.15 * sin(t * 0.8 + float(d["ph"])))
		var col: Color = d["col"]
		c.draw_circle(p, r * 3.2, Color(col.r, col.g, col.b, a * 0.18))
		c.draw_circle(p, r, Color(col.r, col.g, col.b, a))

func _go(path: String) -> void:
	if not ResourceLoader.exists(path):
		push_error("InfoMenu: no scene found at '%s'." % path)
		return
	get_tree().change_scene_to_file(path)

# Every "leave the Info menu" button routes through here, so overlay mode
# only has to be handled once.
func _leave() -> void:
	if overlay_mode:
		closed.emit()
	else:
		_go(MENU_SCENE)

func _exit_button_text(default_text: String) -> String:
	return "Close  (Esc)" if overlay_mode else default_text

func _input(event: InputEvent) -> void:
	if not overlay_mode:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_leave()

# ---------------------------------------------------------------------------
#  HUB
# ---------------------------------------------------------------------------
func _build_hub() -> void:
	hub = Control.new()
	hub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(hub)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hub.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var title := Label.new()
	hub_title = title
	title.text = "Info"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _ui_font(800))
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	col.add_child(title)

	var sub := Label.new()
	hub_sub = sub
	sub.text = "Pick a section. Everything in the lab is explained somewhere in here."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", COL_DIM)
	col.add_child(sub)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	col.add_child(gap)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)

	for i in range(SECTIONS.size()):
		row.add_child(_make_hub_card(i))

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 8)
	col.add_child(gap2)

	var back := _make_button(_exit_button_text("Back to Menu"), Color(0.32, 0.32, 0.35), Vector2(220, 46), 17)
	var back_wrap := CenterContainer.new()
	back_wrap.add_child(back)
	col.add_child(back_wrap)
	back.pressed.connect(_leave)

func _make_hub_card(index: int) -> Button:
	var sec: Dictionary = SECTIONS[index]
	var card := Button.new()
	card.custom_minimum_size = Vector2(300, 330)
	var style := _card_style(COL_PANEL, COL_BORDER)
	for slot in ["normal", "hover", "pressed", "focus"]:
		card.add_theme_stylebox_override(str(slot), style)
	card.pressed.connect(_open_section.bind(index))
	var entry: Dictionary = {"btn": card, "style": style, "cta": null}
	hub_cards.append(entry)
	card.mouse_entered.connect(_on_card_hover.bind(entry, true))
	card.mouse_exited.connect(_on_card_hover.bind(entry, false))
	card.button_down.connect(_on_card_down.bind(entry))
	card.button_up.connect(_on_card_hover.bind(entry, true))

	# Children of a Button don't get laid out by it, so anchor a container
	# over the whole card and let clicks pass through to the button.
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 18)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	card.add_child(pad)

	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 10)
	pad.add_child(vb)

	var icon := Control.new()
	icon.custom_minimum_size = Vector2(0, 120)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var drawer: Callable = sec["icon"]
	icon.draw.connect(func(): drawer.call(icon))
	icon.resized.connect(icon.queue_redraw)
	vb.add_child(icon)
	icon_canvases.append(icon)

	var t := Label.new()
	t.text = str(sec["title"])
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_theme_font_override("font", _ui_font(750))
	t.add_theme_font_size_override("font_size", 20)
	t.add_theme_color_override("font_color", COL_TEXT)
	vb.add_child(t)

	var b := Label.new()
	b.text = str(sec["blurb"])
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", COL_DIM)
	vb.add_child(b)

	var n := Label.new()
	var entries: Array = sec["entries"]
	n.text = "%d topics  ·  Open  →" % entries.size()
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.add_theme_font_size_override("font_size", 13)
	n.add_theme_color_override("font_color", Color(COL_AMBER.r, COL_AMBER.g, COL_AMBER.b, 0.75))
	vb.add_child(n)
	entry["cta"] = n
	return card

func _on_card_hover(entry: Dictionary, on: bool) -> void:
	var btn: Button = entry["btn"]
	var style: StyleBoxFlat = entry["style"]
	btn.pivot_offset = btn.size * 0.5
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "scale", Vector2(1.03, 1.03) if on else Vector2.ONE, 0.18)
	tw.tween_property(style, "border_color", COL_BORDER_HOT if on else COL_BORDER, 0.18)
	tw.tween_property(style, "bg_color", COL_PANEL.lightened(0.05) if on else COL_PANEL, 0.18)
	tw.tween_property(style, "shadow_size", 22 if on else 10, 0.18)
	if entry["cta"] != null:
		var cta: Label = entry["cta"]
		tw.tween_property(cta, "theme_override_colors/font_color", COL_AMBER if on else Color(COL_AMBER.r, COL_AMBER.g, COL_AMBER.b, 0.75), 0.18)

func _on_card_down(entry: Dictionary) -> void:
	var btn: Button = entry["btn"]
	btn.pivot_offset = btn.size * 0.5
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "scale", Vector2(0.985, 0.985), 0.08)

func _play_hub_intro() -> void:
	hub_title.modulate.a = 0.0
	hub_sub.modulate.a = 0.0
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(hub_title, "modulate:a", 1.0, 0.4)
	tw.tween_property(hub_sub, "modulate:a", 1.0, 0.4).set_delay(0.08)
	for i in range(hub_cards.size()):
		var d: Dictionary = hub_cards[i]
		var btn: Button = d["btn"]
		btn.modulate.a = 0.0
		btn.scale = Vector2(0.94, 0.94)
		btn.pivot_offset = btn.custom_minimum_size * 0.5
		var delay: float = 0.14 + 0.09 * float(i)
		tw.tween_property(btn, "modulate:a", 1.0, 0.4).set_delay(delay)
		tw.tween_property(btn, "scale", Vector2.ONE, 0.4).set_delay(delay)

func _card_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(16)
	s.set_border_width_all(1)
	s.border_color = border
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 6)
	return s

# ---------------------------------------------------------------------------
#  PAGE (sidebar + content)
# ---------------------------------------------------------------------------
func _build_page() -> void:
	page = Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(page)

	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 18)
	outer.add_theme_constant_override("margin_right", 18)
	outer.add_theme_constant_override("margin_top", 14)
	outer.add_theme_constant_override("margin_bottom", 14)
	page.add_child(outer)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	outer.add_child(col)

	# Header row
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	col.add_child(header)

	var back := _make_button("←  Sections", Color(0.28, 0.28, 0.31), Vector2(150, 40), 15)
	back.pressed.connect(_show_hub)
	header.add_child(back)

	page_title = Label.new()
	page_title.add_theme_font_override("font", _ui_font(750))
	page_title.add_theme_font_size_override("font_size", 24)
	page_title.add_theme_color_override("font_color", COL_TEXT)
	page_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(page_title)

	var menu := _make_button(_exit_button_text("Main Menu"), Color(0.22, 0.22, 0.25), Vector2(130, 40), 14)
	menu.pressed.connect(_leave)
	header.add_child(menu)

	# Body row
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	# Sidebar
	var side_panel := PanelContainer.new()
	side_panel.custom_minimum_size = Vector2(SIDEBAR_W, 0)
	side_panel.add_theme_stylebox_override("panel", _panel_style(COL_PANEL_DARK))
	body.add_child(side_panel)

	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_panel.add_child(side_scroll)

	sidebar_box = VBoxContainer.new()
	sidebar_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar_box.add_theme_constant_override("separation", 4)
	side_scroll.add_child(sidebar_box)

	# Content
	var content_panel := PanelContainer.new()
	content_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_panel.add_theme_stylebox_override("panel", _panel_style(COL_PANEL))
	body.add_child(content_panel)

	content_scroll = ScrollContainer.new()
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_panel.add_child(content_scroll)

	var content_pad := MarginContainer.new()
	content_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_pad.add_theme_constant_override("margin_left", 22)
	content_pad.add_theme_constant_override("margin_right", 22)
	content_pad.add_theme_constant_override("margin_top", 18)
	content_pad.add_theme_constant_override("margin_bottom", 18)
	content_scroll.add_child(content_pad)

	content_box = VBoxContainer.new()
	content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_box.add_theme_constant_override("separation", 16)
	content_pad.add_child(content_box)

func _panel_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(14)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s

# ---------------------------------------------------------------------------
#  NAVIGATION
# ---------------------------------------------------------------------------
func _show_hub() -> void:
	hub.visible = true
	page.visible = false
	_play_hub_intro()

func _open_section(index: int) -> void:
	current_section = index
	var sec: Dictionary = SECTIONS[index]
	page_title.text = str(sec["title"])
	_build_sidebar(sec)
	hub.visible = false
	page.visible = true
	page.modulate.a = 0.0
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(page, "modulate:a", 1.0, 0.25)
	_select_entry(0)

func _build_sidebar(sec: Dictionary) -> void:
	for child in sidebar_box.get_children():
		child.queue_free()
	sidebar_buttons.clear()

	var entries: Array = sec["entries"]
	var last_group: String = "\u0001"
	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		var group: String = str(e["group"])
		if group != last_group:
			last_group = group
			if group != "":
				var g := Label.new()
				g.text = group
				g.add_theme_font_size_override("font_size", 11)
				g.add_theme_color_override("font_color", COL_DIM)
				var gm := MarginContainer.new()
				gm.add_theme_constant_override("margin_top", 10 if i > 0 else 2)
				gm.add_theme_constant_override("margin_left", 10)
				gm.add_theme_constant_override("margin_bottom", 2)
				gm.add_child(g)
				sidebar_box.add_child(gm)
		var b := Button.new()
		b.text = str(e["title"])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 36)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(_select_entry.bind(i))
		b.mouse_entered.connect(_side_nudge.bind(b, true))
		b.mouse_exited.connect(_side_nudge.bind(b, false))
		sidebar_box.add_child(b)
		sidebar_buttons.append(b)
	_refresh_sidebar_styles()

func _side_nudge(b: Button, on: bool) -> void:
	b.pivot_offset = Vector2(0.0, b.size.y * 0.5)
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "position:x", 6.0 if on else 0.0, 0.14)

func _refresh_sidebar_styles() -> void:
	for i in range(sidebar_buttons.size()):
		var b: Button = sidebar_buttons[i]
		var selected: bool = (i == current_entry)
		var bg: Color = Color(0.22, 0.22, 0.26) if selected else Color(0, 0, 0, 0)
		var hover: Color = Color(0.22, 0.22, 0.26) if selected else Color(0.16, 0.16, 0.19)
		b.add_theme_stylebox_override("normal", _side_style(bg))
		b.add_theme_stylebox_override("hover", _side_style(hover))
		b.add_theme_stylebox_override("pressed", _side_style(bg))
		b.add_theme_stylebox_override("focus", _side_style(bg))
		var fc: Color = COL_TEXT if selected else COL_DIM
		b.add_theme_color_override("font_color", fc)
		b.add_theme_color_override("font_hover_color", COL_TEXT)
		b.add_theme_color_override("font_pressed_color", fc)
		b.add_theme_color_override("font_focus_color", fc)

func _side_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(8)
	s.content_margin_left = 12
	s.content_margin_right = 8
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

func _select_entry(index: int) -> void:
	var sec: Dictionary = SECTIONS[current_section]
	var entries: Array = sec["entries"]
	index = clamp(index, 0, entries.size() - 1)
	current_entry = index
	_refresh_sidebar_styles()

	for child in content_box.get_children():
		child.queue_free()

	var e: Dictionary = entries[index]
	var maker: Callable = e["blocks"]
	var blocks: Array = maker.call()
	for blk in blocks:
		var d: Dictionary = blk
		if d.has("t"):
			_add_text(content_box, str(d["t"]))
		elif d.has("f"):
			_add_figure(content_box, d["f"], int(d["h"]), str(d["c"]))
		elif d.has("call"):
			_add_callout(content_box, str(d["call"]), str(d["body"]), d["col"])

	_add_prev_next(entries, index)
	content_scroll.scroll_vertical = 0
	# stagger the blocks in
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var i: int = 0
	for child in content_box.get_children():
		var ctl: Control = child
		if ctl.is_queued_for_deletion():
			continue
		ctl.modulate.a = 0.0
		tw.tween_property(ctl, "modulate:a", 1.0, 0.28).set_delay(0.035 * float(i))
		i += 1

func _add_prev_next(entries: Array, index: int) -> void:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 12)
	content_box.add_child(sep)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	content_box.add_child(row)

	if index > 0:
		var prev_e: Dictionary = entries[index - 1]
		var pb := _make_button("←  " + str(prev_e["title"]), Color(0.24, 0.24, 0.27), Vector2(0, 40), 14)
		pb.pressed.connect(_select_entry.bind(index - 1))
		row.add_child(pb)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	if index < entries.size() - 1:
		var next_e: Dictionary = entries[index + 1]
		var nb := _make_button(str(next_e["title"]) + "  →", Color(0.86, 0.46, 0.46), Vector2(0, 40), 14)
		nb.pressed.connect(_select_entry.bind(index + 1))
		row.add_child(nb)
	else:
		var hb := _make_button("Back to sections  →", Color(0.86, 0.46, 0.46), Vector2(0, 40), 14)
		hb.pressed.connect(_show_hub)
		row.add_child(hb)

# ---------------------------------------------------------------------------
#  BLOCK BUILDERS
# ---------------------------------------------------------------------------
func _add_text(vb: VBoxContainer, bbcode: String) -> void:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.selection_enabled = true
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_color_override("default_color", COL_TEXT)
	rt.add_theme_font_size_override("normal_font_size", 16)
	rt.meta_clicked.connect(func(meta): OS.shell_open(str(meta)))
	rt.text = bbcode
	vb.add_child(rt)

func _add_callout(vb: VBoxContainer, header: String, body: String, col: Color) -> void:
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := StyleBoxFlat.new()
	st.bg_color = Color(col.r, col.g, col.b, 0.09)
	st.set_corner_radius_all(8)
	st.border_width_left = 4
	st.border_color = col
	st.content_margin_left = 16
	st.content_margin_right = 14
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	frame.add_theme_stylebox_override("panel", st)
	vb.add_child(frame)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	frame.add_child(box)

	var h := Label.new()
	h.text = header
	h.add_theme_font_size_override("font_size", 12)
	h.add_theme_color_override("font_color", col)
	box.add_child(h)

	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.selection_enabled = true
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_color_override("default_color", COL_TEXT)
	rt.add_theme_font_size_override("normal_font_size", 15)
	rt.text = body
	box.add_child(rt)

func _add_figure(vb: VBoxContainer, drawer: Callable, height: int, caption: String) -> void:
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := StyleBoxFlat.new()
	st.bg_color = COL_PANEL_DARK
	st.set_corner_radius_all(10)
	st.set_border_width_all(1)
	st.border_color = Color(0.26, 0.26, 0.31)
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 12
	st.content_margin_bottom = 12
	frame.add_theme_stylebox_override("panel", st)
	vb.add_child(frame)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	frame.add_child(box)

	var canvas := Control.new()
	canvas.custom_minimum_size = Vector2(0, height)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(func(): drawer.call(canvas))
	canvas.resized.connect(canvas.queue_redraw)
	box.add_child(canvas)

	if caption != "":
		var cap := Label.new()
		cap.text = caption
		cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cap.add_theme_font_size_override("font_size", 13)
		cap.add_theme_color_override("font_color", COL_DIM)
		box.add_child(cap)

# Shorthands so the entry functions stay readable.
func T(bbcode: String) -> Dictionary:
	return {"t": bbcode}

func F(drawer: Callable, h: int, caption: String) -> Dictionary:
	return {"f": drawer, "h": h, "c": caption}

func C(header: String, body: String, col: Color) -> Dictionary:
	return {"call": header, "body": body, "col": col}

func _h(title: String) -> String:
	return "[font_size=24][b]%s[/b][/font_size]" % title

func _q(question: String) -> String:
	return "[font_size=17][color=#ffc85c]%s[/color][/font_size]" % question

# ---------------------------------------------------------------------------
#  BUTTONS (same look as the rest of the lab)
# ---------------------------------------------------------------------------
func _make_button(text: String, base_color: Color, min_size: Vector2, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	var style := _rounded_style(base_color)
	for slot in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(str(slot), style)
	b.mouse_entered.connect(func():
		b.pivot_offset = b.size * 0.5
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "scale", Vector2(1.04, 1.04), 0.14)
		tw.tween_property(style, "bg_color", base_color.lightened(0.10), 0.14))
	b.mouse_exited.connect(func():
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "scale", Vector2.ONE, 0.14)
		tw.tween_property(style, "bg_color", base_color, 0.14))
	var text_col := Color(0.10, 0.10, 0.10) if base_color.get_luminance() > 0.5 else Color(0.93, 0.93, 0.93)
	b.add_theme_color_override("font_color", text_col)
	b.add_theme_color_override("font_hover_color", text_col)
	b.add_theme_color_override("font_pressed_color", text_col)
	b.add_theme_color_override("font_focus_color", text_col)
	return b

func _rounded_style(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(33)
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

# ===========================================================================
#  DRAWING PRIMITIVES
# ===========================================================================
func _font() -> Font:
	return _ui_font(600)

func _label(c: Control, pos: Vector2, text: String, size: int, col: Color) -> void:
	c.draw_string(_font(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _label_center(c: Control, pos: Vector2, text: String, size: int, col: Color) -> void:
	var w: float = _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	c.draw_string(_font(), Vector2(pos.x - w * 0.5, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _label_right(c: Control, pos: Vector2, text: String, size: int, col: Color) -> void:
	var w: float = _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	c.draw_string(_font(), Vector2(pos.x - w, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _draw_arrow(c: Control, from: Vector2, to: Vector2, col: Color) -> void:
	var d: Vector2 = (to - from).normalized()
	var shaft_end: Vector2 = to - d * 9.0
	c.draw_line(from, shaft_end, col, 2.0, true)
	var n: Vector2 = Vector2(-d.y, d.x)
	var pts := PackedVector2Array([to, to - d * 11.0 + n * 5.5, to - d * 11.0 - n * 5.5])
	c.draw_colored_polygon(pts, col)

func _draw_x(c: Control, pos: Vector2, r: float, col: Color) -> void:
	c.draw_line(pos + Vector2(-r, -r), pos + Vector2(r, r), col, 3.0, true)
	c.draw_line(pos + Vector2(-r, r), pos + Vector2(r, -r), col, 3.0, true)

func _star_points(center: Vector2, outer: float, inner: float, tips: int) -> PackedVector2Array:
	var arr := PackedVector2Array()
	for i in range(tips * 2):
		var rad: float = outer if i % 2 == 0 else inner
		var a: float = -PI * 0.5 + TAU * float(i) / float(tips * 2)
		arr.append(center + Vector2(cos(a), sin(a)) * rad)
	return arr

func _cached_texture(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = null
	if path != "" and ResourceLoader.exists(path):
		tex = load(path)
	_tex_cache[path] = tex
	return tex

# shape: 0 round, 1 star, 2 flower.  eyes: 1 or 3.
func _draw_blob(c: Control, pos: Vector2, r: float, col: Color, shape: int, eyes: int, blink: bool = false) -> void:
	var keys: Array = ["round", "star", "flower"]
	var path: String = str(BLOB_TEXTURES.get(keys[shape], ""))
	var tex: Texture2D = _cached_texture(path)
	if tex != null:
		c.draw_texture_rect(tex, Rect2(pos - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false, col)
	else:
		match shape:
			0:
				c.draw_circle(pos, r, col)
			1:
				c.draw_colored_polygon(_star_points(pos, r, r * 0.46, 5), col)
			2:
				for i in range(6):
					var a: float = TAU * float(i) / 6.0
					c.draw_circle(pos + Vector2(cos(a), sin(a)) * r * 0.58, r * 0.44, col)
				c.draw_circle(pos, r * 0.56, col)
	if r < 9.0:
		return
	if eyes == 1:
		_draw_eye(c, pos + Vector2(0.0, -r * 0.08), r * 0.28, blink)
	else:
		_draw_eye(c, pos + Vector2(-r * 0.40, -r * 0.02), r * 0.19, blink)
		_draw_eye(c, pos + Vector2(0.0, -r * 0.34), r * 0.19, blink)
		_draw_eye(c, pos + Vector2(r * 0.40, -r * 0.02), r * 0.19, blink)

func _draw_eye(c: Control, pos: Vector2, r: float, blink: bool = false) -> void:
	if blink:
		c.draw_line(pos + Vector2(-r, 0), pos + Vector2(r, 0), Color(0.08, 0.08, 0.10), 2.0, true)
		return
	c.draw_circle(pos, r, Color(0.97, 0.97, 0.98))
	c.draw_circle(pos, r * 0.48, Color(0.08, 0.08, 0.10))

func _draw_box(c: Control, rect: Rect2) -> void:
	c.draw_rect(rect, COL_PLOT_BG, true)
	c.draw_rect(rect, Color(1.0, 1.0, 1.0, 0.12), false, 1.0)

func _draw_cluster(c: Control, rect: Rect2, colors: Array, cols: int) -> void:
	_draw_box(c, rect)
	var n: int = colors.size()
	if n == 0:
		return
	var rows: int = int(ceil(float(n) / float(cols)))
	var cw: float = rect.size.x / float(cols)
	var ch: float = rect.size.y / float(rows)
	var r: float = min(cw, ch) * 0.32
	for i in range(n):
		var cx: int = i % cols
		var cy: int = int(floor(float(i) / float(cols)))
		var p := Vector2(rect.position.x + cw * (float(cx) + 0.5), rect.position.y + ch * (float(cy) + 0.5))
		var col: Color = colors[i]
		c.draw_circle(p, r, col)

# ---------------------------------------------------------------------------
#  SIMULATED DATA (cached, seeded, so figures are stable)
# ---------------------------------------------------------------------------
func _make_walks(pop: int, gens: int, lines: int, seed_value: int, w: float) -> Array:
	# w = fitness multiplier of the tracked allele. 1.0 = pure drift.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Array = []
	for i in range(lines):
		var count: int = int(floor(float(pop) * 0.5))
		var series: Array = [float(count) / float(pop)]
		for g in range(gens):
			if count > 0 and count < pop:
				var p: float = float(count) / float(pop)
				var ps: float = p * w / (p * w + (1.0 - p))
				var next_count: int = 0
				for k in range(pop):
					if rng.randf() < ps:
						next_count += 1
				count = next_count
			series.append(float(count) / float(pop))
		out.append(series)
	return out

func _walks(key: String, pop: int, gens: int, lines: int, seed_value: int, w: float = 1.0) -> Array:
	if not _walk_cache.has(key):
		_walk_cache[key] = _make_walks(pop, gens, lines, seed_value, w)
	return _walk_cache[key]

func _make_three_walk(pop: int, gens: int, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var third: int = int(floor(float(pop) / 3.0))
	var counts: Array = [third, third, pop - 2 * third]
	var out: Array = []
	out.append([float(counts[0]) / float(pop), float(counts[1]) / float(pop), float(counts[2]) / float(pop)])
	for g in range(gens):
		var next: Array = [0, 0, 0]
		for k in range(pop):
			var u: float = rng.randf() * float(pop)
			var idx: int = 2
			if u < float(counts[0]):
				idx = 0
			elif u < float(counts[0] + counts[1]):
				idx = 1
			next[idx] = int(next[idx]) + 1
		counts = next
		out.append([float(counts[0]) / float(pop), float(counts[1]) / float(pop), float(counts[2]) / float(pop)])
	return out

func _three_walk(key: String, pop: int, gens: int, seed_value: int) -> Array:
	if not _walk_cache.has(key):
		_walk_cache[key] = _make_three_walk(pop, gens, seed_value)
	return _walk_cache[key]

# ---------------------------------------------------------------------------
#  CHART HELPERS
# ---------------------------------------------------------------------------
func _draw_plot(c: Control, rect: Rect2, series_list: Array, force_col: Color = Color(0, 0, 0, 0)) -> void:
	c.draw_rect(rect, COL_PLOT_BG, true)
	for f in [0.0, 0.5, 1.0]:
		var y: float = rect.position.y + rect.size.y * (1.0 - float(f))
		c.draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), COL_GRID, 1.0)
	for s in series_list:
		var series: Array = s
		if series.size() < 2:
			continue
		var last: float = float(series[series.size() - 1])
		var col: Color = COL_DIM
		if force_col.a > 0.0:
			col = force_col
		elif last >= 0.999:
			col = COL_GREEN
		elif last <= 0.001:
			col = COL_RED
		var pts := PackedVector2Array()
		for i in range(series.size()):
			var x: float = rect.position.x + rect.size.x * (float(i) / float(series.size() - 1))
			var y2: float = rect.position.y + rect.size.y * (1.0 - float(series[i]))
			pts.append(Vector2(x, clamp(y2, rect.position.y + 1.0, rect.end.y - 1.0)))
		c.draw_polyline(pts, col, 2.0, true)
	c.draw_rect(rect, Color(1.0, 1.0, 1.0, 0.12), false, 1.0)

func _draw_stacked(c: Control, rect: Rect2, data: Array) -> void:
	c.draw_rect(rect, COL_PLOT_BG, true)
	var n: int = data.size()
	if n < 2:
		return
	var cols: Array = [COL_RED, COL_GREEN, COL_BLUE]
	var cw: float = rect.size.x / float(n)
	for i in range(n):
		var fr: Array = data[i]
		var x: float = rect.position.x + cw * float(i)
		var lo: float = 0.0
		for band in range(3):
			var f: float = float(fr[band])
			if f <= 0.0:
				continue
			var y_bot: float = rect.end.y - rect.size.y * lo
			var y_top: float = rect.end.y - rect.size.y * (lo + f)
			c.draw_rect(Rect2(x, y_top, cw + 0.6, y_bot - y_top), cols[band], true)
			lo += f
	c.draw_rect(rect, Color(1.0, 1.0, 1.0, 0.12), false, 1.0)

func _plot_axis_labels(c: Control, rect: Rect2) -> void:
	_label_right(c, Vector2(rect.position.x - 6.0, rect.position.y + 5.0), "100%", 11, COL_DIM)
	_label_right(c, Vector2(rect.position.x - 6.0, rect.position.y + rect.size.y * 0.5 + 4.0), "50%", 11, COL_DIM)
	_label_right(c, Vector2(rect.position.x - 6.0, rect.end.y + 4.0), "0%", 11, COL_DIM)

# ===========================================================================
#  HUB ICONS
# ===========================================================================
func _icon_drift(c: Control) -> void:
	var rect := Rect2(10.0, 10.0, c.size.x - 20.0, c.size.y - 20.0)
	c.draw_rect(rect, COL_PLOT_BG, true)
	for f in [0.25, 0.5, 0.75]:
		var y: float = rect.end.y - rect.size.y * float(f)
		c.draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(1, 1, 1, 0.05), 1.0)
	var cycle: float = fmod(t, 8.0)
	var progress: float = clamp(cycle / 5.0, 0.0, 1.0)
	progress = progress * progress * (3.0 - 2.0 * progress)
	var lines: Array = _walks("icon", 18, 64, 3, 20260906)
	var cols: Array = [COL_RED, COL_GREEN, COL_BLUE]
	for li in range(lines.size()):
		var series: Array = lines[li]
		var col: Color = cols[li % 3]
		var n: int = series.size()
		var reach: float = progress * float(n - 1)
		var full: int = int(floor(reach))
		var pts := PackedVector2Array()
		for i in range(full + 1):
			pts.append(Vector2(rect.position.x + rect.size.x * float(i) / float(n - 1), rect.end.y - rect.size.y * float(series[i])))
		if full < n - 1:
			var frac: float = reach - float(full)
			var yv: float = lerp(float(series[full]), float(series[full + 1]), frac)
			pts.append(Vector2(rect.position.x + rect.size.x * reach / float(n - 1), rect.end.y - rect.size.y * yv))
		if pts.size() >= 2:
			c.draw_polyline(pts, col, 2.0, true)
			c.draw_circle(pts[pts.size() - 1], 3.0, col)
	c.draw_rect(rect, Color(1, 1, 1, 0.12), false, 1.0)

func _icon_lab(c: Control) -> void:
	var cy: float = c.size.y * 0.5
	var cx: float = c.size.x * 0.5
	var specs: Array = [[-84.0, COL_RED, 0, 1, 0.0], [0.0, COL_GREEN, 1, 3, 2.1], [84.0, COL_BLUE, 2, 1, 4.2]]
	for s in specs:
		var sp: Array = s
		var phase: float = float(sp[4])
		var bob: float = sin(t * 1.6 + phase) * 4.0
		var blink: bool = fmod(t + phase * 0.7, 4.3) < 0.13
		_draw_blob(c, Vector2(cx + float(sp[0]), cy + bob), 30.0, sp[1], int(sp[2]), int(sp[3]), blink)

func _icon_scenarios(c: Control) -> void:
	var w: float = c.size.x
	var h: float = c.size.y
	var gap: float = 8.0
	var cw: float = (w - 20.0 - gap) * 0.5
	var ch: float = (h - 20.0 - gap) * 0.5
	var sets: Array = [
		[COL_RED, COL_GREEN, COL_BLUE, COL_RED],
		[COL_BLUE, COL_BLUE, COL_BLUE, COL_BLUE],
		[COL_GREEN, COL_RED, COL_GREEN, COL_GREEN],
		[COL_RED, COL_RED, COL_BLUE, COL_RED],
	]
	for i in range(4):
		var col_i: int = i % 2
		var row_i: int = int(floor(float(i) / 2.0))
		var r := Rect2(10.0 + col_i * (cw + gap), 10.0 + row_i * (ch + gap), cw, ch)
		_draw_cluster(c, r, sets[i], 2)
		# each pen takes a turn lighting up
		var glow: float = clamp(1.0 - abs(fmod(t * 0.5, 4.0) - float(i)) * 1.6, 0.0, 1.0)
		if glow > 0.0:
			c.draw_rect(r, Color(1.0, 0.78, 0.36, 0.55 * glow), false, 1.5)

# ===========================================================================
#  FIGURES — THEORY
# ===========================================================================
func _fig_drift(c: Control) -> void:
	var left: float = 46.0
	var rect := Rect2(left, 22.0, c.size.x - left - 14.0, c.size.y - 52.0)
	_draw_plot(c, rect, _walks("main", 20, 70, 6, 20240917))
	_plot_axis_labels(c, rect)
	_label(c, Vector2(rect.position.x, 16.0), "frequency of one allele", 12, COL_DIM)
	_label(c, Vector2(rect.position.x, c.size.y - 8.0), "generations  →", 12, COL_DIM)
	_label(c, Vector2(rect.end.x - 120.0, rect.position.y + 16.0), "fixed", 12, COL_GREEN)
	_label(c, Vector2(rect.end.x - 120.0, rect.end.y - 8.0), "lost", 12, COL_RED)

func _fig_sampling(c: Control) -> void:
	var rows: Array = [
		[5, "50%", "the parents"],
		[6, "60%", "10 random births"],
		[8, "80%", "10 more random births"],
	]
	var r: float = 11.0
	var spacing: float = 30.0
	var x0: float = 150.0
	for i in range(rows.size()):
		var row: Array = rows[i]
		var blue_n: int = int(row[0])
		var y: float = 40.0 + float(i) * 62.0
		_label_right(c, Vector2(x0 - 24.0, y + 5.0), str(row[2]), 12, COL_DIM)
		for k in range(10):
			var col: Color = COL_BLUE if k < blue_n else COL_RED
			c.draw_circle(Vector2(x0 + spacing * float(k), y), r, col)
		_label(c, Vector2(x0 + spacing * 10.0 + 4.0, y + 5.0), str(row[1]) + " blue", 13, COL_TEXT)
		if i < rows.size() - 1:
			_draw_arrow(c, Vector2(x0 + spacing * 4.5, y + r + 6.0), Vector2(x0 + spacing * 4.5, y + 62.0 - r - 6.0), Color(1, 1, 1, 0.3))
	var nx: float = x0 + spacing * 10.0 + 110.0
	if nx < c.size.x - 160.0:
		_label(c, Vector2(nx, 36.0), "Nobody is favoured.", 13, COL_TEXT)
		_label(c, Vector2(nx, 56.0), "Each generation is just", 13, COL_DIM)
		_label(c, Vector2(nx, 74.0), "a random sample of the", 13, COL_DIM)
		_label(c, Vector2(nx, 92.0), "one before — and samples", 13, COL_DIM)
		_label(c, Vector2(nx, 110.0), "miss the true mix a little", 13, COL_DIM)
		_label(c, Vector2(nx, 128.0), "every single time.", 13, COL_DIM)

func _fig_no_return(c: Control) -> void:
	var left: float = 46.0
	var rect := Rect2(left, 22.0, c.size.x - left - 14.0, c.size.y - 52.0)
	var all_walks: Array = _walks("lost_pool", 10, 60, 8, 991)
	var chosen: Array = all_walks[0]
	for s in all_walks:
		var series: Array = s
		if float(series[series.size() - 1]) <= 0.001:
			chosen = series
			break
	_draw_plot(c, rect, [chosen])
	_plot_axis_labels(c, rect)
	# Find where it hit zero
	var hit: int = chosen.size() - 1
	for i in range(chosen.size()):
		if float(chosen[i]) <= 0.001:
			hit = i
			break
	var hx: float = rect.position.x + rect.size.x * float(hit) / float(chosen.size() - 1)
	c.draw_circle(Vector2(hx, rect.end.y - 1.0), 5.0, COL_RED)
	_label(c, Vector2(min(hx + 10.0, rect.end.x - 200.0), rect.end.y - 12.0), "lost — stays at 0% forever", 12, COL_RED)
	_label(c, Vector2(rect.position.x, 16.0), "one allele, one population", 12, COL_DIM)
	_label(c, Vector2(rect.position.x, c.size.y - 8.0), "generations  →", 12, COL_DIM)

func _fig_fixation_prob(c: Control) -> void:
	var left: float = 150.0
	var bar_w: float = c.size.x - left - 20.0
	var bar_h: float = 34.0
	var fr: Array = [8.0 / 12.0, 2.0 / 12.0, 2.0 / 12.0]
	var cols: Array = [COL_BLUE, COL_RED, COL_GREEN]
	var labels_a: Array = ["8 of 12", "2", "2"]
	var labels_b: Array = ["67%", "17%", "17%"]
	var rows: Array = [["STARTING SHARE", labels_a], ["CHANCE OF TAKING OVER", labels_b]]
	for i in range(2):
		var y: float = 30.0 + float(i) * 66.0
		var row: Array = rows[i]
		_label_right(c, Vector2(left - 14.0, y + bar_h * 0.5 + 5.0), str(row[0]), 12, COL_DIM)
		var x: float = left
		var labs: Array = row[1]
		for k in range(3):
			var w: float = bar_w * float(fr[k])
			c.draw_rect(Rect2(x, y, w, bar_h), cols[k], true)
			_label_center(c, Vector2(x + w * 0.5, y + bar_h * 0.5 + 5.0), str(labs[k]), 13, Color(0.05, 0.05, 0.06))
			x += w
	_label_center(c, Vector2(left + bar_w * 0.5, 30.0 + 66.0 + bar_h + 22.0), "the two bars are the same — that is the whole rule", 12, COL_TEXT)

func _fig_popsize(c: Control) -> void:
	var gap: float = 34.0
	var left: float = 34.0
	var half: float = (c.size.x - gap) * 0.5
	var top: float = 34.0
	var h: float = c.size.y - top - 26.0
	var r1 := Rect2(left, top, half - left, h)
	var r2 := Rect2(half + gap + left, top, half - left, h)
	_draw_plot(c, r1, _walks("small", 8, 70, 4, 777))
	_draw_plot(c, r2, _walks("large", 200, 70, 4, 777))
	_label_center(c, Vector2(r1.position.x + r1.size.x * 0.5, 20.0), "small population  (N = 8)", 13, COL_TEXT)
	_label_center(c, Vector2(r2.position.x + r2.size.x * 0.5, 20.0), "large population  (N = 200)", 13, COL_TEXT)
	_plot_axis_labels(c, r1)
	_plot_axis_labels(c, r2)

func _fig_drift_vs_selection(c: Control) -> void:
	var gap: float = 34.0
	var left: float = 34.0
	var half: float = (c.size.x - gap) * 0.5
	var top: float = 34.0
	var h: float = c.size.y - top - 26.0
	var r1 := Rect2(left, top, half - left, h)
	var r2 := Rect2(half + gap + left, top, half - left, h)
	_draw_plot(c, r1, _walks("dvs_drift", 20, 60, 5, 5150))
	_draw_plot(c, r2, _walks("dvs_sel", 20, 60, 5, 5150, 1.45), COL_RED)
	_label_center(c, Vector2(r1.position.x + r1.size.x * 0.5, 20.0), "DRIFT — no advantage", 13, COL_TEXT)
	_label_center(c, Vector2(r2.position.x + r2.size.x * 0.5, 20.0), "SELECTION — red survives better", 13, COL_TEXT)
	_plot_axis_labels(c, r1)
	_plot_axis_labels(c, r2)
	_label(c, Vector2(r1.position.x + 6.0, r1.end.y - 8.0), "wanders, any ending", 11, COL_DIM)
	_label(c, Vector2(r2.position.x + 6.0, r2.end.y - 8.0), "climbs, same ending every time", 11, COL_DIM)

func _fig_parallel(c: Control) -> void:
	var cell: float = 46.0
	var gap: float = 6.0
	var grid_w: float = cell * 3.0 + gap * 2.0
	var top: float = 30.0
	var lx: float = 40.0
	var rx: float = c.size.x - 40.0 - grid_w
	var start_dots: Array = [COL_RED, COL_GREEN, COL_BLUE, COL_BLUE, COL_RED, COL_GREEN]
	var winners: Array = [COL_BLUE, COL_RED, COL_BLUE, COL_GREEN, COL_BLUE, COL_RED, COL_RED, COL_BLUE, COL_GREEN]
	for i in range(9):
		var cx: int = i % 3
		var cy: int = int(floor(float(i) / 3.0))
		var lr := Rect2(lx + cx * (cell + gap), top + cy * (cell + gap), cell, cell)
		_draw_cluster(c, lr, start_dots, 3)
		var rr := Rect2(rx + cx * (cell + gap), top + cy * (cell + gap), cell, cell)
		var wcol: Color = winners[i]
		c.draw_rect(rr, Color(wcol.r, wcol.g, wcol.b, 0.85), true)
		c.draw_rect(rr, Color(1, 1, 1, 0.15), false, 1.0)
	_label_center(c, Vector2(lx + grid_w * 0.5, top + grid_w + 20.0), "start: nine identical worlds", 12, COL_DIM)
	_label_center(c, Vector2(rx + grid_w * 0.5, top + grid_w + 20.0), "end: nine different answers", 12, COL_DIM)
	var mid_y: float = top + grid_w * 0.5
	_draw_arrow(c, Vector2(lx + grid_w + 30.0, mid_y), Vector2(rx - 30.0, mid_y), Color(1, 1, 1, 0.3))
	_label_center(c, Vector2((lx + grid_w + rx) * 0.5, mid_y - 12.0), "same rules, same time", 12, COL_DIM)
	_label_center(c, Vector2((lx + grid_w + rx) * 0.5, mid_y + 22.0), "4 blue · 3 red · 2 green", 12, COL_TEXT)

func _fig_gene_flow(c: Control) -> void:
	var left: float = 46.0
	var rect := Rect2(left, 26.0, c.size.x - left - 14.0, c.size.y - 58.0)
	# Gate eras as fractions of the run: closed, open, closed, open
	var eras: Array = [[0.0, 0.46, false], [0.46, 0.60, true], [0.60, 0.86, false], [0.86, 1.0, true]]
	c.draw_rect(rect, COL_PLOT_BG, true)
	for e in eras:
		var era: Array = e
		var x0: float = rect.position.x + rect.size.x * float(era[0])
		var x1: float = rect.position.x + rect.size.x * float(era[1])
		var open: bool = bool(era[2])
		var col: Color = Color(COL_GREEN.r, COL_GREEN.g, COL_GREEN.b, 0.16) if open else Color(1, 1, 1, 0.04)
		c.draw_rect(Rect2(x0, rect.position.y, x1 - x0, rect.size.y), col, true)
		_label_center(c, Vector2((x0 + x1) * 0.5, rect.position.y - 6.0), "GATE OPEN" if open else "GATE CLOSED", 11, COL_GREEN if open else COL_DIM)
	# Divergence curve: rises while closed, collapses while open
	var pts := PackedVector2Array()
	var n: int = 120
	var d: float = 0.0
	for i in range(n + 1):
		var t: float = float(i) / float(n)
		var open_now: bool = false
		for e in eras:
			var era: Array = e
			if t >= float(era[0]) and t <= float(era[1]):
				open_now = bool(era[2])
		if open_now:
			d = d * 0.82
		else:
			d = d + (0.70 - d) * 0.045
		pts.append(Vector2(rect.position.x + rect.size.x * t, rect.end.y - rect.size.y * d))
	c.draw_polyline(pts, COL_AMBER, 2.5, true)
	c.draw_rect(rect, Color(1, 1, 1, 0.12), false, 1.0)
	_label_right(c, Vector2(rect.position.x - 6.0, rect.position.y + 5.0), "very", 11, COL_DIM)
	_label_right(c, Vector2(rect.position.x - 6.0, rect.position.y + 17.0), "different", 11, COL_DIM)
	_label_right(c, Vector2(rect.position.x - 6.0, rect.end.y + 4.0), "identical", 11, COL_DIM)
	_label(c, Vector2(rect.position.x, c.size.y - 8.0), "how different the two pens are   →  time", 12, COL_DIM)

func _fig_bottleneck_founder(c: Control) -> void:
	var mixed: Array = [COL_RED, COL_GREEN, COL_BLUE, COL_RED, COL_BLUE, COL_GREEN, COL_BLUE, COL_RED, COL_GREEN, COL_BLUE]
	var survivors: Array = [COL_BLUE, COL_RED, COL_BLUE]
	var recovered: Array = [COL_BLUE, COL_RED, COL_BLUE, COL_BLUE, COL_RED, COL_BLUE, COL_BLUE, COL_RED, COL_BLUE, COL_BLUE]
	var w: float = c.size.x
	var box_w: float = 150.0
	var box_h: float = 78.0
	var small_w: float = 76.0

	var y1: float = 42.0
	_label(c, Vector2(4.0, 22.0), "BOTTLENECK", 13, Color(0.95, 0.62, 0.62))
	var b1 := Rect2(4.0, y1, box_w, box_h)
	_draw_cluster(c, b1, mixed, 5)
	_label_center(c, Vector2(b1.position.x + box_w * 0.5, b1.end.y + 16.0), "the population", 12, COL_DIM)
	var neck_x: float = b1.end.x + 26.0
	var mid1: float = y1 + box_h * 0.5
	var neck_col := Color(0.95, 0.62, 0.62, 0.55)
	c.draw_colored_polygon(PackedVector2Array([Vector2(neck_x, y1 - 2.0), Vector2(neck_x + 44.0, mid1 - 9.0), Vector2(neck_x + 44.0, mid1 - 4.0), Vector2(neck_x, y1 + 14.0)]), neck_col)
	c.draw_colored_polygon(PackedVector2Array([Vector2(neck_x, y1 + box_h + 2.0), Vector2(neck_x + 44.0, mid1 + 9.0), Vector2(neck_x + 44.0, mid1 + 4.0), Vector2(neck_x, y1 + box_h - 14.0)]), neck_col)
	_label_center(c, Vector2(neck_x + 22.0, y1 - 8.0), "crash", 11, COL_DIM)
	var b2 := Rect2(neck_x + 56.0, y1 + 12.0, small_w, box_h - 24.0)
	_draw_cluster(c, b2, survivors, 3)
	_label_center(c, Vector2(b2.position.x + small_w * 0.5, b2.end.y + 16.0), "survivors", 12, COL_DIM)
	var arrow_x: float = b2.end.x + 12.0
	_draw_arrow(c, Vector2(arrow_x, mid1), Vector2(arrow_x + 40.0, mid1), Color(1, 1, 1, 0.35))
	_label_center(c, Vector2(arrow_x + 20.0, mid1 - 12.0), "breed back", 11, COL_DIM)
	var b3 := Rect2(arrow_x + 52.0, y1, box_w, box_h)
	if b3.end.x < w:
		_draw_cluster(c, b3, recovered, 5)
		_label_center(c, Vector2(b3.position.x + box_w * 0.5, b3.end.y + 16.0), "green is gone for good", 12, Color(0.95, 0.62, 0.62))

	var dy: float = 168.0
	c.draw_line(Vector2(4.0, dy), Vector2(w - 4.0, dy), Color(1, 1, 1, 0.10), 1.0)

	var y2: float = dy + 32.0
	_label(c, Vector2(4.0, dy + 22.0), "FOUNDER EFFECT", 13, Color(0.62, 0.85, 0.95))
	var f1 := Rect2(4.0, y2, box_w, box_h)
	_draw_cluster(c, f1, mixed, 5)
	_label_center(c, Vector2(f1.position.x + box_w * 0.5, f1.end.y + 16.0), "mainland — unchanged", 12, COL_DIM)
	var mid2: float = y2 + box_h * 0.5
	var fa_x: float = f1.end.x + 14.0
	_draw_arrow(c, Vector2(fa_x, mid2), Vector2(fa_x + 66.0, mid2), Color(0.62, 0.85, 0.95, 0.7))
	_label_center(c, Vector2(fa_x + 33.0, mid2 - 12.0), "a few leave", 11, COL_DIM)
	var f2 := Rect2(fa_x + 80.0, y2 + 12.0, small_w, box_h - 24.0)
	_draw_cluster(c, f2, survivors, 3)
	_label_center(c, Vector2(f2.position.x + small_w * 0.5, f2.end.y + 16.0), "island", 12, COL_DIM)
	var fa2_x: float = f2.end.x + 12.0
	_draw_arrow(c, Vector2(fa2_x, mid2), Vector2(fa2_x + 40.0, mid2), Color(1, 1, 1, 0.35))
	_label_center(c, Vector2(fa2_x + 20.0, mid2 - 12.0), "grow", 11, COL_DIM)
	var f3 := Rect2(fa2_x + 52.0, y2, box_w, box_h)
	if f3.end.x < w:
		_draw_cluster(c, f3, recovered, 5)
		_label_center(c, Vector2(f3.position.x + box_w * 0.5, f3.end.y + 16.0), "new population, no green", 12, Color(0.62, 0.85, 0.95))

func _fig_recovery(c: Control) -> void:
	var left: float = 46.0
	var rect := Rect2(left, 26.0, c.size.x - left - 150.0, c.size.y - 58.0)
	c.draw_rect(rect, COL_PLOT_BG, true)
	for f in [0.0, 0.5, 1.0]:
		var y: float = rect.position.y + rect.size.y * (1.0 - float(f))
		c.draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), COL_GRID, 1.0)
	var n: int = 100
	var pop_pts := PackedVector2Array()
	var div_pts := PackedVector2Array()
	for i in range(n + 1):
		var t: float = float(i) / float(n)
		var pop_v: float = 1.0
		var div_v: float = 1.0
		if t >= 0.30:
			var u: float = (t - 0.30) / 0.35
			pop_v = clamp(0.18 + 0.82 * min(u, 1.0), 0.0, 1.0)
			div_v = 0.60
		pop_pts.append(Vector2(rect.position.x + rect.size.x * t, rect.end.y - rect.size.y * pop_v))
		div_pts.append(Vector2(rect.position.x + rect.size.x * t, rect.end.y - rect.size.y * div_v))
	c.draw_polyline(pop_pts, COL_TEXT, 2.5, true)
	c.draw_polyline(div_pts, COL_AMBER, 2.5, true)
	c.draw_rect(rect, Color(1, 1, 1, 0.12), false, 1.0)
	var cx: float = rect.position.x + rect.size.x * 0.30
	c.draw_line(Vector2(cx, rect.position.y), Vector2(cx, rect.end.y), Color(COL_RED.r, COL_RED.g, COL_RED.b, 0.6), 1.5)
	_label_center(c, Vector2(cx, rect.position.y - 6.0), "crash", 11, COL_RED)
	_label_right(c, Vector2(rect.position.x - 6.0, rect.position.y + 5.0), "100%", 11, COL_DIM)
	_label_right(c, Vector2(rect.position.x - 6.0, rect.end.y + 4.0), "0%", 11, COL_DIM)
	var lx: float = rect.end.x + 14.0
	c.draw_line(Vector2(lx, rect.position.y + 20.0), Vector2(lx + 22.0, rect.position.y + 20.0), COL_TEXT, 2.5)
	_label(c, Vector2(lx + 28.0, rect.position.y + 25.0), "population size", 12, COL_TEXT)
	c.draw_line(Vector2(lx, rect.position.y + 46.0), Vector2(lx + 22.0, rect.position.y + 46.0), COL_AMBER, 2.5)
	_label(c, Vector2(lx + 28.0, rect.position.y + 51.0), "genetic diversity", 12, COL_AMBER)
	_label(c, Vector2(lx, rect.position.y + 80.0), "numbers come back,", 12, COL_DIM)
	_label(c, Vector2(lx, rect.position.y + 96.0), "diversity does not", 12, COL_DIM)
	_label(c, Vector2(rect.position.x, c.size.y - 8.0), "time  →", 12, COL_DIM)

# ===========================================================================
#  FIGURES — LAB
# ===========================================================================
func _fig_traits(c: Control) -> void:
	var label_x: float = 4.0
	var start_x: float = 112.0
	var spacing: float = 108.0
	var r: float = 26.0
	var neutral := Color(0.62, 0.66, 0.78)
	var y1: float = 42.0
	_label(c, Vector2(label_x, y1 + 5.0), "COLOR", 13, COL_DIM)
	var cols: Array = [COL_RED, COL_GREEN, COL_BLUE]
	var names: Array = ["Red", "Green", "Blue"]
	for i in range(3):
		var x: float = start_x + spacing * float(i)
		_draw_blob(c, Vector2(x, y1), r, cols[i], 0, 1)
		_label_center(c, Vector2(x, y1 + r + 18.0), str(names[i]), 12, COL_DIM)
	var y2: float = 132.0
	_label(c, Vector2(label_x, y2 + 5.0), "SHAPE", 13, COL_DIM)
	var shape_names: Array = ["Round", "Star", "Flower"]
	for i in range(3):
		var x2: float = start_x + spacing * float(i)
		_draw_blob(c, Vector2(x2, y2), r, neutral, i, 1)
		_label_center(c, Vector2(x2, y2 + r + 18.0), str(shape_names[i]), 12, COL_DIM)
	var y3: float = 214.0
	_label(c, Vector2(label_x, y3 + 5.0), "EYES", 13, COL_DIM)
	_draw_blob(c, Vector2(start_x, y3), r, neutral, 0, 1)
	_label_center(c, Vector2(start_x, y3 + r + 6.0), "One eye", 12, COL_DIM)
	_draw_blob(c, Vector2(start_x + spacing, y3), r, neutral, 0, 3)
	_label_center(c, Vector2(start_x + spacing, y3 + r + 6.0), "Three eyes", 12, COL_DIM)
	var nx: float = start_x + spacing * 3.0 + 20.0
	if nx < c.size.x - 200.0:
		_label(c, Vector2(nx, y1 - 4.0), "3 colors", 13, COL_TEXT)
		_label(c, Vector2(nx, y1 + 16.0), "x 3 shapes", 13, COL_TEXT)
		_label(c, Vector2(nx, y1 + 36.0), "x 2 eye counts", 13, COL_TEXT)
		c.draw_line(Vector2(nx, y1 + 48.0), Vector2(nx + 120.0, y1 + 48.0), Color(1, 1, 1, 0.25), 1.0)
		_label(c, Vector2(nx, y1 + 68.0), "= 18 kinds of blob", 13, COL_TEXT)
		_label(c, Vector2(nx, y1 + 92.0), "all equally likely", 12, COL_DIM)
		_label(c, Vector2(nx, y1 + 110.0), "to survive and breed", 12, COL_DIM)

func _fig_inheritance(c: Control) -> void:
	var cx: float = c.size.x * 0.5
	var r: float = 26.0
	var pa := Vector2(cx - 150.0, 52.0)
	var pb := Vector2(cx + 150.0, 52.0)
	_draw_blob(c, pa, r, COL_BLUE, 0, 1)
	_draw_blob(c, pb, r, COL_RED, 0, 1)
	_label_center(c, Vector2(pa.x, pa.y - r - 12.0), "parent", 12, COL_DIM)
	_label_center(c, Vector2(pb.x, pb.y - r - 12.0), "parent", 12, COL_DIM)
	var meet := Vector2(cx, 108.0)
	_draw_arrow(c, pa + Vector2(24.0, 22.0), meet - Vector2(14.0, 8.0), Color(1, 1, 1, 0.35))
	_draw_arrow(c, pb - Vector2(24.0, -22.0), meet + Vector2(14.0, -8.0), Color(1, 1, 1, 0.35))
	_label_center(c, Vector2(cx, meet.y + 4.0), "50 / 50", 15, COL_TEXT)
	var ca := Vector2(cx - 78.0, 168.0)
	var cb := Vector2(cx + 78.0, 168.0)
	_draw_arrow(c, meet + Vector2(-18.0, 12.0), ca - Vector2(0.0, r + 6.0), Color(1, 1, 1, 0.25))
	_draw_arrow(c, meet + Vector2(18.0, 12.0), cb - Vector2(0.0, r + 6.0), Color(1, 1, 1, 0.25))
	_draw_blob(c, ca, r * 0.78, COL_BLUE, 0, 1)
	_draw_blob(c, cb, r * 0.78, COL_RED, 0, 1)
	_label_center(c, Vector2(ca.x, ca.y + r + 16.0), "50%", 12, COL_DIM)
	_label_center(c, Vector2(cb.x, cb.y + r + 16.0), "50%", 12, COL_DIM)
	_label(c, Vector2(6.0, 20.0), "one offspring, one trait", 12, COL_DIM)

func _fig_tracker(c: Control) -> void:
	var w: float = c.size.x
	var lw: float = w * 0.56 - 12.0
	var lp := Rect2(6.0, 6.0, lw, c.size.y - 12.0)
	var rp := Rect2(lp.end.x + 14.0, 6.0, w - lp.end.x - 20.0, c.size.y - 12.0)
	_draw_box(c, lp)
	_draw_box(c, rp)
	_label(c, Vector2(lp.position.x + 12.0, lp.position.y + 22.0), "ALLELE TRACKER — COLOR", 12, COL_DIM)
	var rows: Array = [["Red", 0.42, COL_RED, true], ["Green", 0.33, COL_GREEN, false], ["Blue", 0.25, COL_BLUE, false]]
	var bar_x: float = lp.position.x + 70.0
	var bar_w: float = lp.size.x - 70.0 - 60.0
	for i in range(rows.size()):
		var row: Array = rows[i]
		var y: float = lp.position.y + 48.0 + float(i) * 36.0
		var lead: bool = bool(row[3])
		_label(c, Vector2(lp.position.x + 12.0, y + 5.0), str(row[0]), 13, COL_TEXT if lead else COL_DIM)
		c.draw_rect(Rect2(bar_x, y - 9.0, bar_w, 18.0), Color(1, 1, 1, 0.06), true)
		var col: Color = row[2]
		c.draw_rect(Rect2(bar_x, y - 9.0, bar_w * float(row[1]), 18.0), col, true)
		if lead:
			c.draw_rect(Rect2(bar_x - 2.0, y - 11.0, bar_w + 4.0, 22.0), COL_AMBER, false, 1.5)
		_label(c, Vector2(bar_x + bar_w + 10.0, y + 5.0), "%d%%" % int(round(float(row[1]) * 100.0)), 13, COL_TEXT if lead else COL_DIM)
	_label(c, Vector2(rp.position.x + 12.0, rp.position.y + 22.0), "LAST EVENT", 12, COL_DIM)
	var deltas: Array = [["Red", "+9", true], ["Green", "−4", false], ["Blue", "−5", false]]
	for i in range(deltas.size()):
		var d: Array = deltas[i]
		var y: float = rp.position.y + 48.0 + float(i) * 36.0
		var up: bool = bool(d[2])
		_label(c, Vector2(rp.position.x + 12.0, y + 5.0), str(d[0]), 13, COL_TEXT)
		_label_right(c, Vector2(rp.end.x - 14.0, y + 5.0), str(d[1]) + ("  ▲" if up else "  ▼"), 13, COL_GREEN if up else COL_RED)

# ===========================================================================
#  FIGURES — SCENARIOS
# ===========================================================================
func _fig_three_color(c: Control) -> void:
	var left: float = 46.0
	var rect := Rect2(left, 22.0, c.size.x - left - 14.0, c.size.y - 52.0)
	_draw_stacked(c, rect, _three_walk("coin", 12, 70, 31337))
	_plot_axis_labels(c, rect)
	_label(c, Vector2(rect.position.x, 16.0), "share of each color, stacked", 12, COL_DIM)
	_label(c, Vector2(rect.position.x, c.size.y - 8.0), "time  →     (starts 4 · 4 · 4, ends with one color at 100%)", 12, COL_DIM)

func _fig_moran(c: Control) -> void:
	var order: Array = [COL_RED, COL_GREEN, COL_BLUE, COL_RED, COL_GREEN, COL_BLUE, COL_RED, COL_GREEN, COL_BLUE, COL_RED, COL_GREEN, COL_BLUE]
	var dead: int = 4
	var parent: int = 2
	var r: float = 13.0
	var spacing: float = 36.0
	var x0: float = 90.0
	var y1: float = 48.0
	var y2: float = 134.0
	_label_right(c, Vector2(x0 - 24.0, y1 + 5.0), "before", 12, COL_DIM)
	_label_right(c, Vector2(x0 - 24.0, y2 + 5.0), "after", 12, COL_DIM)
	for i in range(12):
		var p := Vector2(x0 + spacing * float(i), y1)
		_draw_blob(c, p, r, order[i], 0, 1)
		if i == dead:
			_draw_x(c, p, r + 4.0, Color(1, 1, 1, 0.9))
		var q := Vector2(x0 + spacing * float(i), y2)
		var col: Color = order[i]
		if i == dead:
			col = order[parent]
		_draw_blob(c, q, r, col, 0, 1)
	var parent_p := Vector2(x0 + spacing * float(parent), y1)
	var slot := Vector2(x0 + spacing * float(dead), y2)
	_draw_arrow(c, parent_p + Vector2(10.0, r + 4.0), slot + Vector2(-8.0, -r - 6.0), COL_AMBER)
	c.draw_rect(Rect2(slot.x - r - 4.0, slot.y - r - 4.0, (r + 4.0) * 2.0, (r + 4.0) * 2.0), COL_AMBER, false, 1.5)
	var tx: float = x0 + spacing * 12.0 + 10.0
	_label(c, Vector2(tx, y1 + 5.0), "4 · 4 · 4", 13, COL_TEXT)
	_label(c, Vector2(tx, y2 + 5.0), "4 · 3 · 5", 13, COL_TEXT)
	_label_center(c, Vector2(x0 + spacing * 5.5, y1 + y2 * 0.5 - 12.0), "one random death  →  one random birth fills the gap", 12, COL_DIM)
	_label_center(c, Vector2(x0 + spacing * 5.5, c.size.y - 6.0), "12 blobs before, 12 after — only the mix moved", 12, COL_DIM)

func _fig_disaster(c: Control) -> void:
	var pen := Rect2(30.0, 18.0, c.size.x - 60.0, c.size.y - 36.0)
	_draw_box(c, pen)
	var offsets: Array = [Vector2(0, 0), Vector2(22, -14), Vector2(-20, 16), Vector2(18, 20), Vector2(-24, -12), Vector2(6, -30), Vector2(-4, 30)]
	var families: Array = [
		[Vector2(0.22, 0.42), COL_RED],
		[Vector2(0.55, 0.70), COL_GREEN],
		[Vector2(0.78, 0.30), COL_BLUE],
	]
	for f in families:
		var fam: Array = f
		var cen: Vector2 = pen.position + Vector2(pen.size.x * float(fam[0].x), pen.size.y * float(fam[0].y))
		for o in offsets:
			var off: Vector2 = o
			c.draw_circle(cen + off, 8.0, fam[1])
	var zc: Vector2 = pen.position + Vector2(pen.size.x * 0.22, pen.size.y * 0.42)
	c.draw_circle(zc, 58.0, Color(1.0, 0.45, 0.35, 0.18))
	c.draw_arc(zc, 58.0, 0.0, TAU, 48, Color(1.0, 0.45, 0.35, 0.9), 2.0, true)
	_label_center(c, Vector2(zc.x, zc.y - 66.0), "aimed zone", 12, Color(1.0, 0.55, 0.45))
	var tx: float = pen.position.x + pen.size.x * 0.40
	_label(c, Vector2(tx, pen.position.y + 30.0), "blobs are born next to their parents,", 12, COL_DIM)
	_label(c, Vector2(tx, pen.position.y + 48.0), "so colors clump by accident", 12, COL_DIM)
	_label(c, Vector2(tx, pen.position.y + 76.0), "the zone doesn't know what red is —", 12, COL_TEXT)
	_label(c, Vector2(tx, pen.position.y + 94.0), "but it lands where red happens to live", 12, COL_TEXT)

# ===========================================================================
#  ENTRIES — WHAT IS GENETIC DRIFT?
# ===========================================================================
func _e_basic() -> Array:
	return [
		T(_h("The basic idea") + """

A population carries different versions of a trait, called [b][color=#6db3ff][url=https://en.wikipedia.org/wiki/Allele]alleles[/url][/color][/b]. [b][color=#6db3ff][url=https://en.wikipedia.org/wiki/Genetic_drift]Genetic drift[/url][/color][/b] is when the share of each allele changes over time [b]by chance alone[/b] — not because any version is better.

Think of drawing marbles from a bag and refilling it with what you drew. Nothing is special, yet the mix wanders. Eventually one version hits 100% ([b]fixed[/b]) or 0% ([b]lost[/b])."""),
		F(_fig_drift, 210, "Six populations, all starting 50/50, with nothing acting on them but chance. Green lines drifted to fixation, red to loss, grey are still wandering."),
		T("""Three things to hold onto:

•  Drift is [b]random[/b] — no direction, no goal.
•  Drift is [b]stronger in small populations[/b].
•  Drift is [b]not selection[/b] — only selection cares whether an allele is useful.

In this lab every trait is cosmetic and every blob lives equally long. So everything you see is drift, and only drift."""),
		C("IN ONE SENTENCE", "Genetic drift is the random wandering of allele frequencies that happens in every finite population, because each generation is a random sample of the last.", COL_BLUE),
	]

func _e_why() -> Array:
	return [
		T(_h("Why it happens") + """

Drift is not a force. It comes from one boring fact: [b]a sample is never a perfect copy of what it was drawn from.[/b]

Ten blobs, half blue and half red, make ten babies. Which parents bump into each other is random, so 6 blue and 4 red is as likely as 5 and 5. The next generation samples [i]that[/i] 60/40 — drift has no memory of the original split."""),
		F(_fig_sampling, 200, "Every generation is a random sample of the one before. Nothing is favoured, yet the mix moves, because random samples miss the true proportions a little every time."),
		T("""Biologists call this [b]sampling error[/b]. In the lab it enters in three places:

•  [b]Who meets whom[/b] — blobs wander randomly.
•  [b]Which trait the baby gets[/b] — a fair coin flip per trait.
•  [b]Who's an adult when[/b] — birth timing is random.

None of these look at colour. That's why it's drift, not selection."""),
	]

func _e_fixation() -> Array:
	return [
		T(_h("Fixation and loss") + """

Drift keeps wandering, and 0% and 100% are walls. So every allele eventually ends at one: [b]fixed[/b] (100%) or [b]lost[/b] (0%).

Both are one-way doors. A lost colour has no parent left to inherit it from. Only [b]mutation[/b] or [b]migration[/b] can bring it back — and this lab has neither unless you open a gate."""),
		F(_fig_no_return, 190, "One allele wandering until it touches 0%. After that the line is flat forever."),
		T("""The clean rule: under pure drift, [b]an allele's chance of fixing equals its current frequency.[/b] 67% share → 67% chance. 17% share → 17% chance. Rare is a disadvantage, not a verdict."""),
		F(_fig_fixation_prob, 160, "Starting share on top, chance of taking over underneath — the same bar. The Long Shot preset tests this by running over and over."),
		C("WHY THE RULE IS TRUE", "Eventually one blob's lineage becomes everyone's ancestor. Drift is blind, so every blob has an equal shot at being that ancestor — so the chance the winner is blue is just the fraction of blobs that are blue now.", COL_BLUE),
	]

func _e_popsize() -> Array:
	return [
		T(_h("Population size") + """

Drift is [b]strongest in small populations[/b], where a few lucky or unlucky events swing the percentages hard. In large populations the numbers barely move.

Same sampling logic: flip 8 coins and 6 heads is common; flip 200 and 150 heads never happens. A big population is a big sample, and big samples are faithful."""),
		F(_fig_popsize, 210, "Same number of generations in both panels. The small population lurches and hits an edge fast; the large one barely leaves the middle."),
		T("""Two consequences:

•  [b]Small populations fix fast.[/b] Time to fixation grows roughly with population size.
•  [b]Small populations lose diversity fast.[/b] Every fixation removes the other versions for good.

This is why conservation biologists worry about tiny populations even when the animals look healthy."""),
		C("A DETAIL WORTH KNOWING", "What matters is the [b]effective[/b] population size — roughly, how many are actually breeding. A herd of 1,000 where 20 breed drifts like a population of 20. In the lab, only adults breed.", COL_BLUE),
	]

func _e_not_selection() -> Array:
	return [
		T(_h("Drift is not selection") + """

Both change allele frequencies. Both can fix an allele. That's where the resemblance ends.

[b]Selection[/b] has a direction: the helpful version climbs, run after run. [b]Drift[/b] has none: the same start can end red, green, or blue, and nothing tells you which."""),
		F(_fig_drift_vs_selection, 210, "Left: pure drift, five runs, five different endings. Right: red gets a survival edge — five runs, five near-identical climbs. Direction is the fingerprint of selection."),
		T("""The test: [b]run it again.[/b] One run of drift can look exactly like selection. Ten runs can't — if the same colour wins every time, something is favouring it.

In real populations both act at once. In small populations drift's noise can drown out weak selection; in large ones even tiny advantages win eventually."""),
		C("WHY THE LAB BANS SELECTION", "Every trait is cosmetic and every lifespan is identical, so there's no signal — only noise. The one exception is Drift vs Selection, which switches an advantage on in one pen so you can see the difference.", COL_AMBER),
	]

func _e_diverge() -> Array:
	return [
		T(_h("Isolated populations diverge") + """

Start two populations from the same mix, wall them off, let drift run. They will not stay the same. Each wanders its own random path and, given time, fixes on a different allele.

Neither adapted to anything. They drifted apart the way two people flipping coins in separate rooms get different sequences."""),
		F(_fig_parallel, 230, "Nine populations, identical at the start, identical rules. By the end some are blue, some red, some green."),
		T("""This is a big reason island, cave, and mountain populations differ from their mainland relatives even in similar habitats. Some of it is adaptation. A lot is just drift in isolation.

It also means one population's ending tells you nothing about what "should" happen. Only the pattern across many does."""),
	]

func _e_geneflow() -> Array:
	return [
		T(_h("Gene flow pulls them back") + """

[b]Gene flow[/b] is alleles moving between populations — migration followed by breeding. It works against drift.

Two sealed populations drift apart. Open a door and even a trickle of migrants drags their frequencies back together. A colour that went extinct in one group can return, carried in by a migrant."""),
		F(_fig_gene_flow, 210, "How different two neighbouring populations are over time. Gate shut: they drift apart. Gate open: a few crossings snap them back."),
		T("""How much flow it takes is a classic result: [b]remarkably little.[/b] About one migrant per generation stops two populations fixing on different alleles. That's why barriers — mountains, rivers, oceans — matter so much for populations splitting.

In the lab, your population is whichever pen you're standing in. Cross the gate and you breed with the other side."""),
	]

func _e_bottleneck_theory() -> Array:
	return [
		T(_h("Bottlenecks and founders") + """

Two kinds of event make a population suddenly small, and both are famous for what they do to diversity.

A [b]bottleneck[/b] is a crash: most die at random, a few survive. A [b]founder effect[/b] is a split: a handful leave and start a new population elsewhere, while the original carries on.

Either way the small group is a [b]random sample[/b] of the big one, and a small sample can't carry everything."""),
		F(_fig_bottleneck_founder, 285, "Both routes end with a small, less diverse group — but only the bottleneck destroys the original population."),
		T("""The part people miss: [b]recovery doesn't fix it.[/b] Numbers can bounce all the way back. But every new individual descends from the same few survivors, so whatever they lacked is gone for good."""),
		F(_fig_recovery, 190, "Population size recovers fully (white). The number of alleles still present (amber) drops at the crash and never returns."),
	]

func _e_real_world() -> Array:
	return [
		T(_h("Drift in the real world") + """

Every effect in the lab has a real counterpart.

[b]Northern elephant seals[/b] were hunted to a few dozen in the 1800s. They're back to over 100,000 — but with some of the lowest genetic diversity of any mammal. A textbook bottleneck.

[b]Cheetahs[/b] are so uniform that skin grafts between unrelated animals are rarely rejected — the mark of ancient bottlenecks.

[b]The Amish of Pennsylvania[/b] descend from a few founding families. A rare form of dwarfism, almost unheard of elsewhere, is common among them because one founding couple happened to carry it. Founder effect, in people.

[b]Island populations[/b] of lizards, birds, and plants routinely differ wildly from mainland relatives for no adaptive reason. A few colonists, then drift alone."""),
		C("WHY IT MATTERS", "Small, isolated populations quietly discard variation every generation. Keeping populations large and connected is, in large part, keeping drift in check.", COL_GREEN),
		T("""[b]Learn more[/b]
•  [color=#6db3ff][url=https://en.wikipedia.org/wiki/Genetic_drift]Genetic drift[/url][/color]
•  [color=#6db3ff][url=https://en.wikipedia.org/wiki/Fixation_(population_genetics)]Fixation and loss[/url][/color]
•  [color=#6db3ff][url=https://en.wikipedia.org/wiki/Effective_population_size]Effective population size[/url][/color]
•  [color=#6db3ff][url=https://en.wikipedia.org/wiki/Gene_flow]Gene flow[/url][/color]
•  [color=#6db3ff][url=https://en.wikipedia.org/wiki/Population_bottleneck]Population bottleneck[/url][/color]
•  [color=#6db3ff][url=https://en.wikipedia.org/wiki/Founder_effect]Founder effect[/url][/color]
•  [color=#6db3ff][url=https://en.wikipedia.org/wiki/Moran_process]The Moran model[/url][/color]"""),
	]

# ===========================================================================
#  ENTRIES — HOW THE LAB WORKS
# ===========================================================================
func _e_blobs() -> Array:
	return [
		T(_h("The blobs") + """

Each blob is one individual. Every blob carries three independent traits:
•  [b]Color[/b] — Red, Green, or Blue
•  [b]Shape[/b] — Round, Star, or Flower
•  [b]Eyes[/b] — one or three

All three are [b]purely cosmetic[/b]. No colour survives better, no shape breeds faster. That keeps this a [b]pure drift model[/b]: every change you see is chance."""),
		F(_fig_traits, 250, "The three trait sets. Every combination is possible, and none affects survival or reproduction."),
		T("""The presets track [b]colour only[/b] — one clear number is easier to read than three. The Sandbox tracks all three, and they drift independently."""),
	]

func _e_life() -> Array:
	return [
		T(_h("The life of a blob") + """

•  Born [b]small[/b]; grows over a few seconds.
•  At full size it [b]glows[/b] once — now an adult, can reproduce.
•  Two adults bump → [b]one offspring[/b]. Each trait is a 50/50 coin flip between the parents.
•  Every blob has the same [b]lifespan[/b] and eventually dies.

Births, deaths, and who meets whom are all chance — and that chance is the drift."""),
		F(_fig_inheritance, 215, "One trait, one coin flip. The child takes one parent's version at random, independently for each trait."),
		C("DELIBERATELY MISSING", "No food, no predators, no mutation. Food would be selection. Mutation would hide fixation. They're left out so what you watch is drift and nothing else.", COL_AMBER),
	]

func _e_tracker() -> Array:
	return [
		T(_h("The allele tracker") + """

The [b]Allele Tracker[/b] shows each trait variant's live share of the population, leader highlighted. The [b]Last Event[/b] panel shows how those shares changed right after an event — green rose, red fell."""),
		F(_fig_tracker, 170, "Left: live shares, leader outlined. Right: the change from the most recent event. A colour reading 0% has been lost."),
		T("""Things to notice:

•  The bars never sit still. That everyday wobble is drift.
•  When one bar hits 100%, the others stay at 0% forever — fixation.
•  After an event, Last Event separates that one moment from the slow background wander."""),
	]

func _e_speed() -> Array:
	return [
		T(_h("Speed and controls") + """

The speed slider scales the whole simulation uniformly — five settings from 0.25× to 1.25×. It never favours any trait; it only changes how fast time passes. A run at high speed is the same run, just faster."""),
		C("A GOOD HABIT", "Before pressing anything, write down the tracker numbers. Then trigger the event and compare. Drift Events does this for you; in the Sandbox the Last event card in the Events tab does it too.", COL_GREEN),
	]

func _e_modes() -> Array:
	return [
		T(_h("The three modes") + """

[b]Presets[/b] — Six guided lessons, in order. Each opens with a [b]Predict First[/b] panel: commit to a guess, then run it. Start here.

[b]Drift Events[/b] — Four hands-on experiments. Take a reading, fire the event yourself, compare before and after.

[b]Sandbox[/b] — Your own lab. Build a population, then paint in migrants, drop meteors, build walls and change the rules. Six optional goals."""),
		C("SUGGESTED ORDER", "Presets L1 → L6, then the four Drift Events, then the Sandbox. Every scenario is explained in the [b]Scenarios[/b] section here.", COL_BLUE),
	]

# ===========================================================================
#  ENTRIES — SCENARIOS (PRESETS)
# ===========================================================================
func _e_coin_flip() -> Array:
	return [
		T(_h("L1 — Randomness: The Basis of Genetic Drift") + "\n" + _q("Does a color have to be better to take over?")),
		C("SETUP", "One pen. 12 blobs, 4 of each colour, capped at 16. Nothing favours any colour.", COL_DIM),
		T("""[b]On screen.[/b] The blobs grow up, bump, and the colour graph wobbles. One colour edges ahead, another gets squeezed out, and eventually one reaches 100%. Which one is different every time.

Watch the graph, not the blobs. The wobble is drift; a band vanishing is a colour lost forever."""),
		F(_fig_three_color, 210, "The three colours' shares over one run. Each starts at a third; by the end one has everything."),
		C("THE CONCEPT", "A trait doesn't need to be better to take over. Chance — who meets whom, who's an adult when, which way the coin flips — is enough. Every other lesson builds on this.", COL_BLUE),
		C("WATCH FOR", "The first colour to drop out — it's often not the one that was behind early. And how the end accelerates: at one or two blobs, a single death finishes it.", COL_AMBER),
		C("COMMON MIX-UP", "\"Blue won, so blue must have been better.\" No — identical rules. Run it five times and count winners. An advantage would win every time.", COL_RED),
	]

func _e_long_shot() -> Array:
	return [
		T(_h("L2 — The Long Shot") + "\n" + _q("Can a rare color beat a common one on luck alone?")),
		C("SETUP", "One pen. 12 blobs: 8 of one colour, 2 each of the others. Same rules as L1. A tally of winners is kept across the session.", COL_DIM),
		T("""[b]On screen.[/b] Usually the common colour wins and it looks inevitable. Every so often a rare colour takes over instead — and nothing about that run was different. It was its turn.

The scoreboard is the real experiment: the observed win rates slowly settle toward the predicted ones."""),
		F(_fig_fixation_prob, 160, "The rule this preset tests: chance of taking over equals starting share. 8 of 12 ≈ 67%; 2 of 12 ≈ 17%. Rare, not doomed."),
		C("THE CONCEPT", "Under pure drift, an allele's chance of fixing equals its current frequency. Over many runs the tally converges on the starting proportions — which is how you check the lab really is pure drift.", COL_BLUE),
		C("WATCH FOR", "How close the tally is after ten runs versus thirty. Few runs are lumpy; that lumpiness is sampling error too.", COL_AMBER),
		C("COMMON MIX-UP", "\"The rare colour won, so it had a hidden edge.\" A 1-in-6 event happens one time in six.", COL_RED),
	]

func _e_small_large() -> Array:
	return [
		T(_h("L3 — Small vs Large") + "\n" + _q("Why does population size change how fast drift works?")),
		C("SETUP", "Two walled-off pens, identical starting mix. Left holds a small population, right a large one. Pens are sized so crowding is equal — only head count differs.", COL_DIM),
		T("""[b]On screen.[/b] The small pen lurches: big swings, colours dropping out, usually fixed well before time is up. The large pen barely moves and may not fix at all."""),
		F(_fig_popsize, 210, "Identical rules, mix, and time. Only population size differs — and it changes everything about how fast the frequencies move."),
		C("THE CONCEPT", "Drift is sampling error, and big samples are accurate. Each generation in the large pen is a large draw, so it lands close to the truth. The small pen's draws are tiny and wild.", COL_BLUE),
		C("WATCH FOR", "Which pen settles first, and which pen's winner was easier to guess. In the large pen the starting leader almost always holds on.", COL_AMBER),
		C("COMMON MIX-UP", "\"The big population is better at keeping the fittest colour.\" There is no fittest colour. It's better at keeping [i]whatever it started with[/i]. That's stability, not selection.", COL_RED),
	]

func _e_parallel() -> Array:
	return [
		T(_h("L4 — Parallel Worlds") + "\n" + _q("Same start, same rules — same ending?")),
		C("SETUP", "Nine tiny sealed pens in a 3×3 grid, each starting 2 red, 2 green, 2 blue. When a pen fixes its border turns the winner's colour. A cross-run tally counts endings.", COL_DIM),
		T("""[b]On screen.[/b] Nine identical worlds start moving and within seconds look different. One fixes red early, another green, a third takes ages and lands blue. By the end the grid is a patchwork."""),
		F(_fig_parallel, 230, "Nine identical starts, nine independent endings. Over many sessions the tally settles near a third each."),
		C("THE CONCEPT", "Isolated populations diverge under drift even with identical starts and identical environments. One population's outcome tells you nothing about what \"should\" happen.", COL_BLUE),
		C("WATCH FOR", "How many of nine land on the same colour. If a colour were genuinely better, all nine would end the same way. The scatter is the evidence.", COL_AMBER),
		C("COMMON MIX-UP", "\"Five of nine went blue — blue must be strong.\" Five of nine is well within a fair three-way split. Trust the session tally.", COL_RED),
	]

func _e_gene_flow() -> Array:
	return [
		T(_h("L5 — Gene Flow") + "\n" + _q("What happens when two isolated groups start mixing?")),
		C("SETUP", "Two pens sharing a wall with a gate. Sealed for the first stretch, then the gate cycles open and shut. Your population is whichever pen you're in. The graph plots how [i]different[/i] the pens are.", COL_DIM),
		T("""[b]On screen.[/b] Gate shut: the pens drift apart and the difference line climbs. Gate open: a few blobs cross and the line drops sharply. Shut again: it climbs. A colour extinct in one pen can reappear when a migrant carries it in."""),
		F(_fig_gene_flow, 210, "Grey eras are gate closed, green are open. Isolation lets the pens drift apart; even a trickle of migration pulls them back."),
		C("THE CONCEPT", "Gene flow works against drift. It homogenises populations and refills lost diversity. About one migrant per generation is enough to stop two populations fixing on different alleles.", COL_BLUE),
		C("WATCH FOR", "The first ten seconds after the gate opens. And whether a colour extinct on one side comes back — one migrant reversing a loss drift alone could never undo.", COL_AMBER),
		C("COMMON MIX-UP", "\"The gate opened and nothing crossed, so gene flow didn't happen.\" Correct — and the line won't drop. Gene flow needs actual movement plus actual breeding.", COL_RED),
	]

func _e_drift_vs_sel() -> Array:
	return [
		T(_h("L6 — Drift vs Selection") + "\n" + _q("How is a real advantage different from pure luck?")),
		C("BREAKS THE NO-SELECTION RULE", "The one preset that deliberately violates the lab's rule. In the right pen only, red blobs live longer — ringed in gold so you can see who's favoured. Everything else is identical.", COL_RED),
		C("SETUP", "Two equal pens. Left: pure drift. Right: red has a survival advantage. A cross-run tally records each pen's winner.", COL_DIM),
		T("""[b]On screen.[/b] The left pen wanders and lands somewhere. The right pen has a direction: red keeps climbing. Not always winning, but climbing, run after run."""),
		F(_fig_drift_vs_selection, 210, "Left: drift — five runs, five stories. Right: red survives better — five runs, one story. Consistency is the signature of selection."),
		C("THE CONCEPT", "Only selection has a direction. A single run of drift can look like selection, so the test is repetition: drift's winners scatter, selection's pile up.", COL_BLUE),
		C("WATCH FOR", "The tally after a few runs: drift column scatters, selection column stacks on red. Then: if you shrank the right pen, would red's edge matter more or less? (Less — noise drowns weak selection.)", COL_AMBER),
		C("COMMON MIX-UP", "\"Red lives longer, so red always wins.\" No. Selection tilts the odds, it doesn't fix the result. A rare red in a small pen can still be lost before its edge matters.", COL_RED),
	]

# ===========================================================================
#  ENTRIES — SCENARIOS (DRIFT EVENTS)
# ===========================================================================
func _e_unlucky() -> Array:
	return [
		T(_h("One Unlucky Death") + "\n" + _q("What is the smallest possible unit of drift?")),
		C("SETUP", "12 blobs, nobody ages. Each press: one random blob dies, one random survivor has a child. Population never changes size.", COL_DIM),
		T("""[b]On screen.[/b] A blob vanishes. A baby appears beside a random survivor. The count is unchanged; the mix has shifted by one blob. Press twenty times and the shifts pile up. Eventually a colour hits zero and is gone."""),
		F(_fig_moran, 170, "One random death, one random birth. Twelve before, twelve after — only the colour mix moved, by exactly one."),
		C("THE CONCEPT", "This is the Moran model, the simplest description of drift: one dies at random, one reproduces at random, repeat. Every drift curve is built from steps like this.", COL_BLUE),
		C("WATCH FOR", "Which colour loses its last blob first. Usually the rarest, but not always — and never the \"worst\", because there is no worst.", COL_AMBER),
		C("COMMON MIX-UP", "\"The population didn't shrink, so nothing happened.\" The mix changed, and mix changes are permanent in a way head counts are not.", COL_RED),
	]

func _e_disaster() -> Array:
	return [
		T(_h("Natural Disaster") + "\n" + _q("Can a random event that ignores colour still change the colour mix?")),
		C("SETUP", "Arm a zone, move it around the pen — a readout shows what's inside. Click to strike; everything inside dies. Survivors breed back. Before/after is compared.", COL_DIM),
		T("""[b]On screen.[/b] As you move the zone, the readout is rarely a fair mix. Offspring are born beside their parents, so same-colour families clump. Drop the zone on a clump and one colour takes most of the damage — though the disaster has no idea what colour is."""),
		F(_fig_disaster, 200, "The zone knows only location. But location and colour are accidentally linked, because offspring appear next to their parents."),
		C("THE CONCEPT", "Drift doesn't need the random event to be about the trait. A flood kills whoever is in its path, and whoever is in its path is not a representative sample. Same sampling error, delivered by a map instead of a coin.", COL_BLUE),
		C("WATCH FOR", "Aim at a mixed area, then a clumped one, and compare before/after. Then think about why real populations are clumped too.", COL_AMBER),
		C("COMMON MIX-UP", "\"I killed mostly red, so I selected against red.\" Selection means red died [i]because it was red[/i]. Here red died because it was standing in the wrong place.", COL_RED),
	]

func _e_bottleneck() -> Array:
	return [
		T(_h("Bottleneck") + "\n" + _q("If the population recovers, is anything really lost?")),
		C("SETUP", "Fire: most blobs die at random, a few survive. Survivors breed the pen back to full. Before / after crash / after recovery are all tracked.", COL_DIM),
		T("""[b]On screen.[/b] The pen empties to two or five blobs. Slowly it refills. The head count comes all the way back — but the recovered population is made of whatever the survivors were. No green survived? No green, ever again."""),
		F(_fig_bottleneck_founder, 285, "Top row is the bottleneck. A random crash leaves a few survivors; they breed the numbers back, but any colour they didn't carry is gone."),
		F(_fig_recovery, 190, "Population size recovers fully. The number of alleles present drops at the crash and stays there."),
		C("THE CONCEPT", "A bottleneck is drift at maximum strength. Recovery restores numbers but not variation, because every new individual descends from the same few survivors.", COL_BLUE),
		C("WATCH FOR", "Compare the mix before the crash with the mix [i]after recovery[/i] — that's the honest measure of what it cost.", COL_AMBER),
		C("COMMON MIX-UP", "\"The survivors were the tough ones.\" They were the lucky ones. The crash chose at random.", COL_RED),
	]

func _e_founder() -> Array:
	return [
		T(_h("Founder Effect") + "\n" + _q("What happens when a few individuals start a new population?")),
		C("SETUP", "A full mainland and an empty island. Fire: a few random blobs cross to the island and start breeding. Nobody dies — the mainland carries on unchanged.", COL_DIM),
		T("""[b]On screen.[/b] A handful land on the island and multiply. Soon the island is full — but its mix is nothing like the mainland's. Often a colour is missing outright. Sometimes a rare mainland colour is the island majority, because two of three founders carried it."""),
		F(_fig_bottleneck_founder, 285, "Bottom row is the founder effect. The mainland is untouched; a small random sample grows into a population carrying only what the founders carried."),
		C("THE CONCEPT", "A new population inherits only what its founders had, at whatever frequencies chance dealt. Small founding group → intense early drift → a mix far from the source. This is why island populations differ from the mainland.", COL_BLUE),
		C("WATCH FOR", "Which colours the island is missing, and whether its leader matches the mainland's. Run again with different founders — the island differs every time.", COL_AMBER),
		C("BOTTLENECK VS FOUNDER", "In a [b]bottleneck[/b] the population itself crashes. In a [b]founder effect[/b] nothing dies — a few leave and the source continues. Both lose diversity the same way: a small sample can't carry everything.", COL_RED),
	]

# ===========================================================================
#  ENTRIES — SANDBOX
# ===========================================================================
func _e_sandbox() -> Array:
	return [
		T(_h("Sandbox") + "\n" + _q("What can you make chance do?")),
		C("SETUP", "You choose: 2 to 40 starting blobs, and for each trait an Even, Random, One rare or Off mix. Everything else is up to you.", COL_DIM),
		T("""[b]Tools[/b] (keys 1 to 5)
•  [b]Inspect[/b] — hover a blob for its traits, generation and children. Click to pin.
•  [b]Spawn[/b] — click or drag to add migrants with the traits you pick.
•  [b]Meteor[/b] — aim a crater and strike a place.
•  [b]Wall[/b] — drag to build barriers; right-click to remove.
•  [b]Stir[/b] — a gust that scatters blobs and mixes clumps.

[b]Events[/b] — Unlucky Death, Bottleneck (50–95%), Random Meteor, and Chaos Mode, which fires them on a timer.

[b]World[/b] — population cap, lifespan, breeding rest and wander speed. Each changes every blob equally.

[b]Data[/b] — a graph for Color, Shape or Eyes with event lines, the allele tracker, the last event's before and after, and a log."""),
		C("STILL PURE DRIFT", "Nothing kills by trait: meteors hit places and events pick at random. Spawning is gene flow, and walls make isolated populations. No version is ever better.", COL_AMBER),
		C("TRY THIS", "Split the lab with a wall from edge to edge and wait. Each side usually fixes a different color. Then knock the wall down and watch gene flow mix them again.", COL_GREEN),
	]
