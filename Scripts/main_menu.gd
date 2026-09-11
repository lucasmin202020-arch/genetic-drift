extends Control

# ===========================================================================
#  MAIN MENU
#  Built entirely in code; the scene is a single Control named "MainMenu".
#
#  LAYOUT      title → three mode cards → one wide Info card
#  BACKGROUND  a calm field of soft drifting particles in the trait colours,
#              two slow colour glows behind them
#  CARD ICONS  Presets: a seeded 3-colour drift chart that draws itself in,
#                       pauses, and repeats
#              Events:  a bottleneck funnel — many dots go in, few come out
#              Playground: three blobs bobbing and blinking
#  MOTION      hover lift + border/shadow brighten; staggered fade-in on load
#  FONT        Nunito (variable). Drop the .ttf at FONT_PATH. If it isn't
#              there the menu silently uses Godot's default font.
# ===========================================================================

const PLAYGROUND_SCENE := "res://Scenes/Game.tscn"
const PRESET_MENU_SCENE := "res://Scenes/PresetMenu.tscn"
const EVENTS_MENU_SCENE := "res://Scenes/EventsMenu.tscn"
const INFO_MENU_SCENE := "res://Scenes/InfoMenu.tscn"
const FONT_PATH := "res://Fonts/Nunito.ttf"

const COL_RED := Color(0.90, 0.38, 0.38)
const COL_GREEN := Color(0.42, 0.80, 0.48)
const COL_BLUE := Color(0.42, 0.62, 0.95)
const COL_AMBER := Color(1.0, 0.78, 0.36)
const COL_TEXT := Color(0.92, 0.92, 0.94)
const COL_DIM := Color(0.60, 0.60, 0.66)
const COL_PANEL := Color(0.14, 0.14, 0.17)
const COL_PANEL_DARK := Color(0.11, 0.11, 0.14)
const COL_BORDER := Color(0.26, 0.26, 0.31)
const COL_BORDER_HOT := Color(0.62, 0.62, 0.70)
const COL_BG := Color(0.10, 0.10, 0.12)
const COL_PLOT_BG := Color(0.07, 0.07, 0.09)

const CARD_W := 296.0
const CARD_H := 250.0
const CARD_GAP := 22.0
const PARTICLES := 42

var t: float = 0.0
var rng := RandomNumberGenerator.new()

var bg_canvas: Control
var glow_a: Sprite2D
var glow_b: Sprite2D
var particles: Array = []     # {"p": Vector2, "v": Vector2, "r": float, "col": Color, "ph": float}

var cards: Array = []         # {"btn", "style", "cta"}
var icon_canvases: Array = []
var title_lbl: Label
var info_btn: Button

# Presets icon: a live allele tracker whose bars drift toward new targets
var bar_vals: Array = [0.34, 0.33, 0.33]
var bar_targets: Array = [0.34, 0.33, 0.33]
var bar_timer: float = 0.0
const LESSON_NAMES := ["L1 · Coin Flip", "L2 · The Long Shot", "L3 · Small vs Large", "L4 · Parallel Worlds", "L5 · Gene Flow", "L6 · Drift vs Selection"]

# Playground icon: a miniature simulation in a fixed-size pen
const PEN_W := 260.0
const PEN_H := 92.0
const MINI_CAP := 8
var mini_blobs: Array = []    # {"p","v","col","shape","eyes","age","life","cd"}

# Font cache
var _font_file: FontFile = null
var _fonts: Dictionary = {}

# ---------------------------------------------------------------------------
func _ready():
	rng.randomize()
	_apply_font_theme()
	_fit_to_window()
	get_viewport().size_changed.connect(_fit_to_window)
	_init_particles()
	_init_mini_sim()
	_build_background()
	_build_ui()
	_play_intro()

func _fit_to_window():
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size

func _go(path: String) -> void:
	if not ResourceLoader.exists(path):
		push_error("MainMenu: no scene found at '%s'. Right-click the .tscn in the FileSystem dock -> Copy Path, and paste it into the constant at the top of main_menu.gd." % path)
		return
	get_tree().change_scene_to_file(path)

