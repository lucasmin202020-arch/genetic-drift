extends Node2D

# --- BLOB SCENE ---
@export var blob_scene: PackedScene

# --- TEXTURES ---
@export var blob_tex_1: Texture2D
@export var blob_tex_2: Texture2D
@export var blob_tex_3: Texture2D
@export var eye_tex_1: Texture2D
@export var eye_tex_2: Texture2D

# --- SETTINGS ---
var spawn_count: int = 12
var world_bounds = Rect2(80, 60, 620, 520)

# --- STATE ---
var simulation_running: bool = false
var blobs: Array = []

# --- TRACKER ---
var tracker_update_timer: float = 0.0
var tracker_update_interval: float = 0.5
var bar_max_width: float = 100.0

# --- COLLAPSE STATE ---
var tracker_expanded: bool = true
var delta_expanded: bool = true

# --- DELTA TRACKING ---
var snapshot_before: Dictionary = {}

# --- SPEED CONTROL ---
var speed_scales: Array = [0.25, 0.5, 0.75, 1.0, 1.25]
var speed_names: Array  = ["Very Slow", "Slow", "Medium", "Normal", "Fast"]
var default_speed_index: int = 2          # 0.75x — gentle default for new users
var is_dragging: bool = false
var is_snapping: bool = false
var snap_tween: Tween = null

# --- POPULATION LIMIT (prevents runaway growth / browser freeze) ---
var max_population: int = 80

# --- RUN STATS ---
var sim_time: float = 0.0
var births: int = 0
var deaths: int = 0

# --- BLOB INSPECTOR ---
# Hovering shows a blob's card temporarily; CLICKING pins it, so the card
# stays put without having to chase the blob with the cursor. Clicking
# anywhere else (empty space, or the pinned blob again) clears it.
# Presets set show_all to false — only color varies there.
var inspector_show_all_traits: bool = true
var hovered_blob = null
var pinned_blob = null
var inspector: BlobInspector = null
const INSPECT_MIN_TOUCH_RADIUS := 24.0

# --- MENU SCENE (for the back button) ---
# <-- set this to your MainMenu scene path (right-click the scene -> Copy Path)
const MENU_SCENE := "res://Scenes/MainMenu.tscn"

# --- START-GATED UI (hidden until Start, hidden again on Reset) ---
# Commands live in the static block; the tracker lives in the scroll block.
# Both stay hidden until Start. The Start/Speed rows above never move because
# the VBox is top-anchored, so revealing the commands can't shift them.
var gated_node_paths: Array = [
	"UIPanel/VBox/CommandsLabel",
	"UIPanel/VBox/BtnBottleneck",
	"UIPanel/VBox/BtnUnluckyDeath",
	"UIPanel/VBox/BtnNaturalDisaster",
	"UIPanel/VBox/TrackerScroll",
]

