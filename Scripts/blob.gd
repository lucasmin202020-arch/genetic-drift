extends CharacterBody2D

var interaction_cooldown: float = 0.0

# --- TRAITS ---
var shape_trait: int = 0
var color_trait: int = 0
var eye_count: int = 1

# --- MOVEMENT ---
var speed: float = randf_range(70.0, 105.0)
var direction: Vector2 = Vector2.ZERO

# --- LIFESPAN ---
var lifespan: float = 40.0
var age: float = 0.0

# --- MATURITY / LIFE STAGE ---
var maturation_time: float = 9.0      # GLOBAL constant — same for all blobs (keeps drift pure)
var is_mature: bool = false
var spawn_scale: float = 0.10         # juvenile size
var mature_scale: float = 0.15        # adult size
var maturity_flash_timer: float = 0.0
var maturity_flash_duration: float = 0.5
var base_modulate: Color = Color.WHITE   # tint captured for the maturity glow

# --- REPRODUCTION ---
var reproduction_cooldown: float = 0.0
var reproduction_cooldown_max: float = 2.0

# --- BIRTH ANIMATION ---
var is_being_born: bool = true
var birth_timer: float = 0.0
var birth_duration: float = 0.6

# --- DEATH ANIMATION ---
var is_dying: bool = false
var death_timer: float = 0.0
var death_duration: float = 0.8
var death_start_scale: float = 0.15

# --- TEXTURES ---
var blob_textures: Array = []
var eye_textures: Array = []

# --- INTERNAL ---
var direction_timer: float = 0.0
var glow_timer: float = 0.0
var wobble_timer: float = 0.0

# --- JIGGLE ---
var jiggle_timer: float = 0.0
var jiggle_duration: float = 0.18

# --- COLOR SHADE ---
var shade_offset: float = 0.0

# --- SIGNAL ---
signal reproduce(my_traits: Dictionary, other_traits: Dictionary, spawn_pos: Vector2)

func _ready():
	randomize()
	direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	direction_timer = randf_range(2.0, 5.0)
	wobble_timer = randf_range(0.0, 6.28)
	glow_timer = randf_range(0.0, 6.28)
	reproduction_cooldown = reproduction_cooldown_max

func _physics_process(delta):
	# --- BIRTH ANIMATION (pops in to juvenile size) ---
	if is_being_born:
		birth_timer += delta
		var t = min(birth_timer / birth_duration, 1.0)
		scale = Vector2(spawn_scale * t, spawn_scale * t)
		$CollisionShape2D.scale = Vector2(t, t)
		if t >= 1.0:
			is_being_born = false
			scale = Vector2(spawn_scale, spawn_scale)
			$CollisionShape2D.scale = Vector2(1.0, 1.0)
		return

	# --- DEATH ANIMATION (shrinks from whatever size it was) ---
	if is_dying:
		death_timer += delta
		var t = min(death_timer / death_duration, 1.0)
		var s = death_start_scale * (1.0 - t)
		scale = Vector2(s, s)
		$BodySprite.modulate.a = lerp(1.0, 0.0, t)
		$EyeSprite.modulate.a = lerp(1.0, 0.0, t)
		if t >= 1.0:
			queue_free()
		return

	age += delta
	if age >= lifespan:
		die()
		return

	# --- MATURITY CHECK ---
	if not is_mature and age >= maturation_time:
		is_mature = true
		maturity_flash_timer = maturity_flash_duration

	# --- CONTINUOUS GROWTH (root scale) + maturity pop ---
	var growth = _get_growth_scale()
	var pop = 0.0
	if maturity_flash_timer > 0:
		maturity_flash_timer -= delta
		var mt = 1.0 - (maturity_flash_timer / maturity_flash_duration)
		pop = sin(mt * PI) * growth * 0.3   # brief transient puff at adulthood
	scale = Vector2(growth + pop, growth + pop)

	# --- REPRODUCTION COOLDOWN ---
	if reproduction_cooldown > 0:
		reproduction_cooldown -= delta

	# --- RANDOM DIRECTION CHANGES ---
	direction_timer -= delta
	if direction_timer <= 0:
		var angle_change = randf_range(PI/4, PI/2)
		if randf() > 0.5:
			angle_change = -angle_change
		direction = direction.rotated(angle_change)
		direction_timer = randf_range(3.0, 6.0)

	# --- ROTATION BASED ON X DIRECTION ---
	if direction.x > 0:
		rotation -= delta * 0.2
	else:
		rotation += delta * 0.2

	# --- COLLISION ---
	if interaction_cooldown > 0:
		interaction_cooldown -= delta

	var collision = move_and_collide(direction * speed * delta)
	if collision:
		var collider = collision.get_collider()
		if collider is CharacterBody2D and collider.has_method("get_traits"):
			if interaction_cooldown <= 0:
				# Only burn the interaction cooldown when a birth actually
				# happened. Previously a bump between two juveniles (or a pair
				# still on cooldown) locked BOTH blobs out for half a second,
				# which stalled reproduction right after everyone matured.
				if _try_reproduce(collider):
					interaction_cooldown = 0.5
		direction = direction.bounce(collision.get_normal())
		jiggle_timer = jiggle_duration

	# --- JIGGLE / WOBBLE (child sprites only — root scale stays clean for growth) ---
	if jiggle_timer > 0:
		jiggle_timer -= delta
		var jt = jiggle_timer / jiggle_duration
		var squish = sin(jt * PI) * 0.12
		$BodySprite.scale = Vector2(1.0 + squish, 1.0 - squish)
		$EyeSprite.scale = Vector2(1.0 + squish, 1.0 - squish)
	else:
		wobble_timer += delta * 2.0
		var wobble = sin(wobble_timer) * 0.03
		$BodySprite.scale = Vector2(1.0 + wobble, 1.0 + wobble)
		$EyeSprite.scale = Vector2(1.0 + wobble, 1.0 + wobble) if eye_count == 3 else Vector2(0.75 + wobble, 0.75 + wobble)

	# --- UNIVERSAL GLOW PULSE ---
	glow_timer += delta
	var pulse = (sin(glow_timer * 3.0) + 1.0) / 2.0
	$BodySprite.modulate.a = lerp(0.7, 1.0, pulse)

	# --- MATURITY GLOW (brief brighten the instant it reaches full size) ---
	if maturity_flash_timer > 0:
		var gt = 1.0 - (maturity_flash_timer / maturity_flash_duration)
		var g = sin(gt * PI)   # 0 -> 1 -> 0 across the flash
		$BodySprite.modulate = Color(
			lerp(base_modulate.r, 1.0, g * 0.7),
			lerp(base_modulate.g, 1.0, g * 0.7),
			lerp(base_modulate.b, 1.0, g * 0.7),
			1.0
		)