# ---------------------------------------------------------------------------
#  FONT
# ---------------------------------------------------------------------------
func _font(weight: int) -> Font:
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
	th.default_font = _font(500)
	th.default_font_size = 16
	th.set_font("bold_font", "RichTextLabel", _font(750))
	theme = th

# ---------------------------------------------------------------------------
#  PARTICLE BACKGROUND
# ---------------------------------------------------------------------------
func _init_particles() -> void:
	var cols: Array = [COL_RED, COL_GREEN, COL_BLUE, COL_BLUE, COL_DIM]
	var s: Vector2 = get_viewport_rect().size
	for i in range(PARTICLES):
		var depth: float = rng.randf()                       # 0 = far, 1 = near
		particles.append({
			"p": Vector2(rng.randf() * s.x, rng.randf() * s.y),
			"v": Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized() * (6.0 + 14.0 * depth),
			"r": 2.5 + 6.0 * depth,
			"a": 0.06 + 0.16 * depth,
			"col": cols[rng.randi() % cols.size()],
			"ph": rng.randf() * TAU,
		})

func _step_particles(delta: float) -> void:
	var s: Vector2 = get_viewport_rect().size
	for pt in particles:
		var d: Dictionary = pt
		var v: Vector2 = d["v"]
		var ph: float = float(d["ph"])
		# gentle wander: rotate velocity a little on a slow sine
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

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	glow_a = _make_glow(380, COL_BLUE, 0.08)
	glow_b = _make_glow(440, COL_RED, 0.06)
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
	var s := Sprite2D.new()
	s.texture = ImageTexture.create_from_image(img)
	return s

func _process(delta: float) -> void:
	t += delta
	_step_particles(delta)
	_step_bars(delta)
	_step_mini_sim(delta)
	if bg_canvas:
		bg_canvas.queue_redraw()
	for ic in icon_canvases:
		var c: Control = ic
		c.queue_redraw()
	if glow_a and glow_b:
		var s: Vector2 = get_viewport_rect().size
		glow_a.position = Vector2(s.x * 0.20 + sin(t * 0.13) * 70.0, s.y * 0.28 + cos(t * 0.11) * 40.0)
		glow_b.position = Vector2(s.x * 0.82 + sin(t * 0.09 + 2.0) * 70.0, s.y * 0.80 + cos(t * 0.14 + 1.0) * 40.0)

# ---------------------------------------------------------------------------
#  UI
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	title_lbl = Label.new()
	title_lbl.text = "Genetic Drift Lab"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_override("font", _font(800))
	title_lbl.add_theme_font_size_override("font_size", 44)
	title_lbl.add_theme_color_override("font_color", Color(0.97, 0.97, 0.98))
	col.add_child(title_lbl)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 30)
	col.add_child(gap)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(CARD_GAP))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)

	row.add_child(_make_card("Presets", "Six guided lessons. Predict, run, then read what happened.", "L1 – L6  ·  Start here", _icon_presets, PRESET_MENU_SCENE))
	row.add_child(_make_card("Drift Events", "Four experiments. Take a reading, fire the event, compare.", "4 events  ·  Hands-on", _icon_events, EVENTS_MENU_SCENE))
	row.add_child(_make_card("Playground", "The open sandbox. All three traits tracked, every tool unlocked.", "Sandbox  ·  No rules", _icon_playground, PLAYGROUND_SCENE))

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, CARD_GAP)
	col.add_child(gap2)

	info_btn = _make_info_bar()
	var info_wrap := CenterContainer.new()
	info_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_wrap.add_child(info_btn)
	col.add_child(info_wrap)