# ===========================================================================
#  BLOB INSPECTOR
#  Highlights a blob with diagonal yellow stripes and draws a leader line to
#  a card showing a portrait, its alleles, and a live countdown of its
#  remaining lifespan. Drawn in world space so it tracks the blob as it moves.
#  A pinned blob is drawn more strongly than a merely hovered one.
# ===========================================================================
class BlobInspector extends Node2D:
	var target = null
	var pinned: bool = false
	var show_all: bool = true
	var bounds: Rect2 = Rect2(0, 0, 1152, 648)

	var portrait_body: Sprite2D
	var portrait_eye: Sprite2D

	const BOX_W := 196.0
	const PAD := 12.0
	const LINE_H := 19.0
	const PORTRAIT_BOX := 52.0
	const FONT_SIZE := 13
	const TITLE_SIZE := 14

	# --- highlight look ---
	const STRIPE_SPACING := 7.0
	const STRIPE_WIDTH := 3.0
	const HL := Color(1.0, 0.87, 0.25)

	const COLOR_NAMES := ["Red", "Green", "Blue"]
	const SHAPE_NAMES := ["Round", "Star", "Flower"]
	const SWATCHES := [
		Color(1.0, 0.45, 0.45),
		Color(0.45, 0.9, 0.45),
		Color(0.45, 0.65, 1.0)
	]

	func _ready():
		z_index = 200
		visible = false
		portrait_body = Sprite2D.new()
		portrait_eye = Sprite2D.new()
		add_child(portrait_body)
		add_child(portrait_eye)

	func show_blob(b, is_pinned: bool):
		var changed: bool = b != target
		target = b
		pinned = is_pinned
		visible = b != null
		if b == null:
			return
		if changed:
			_build_portrait()
		queue_redraw()

	# Mirror the blob's own sprites, at a fixed readable size.
	func _build_portrait():
		var bs = target.get_node_or_null("BodySprite")
		var es = target.get_node_or_null("EyeSprite")
		if bs and bs.texture:
			portrait_body.texture = bs.texture
			var tint: Color = target.base_modulate
			portrait_body.modulate = Color(tint.r, tint.g, tint.b, 1.0)
			var s: float = (PORTRAIT_BOX * 0.78) / float(bs.texture.get_height())
			portrait_body.scale = Vector2(s, s)
			if es and es.texture:
				portrait_eye.texture = es.texture
				portrait_eye.modulate = Color(1, 1, 1, 1)
				# EyeSprite is scaled relative to the body, so carry that through
				portrait_eye.scale = Vector2(s, s) * es.scale
				portrait_eye.visible = true
			else:
				portrait_eye.visible = false

	func _process(_delta):
		if target == null:
			return
		# Drop it when the blob dies or is freed.
		if not is_instance_valid(target) or target.is_dying:
			show_blob(null, false)
			return
		queue_redraw()

	func _info_lines() -> Array:
		var lines: Array = []
		lines.append(["Color", COLOR_NAMES[target.color_trait], SWATCHES[target.color_trait]])
		if show_all:
			lines.append(["Shape", SHAPE_NAMES[target.shape_trait], Color(0.85, 0.85, 0.88)])
			lines.append(["Eyes", str(target.eye_count), Color(0.85, 0.85, 0.88)])
		var remaining: float = max(0.0, target.lifespan - target.age)
		lines.append(["Life left", "%.1fs" % remaining, _life_color(remaining)])
		var stage := "Adult"
		if not target.is_mature:
			var to_adult: float = max(0.0, target.maturation_time - target.age)
			stage = "Juvenile (%.0fs)" % to_adult
		lines.append(["Stage", stage, Color(0.80, 0.80, 0.85)])
		return lines

	func _life_color(remaining: float) -> Color:
		if remaining <= 5.0:
			return Color(1.0, 0.45, 0.45)
		elif remaining <= 12.0:
			return Color(0.95, 0.78, 0.40)
		return Color(0.55, 0.90, 0.60)

	# Diagonal stripes clipped to the blob's circle. For each offset along the
	# perpendicular axis, the chord half-length is sqrt(r^2 - d^2) — that keeps
	# the striped patch perfectly round without needing a mask.
	func _draw_stripes(centre: Vector2, r: float, alpha: float):
		var dir := Vector2(1, 1).normalized()
		var perp := Vector2(-1, 1).normalized()
		var col := Color(HL.r, HL.g, HL.b, alpha)
		var d: float = -r + STRIPE_SPACING * 0.5
		while d < r:
			var half: float = sqrt(max(0.0, r * r - d * d))
			if half > 1.0:
				var mid: Vector2 = centre + perp * d
				draw_line(mid - dir * half, mid + dir * half, col, STRIPE_WIDTH, true)
			d += STRIPE_SPACING

	func _draw():
		if target == null or not is_instance_valid(target):
			return

		var font := ThemeDB.fallback_font
		var lines := _info_lines()
		var text_h: float = lines.size() * LINE_H
		var box_h: float = max(PORTRAIT_BOX, text_h) + PAD * 2.0 + 18.0

		var bp: Vector2 = target.global_position
		var r: float = _target_radius()

		# Pinned reads stronger than a passing hover.
		var stripe_a: float = 0.50 if pinned else 0.30
		var ring_a: float = 0.95 if pinned else 0.55
		var line_a: float = 0.85 if pinned else 0.50

		# --- striped highlight ---
		_draw_stripes(bp, r, stripe_a)
		draw_arc(bp, r, 0.0, TAU, 40, Color(HL.r, HL.g, HL.b, ring_a), 2.0, true)
		if pinned:
			# second, outer ring marks the locked selection
			draw_arc(bp, r + 5.0, 0.0, TAU, 40, Color(HL.r, HL.g, HL.b, 0.45), 1.5, true)

		# Prefer placing the card up-and-right; flip near the edges so it
		# never leaves the play area.
		var to_right: bool = bp.x < bounds.position.x + bounds.size.x * 0.6
		var bx: float = bp.x + r + 46.0 if to_right else bp.x - r - 46.0 - BOX_W
		var by: float = bp.y - box_h * 0.5
		bx = clamp(bx, bounds.position.x + 6.0, bounds.end.x - BOX_W - 6.0)
		by = clamp(by, bounds.position.y + 6.0, bounds.end.y - box_h - 6.0)
		var box := Rect2(bx, by, BOX_W, box_h)

		# --- leader line: blob edge -> card edge ---
		var anchor := Vector2(box.position.x, box.position.y + box_h * 0.5)
		if not to_right:
			anchor = Vector2(box.end.x, box.position.y + box_h * 0.5)
		var dir: Vector2 = (anchor - bp).normalized()
		var line_start: Vector2 = bp + dir * (r + 3.0)
		draw_line(line_start, anchor, Color(HL.r, HL.g, HL.b, line_a), 1.5, true)

		# --- dot on the blob ---
		draw_circle(bp, 4.0, Color(1, 1, 1, 0.95))
		draw_circle(bp, 2.2, Color(0.95, 0.75, 0.15, 1.0))

		# --- card ---
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.13, 0.13, 0.165, 0.97)
		sb.border_color = Color(0.55, 0.48, 0.26) if pinned else Color(0.34, 0.33, 0.30)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(9)
		draw_style_box(sb, box)

		# --- title ---
		var title := "Blob — pinned" if pinned else "Blob"
		draw_string(font, Vector2(box.position.x + PAD, box.position.y + PAD + 11.0),
			title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE,
			Color(0.85, 0.76, 0.45) if pinned else Color(0.62, 0.62, 0.68))

		# --- portrait ---
		var px: float = box.position.x + PAD + PORTRAIT_BOX * 0.5
		var py: float = box.position.y + PAD + 20.0 + PORTRAIT_BOX * 0.5
		var pbox := Rect2(box.position.x + PAD, box.position.y + PAD + 20.0,
			PORTRAIT_BOX, PORTRAIT_BOX)
		var pstyle := StyleBoxFlat.new()
		pstyle.bg_color = Color(0.08, 0.08, 0.10)
		pstyle.set_corner_radius_all(7)
		draw_style_box(pstyle, pbox)
		portrait_body.position = Vector2(px, py)
		portrait_eye.position = Vector2(px, py)

		# --- text rows ---
		var tx: float = box.position.x + PAD + PORTRAIT_BOX + 12.0
		var ty: float = box.position.y + PAD + 30.0
		for i in range(lines.size()):
			var row: Array = lines[i]
			var y: float = ty + i * LINE_H
			draw_string(font, Vector2(tx, y), str(row[0]) + ":",
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0.58, 0.60, 0.68))
			var lw: float = font.get_string_size(str(row[0]) + ":",
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
			draw_string(font, Vector2(tx + lw + 6.0, y), str(row[1]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, row[2])

	func _target_radius() -> float:
		var bs = target.get_node_or_null("BodySprite")
		if bs and bs.texture:
			return bs.texture.get_width() * 0.5 * target.scale.x * bs.scale.x
		return 22.0

func _ready():
	randomize()
	$UIPanel/VBox/TrackerScroll/TrackerVBox/TrackerToggle.pressed.connect(_on_tracker_toggle)
	$UIPanel/VBox/TrackerScroll/TrackerVBox/DeltaToggle.pressed.connect(_on_delta_toggle)

	# --- SPEED SLIDER ---
	var speed_slider = get_node_or_null("UIPanel/VBox/SpeedSlider")
	if speed_slider:
		speed_slider.min_value = 0
		speed_slider.max_value = 4
		speed_slider.step = 0.01          # smooth drag; we auto-lock on release
		speed_slider.value = default_speed_index
		speed_slider.value_changed.connect(_on_slider_value_changed)
		speed_slider.drag_started.connect(_on_slider_drag_started)
		speed_slider.drag_ended.connect(_on_slider_drag_ended)
	_apply_speed(default_speed_index)
	_style_speed_slider()
	_build_back_button()
	_pin_panel_top()
	_build_inspector()
	get_viewport().size_changed.connect(_fit_tracker_height)

	# --- TOOLTIPS: Controls ---
	$UIPanel/VBox/TopButtons/BtnStart.tooltip_text = "Start the simulation. Blobs will begin moving and reproducing."
	$UIPanel/VBox/TopButtons/BtnPause.tooltip_text = "Pause or resume the simulation."
	$UIPanel/VBox/TopButtons/BtnReset.tooltip_text = "Stop the simulation and remove all blobs."

	# --- TOOLTIPS: Commands ---
	$UIPanel/VBox/BtnBottleneck.tooltip_text = "Bottleneck Effect: Randomly kills 70-80% of all blobs, simulating a population crash. Surviving traits may dominate purely by chance."
	$UIPanel/VBox/BtnUnluckyDeath.tooltip_text = "Unlucky Death: Kills one random blob. Even one death can shift allele frequencies over time."
	$UIPanel/VBox/BtnNaturalDisaster.tooltip_text = "Natural Disaster: Kills all blobs in a random zone. Traits concentrated in that area may be wiped out entirely."

	# --- TOOLTIPS: Tracker ---
	$UIPanel/VBox/TrackerScroll/TrackerVBox/TrackerToggle.tooltip_text = "Shows the current percentage of each trait variant in the live population."
	$UIPanel/VBox/TrackerScroll/TrackerVBox/DeltaToggle.tooltip_text = "Shows how trait percentages changed after the last event."

	# --- HIDE COMMANDS + TRACKER UNTIL START ---
	_set_gated_visible(false)

func _process(delta):
	_update_pop_label()
	_update_inspector()
	if simulation_running:
		sim_time += delta
		tracker_update_timer += delta
		if tracker_update_timer >= tracker_update_interval:
			tracker_update_timer = 0.0
			update_tracker()

# ---------------------------------------------------------------------------
#  BLOB INSPECTOR
# ---------------------------------------------------------------------------
func _build_inspector():
	inspector = BlobInspector.new()
	inspector.show_all = inspector_show_all_traits
	inspector.bounds = world_bounds
	add_child(inspector)

# A pinned blob always wins; otherwise whatever the cursor is over shows
# temporarily. Re-checked every frame rather than on mouse-motion only,
# because the blobs move — a stationary cursor should pick up whatever
# drifts underneath it.
func _update_inspector():
	if inspector == null:
		return
	inspector.show_all = inspector_show_all_traits

	if pinned_blob != null:
		if not is_instance_valid(pinned_blob) or pinned_blob.is_dying:
			pinned_blob = null
		else:
			inspector.show_blob(pinned_blob, true)
			return

	var pos := get_global_mouse_position()
	var hit = null
	# Ignore the cursor when it's outside the play area (e.g. over the panel).
	if world_bounds.grow(30.0).has_point(pos):
		hit = _blob_at(pos)
	hovered_blob = hit
	inspector.show_blob(hit, false)

# Click a blob to pin its card in place. Clicking empty space — or the
# pinned blob again — releases it.
func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos := get_global_mouse_position()
		if not world_bounds.grow(30.0).has_point(pos):
			return
		var hit = _blob_at(pos)
		if hit == null or hit == pinned_blob:
			pinned_blob = null
		else:
			pinned_blob = hit

func _blob_at(pos: Vector2):
	var best = null
	var best_d: float = INF
	for b in blobs:
		if not is_instance_valid(b) or b.is_dying:
			continue
		var r: float = INSPECT_MIN_TOUCH_RADIUS
		var bs = b.get_node_or_null("BodySprite")
		if bs and bs.texture:
			r = max(r, bs.texture.get_width() * 0.5 * b.scale.x * bs.scale.x)
		var d: float = pos.distance_to(b.global_position)
		if d <= r and d < best_d:
			best_d = d
			best = b
	return best

func _clear_inspection():
	hovered_blob = null
	pinned_blob = null
	if inspector:
		inspector.show_blob(null, false)

# --- POPULATION COUNTER + RUN STATS ---
func _update_pop_label():
	var pop_label = get_node_or_null("PopLabel")
	if not pop_label:
		return
	var alive = blobs.filter(func(b): return is_instance_valid(b) and not b.is_dying)
	var mins = int(sim_time) / 60
	var secs = int(sim_time) % 60
	pop_label.text = "Population: %d / %d    Time: %d:%02d    Births: %d    Deaths: %d" % [
		alive.size(), max_population, mins, secs, births, deaths
	]

# --- START-GATED VISIBILITY ---
func _set_gated_visible(vis: bool):
	for p in gated_node_paths:
		var n = get_node_or_null(p)
		if n:
			n.visible = vis

# --- BACK BUTTON (top of the panel, in place of the old title) ---
func _build_back_button():
	var vbox = get_node_or_null("UIPanel/VBox")
	if not vbox:
		return
	# Hide the old "Genetic Drift Lab" title — the back button replaces it.
	_hide_title_label(get_node_or_null("UIPanel"))
	var back := Button.new()
	back.text = "← Menu"
	back.add_theme_font_size_override("font_size", 16)
	vbox.add_child(back)
	vbox.move_child(back, 0)   # very top of the panel
	back.pressed.connect(_on_back_to_menu)

func _on_back_to_menu():
	Engine.time_scale = 1.0    # restore normal time before leaving the sim
	get_tree().change_scene_to_file(MENU_SCENE)

# Recursively hide the old panel title label.
func _hide_title_label(node):
	if node == null:
		return
	for child in node.get_children():
		if child is Label and "Genetic Drift Lab" in child.text:
			child.visible = false
		else:
			_hide_title_label(child)

# Pin the panel content to the top so the static block (back button -> commands)
# stays put and the stack grows DOWNWARD when the tracker appears on Start.
# (Does NOT touch the panel — only the VBox growth direction.)
func _pin_panel_top():
	var vbox = get_node_or_null("UIPanel/VBox")
	if not vbox:
		return
	vbox.anchor_top = 0.0
	vbox.anchor_bottom = 0.0
	vbox.offset_top = 8.0
	vbox.offset_bottom = 8.0
	vbox.grow_vertical = Control.GROW_DIRECTION_END
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN

# Cap the tracker's height to the space left below it, so it scrolls internally
# instead of running off the bottom. Recomputed on Start and on window resize.
# This touches ONLY the tracker — nothing else in the panel.
func _fit_tracker_height():
	var tracker_scroll = get_node_or_null("UIPanel/VBox/TrackerScroll")
	if not tracker_scroll or not tracker_scroll.visible:
		return
	var vp_h = get_viewport_rect().size.y
	var top_y = tracker_scroll.global_position.y
	var avail = vp_h - top_y - 16.0
	tracker_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tracker_scroll.custom_minimum_size.y = max(120.0, avail)

# --- SPEED CONTROL (uniform time scaling — drift-safe) ---
# 5 discrete settings; the slider drags smoothly then auto-locks to the nearest.
func _apply_speed(idx: int):
	idx = clampi(idx, 0, 4)
	Engine.time_scale = speed_scales[idx]
	_set_speed_label(idx)

func _set_speed_label(idx: int):
	idx = clampi(idx, 0, 4)
	var speed_label = get_node_or_null("UIPanel/VBox/SpeedLabel")
	if speed_label:
		speed_label.text = "Speed: " + speed_names[idx]

func _on_slider_value_changed(value):
	if is_snapping:
		return
	# Live preview of the nearest setting while the user drags
	_set_speed_label(int(round(value)))
	# A click or keypress (not a drag) should auto-lock immediately
	if not is_dragging:
		_snap_to_nearest()

func _on_slider_drag_started():
	is_dragging = true
	if snap_tween and snap_tween.is_running():
		snap_tween.kill()
	is_snapping = false

func _on_slider_drag_ended(_value_changed):
	is_dragging = false
	_snap_to_nearest()

func _snap_to_nearest():
	var slider = get_node_or_null("UIPanel/VBox/SpeedSlider")
	if not slider:
		return
	var nearest = clampi(int(round(slider.value)), 0, 4)
	is_snapping = true
	snap_tween = create_tween()
	var t = snap_tween.tween_property(slider, "value", float(nearest), 0.15)
	t.set_trans(Tween.TRANS_QUAD)
	t.set_ease(Tween.EASE_OUT)
	snap_tween.tween_callback(_finish_snap.bind(nearest))

func _finish_snap(nearest: int):
	is_snapping = false
	_apply_speed(nearest)

# --- SLIDER LOOK: full-width horizontal track, ticks, centered label ---
func _style_speed_slider():
	var slider = get_node_or_null("UIPanel/VBox/SpeedSlider")
	if slider:
		slider.custom_minimum_size = Vector2(0, 22)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.tick_count = 5
		slider.ticks_on_borders = true

		# Track (the full bar behind the grabber)
		var track = StyleBoxFlat.new()
		track.bg_color = Color(0.16, 0.16, 0.19)
		track.set_corner_radius_all(6)
		track.content_margin_top = 5
		track.content_margin_bottom = 5
		slider.add_theme_stylebox_override("slider", track)

		# Filled portion to the left of the grabber
		var fill = StyleBoxFlat.new()
		fill.bg_color = Color(0.40, 0.60, 1.0)
		fill.set_corner_radius_all(6)
		slider.add_theme_stylebox_override("grabber_area", fill)
		slider.add_theme_stylebox_override("grabber_area_highlight", fill)

	var speed_label = get_node_or_null("UIPanel/VBox/SpeedLabel")
	if speed_label:
		speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func start_simulation():
	if blob_scene == null:
		push_error("Blob Scene is not assigned — select the root node and drag Blob.tscn into the 'Blob Scene' field in the Inspector.")
		return
	simulation_running = true
	sim_time = 0.0
	births = 0
	deaths = 0
	_clear_inspection()
	_set_gated_visible(true)
	_fit_tracker_height.call_deferred()
	_spawn_guaranteed_coverage()
	var remaining = spawn_count - 6
	for i in range(remaining):
		spawn_blob()
	set_blobs_paused(false)
	update_tracker()

func pause_simulation():
	simulation_running = false
	set_blobs_paused(true)

func resume_simulation():
	simulation_running = true
	set_blobs_paused(false)

func reset_simulation():
	simulation_running = false
	_clear_inspection()
	for blob in blobs:
		if is_instance_valid(blob):
			blob.queue_free()
	blobs.clear()
	sim_time = 0.0
	births = 0
	deaths = 0
	_clear_tracker()
	_clear_delta()
	_set_gated_visible(false)

func set_blobs_paused(paused: bool):
	for blob in blobs:
		if is_instance_valid(blob):
			blob.set_physics_process(!paused)

func _spawn_guaranteed_coverage():
	var guaranteed = [
		[0, 0, 1],
		[1, 1, 3],
		[2, 2, 1],
		[0, 1, 3],
		[1, 2, 1],
		[2, 0, 3],
	]
	for combo in guaranteed:
		var blob = _create_blob()
		blob.setup(combo[0], combo[1], combo[2],
			[blob_tex_1, blob_tex_2, blob_tex_3], [eye_tex_1, eye_tex_2])

func spawn_blob():
	var blob = _create_blob()
	blob.setup(randi() % 3, randi() % 3, 1 if randf() > 0.5 else 3,
		[blob_tex_1, blob_tex_2, blob_tex_3], [eye_tex_1, eye_tex_2])

func _create_blob() -> CharacterBody2D:
	var blob = blob_scene.instantiate()
	add_child(blob)
	var cols = 4
	var rows = 3
	var cell_w = world_bounds.size.x / cols
	var cell_h = world_bounds.size.y / rows
	var index = blobs.size() % (cols * rows)
	var col = index % cols
	var row = index / cols
	var cell_center = Vector2(
		world_bounds.position.x + col * cell_w + cell_w * 0.5,
		world_bounds.position.y + row * cell_h + cell_h * 0.5
	)
	blob.global_position = cell_center + Vector2(
		randf_range(-cell_w * 0.25, cell_w * 0.25),
		randf_range(-cell_h * 0.25, cell_h * 0.25)
	)
	blob.connect("reproduce", _on_blob_reproduce)
	blob.connect("tree_exited", _on_blob_removed.bind(blob))
	blobs.append(blob)
	return blob

func spawn_blob_from_parents(traits_a: Dictionary, traits_b: Dictionary, pos: Vector2):
	var blob = blob_scene.instantiate()
	add_child(blob)
	blob.global_position = Vector2(
		clamp(pos.x, world_bounds.position.x, world_bounds.end.x),
		clamp(pos.y, world_bounds.position.y, world_bounds.end.y)
	)
	var child_shape = traits_a["shape_trait"] if randf() > 0.5 else traits_b["shape_trait"]
	var child_color = traits_a["color_trait"] if randf() > 0.5 else traits_b["color_trait"]
	var child_eyes  = traits_a["eye_count"]   if randf() > 0.5 else traits_b["eye_count"]
	blob.setup(child_shape, child_color, child_eyes,
		[blob_tex_1, blob_tex_2, blob_tex_3], [eye_tex_1, eye_tex_2])
	blob.connect("reproduce", _on_blob_reproduce)
	blob.connect("tree_exited", _on_blob_removed.bind(blob))
	blobs.append(blob)
	births += 1
	if not simulation_running:
		blob.set_physics_process(false)

func _on_blob_reproduce(traits_a: Dictionary, traits_b: Dictionary, pos: Vector2):
	await get_tree().create_timer(0.2).timeout
	if not simulation_running:
		return
	# Population cap: block new births at the limit. This is random with respect
	# to traits (just timing), so drift stays pure — no allele is favored.
	var alive = blobs.filter(func(b): return is_instance_valid(b) and not b.is_dying)
	if alive.size() >= max_population:
		return
	spawn_blob_from_parents(traits_a, traits_b, pos)

func _on_blob_removed(blob):
	blobs.erase(blob)
	if blob == pinned_blob:
		pinned_blob = null
	if blob == hovered_blob:
		hovered_blob = null
	if simulation_running:
		deaths += 1

# --- COLLAPSE TOGGLES ---
func _on_tracker_toggle():
	tracker_expanded = !tracker_expanded
	var container = get_node_or_null("UIPanel/VBox/TrackerScroll/TrackerVBox/TrackerContainer")
	var btn = get_node_or_null("UIPanel/VBox/TrackerScroll/TrackerVBox/TrackerToggle")
	if container:
		container.visible = tracker_expanded
	if btn:
		btn.text = "▼ Allele Tracker" if tracker_expanded else "▶ Allele Tracker"

func _on_delta_toggle():
	delta_expanded = !delta_expanded
	var container = get_node_or_null("UIPanel/VBox/TrackerScroll/TrackerVBox/DeltaContainer")
	var btn = get_node_or_null("UIPanel/VBox/TrackerScroll/TrackerVBox/DeltaToggle")
	if container:
		container.visible = delta_expanded
	if btn:
		btn.text = "▼ Last Event" if delta_expanded else "▶ Last Event"

# --- SNAPSHOT ---
func take_snapshot() -> Dictionary:
	var alive = blobs.filter(func(b): return is_instance_valid(b) and not b.is_dying and not b.is_being_born)
	var total = alive.size()
	if total == 0:
		return {}
	var color_counts = [0, 0, 0]
	var shape_counts = [0, 0, 0]
	var eye_counts = [0, 0]
	for blob in alive:
		color_counts[blob.color_trait] += 1
		shape_counts[blob.shape_trait] += 1
		if blob.eye_count == 1:
			eye_counts[0] += 1
		else:
			eye_counts[1] += 1
	return {
		"total": total,
		"color": color_counts,
		"shape": shape_counts,
		"eyes": eye_counts
	}

# --- TRACKER ---
func update_tracker():
	var alive = blobs.filter(func(b): return is_instance_valid(b) and not b.is_dying and not b.is_being_born)
	var total = alive.size()
	if total == 0:
		_clear_tracker()
		return

	var color_counts = [0, 0, 0]
	var shape_counts = [0, 0, 0]
	var eye_counts   = [0, 0]

	for blob in alive:
		color_counts[blob.color_trait] += 1
		shape_counts[blob.shape_trait] += 1
		if blob.eye_count == 1:
			eye_counts[0] += 1
		else:
			eye_counts[1] += 1

	var color_lead = color_counts.find(color_counts.max())
	var shape_lead = shape_counts.find(shape_counts.max())
	var eye_lead   = eye_counts.find(eye_counts.max())

	# --- COLOR BARS ---
	var color_data = [
		["RedFill",   "RedPct",   color_counts[0], Color(1.0, 0.35, 0.35)],
		["GreenFill", "GreenPct", color_counts[1], Color(0.4, 0.9,  0.4)],
		["BlueFill",  "BluePct",  color_counts[2], Color(0.4, 0.6,  1.0)],
	]
	for i in range(3):
		var d = color_data[i]
		_set_bar(d[0], d[1], d[2], total, d[3], i == color_lead)

	# --- SHAPE BARS ---
	var shape_data = [
		["RoundFill",  "RoundPct",  shape_counts[0]],
		["StarFill",   "StarPct",   shape_counts[1]],
		["FlowerFill", "FlowerPct", shape_counts[2]],
	]
	for i in range(3):
		var d = shape_data[i]
		_set_bar(d[0], d[1], d[2], total, Color(0.8, 0.8, 0.8), i == shape_lead)

	# --- EYE BARS ---
	var eye_data = [
		["OneEyeFill",   "OneEyePct",   eye_counts[0]],
		["ThreeEyeFill", "ThreeEyePct", eye_counts[1]],
	]
	for i in range(2):
		var d = eye_data[i]
		_set_bar(d[0], d[1], d[2], total, Color(0.9, 0.85, 0.5), i == eye_lead)

func _set_bar(fill_name: String, pct_name: String, count: int, total: int, color: Color, is_leading: bool = false):
	var pct = float(count) / float(total)
	var bar_name = fill_name.replace("Fill", "Bar")
	var base = "UIPanel/VBox/TrackerScroll/TrackerVBox/TrackerContainer/"
	var fill = get_node_or_null(base + bar_name + "/" + fill_name)
	var label = get_node_or_null(base + bar_name + "/" + pct_name)
	if fill:
		fill.custom_minimum_size.x = pct * bar_max_width
		fill.color = color
	if label:
		label.text = "%s  %d%% (%d)" % [fill_name.replace("Fill", ""), int(pct * 100), count]
		label.add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.2) if is_leading else Color(1.0, 1.0, 1.0))