func _get_growth_scale() -> float:
	if age >= maturation_time:
		return mature_scale
	var t = age / maturation_time
	return lerp(spawn_scale, mature_scale, t)

# Returns TRUE only if a birth was actually triggered.
func _try_reproduce(other) -> bool:
	# --- MATURITY GATE: both parents must be adults ---
	if not is_mature or not other.is_mature:
		return false
	if reproduction_cooldown > 0:
		return false
	if other.reproduction_cooldown > 0:
		return false
	if other.is_dying or other.is_being_born:
		return false
	reproduction_cooldown = reproduction_cooldown_max
	other.reproduction_cooldown = other.reproduction_cooldown_max
	var spawn_pos = (global_position + other.global_position) / 2.0
	emit_signal("reproduce", get_traits(), other.get_traits(), spawn_pos)
	return true

func die():
	if is_dying:
		return
	is_dying = true
	death_start_scale = scale.x   # shrink from current size, not a fixed value
	$BodySprite.modulate = Color(0.5, 0.5, 0.5, 1.0)
	$EyeSprite.modulate = Color(0.5, 0.5, 0.5, 1.0)

func get_traits() -> Dictionary:
	return {
		"shape_trait": shape_trait,
		"color_trait": color_trait,
		"eye_count": eye_count
	}

func apply_traits():
	# --- SHAPE ---
	if blob_textures.size() == 3:
		$BodySprite.texture = blob_textures[shape_trait]

	# --- COLOR with per-blob shade variation ---
	shade_offset = randf_range(-0.08, 0.08)
	match color_trait:
		0:  # red
			$BodySprite.modulate = Color(
				clamp(1.0  + shade_offset, 0.0, 1.0),
				clamp(0.47 + shade_offset * 0.5, 0.0, 1.0),
				clamp(0.46 + shade_offset * 0.5, 0.0, 1.0),
				0.85)
		1:  # green
			$BodySprite.modulate = Color(
				clamp(0.78 + shade_offset * 0.5, 0.0, 1.0),
				clamp(1.0  + shade_offset, 0.0, 1.0),
				clamp(0.76 + shade_offset * 0.5, 0.0, 1.0),
				0.85)
		2:  # blue
			$BodySprite.modulate = Color(
				clamp(0.57 + shade_offset * 0.5, 0.0, 1.0),
				clamp(0.70 + shade_offset * 0.5, 0.0, 1.0),
				clamp(1.0  + shade_offset, 0.0, 1.0),
				0.85)

	base_modulate = $BodySprite.modulate

	# --- EYES ---
	if eye_textures.size() == 2:
		if eye_count == 1:
			$EyeSprite.texture = eye_textures[0]
			$EyeSprite.scale = Vector2(0.75, 0.75)
		else:
			$EyeSprite.texture = eye_textures[1]
			$EyeSprite.scale = Vector2(1.0, 1.0)
		$EyeSprite.visible = true

	# --- SIZE: starts juvenile, grows with age (no longer a trait) ---
	scale = Vector2(spawn_scale, spawn_scale)

func setup(p_shape: int, p_color: int, p_eyes: int, p_textures: Array, p_eye_textures: Array):
	shape_trait = p_shape
	color_trait = p_color
	eye_count = p_eyes
	blob_textures = p_textures
	eye_textures = p_eye_textures
	apply_traits()
	$CollisionShape2D.scale = Vector2(0.01, 0.01)