# ---------------------------------------------------------------------------
#  CARDS
# ---------------------------------------------------------------------------
func _card_style(bg: Color, border: Color, shadow: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(16)
	s.set_border_width_all(1)
	s.border_color = border
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = shadow
	s.shadow_offset = Vector2(0, 6)
	return s

func _card_shell(min_size: Vector2, scene: String) -> Dictionary:
	var card := Button.new()
	card.custom_minimum_size = min_size
	var style := _card_style(COL_PANEL, COL_BORDER, 10)
	for slot in ["normal", "hover", "pressed", "focus"]:
		card.add_theme_stylebox_override(str(slot), style)
	card.pressed.connect(func(): _go(scene))
	var entry: Dictionary = {"btn": card, "style": style, "cta": null}
	card.mouse_entered.connect(_on_card_hover.bind(entry, true))
	card.mouse_exited.connect(_on_card_hover.bind(entry, false))
	card.button_down.connect(_on_card_down.bind(entry))
	card.button_up.connect(_on_card_hover.bind(entry, true))
	cards.append(entry)
	return entry

func _make_card(title: String, blurb: String, cta: String, icon_fn: Callable, scene: String) -> Button:
	var entry: Dictionary = _card_shell(Vector2(CARD_W, CARD_H), scene)
	var card: Button = entry["btn"]

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 18)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 14)
	card.add_child(pad)

	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 8)
	pad.add_child(vb)

	var icon := Control.new()
	icon.custom_minimum_size = Vector2(0, 92)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(func(): icon_fn.call(icon))
	vb.add_child(icon)
	icon_canvases.append(icon)

	var tl := Label.new()
	tl.text = title
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_theme_font_override("font", _font(750))
	tl.add_theme_font_size_override("font_size", 22)
	tl.add_theme_color_override("font_color", COL_TEXT)
	vb.add_child(tl)

	var bl := Label.new()
	bl.text = blurb
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bl.add_theme_font_size_override("font_size", 14)
	bl.add_theme_color_override("font_color", COL_DIM)
	vb.add_child(bl)

	var cl := Label.new()
	cl.text = cta + "   →"
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_theme_font_override("font", _font(700))
	cl.add_theme_font_size_override("font_size", 13)
	cl.add_theme_color_override("font_color", Color(COL_AMBER.r, COL_AMBER.g, COL_AMBER.b, 0.75))
	vb.add_child(cl)
	entry["cta"] = cl
	return card

# Compact card under the three modes, centred, contents centred.
func _make_info_bar() -> Button:
	var entry: Dictionary = _card_shell(Vector2(340, 56), INFO_MENU_SCENE)
	var card: Button = entry["btn"]

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(center)

	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 12)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(hb)

	var icon := Control.new()
	icon.custom_minimum_size = Vector2(28, 28)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.draw.connect(func(): _icon_info(icon))
	hb.add_child(icon)

	var tl := Label.new()
	tl.text = "Info & Explanations"
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_theme_font_override("font", _font(750))
	tl.add_theme_font_size_override("font_size", 17)
	tl.add_theme_color_override("font_color", COL_TEXT)
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(tl)

	var cl := Label.new()
	cl.text = "→"
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_theme_font_override("font", _font(700))
	cl.add_theme_font_size_override("font_size", 16)
	cl.add_theme_color_override("font_color", Color(COL_AMBER.r, COL_AMBER.g, COL_AMBER.b, 0.75))
	cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(cl)
	entry["cta"] = cl
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

# ---------------------------------------------------------------------------
#  INTRO ANIMATION
# ---------------------------------------------------------------------------
func _play_intro() -> void:
	title_lbl.modulate.a = 0.0
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(title_lbl, "modulate:a", 1.0, 0.5)
	for i in range(cards.size()):
		var d: Dictionary = cards[i]
		var btn: Button = d["btn"]
		btn.modulate.a = 0.0
		btn.scale = Vector2(0.94, 0.94)
		btn.call_deferred("set_pivot_offset", btn.custom_minimum_size * 0.5)
		var delay: float = 0.18 + 0.09 * float(i)
		tw.tween_property(btn, "modulate:a", 1.0, 0.45).set_delay(delay)
		tw.tween_property(btn, "scale", Vector2.ONE, 0.45).set_delay(delay)