func _clear_tracker():
	var entries = [
		["RedBar",      "RedFill",      "RedPct"],
		["GreenBar",    "GreenFill",    "GreenPct"],
		["BlueBar",     "BlueFill",     "BluePct"],
		["RoundBar",    "RoundFill",    "RoundPct"],
		["StarBar",     "StarFill",     "StarPct"],
		["FlowerBar",   "FlowerFill",   "FlowerPct"],
		["OneEyeBar",   "OneEyeFill",   "OneEyePct"],
		["ThreeEyeBar", "ThreeEyeFill", "ThreeEyePct"],
	]
	var base = "UIPanel/VBox/TrackerScroll/TrackerVBox/TrackerContainer/"
	for entry in entries:
		var fill = get_node_or_null(base + entry[0] + "/" + entry[1])
		var label = get_node_or_null(base + entry[0] + "/" + entry[2])
		if fill:
			fill.custom_minimum_size.x = 0
		if label:
			label.text = ""

# --- DELTA DISPLAY ---
func show_delta(event_name: String):
	await get_tree().create_timer(0.9).timeout
	var after = take_snapshot()
	if snapshot_before.is_empty() or after.is_empty():
		return

	var base = "UIPanel/VBox/TrackerScroll/TrackerVBox/DeltaContainer/"
	var event_label = get_node_or_null(base + "DeltaEventLabel")
	if event_label:
		event_label.text = "Event: " + event_name

	var before_total = float(snapshot_before["total"])
	var after_total  = float(after["total"])

	var color_names = ["Red",    "Green",   "Blue"]
	var shape_names = ["Round",  "Star",    "Flower"]
	var eye_names   = ["OneEye", "ThreeEye"]

	for i in range(3):
		var b_pct = int((snapshot_before["color"][i] / before_total) * 100)
		var a_pct = int((after["color"][i] / after_total) * 100)
		_set_delta_label(base + color_names[i] + "DeltaLabel",
			color_names[i], b_pct, a_pct)

	for i in range(3):
		var b_pct = int((snapshot_before["shape"][i] / before_total) * 100)
		var a_pct = int((after["shape"][i] / after_total) * 100)
		_set_delta_label(base + shape_names[i] + "DeltaLabel",
			shape_names[i], b_pct, a_pct)

	for i in range(2):
		var b_pct = int((snapshot_before["eyes"][i] / before_total) * 100)
		var a_pct = int((after["eyes"][i] / after_total) * 100)
		_set_delta_label(base + eye_names[i] + "DeltaLabel",
			eye_names[i], b_pct, a_pct)

