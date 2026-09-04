extends Control

# ===========================================================================
#  MAIN MENU
#  The whole menu is built in code, so the scene only needs to be:
#    - a Control node named "MainMenu" (this script attached)
#  Set this scene as the project's Main Scene, and set PLAYGROUND_SCENE below
#  to the path of your existing simulation scene.
# ===========================================================================

# <-- IMPORTANT: set this to your actual simulation scene file.
# In the FileSystem dock, right-click your sim scene -> Copy Path, paste here.
const PLAYGROUND_SCENE := "res://Scenes/Game.tscn"
const PRESET_MENU_SCENE := "res://Scenes/PresetMenu.tscn"
const EVENTS_MENU_SCENE := "res://Scenes/EventsMenu.tscn"

var info_overlay: Control
var bg_blobs: Array = []   # decorative bouncing blobs behind the menu

func _ready():
	_fit_to_window()
	get_viewport().size_changed.connect(_fit_to_window)
	_build_ui()
	_build_info_overlay()

func _fit_to_window():
	# Force this root Control to fill the whole window so its children have size
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size

# ---------------------------------------------------------------------------
#  DECORATIVE BACKGROUND BLOBS (bounce around behind the menu)
# ---------------------------------------------------------------------------
func _build_bg_blobs():
	var tex_a := _make_circle_texture(120, Color(0.45, 0.65, 1.0))
	var tex_b := _make_circle_texture(95,  Color(1.0, 0.5, 0.5))
	_spawn_bg_blob(tex_a, Vector2(320, 300), Vector2(95, 70))
	_spawn_bg_blob(tex_b, Vector2(820, 380), Vector2(-78, 96))

func _spawn_bg_blob(tex: Texture2D, pos: Vector2, vel: Vector2):
	var s := Sprite2D.new()
	s.texture = tex
	s.position = pos
	s.modulate = Color(1, 1, 1, 0.18)   # subtle, so buttons stay readable
	add_child(s)
	move_child(s, 1)                     # above the background, below the UI
	bg_blobs.append({"sprite": s, "vel": vel})

func _make_circle_texture(radius: int, color: Color) -> ImageTexture:
	var size := radius * 2
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(radius, radius)
	for y in range(size):
		for x in range(size):
			var d := Vector2(x, y).distance_to(c)
			if d <= radius:
				var edge := 1.0 - smoothstep(float(radius) * 0.82, float(radius), d)
				img.set_pixel(x, y, Color(color.r, color.g, color.b, edge))
	return ImageTexture.create_from_image(img)

func _process(delta):
	if bg_blobs.is_empty():
		return
	var b := get_viewport_rect().size
	for entry in bg_blobs:
		var s: Sprite2D = entry["sprite"]
		var v: Vector2 = entry["vel"]
		s.position += v * delta
		var r := s.texture.get_width() * 0.5
		if s.position.x < r and v.x < 0: v.x = abs(v.x)
		if s.position.x > b.x - r and v.x > 0: v.x = -abs(v.x)
		if s.position.y < r and v.y < 0: v.y = abs(v.y)
		if s.position.y > b.y - r and v.y > 0: v.y = -abs(v.y)
		entry["vel"] = v

# ---------------------------------------------------------------------------
#  MENU LAYOUT
# ---------------------------------------------------------------------------
func _build_ui():
	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.10, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Decorative bouncing blobs behind the menu
	_build_bg_blobs()

	# Centered column
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	# Title
	var title := Label.new()
	title.text = "Genetic Drift Lab"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	col.add_child(title)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	col.add_child(gap)

	# Three big buttons (greyscale, getting darker downward)
	var btn_presets := _make_button("Presets", Color(0.32, 0.32, 0.35), Vector2(360, 66), 22)
	var btn_events  := _make_button("Drift Events", Color(0.25, 0.25, 0.28), Vector2(360, 66), 22)
	var btn_play    := _make_button("Playground", Color(0.18, 0.18, 0.21), Vector2(360, 66), 22)
	col.add_child(btn_presets)
	col.add_child(btn_events)
	col.add_child(btn_play)

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 8)
	col.add_child(gap2)

	# Smaller info button (light red), centered under the others
	var btn_info := _make_button("Info", Color(0.86, 0.46, 0.46), Vector2(200, 48), 18)
	var info_wrap := CenterContainer.new()
	info_wrap.add_child(btn_info)
	col.add_child(info_wrap)

	# Connections
	btn_presets.pressed.connect(_on_presets)
	btn_events.pressed.connect(_on_drift_events)
	btn_play.pressed.connect(_on_playground)
	btn_info.pressed.connect(_show_info)