# ---------------------------------------------------------------------------
#  CARD ICONS
# ---------------------------------------------------------------------------
# Presets: a live allele tracker. Every couple of seconds the bars pick new
# targets (a random nudge, renormalised) and glide there; the leader is
# outlined in amber and the header cycles through the six lessons.
func _step_bars(delta: float) -> void:
	bar_timer -= delta
	if bar_timer <= 0.0:
		bar_timer = rng.randf_range(1.4, 2.2)
		var total: float = 0.0
		var next: Array = []
		for i in range(3):
			var v: float = clamp(float(bar_targets[i]) + rng.randf_range(-0.16, 0.16), 0.04, 0.88)
			next.append(v)
			total += v
		for i in range(3):
			next[i] = float(next[i]) / total
		bar_targets = next
	var k: float = clamp(delta * 3.0, 0.0, 1.0)
	for i in range(3):
		bar_vals[i] = lerp(float(bar_vals[i]), float(bar_targets[i]), k)

func _icon_presets(c: Control) -> void:
	var rect := Rect2(6.0, 6.0, c.size.x - 12.0, c.size.y - 12.0)
	c.draw_rect(rect, COL_PLOT_BG, true)
	var lesson: int = int(floor(fmod(t / 6.0, 6.0)))
	_label(c, Vector2(rect.position.x + 10.0, rect.position.y + 16.0), LESSON_NAMES[lesson], 11, Color(1, 1, 1, 0.5))
	var cols: Array = [COL_RED, COL_GREEN, COL_BLUE]
	var leader: int = 0
	for i in range(3):
		if float(bar_vals[i]) > float(bar_vals[leader]):
			leader = i
	var bar_x: float = rect.position.x + 10.0
	var bar_w: float = rect.size.x - 20.0 - 40.0
	for i in range(3):
		var y: float = rect.position.y + 30.0 + float(i) * 18.0
		var v: float = float(bar_vals[i])
		c.draw_rect(Rect2(bar_x, y, bar_w, 12.0), Color(1, 1, 1, 0.06), true)
		c.draw_rect(Rect2(bar_x, y, bar_w * v, 12.0), cols[i], true)
		if i == leader:
			c.draw_rect(Rect2(bar_x - 2.0, y - 2.0, bar_w + 4.0, 16.0), COL_AMBER, false, 1.2)
		_label(c, Vector2(bar_x + bar_w + 8.0, y + 10.0), "%d%%" % int(round(v * 100.0)), 11, COL_TEXT if i == leader else COL_DIM)
	c.draw_rect(rect, Color(1, 1, 1, 0.12), false, 1.0)

# Events: a bottleneck. Dots flow left-to-right into a narrowing funnel;
# most vanish at the neck, a lucky few come out the other side.
func _icon_events(c: Control) -> void:
	var rect := Rect2(6.0, 6.0, c.size.x - 12.0, c.size.y - 12.0)
	c.draw_rect(rect, COL_PLOT_BG, true)
	var mid: float = rect.position.y + rect.size.y * 0.5
	var neck_x: float = rect.position.x + rect.size.x * 0.58
	var neck_half: float = 9.0
	var wall := Color(0.95, 0.62, 0.62, 0.55)
	# funnel walls
	c.draw_polyline(PackedVector2Array([Vector2(rect.position.x + 10.0, rect.position.y + 8.0), Vector2(neck_x, mid - neck_half), Vector2(neck_x + 28.0, mid - neck_half)]), wall, 2.0, true)
	c.draw_polyline(PackedVector2Array([Vector2(rect.position.x + 10.0, rect.end.y - 8.0), Vector2(neck_x, mid + neck_half), Vector2(neck_x + 28.0, mid + neck_half)]), wall, 2.0, true)
	# dots
	var cols: Array = [COL_RED, COL_GREEN, COL_BLUE]
	var period: float = 5.5
	var n: int = 16
	for i in range(n):
		var ph: float = float(i) / float(n)
		var u: float = fmod(t / period + ph, 1.0)                    # 0..1 along the path
		var survivor: bool = (i % 5 == 0)                             # ~1 in 5 makes it through
		var lane: float = (float((i * 7) % n) / float(n - 1)) * 2.0 - 1.0   # -1..1 spread
		var x: float = rect.position.x + 6.0 + (rect.size.x - 12.0) * u
		var squeeze: float = clamp((neck_x - x) / (neck_x - rect.position.x), 0.0, 1.0)
		var y: float = mid + lane * (rect.size.y * 0.5 - 12.0) * squeeze
		var col: Color = cols[i % 3]
		var a: float = 0.95
		if not survivor:
			# fade out in the last stretch before the neck
			var gate: float = (neck_x - x) / 40.0
			a = clamp(gate, 0.0, 1.0)
			if x >= neck_x:
				continue
		else:
			if x > neck_x:
				y = mid + lane * 6.0 * clamp((x - neck_x) / 60.0, 0.0, 1.0)
		c.draw_circle(Vector2(x, y), 4.5, Color(col.r, col.g, col.b, a))
	c.draw_rect(rect, Color(1, 1, 1, 0.12), false, 1.0)