func _set_delta_label(path: String, name: String, b_pct: int, a_pct: int):
	var node = get_node_or_null(path)
	if not node:
		return
	var arrow = "▲" if a_pct > b_pct else ("▼" if a_pct < b_pct else "─")
	node.text = "%s  %d%% → %d%%  %s" % [name, b_pct, a_pct, arrow]
	node.add_theme_color_override("font_color",
		Color(0.4, 1.0, 0.4) if a_pct > b_pct else
		(Color(1.0, 0.4, 0.4) if a_pct < b_pct else
		Color(1.0, 1.0, 1.0)))

func _clear_delta():
	var base = "UIPanel/VBox/TrackerScroll/TrackerVBox/DeltaContainer/"
	var all_labels = [
		"DeltaEventLabel",
		"RedDeltaLabel", "GreenDeltaLabel", "BlueDeltaLabel",
		"RoundDeltaLabel", "StarDeltaLabel", "FlowerDeltaLabel",
		"OneEyeDeltaLabel", "ThreeEyeDeltaLabel"
	]
	for l in all_labels:
		var node = get_node_or_null(base + l)
		if node:
			node.text = ""

# --- COMMANDS ---
func cmd_bottleneck():
	snapshot_before = take_snapshot()
	var alive = blobs.filter(func(b): return is_instance_valid(b))
	if alive.is_empty():
		return
	alive.shuffle()
	if alive.size() <= 3:
		alive[0].die()
	else:
		var kill_count = int(alive.size() * randf_range(0.7, 0.8))
		for i in range(kill_count):
			alive[i].die()
	show_delta("Bottleneck")

func cmd_unlucky_death():
	snapshot_before = take_snapshot()
	var alive = blobs.filter(func(b): return is_instance_valid(b))
	if alive.size() == 0:
		return
	alive[randi() % alive.size()].die()
	show_delta("Unlucky Death")

func cmd_natural_disaster():
	snapshot_before = take_snapshot()
	var zone_w = randf_range(150, 320)
	var zone_h = randf_range(120, 260)
	var zone_x = randf_range(world_bounds.position.x, world_bounds.end.x - zone_w)
	var zone_y = randf_range(world_bounds.position.y, world_bounds.end.y - zone_h)
	var disaster_zone = Rect2(zone_x, zone_y, zone_w, zone_h)

	var flash = ColorRect.new()
	flash.position = disaster_zone.position
	flash.size = disaster_zone.size
	flash.color = Color(1.0, 0.3, 0.0, 0.35)
	add_child(flash)

	await get_tree().create_timer(0.4).timeout
	flash.queue_free()

	for blob in blobs:
		if is_instance_valid(blob) and not blob.is_dying:
			if disaster_zone.has_point(blob.global_position):
				blob.die()
	show_delta("Natural Disaster")