# ---------------------------------------------------------------------------
#  BUTTON STYLING (rounded pill, greyscale or tinted)
# ---------------------------------------------------------------------------
func _make_button(text: String, base_color: Color, min_size: Vector2, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)

	b.add_theme_stylebox_override("normal",  _rounded_style(base_color))
	b.add_theme_stylebox_override("hover",   _rounded_style(base_color.lightened(0.10)))
	b.add_theme_stylebox_override("pressed", _rounded_style(base_color.darkened(0.12)))
	b.add_theme_stylebox_override("focus",   _rounded_style(base_color))  # hides default focus rect

	# Dark text on light buttons, light text on dark ones
	var text_col := Color(0.10, 0.10, 0.10) if base_color.get_luminance() > 0.5 else Color(0.93, 0.93, 0.93)
	b.add_theme_color_override("font_color", text_col)
	b.add_theme_color_override("font_hover_color", text_col)
	b.add_theme_color_override("font_pressed_color", text_col)
	b.add_theme_color_override("font_focus_color", text_col)
	return b

func _rounded_style(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(33)   # >= half the height => full pill ends
	s.content_margin_left = 24
	s.content_margin_right = 24
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s

# ---------------------------------------------------------------------------
#  BUTTON ACTIONS
# ---------------------------------------------------------------------------
# Loud about a missing scene, so a bad path doesn't just look like a dead
# button — the same failure mode the preset and events menus guard against.
func _go(path: String):
	if not ResourceLoader.exists(path):
		push_error("MainMenu: no scene found at '%s'. Right-click the .tscn in the FileSystem dock -> Copy Path, and paste it into the constant at the top of main_menu.gd." % path)
		print("MENU NAVIGATION FAILED — file not found: ", path)
		return
	get_tree().change_scene_to_file(path)

func _on_presets():
	_go(PRESET_MENU_SCENE)

func _on_drift_events():
	_go(EVENTS_MENU_SCENE)

func _on_playground():
	_go(PLAYGROUND_SCENE)

# ---------------------------------------------------------------------------
#  INFO OVERLAY (built in code, hidden until the Info button is pressed)
# ---------------------------------------------------------------------------
func _build_info_overlay():
	info_overlay = Control.new()
	info_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	info_overlay.visible = false
	add_child(info_overlay)

	# Dimmed backdrop
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	info_overlay.add_child(dim)

	# Centered panel
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	info_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(880, 560)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.14, 0.14, 0.17)
	panel_style.set_corner_radius_all(16)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 22)
	pad.add_theme_constant_override("margin_right", 22)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(pad)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	pad.add_child(vb)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)

	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.selection_enabled = true                  # allow select + copy (Ctrl+C)
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.custom_minimum_size = Vector2(820, 0)
	rt.add_theme_color_override("default_color", Color(0.90, 0.90, 0.92))
	rt.add_theme_font_size_override("normal_font_size", 16)
	rt.meta_clicked.connect(func(meta): OS.shell_open(str(meta)))   # open hyperlinks
	rt.text = _info_text()
	scroll.add_child(rt)

	# Close button
	var close := _make_button("Close", Color(0.32, 0.32, 0.35), Vector2(160, 44), 18)
	var close_wrap := CenterContainer.new()
	close_wrap.add_child(close)
	vb.add_child(close_wrap)
	close.pressed.connect(_hide_info)

func _show_info():
	info_overlay.visible = true

func _hide_info():
	info_overlay.visible = false