# Playground: a tiny version of the real thing. Blobs wander a pen, bounce,
# make a baby when two adults touch, grow up, and die of old age.
func _spawn_mini(p: Vector2, col: Color, shape: int, eyes: int, age: float) -> void:
	var ang: float = rng.randf() * TAU
	mini_blobs.append({
		"p": p, "v": Vector2(cos(ang), sin(ang)) * rng.randf_range(22.0, 34.0),
		"col": col, "shape": shape, "eyes": eyes,
		"age": age, "life": rng.randf_range(9.0, 14.0), "cd": 0.0,
	})

func _random_mini(age: float) -> void:
	var cols: Array = [COL_RED, COL_GREEN, COL_BLUE]
	_spawn_mini(Vector2(rng.randf_range(16.0, PEN_W - 16.0), rng.randf_range(16.0, PEN_H - 16.0)),
		cols[rng.randi() % 3], rng.randi() % 3, 1 if rng.randf() < 0.5 else 3, age)

func _init_mini_sim() -> void:
	for i in range(5):
		_random_mini(rng.randf_range(1.5, 6.0))

func _step_mini_sim(delta: float) -> void:
	var r_full: float = 9.0
	# move, steer, bounce, age
	for b in mini_blobs:
		var d: Dictionary = b
		var v: Vector2 = d["v"]
		v = v.rotated(rng.randf_range(-1.2, 1.2) * delta)
		var p: Vector2 = d["p"] + v * delta
		if p.x < r_full and v.x < 0.0: v.x = abs(v.x)
		if p.x > PEN_W - r_full and v.x > 0.0: v.x = -abs(v.x)
		if p.y < r_full and v.y < 0.0: v.y = abs(v.y)
		if p.y > PEN_H - r_full and v.y > 0.0: v.y = -abs(v.y)
		d["p"] = p.clamp(Vector2(r_full, r_full), Vector2(PEN_W - r_full, PEN_H - r_full))
		d["v"] = v
		d["age"] = float(d["age"]) + delta
		d["cd"] = max(0.0, float(d["cd"]) - delta)
	# births: two adults touching, both off cooldown, room in the pen
	var births: Array = []
	for i in range(mini_blobs.size()):
		for j in range(i + 1, mini_blobs.size()):
			if mini_blobs.size() + births.size() >= MINI_CAP:
				break
			var a: Dictionary = mini_blobs[i]
			var bb: Dictionary = mini_blobs[j]
			if float(a["age"]) < 1.5 or float(bb["age"]) < 1.5:
				continue
			if float(a["cd"]) > 0.0 or float(bb["cd"]) > 0.0:
				continue
			var pa: Vector2 = a["p"]
			var pb: Vector2 = bb["p"]
			if pa.distance_to(pb) < r_full * 2.0:
				a["cd"] = 3.5
				bb["cd"] = 3.5
				var away: Vector2 = (pa - pb).normalized()
				a["v"] = away * float(a["v"].length())
				bb["v"] = -away * float(bb["v"].length())
				births.append({
					"p": (pa + pb) * 0.5,
					"col": a["col"] if rng.randf() < 0.5 else bb["col"],
					"shape": a["shape"] if rng.randf() < 0.5 else bb["shape"],
					"eyes": a["eyes"] if rng.randf() < 0.5 else bb["eyes"],
				})
	for nb in births:
		var n: Dictionary = nb
		_spawn_mini(n["p"], n["col"], int(n["shape"]), int(n["eyes"]), 0.0)
	# deaths
	var alive: Array = []
	for b in mini_blobs:
		var d: Dictionary = b
		if float(d["age"]) < float(d["life"]):
			alive.append(d)
	mini_blobs = alive
	# never let the pen go empty
	while mini_blobs.size() < 3:
		_random_mini(2.0)

func _icon_playground(c: Control) -> void:
	var rect := Rect2(6.0, 6.0, c.size.x - 12.0, c.size.y - 12.0)
	c.draw_rect(rect, COL_PLOT_BG, true)
	var sx: float = rect.size.x / PEN_W
	var sy: float = rect.size.y / PEN_H
	for b in mini_blobs:
		var d: Dictionary = b
		var age: float = float(d["age"])
		var life: float = float(d["life"])
		var grow: float = clamp(0.35 + 0.65 * age / 1.5, 0.35, 1.0)
		var fade: float = clamp((life - age) / 1.0, 0.0, 1.0)
		var col: Color = d["col"]
		col.a = fade
		var p: Vector2 = d["p"]
		var pos: Vector2 = rect.position + Vector2(p.x * sx, p.y * sy)
		var r: float = 9.0 * grow
		var blink: bool = fmod(t + p.x * 0.05, 4.1) < 0.12
		_draw_blob(c, pos, r, col, int(d["shape"]), int(d["eyes"]), blink)
		# adult glow: a brief ring when a blob comes of age
		if age >= 1.5 and age < 2.1:
			var k: float = 1.0 - (age - 1.5) / 0.6
			c.draw_arc(pos, r + 3.0 + 4.0 * (1.0 - k), 0.0, TAU, 24, Color(1.0, 1.0, 1.0, 0.6 * k * fade), 1.5, true)
	c.draw_rect(rect, Color(1, 1, 1, 0.12), false, 1.0)

func _icon_info(c: Control) -> void:
	var centre: Vector2 = c.size * 0.5
	var r: float = min(c.size.x, c.size.y) * 0.5 - 1.0
	c.draw_circle(centre, r, Color(0.86, 0.46, 0.46))
	c.draw_string(_font(800), Vector2(centre.x - 2.5, centre.y + 6.0), "i", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.10, 0.10, 0.10))

# ---------------------------------------------------------------------------
#  DRAWING PRIMITIVES
# ---------------------------------------------------------------------------
func _label(c: Control, pos: Vector2, text: String, size_px: int, col: Color) -> void:
	c.draw_string(_font(600), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, col)

func _star_points(center: Vector2, outer: float, inner: float, tips: int) -> PackedVector2Array:
	var arr := PackedVector2Array()
	for i in range(tips * 2):
		var rad: float = outer if i % 2 == 0 else inner
		var a: float = -PI * 0.5 + TAU * float(i) / float(tips * 2)
		arr.append(center + Vector2(cos(a), sin(a)) * rad)
	return arr

func _draw_blob(c: Control, pos: Vector2, r: float, col: Color, shape: int, eyes: int, blink: bool) -> void:
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
	if eyes == 1:
		_draw_eye(c, pos + Vector2(0.0, -r * 0.08), r * 0.28, blink, col.a)
	else:
		_draw_eye(c, pos + Vector2(-r * 0.40, -r * 0.02), r * 0.19, blink, col.a)
		_draw_eye(c, pos + Vector2(0.0, -r * 0.34), r * 0.19, blink, col.a)
		_draw_eye(c, pos + Vector2(r * 0.40, -r * 0.02), r * 0.19, blink, col.a)

func _draw_eye(c: Control, pos: Vector2, r: float, blink: bool, alpha: float = 1.0) -> void:
	if blink:
		c.draw_line(pos + Vector2(-r, 0), pos + Vector2(r, 0), Color(0.08, 0.08, 0.10, alpha), 2.0, true)
		return
	c.draw_circle(pos, r, Color(0.97, 0.97, 0.98, alpha))
	c.draw_circle(pos, r * 0.48, Color(0.08, 0.08, 0.10, alpha))