# ---------------------------------------------------------------------------
#  INFO CONTENT
# ---------------------------------------------------------------------------
func _info_text() -> String:
	return """[font_size=24][b]Genetic Drift Lab[/b][/font_size]

[font_size=20][b]What is genetic drift?[/b][/font_size]
Every population carries variation — different versions of a trait, called [b][color=#6db3ff][url=https://en.wikipedia.org/wiki/Allele]alleles[/url][/color][/b]. [b][color=#6db3ff][url=https://en.wikipedia.org/wiki/Genetic_drift]Genetic drift[/url][/color][/b] is the change in how common each allele is over time, caused purely by [b]random chance[/b] rather than by any version being "better."

Picture drawing colored marbles from a bag and refilling based on what you happened to draw. Even when no marble is special, the proportions wander. Sometimes a version drifts all the way to 100% and becomes [b]fixed[/b]; sometimes it drifts to 0% and is [b]lost[/b], unable to return on its own.

The key idea: [b]drift is random[/b], and it is strongest in [b]small populations[/b], where a few lucky or unlucky events swing the percentages hard. In large populations the numbers barely move. This lab lets you watch that happen live.

[font_size=20][b]What the blobs are[/b][/font_size]
Each blob is one individual in the population. Every blob carries three independent traits:
•  [b]Color[/b] — Red, Green, or Blue
•  [b]Shape[/b] — Round, Star, or Flower
•  [b]Eyes[/b] — one eye or three eyes

These traits are [b]purely cosmetic[/b]. No color survives better, no shape reproduces faster. That is on purpose — it keeps this a [b]pure drift model[/b], so every change you see in the percentages is caused by chance alone, never by selection.

[font_size=20][b]The life of a blob[/b][/font_size]
•  A blob is born [b]small[/b] and grows over several seconds.
•  When it reaches full size it gives a quick [b]glow[/b] — it is now an adult and can reproduce.
•  When two adult blobs bump into each other they produce [b]one offspring[/b]. For each trait the baby inherits one parent's version at random — a 50/50 coin flip per trait.
•  Every blob has a fixed [b]lifespan[/b] and eventually dies. Because lifespan is identical for all blobs, no trait gets an unfair advantage.

Births, deaths, and which blobs happen to meet are all left to chance — and that chance is exactly what drives the drift.

[font_size=20][b]The three modes[/b][/font_size]
[b]Presets[/b] — Six guided lessons, in order. Each one asks a question, runs on its own, then explains what happened. Start here if you're new to drift.

[b]Drift Events[/b] — Four hands-on experiments about the individual random events that cause drift. Each one takes a reading of the population, lets you fire the event yourself, then compares the numbers before and after.

[b]Playground[/b] — The open sandbox. Start a population and do whatever you like: trigger events, change the speed, and watch the tracker.

[font_size=20][b]The drift events[/b][/font_size]
[b]One Unlucky Death[/b] — One blob dies at random, and one survivor immediately has a child. The population never changes size, so the only thing that moves is the color mix. Press it enough times and a color disappears entirely. This is the smallest possible unit of drift.

[b]Natural Disaster[/b] — Wipes out every blob inside a zone that [b]you aim[/b], with a live readout of what's inside before you fire. The disaster knows nothing about color — only location. But blobs are born next to their parents, so colors clump by accident, and hitting a place means hitting a color.

[b]Bottleneck[/b] — A population crash. Most blobs die at random and a handful survive, then the survivors breed the population back to full size. Watch carefully: the [b]numbers[/b] recover, but the [b]diversity[/b] doesn't, because everything alive afterwards descends from the few that made it.

[b]Founder Effect[/b] — A few randomly chosen blobs cross to an empty island and start a new population. Nobody dies — the mainland carries on untouched, so you can compare the two side by side. The island's mix is just a small random sample of the mainland's, which is often missing a color entirely.

[font_size=20][b]Bottleneck vs. founder effect[/b][/font_size]
These two are easy to confuse because they produce similar-looking populations. The difference is what happens to the original group. In a [b]bottleneck[/b], the population itself crashes and the survivors are all that's left. In a [b]founder effect[/b], nothing dies at all — a few individuals simply leave and start somewhere new, and the source population continues as before. Both lose diversity through the same mechanism: a small sample can't carry everything the big one had.

[font_size=20][b]The tracker[/b][/font_size]
The [b]Allele Tracker[/b] shows the live percentage of each trait variant in the current population, with the leading variant highlighted. The [b]Last Event[/b] panel shows how those percentages changed right after an event — green for variants that rose, red for those that fell. Watching the numbers wander, fix, and vanish is the whole point: that wandering is genetic drift.

[font_size=20][b]The speed control[/b][/font_size]
The speed slider scales the whole simulation uniformly, so you can slow things down to study the action or speed them up to watch alleles fix over many generations. Speed never favors any trait — it only changes how fast time passes.

[font_size=20][b]Learn more[/b][/font_size]
Open these in your browser for the full biology:
•  [color=#6db3ff][url=https://en.wikipedia.org/wiki/Genetic_drift]Genetic drift[/url][/color]
•  [color=#6db3ff][url=https://en.wikipedia.org/wiki/Allele]Alleles[/url][/color]
•  [color=#6db3ff][url=https://en.wikipedia.org/wiki/Population_bottleneck]Population bottleneck[/url][/color]
•  [color=#6db3ff][url=https://en.wikipedia.org/wiki/Founder_effect]Founder effect[/url][/color]
•  [color=#6db3ff][url=https://en.wikipedia.org/wiki/Moran_process]The Moran model[/url][/color]
•  [color=#6db3ff][url=https://en.wikipedia.org/wiki/Fixation_(population_genetics)]Fixation and loss[/url][/color]"""
